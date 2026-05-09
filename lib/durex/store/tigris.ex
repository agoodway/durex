defmodule Durex.Store.Tigris do
  @moduledoc """
  Tigris-backed storage backend for Durex checkpoint payloads.

  The host application owns bucket and credential configuration:

      config :durex, Durex.Store.Tigris,
        bucket: "my-bucket",
        access_key_id: "tid_xxx",
        secret_access_key: "tsec_xxx"

  Optional `:endpoint`, `:region`, and `:prefix` values default to Tigris' public
  endpoint, region `"auto"`, and no prefix.
  """

  @behaviour Durex.Store

  @compile {:no_warn_undefined, Req}

  @default_endpoint "https://t3.storage.dev"
  @default_region "auto"
  @default_req_options [receive_timeout: 5_000, pool_timeout: 1_000]
  @expires_header "x-amz-meta-durex-expires-at"
  @safe_req_options [
    :adapter,
    :connect_options,
    :receive_timeout,
    :pool_timeout,
    :finch,
    :finch_options
  ]

  @type config :: %{
          bucket: String.t(),
          access_key_id: String.t(),
          secret_access_key: String.t(),
          endpoint: URI.t(),
          region: String.t(),
          prefix: String.t() | nil,
          req_options: keyword()
        }

  @impl Durex.Store
  @spec write(String.t(), binary(), keyword()) :: :ok | {:error, term()}
  def write(key, payload, opts \\ []) do
    headers = ttl_headers(opts)

    with {:ok, response} <- request(:put, key, body: payload, headers: headers) do
      case response.status do
        status when status in 200..299 -> :ok
        status -> {:error, {:unexpected_status, status}}
      end
    end
  end

  @impl Durex.Store
  @spec read(String.t()) :: {:ok, binary() | nil} | {:error, term()}
  def read(key) do
    with {:ok, response} <- request(:get, key, raw: true, decode_body: false) do
      case response.status do
        status when status in 200..299 -> read_body(response)
        404 -> {:ok, nil}
        status -> {:error, {:unexpected_status, status}}
      end
    end
  end

  @impl Durex.Store
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(key) do
    with {:ok, response} <- request(:delete, key) do
      case response.status do
        status when status in 200..299 -> :ok
        404 -> :ok
        status -> {:error, {:unexpected_status, status}}
      end
    end
  end

  @spec request(:delete | :get | :put, String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defp request(method, key, opts \\ []) do
    req_module = req_module()

    with :ok <- ensure_req(req_module),
         {:ok, config} <- config(),
         {:ok, url} <- object_url(config, key) do
      options =
        config.req_options
        |> Keyword.merge(opts)
        |> Keyword.merge(method: method, url: url, aws_sigv4: aws_sigv4(config), retry: false)

      req_module.request(options)
    end
  rescue
    error -> {:error, error}
  end

  @spec req_module() :: module()
  defp req_module do
    Process.get({__MODULE__, :req_module}, Req)
  end

  @spec ensure_req(module()) :: :ok | {:error, :req_not_available}
  defp ensure_req(req_module) do
    if Code.ensure_loaded?(req_module) do
      :ok
    else
      {:error, :req_not_available}
    end
  end

  @spec config() :: {:ok, config()} | {:error, term()}
  defp config do
    app_config = Application.get_env(:durex, __MODULE__, [])

    with {:ok, bucket} <- required(app_config, :bucket),
         :ok <- validate_bucket(bucket),
         {:ok, access_key_id} <- required(app_config, :access_key_id),
         {:ok, secret_access_key} <- required(app_config, :secret_access_key),
         {:ok, region} <- optional_string(app_config, :region, @default_region),
         {:ok, endpoint} <- endpoint(Keyword.get(app_config, :endpoint, @default_endpoint)) do
      {:ok,
       %{
         bucket: bucket,
         access_key_id: access_key_id,
         secret_access_key: secret_access_key,
         endpoint: endpoint,
         region: region,
         prefix: normalize_prefix(Keyword.get(app_config, :prefix)),
         req_options: req_options(app_config)
       }}
    end
  end

  @spec required(keyword(), atom()) :: {:ok, String.t()} | {:error, {:missing_config, atom()}}
  defp required(config, key) do
    case Keyword.get(config, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:missing_config, key}}
    end
  end

  @spec validate_bucket(String.t()) :: :ok | {:error, :invalid_bucket}
  defp validate_bucket(bucket) do
    valid? =
      String.match?(bucket, ~r/^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$/) and
        not String.contains?(bucket, "..") and not Regex.match?(~r/^\d+\.\d+\.\d+\.\d+$/, bucket)

    if valid?, do: :ok, else: {:error, :invalid_bucket}
  end

  @spec optional_string(keyword(), atom(), String.t()) ::
          {:ok, String.t()} | {:error, {:invalid_config, atom()}}
  defp optional_string(config, key, default) do
    case Keyword.get(config, key, default) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:invalid_config, key}}
    end
  end

  @spec req_options(keyword()) :: keyword()
  defp req_options(config) do
    configured_options =
      config
      |> Keyword.get(:req_options, [])
      |> Keyword.take(@safe_req_options)

    Keyword.merge(@default_req_options, configured_options)
  end

  @spec endpoint(String.t()) :: {:ok, URI.t()} | {:error, :invalid_endpoint}
  defp endpoint(endpoint) when is_binary(endpoint) do
    uri = URI.parse(endpoint)

    if valid_endpoint?(uri) do
      {:ok, %{uri | path: nil}}
    else
      {:error, :invalid_endpoint}
    end
  end

  defp endpoint(_endpoint), do: {:error, :invalid_endpoint}

  @spec valid_endpoint?(URI.t()) :: boolean()
  defp valid_endpoint?(%URI{} = uri) do
    uri.scheme == "https" and is_binary(uri.host) and uri.host != "" and
      uri.userinfo == nil and uri.path in [nil, "", "/"] and uri.query == nil and
      uri.fragment == nil
  end

  @spec object_url(config(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defp object_url(config, key) do
    path = object_path(config.prefix, key)
    host = "#{config.bucket}.#{config.endpoint.host}"

    {:ok, URI.to_string(%{config.endpoint | host: host, path: path})}
  end

  @spec object_path(String.t() | nil, String.t()) :: String.t()
  defp object_path(prefix, key) do
    segments = prefix_segments(prefix) ++ [key]
    "/" <> Enum.map_join(segments, "/", &encode_path_segment/1)
  end

  @spec prefix_segments(String.t() | nil) :: [String.t()]
  defp prefix_segments(nil), do: []
  defp prefix_segments(prefix), do: String.split(prefix, "/", trim: true)

  @spec normalize_prefix(String.t() | nil | term()) :: String.t() | nil
  defp normalize_prefix(prefix) when is_binary(prefix) do
    prefix
    |> String.trim()
    |> String.trim("/")
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_prefix(_prefix), do: nil

  @spec encode_path_segment(String.t()) :: String.t()
  defp encode_path_segment(segment) do
    URI.encode(segment, fn char -> URI.char_unreserved?(char) or char == ?: end)
  end

  @spec aws_sigv4(config()) :: keyword()
  defp aws_sigv4(config) do
    [
      access_key_id: config.access_key_id,
      secret_access_key: config.secret_access_key,
      region: config.region,
      service: "s3"
    ]
  end

  @spec ttl_headers(keyword()) :: [{String.t(), String.t()}]
  defp ttl_headers(opts) do
    case Keyword.get(opts, :ttl) do
      ttl when is_integer(ttl) and ttl > 0 -> [{@expires_header, expires_at(ttl)}]
      _ttl -> []
    end
  end

  @spec expires_at(pos_integer()) :: String.t()
  defp expires_at(ttl) do
    DateTime.utc_now(:second)
    |> DateTime.add(ttl, :second)
    |> DateTime.to_unix()
    |> Integer.to_string()
  end

  @spec read_body(term()) :: {:ok, binary() | nil}
  defp read_body(response) do
    if expired?(response.headers) do
      {:ok, nil}
    else
      {:ok, response.body}
    end
  end

  @spec expired?(map()) :: boolean()
  defp expired?(headers) do
    case metadata_expires_at(headers) do
      nil -> false
      expires_at -> expires_at <= DateTime.to_unix(DateTime.utc_now(:second))
    end
  end

  @spec metadata_expires_at(map()) :: integer() | nil
  defp metadata_expires_at(headers) do
    headers
    |> Enum.find_value([], fn {name, values} ->
      if String.downcase(to_string(name), :ascii) == @expires_header do
        values
      end
    end)
    |> List.first()
    |> parse_unix_seconds()
  end

  @spec parse_unix_seconds(String.t() | nil) :: integer() | nil
  defp parse_unix_seconds(nil), do: nil

  defp parse_unix_seconds(value) do
    case Integer.parse(value) do
      {seconds, ""} -> seconds
      _invalid -> nil
    end
  end
end

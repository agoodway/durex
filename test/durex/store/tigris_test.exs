defmodule Durex.Store.TigrisTest do
  use ExUnit.Case, async: false

  alias Durex.Store.Tigris

  @base_config [
    bucket: "my-bucket",
    access_key_id: "test-access-key",
    secret_access_key: "test-secret-key"
  ]

  setup do
    previous_config = Application.get_env(:durex, Durex.Store.Tigris)

    on_exit(fn ->
      if previous_config do
        Application.put_env(:durex, Durex.Store.Tigris, previous_config)
      else
        Application.delete_env(:durex, Durex.Store.Tigris)
      end
    end)
  end

  describe "configuration" do
    test "returns an error when all configuration is missing" do
      Application.delete_env(:durex, Durex.Store.Tigris)

      assert {:error, {:missing_config, :bucket}} = Tigris.read("durex:app:mod:k1")
    end

    test "returns an error when required configuration keys are missing" do
      for key <- [:bucket, :access_key_id, :secret_access_key] do
        @base_config
        |> Keyword.delete(key)
        |> Keyword.put(:req_options, adapter: request_adapter())
        |> then(&Application.put_env(:durex, Durex.Store.Tigris, &1))

        assert {:error, {:missing_config, ^key}} = Tigris.read("durex:app:mod:k1")
      end
    end

    test "returns an error when Req is unavailable" do
      Process.put({Durex.Store.Tigris, :req_module}, Durex.Store.TigrisTest.MissingReq)
      on_exit(fn -> Process.delete({Durex.Store.Tigris, :req_module}) end)
      configure(adapter: request_adapter())

      assert {:error, :req_not_available} = Tigris.read("durex:app:mod:k1")
    end

    test "uses default endpoint, region, and no prefix" do
      configure(adapter: request_adapter())

      assert {:ok, ""} = Tigris.read("durex:app:mod:k1")
      assert_receive {:request, request}
      assert request.url.scheme == "https"
      assert request.url.host == "my-bucket.t3.storage.dev"
      assert request.url.path == "/durex:app:mod:k1"
      assert authorization_header(request) =~ "/auto/s3/aws4_request"
      assert request.options[:receive_timeout] == 5_000
      assert request.options[:pool_timeout] == 1_000
    end

    test "rejects invalid buckets" do
      for bucket <- ["BadBucket", "bad/bucket", "bad..bucket", "192.168.0.1"] do
        configure(bucket: bucket, adapter: request_adapter())

        assert {:error, :invalid_bucket} = Tigris.read("durex:app:mod:k1")
      end
    end
  end

  describe "object key prefix normalization" do
    test "prepends a normalized prefix" do
      configure(prefix: "/checkpoints//", adapter: request_adapter())

      assert :ok = Tigris.write("durex:app:mod:k1", "payload")
      assert_receive {:request, request}
      assert request.url.path == "/checkpoints/durex:app:mod:k1"
    end

    test "encodes reserved characters in prefix segments" do
      configure(prefix: "check points/#frag", adapter: request_adapter())

      assert :ok = Tigris.write("k?1", "payload")
      assert_receive {:request, request}
      assert request.url.path == "/check%20points/%23frag/k%3F1"
      assert request.url.query == nil
      assert request.url.fragment == nil
    end
  end

  describe "virtual-hosted URL construction" do
    test "builds custom endpoint URLs with ports" do
      configure(endpoint: "https://objects.example.com:8443", adapter: request_adapter())

      assert :ok = Tigris.delete("durex:app:mod:k1")
      assert_receive {:request, request}

      assert URI.to_string(request.url) ==
               "https://my-bucket.objects.example.com:8443/durex:app:mod:k1"
    end

    test "accepts endpoint trailing slashes" do
      configure(endpoint: "https://objects.example.com/", adapter: request_adapter())

      assert :ok = Tigris.delete("durex:app:mod:k1")
      assert_receive {:request, request}

      assert URI.to_string(request.url) ==
               "https://my-bucket.objects.example.com/durex:app:mod:k1"
    end

    test "rejects non-https endpoints and endpoints with invalid URL parts" do
      invalid_endpoints = [
        "http://objects.example.com",
        "https://objects.example.com/path",
        "https://objects.example.com?x=1",
        "https://objects.example.com#frag",
        "https://user:pass@objects.example.com",
        "objects.example.com"
      ]

      for endpoint <- invalid_endpoints do
        configure(endpoint: endpoint, adapter: request_adapter())
        assert {:error, :invalid_endpoint} = Tigris.delete("key")
      end
    end
  end

  describe "AWS SigV4 request construction" do
    test "signs requests with configured credentials and service s3" do
      configure(region: "auto", adapter: request_adapter())

      assert :ok = Tigris.write("durex:app:mod:k1", "payload")
      assert_receive {:request, request}

      assert request.method == :put
      assert authorization_header(request) =~ "Credential=test-access-key/"
      assert authorization_header(request) =~ "/auto/s3/aws4_request"
    end

    test "includes TTL metadata in signed headers" do
      configure(adapter: request_adapter())

      assert :ok = Tigris.write("space key", "payload", ttl: 60)
      assert_receive {:request, request}

      auth = authorization_header(request)
      assert auth =~ "SignedHeaders="
      assert auth =~ "host"
      assert auth =~ "x-amz-meta-durex-expires-at"
      assert request.url.path == "/space%20key"
    end

    test "does not allow req_options to override request invariants" do
      adapter = request_adapter()

      configure(
        adapter: adapter,
        req_options: [
          method: :delete,
          url: "https://evil.example.com/changed",
          aws_sigv4: nil,
          body: "changed",
          headers: [{"x-amz-meta-durex-expires-at", "1"}],
          retry: true
        ]
      )

      assert :ok = Tigris.write("durex:app:mod:k1", "payload", ttl: 60)
      assert_receive {:request, request}

      assert request.method == :put
      assert request.url.host == "my-bucket.t3.storage.dev"
      assert request.body == "payload"
      assert authorization_header(request) =~ "/auto/s3/aws4_request"
      assert request.options[:retry] == false
    end
  end

  describe "write/3" do
    test "uploads raw payload body" do
      configure(adapter: request_adapter())

      assert :ok = Tigris.write("durex:app:mod:k1", <<0, 1, 2>>)
      assert_receive {:request, request}
      assert request.body == <<0, 1, 2>>
    end

    test "adds TTL expiration metadata" do
      configure(adapter: request_adapter())

      assert :ok = Tigris.write("durex:app:mod:k1", "payload", ttl: 300)
      assert_receive {:request, request}
      [expires_at] = Req.Fields.get_values(request.headers, "x-amz-meta-durex-expires-at")

      assert {seconds, ""} = Integer.parse(expires_at)
      now = DateTime.to_unix(DateTime.utc_now(:second))
      latest = DateTime.utc_now(:second) |> DateTime.add(300, :second) |> DateTime.to_unix()

      assert seconds > now
      assert seconds <= latest
    end

    test "does not add TTL metadata for invalid TTL values" do
      for ttl <- [nil, 0, -1, "60"] do
        configure(adapter: request_adapter())

        assert :ok = Tigris.write("durex:app:mod:k1", "payload", ttl: ttl)
        assert_receive {:request, request}
        assert Req.Fields.get_values(request.headers, "x-amz-meta-durex-expires-at") == []
      end
    end
  end

  describe "read/1" do
    test "returns {:ok, nil} for missing objects" do
      configure(adapter: request_adapter(status: 404))

      assert {:ok, nil} = Tigris.read("durex:app:mod:missing")
    end

    test "returns {:ok, nil} for expired objects" do
      expires_at =
        DateTime.utc_now(:second)
        |> DateTime.add(-1, :second)
        |> DateTime.to_unix()
        |> to_string()

      configure(
        adapter:
          request_adapter(body: "payload", headers: [{"x-amz-meta-durex-expires-at", expires_at}])
      )

      assert {:ok, nil} = Tigris.read("durex:app:mod:k1")
    end

    test "treats expiration metadata equal to now as expired" do
      expires_at = DateTime.utc_now(:second) |> DateTime.to_unix() |> to_string()

      configure(
        adapter:
          request_adapter(body: "payload", headers: [{"x-amz-meta-durex-expires-at", expires_at}])
      )

      assert {:ok, nil} = Tigris.read("durex:app:mod:k1")
    end

    test "matches expiration metadata case-insensitively" do
      expires_at =
        DateTime.utc_now(:second)
        |> DateTime.add(-1, :second)
        |> DateTime.to_unix()
        |> to_string()

      configure(
        adapter:
          request_adapter(body: "payload", headers: [{"X-Amz-Meta-Durex-Expires-At", expires_at}])
      )

      assert {:ok, nil} = Tigris.read("durex:app:mod:k1")
    end

    test "returns raw binaries for unexpired and non-expiring objects" do
      expires_at =
        DateTime.utc_now(:second)
        |> DateTime.add(300, :second)
        |> DateTime.to_unix()
        |> to_string()

      configure(
        adapter:
          request_adapter(
            body: ~s({"json":true}),
            headers: [{"x-amz-meta-durex-expires-at", expires_at}]
          )
      )

      assert {:ok, ~s({"json":true})} = Tigris.read("durex:app:mod:k1")
      assert_receive {:request, request}
      assert request.options[:decode_body] == false

      configure(adapter: request_adapter(body: "plain"))
      assert {:ok, "plain"} = Tigris.read("durex:app:mod:k1")
    end

    test "treats malformed expiration metadata as non-expiring" do
      configure(
        adapter:
          request_adapter(body: "payload", headers: [{"x-amz-meta-durex-expires-at", "bad"}])
      )

      assert {:ok, "payload"} = Tigris.read("durex:app:mod:k1")
    end
  end

  describe "delete/1" do
    test "returns :ok for existing and missing objects" do
      configure(adapter: request_adapter(status: 204))
      assert :ok = Tigris.delete("durex:app:mod:k1")

      configure(adapter: request_adapter(status: 404))
      assert :ok = Tigris.delete("durex:app:mod:missing")
    end
  end

  describe "error handling" do
    test "returns errors for write non-success responses" do
      configure(adapter: request_adapter(status: 500))

      assert {:error, {:unexpected_status, 500}} = Tigris.write("durex:app:mod:k1", "payload")
    end

    test "returns errors for read and delete non-success responses" do
      configure(adapter: request_adapter(status: 403))
      assert {:error, {:unexpected_status, 403}} = Tigris.read("durex:app:mod:k1")

      configure(adapter: request_adapter(status: 500))
      assert {:error, {:unexpected_status, 500}} = Tigris.delete("durex:app:mod:k1")
    end

    test "returns errors for raised request failures" do
      adapter = fn _request -> raise "boom" end
      configure(adapter: adapter)

      assert {:error, %RuntimeError{message: "boom"}} = Tigris.read("durex:app:mod:k1")
    end

    test "returns errors for transport failures" do
      test_pid = self()

      adapter = fn request ->
        send(test_pid, {:request, request})
        {request, %Req.TransportError{reason: :timeout}}
      end

      configure(adapter: adapter)

      assert {:error, %Req.TransportError{reason: :timeout}} = Tigris.read("durex:app:mod:k1")
    end

    test "encodes reserved URL characters in Durex keys" do
      configure(adapter: request_adapter(body: "payload"))

      assert {:ok, "payload"} = Tigris.read("durex:app:mod:k 1?#%/slash")
      assert_receive {:request, request}
      assert request.url.path == "/durex:app:mod:k%201%3F%23%25%2Fslash"
      assert request.url.query == nil
      assert request.url.fragment == nil
    end
  end

  @spec configure(keyword()) :: :ok
  defp configure(opts) do
    {adapter, opts} = Keyword.pop(opts, :adapter, request_adapter())
    {req_options, opts} = Keyword.pop(opts, :req_options, [])

    Application.put_env(
      :durex,
      Durex.Store.Tigris,
      @base_config
      |> Keyword.merge(opts)
      |> Keyword.put(:req_options, Keyword.put(req_options, :adapter, adapter))
    )
  end

  @spec request_adapter(keyword()) :: (Req.Request.t() ->
                                         {Req.Request.t(), Req.Response.t() | Exception.t()})
  defp request_adapter(opts \\ []) do
    test_pid = self()
    status = Keyword.get(opts, :status, 200)
    body = Keyword.get(opts, :body, "")
    headers = Keyword.get(opts, :headers, [])

    fn request ->
      send(test_pid, {:request, request})
      {request, Req.Response.new(status: status, body: body, headers: headers)}
    end
  end

  @spec authorization_header(Req.Request.t()) :: String.t()
  defp authorization_header(request) do
    request.headers
    |> Req.Fields.get_values("authorization")
    |> List.first()
  end
end

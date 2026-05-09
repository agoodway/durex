defmodule Durex.Store.Redis do
  @moduledoc """
  Redis-backed storage backend for Durex using a named Redix connection.

  The host application owns the Redix connection. Configure the connection name:

      config :durex, Durex.Store.Redis,
        connection: MyApp.Redis
  """

  @behaviour Durex.Store

  @compile {:no_warn_undefined, Redix}

  @impl Durex.Store
  @spec write(String.t(), binary(), keyword()) :: :ok | {:error, term()}
  def write(key, payload, opts \\ []) do
    with {:ok, conn} <- connection() do
      command = set_command(key, payload, opts)

      case Redix.command(conn, command) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl Durex.Store
  @spec read(String.t()) :: {:ok, binary() | nil} | {:error, term()}
  def read(key) do
    with {:ok, conn} <- connection() do
      case Redix.command(conn, ["GET", key]) do
        {:ok, nil} -> {:ok, nil}
        {:ok, binary} when is_binary(binary) -> {:ok, binary}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl Durex.Store
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(key) do
    with {:ok, conn} <- connection() do
      case Redix.command(conn, ["DEL", key]) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec set_command(String.t(), binary(), keyword()) :: [String.t() | binary() | integer()]
  defp set_command(key, payload, opts) do
    case Keyword.get(opts, :ttl) do
      nil -> ["SET", key, payload]
      ttl -> ["SET", key, payload, "EX", ttl]
    end
  end

  @spec connection() :: {:ok, atom()} | {:error, :connection_not_configured}
  defp connection do
    config = Application.get_env(:durex, __MODULE__, [])

    case Keyword.fetch(config, :connection) do
      {:ok, name} -> {:ok, name}
      :error -> {:error, :connection_not_configured}
    end
  end
end

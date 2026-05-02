defmodule Durex.Key do
  @moduledoc """
  Builds namespaced checkpoint keys in the format `durex:{app}:{module}:{user_key}`.
  """

  @doc """
  Constructs a checkpoint key from the module and user-provided key.

  The app name is read from `config :durex, :app_name`. The module is split
  into segments, underscored, downcased, and dot-separated.

  Raises `ArgumentError` if `user_key` is not a non-empty binary.

  ## Examples

      iex> Application.put_env(:durex, :app_name, :my_app)
      iex> Durex.Key.build(MyApp.SessionServer, "session_123")
      "durex:my_app:my_app.session_server:session_123"

  """
  @spec build(module(), String.t()) :: String.t()
  def build(module, user_key) when is_binary(user_key) and byte_size(user_key) > 0 do
    app = app_name!()
    mod = format_module(module)

    "durex:#{app}:#{mod}:#{user_key}"
  end

  def build(_module, user_key) do
    raise ArgumentError,
          "checkpoint_key/1 must return a non-empty binary, got: #{inspect(user_key)}"
  end

  @spec app_name!() :: atom()
  defp app_name! do
    case Application.fetch_env(:durex, :app_name) do
      {:ok, name} ->
        name

      :error ->
        raise ArgumentError,
              "missing required config :durex, :app_name — " <>
                "set it in your config.exs (e.g., config :durex, :app_name, :my_app)"
    end
  end

  @spec format_module(module()) :: String.t()
  defp format_module(module) do
    module
    |> Module.split()
    |> Enum.map_join(".", &Macro.underscore/1)
  end
end

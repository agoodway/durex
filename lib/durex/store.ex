defmodule Durex.Store do
  @moduledoc """
  Behaviour for Durex checkpoint storage backends.

  Stores operate on raw binaries (JSON-encoded by Durex core). TTL is passed
  in `opts` — stores that don't support TTL can ignore it.
  """

  @doc """
  Writes a binary payload at the given key.

  The `opts` keyword list may contain `:ttl` (seconds).
  Returns `:ok` or `{:error, reason}`.
  """
  @callback write(key :: String.t(), payload :: binary(), opts :: keyword()) ::
              :ok | {:error, term()}

  @doc """
  Reads a binary payload from the given key.

  Returns `{:ok, binary}` when the key exists, `{:ok, nil}` when it does not,
  or `{:error, reason}` on failure.
  """
  @callback read(key :: String.t()) :: {:ok, binary() | nil} | {:error, term()}

  @doc """
  Removes the given key from the store.

  Deleting a non-existent key returns `:ok`.
  Returns `:ok` or `{:error, reason}`.
  """
  @callback delete(key :: String.t()) :: :ok | {:error, term()}
end

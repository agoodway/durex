defmodule Durex.Checkpoint do
  @moduledoc """
  JSON encoding/decoding with per-module versioning and size guards for checkpoint payloads.

  Payloads are stored in an envelope format: `{"v": <version>, "d": <data>}`.
  This avoids key collisions between versioning metadata and user data.
  """

  require Logger

  @default_max_payload_bytes 1_048_576

  @doc """
  Encodes a map into a JSON envelope with version tag.

  Returns `{:ok, binary}`, `{:error, :payload_too_large}` if the encoded
  payload exceeds the configured max size, or `{:error, :encode_failed}` if
  the data cannot be JSON-encoded.
  """
  @spec encode(map(), pos_integer()) ::
          {:ok, binary()} | {:error, :payload_too_large} | {:error, :encode_failed}
  def encode(data, version) when is_map(data) and is_integer(version) do
    case Jason.encode(%{"v" => version, "d" => data}) do
      {:ok, payload} ->
        max_bytes = max_payload_bytes()

        if byte_size(payload) > max_bytes do
          Logger.warning(
            "[Durex] Checkpoint payload exceeds max size " <>
              "(#{byte_size(payload)} > #{max_bytes} bytes), skipping write"
          )

          {:error, :payload_too_large}
        else
          {:ok, payload}
        end

      {:error, reason} ->
        Logger.warning("[Durex] Failed to JSON-encode checkpoint: #{inspect(reason)}")
        {:error, :encode_failed}
    end
  end

  @doc """
  Decodes a JSON envelope and checks the version tag.

  Returns `{:ok, map}` if version matches, `{:ok, nil}` if version mismatches
  or data is missing/corrupted.
  """
  @spec decode(binary() | nil, pos_integer()) :: {:ok, map() | nil}
  def decode(nil, _version), do: {:ok, nil}

  def decode(binary, version) when is_binary(binary) do
    case Jason.decode(binary) do
      {:ok, %{"v" => ^version, "d" => data}} when is_map(data) ->
        {:ok, data}

      {:ok, %{"v" => stored_version, "d" => _data}} ->
        Logger.warning(
          "[Durex] Version mismatch: stored=#{stored_version}, expected=#{version}. " <>
            "Discarding stale checkpoint."
        )

        {:ok, nil}

      {:ok, _data} ->
        Logger.warning("[Durex] Stored checkpoint has invalid envelope format. Discarding.")
        {:ok, nil}

      {:error, _reason} ->
        Logger.warning("[Durex] Failed to decode checkpoint JSON. Discarding corrupted data.")
        {:ok, nil}
    end
  end

  @doc """
  Decodes a JSON envelope and returns structured conflict reasons instead of `{:ok, nil}`.

  Returns `{:ok, data}` when the version matches and data is valid, or
  `{:conflict, reason}` describing why the checkpoint cannot be used.
  """
  @spec decode_detailed(binary() | nil, pos_integer()) ::
          {:ok, map()} | {:conflict, Durex.restore_conflict_reason()}
  def decode_detailed(nil, _version), do: {:conflict, :missing_checkpoint}

  def decode_detailed(binary, version) when is_binary(binary) do
    case Jason.decode(binary) do
      {:ok, %{"v" => ^version, "d" => data}} when is_map(data) ->
        {:ok, data}

      {:ok, %{"v" => ^version, "d" => _non_map}} = {:ok, decoded} ->
        Logger.warning("[Durex] Stored checkpoint has invalid envelope format. Discarding.")
        {:conflict, {:invalid_envelope, decoded}}

      {:ok, %{"v" => stored_version, "d" => _data}} ->
        Logger.warning(
          "[Durex] Version mismatch: stored=#{stored_version}, expected=#{version}. " <>
            "Discarding stale checkpoint."
        )

        {:conflict, {:version_mismatch, version, stored_version}}

      {:ok, decoded} ->
        Logger.warning("[Durex] Stored checkpoint has invalid envelope format. Discarding.")
        {:conflict, {:invalid_envelope, decoded}}

      {:error, reason} ->
        Logger.warning("[Durex] Failed to decode checkpoint JSON. Discarding corrupted data.")
        {:conflict, {:corrupted_json, reason}}
    end
  end

  @spec max_payload_bytes() :: pos_integer()
  defp max_payload_bytes do
    value = Application.get_env(:durex, :max_payload_bytes, @default_max_payload_bytes)

    unless is_integer(value) and value > 0 do
      raise ArgumentError,
            "config :durex, :max_payload_bytes must be a positive integer, got: #{inspect(value)}"
    end

    value
  end
end

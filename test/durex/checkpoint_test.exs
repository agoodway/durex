defmodule Durex.CheckpointTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Durex.Checkpoint

  setup do
    original = Application.get_env(:durex, :max_payload_bytes)

    on_exit(fn ->
      if original do
        Application.put_env(:durex, :max_payload_bytes, original)
      else
        Application.delete_env(:durex, :max_payload_bytes)
      end
    end)

    :ok
  end

  describe "encode/2" do
    test "encodes map to JSON envelope with version" do
      {:ok, payload} = Checkpoint.encode(%{"count" => 42}, 1)
      decoded = Jason.decode!(payload)

      assert decoded["v"] == 1
      assert decoded["d"] == %{"count" => 42}
    end

    test "does not merge version into user data" do
      {:ok, payload} = Checkpoint.encode(%{"v" => "user_value"}, 1)
      decoded = Jason.decode!(payload)

      assert decoded["v"] == 1
      assert decoded["d"]["v"] == "user_value"
    end

    test "returns error when payload exceeds size limit" do
      Application.put_env(:durex, :max_payload_bytes, 10)

      {result, _log} =
        with_log(fn ->
          Checkpoint.encode(%{"data" => String.duplicate("x", 100)}, 1)
        end)

      assert result == {:error, :payload_too_large}
    end

    test "returns error for non-JSON-encodable data" do
      {result, log} =
        with_log(fn ->
          Checkpoint.encode(%{"pid" => self()}, 1)
        end)

      assert result == {:error, :encode_failed}
      assert log =~ "Failed to JSON-encode"
    end

    test "uses default 1MB limit" do
      data = %{"small" => "value"}
      assert {:ok, _} = Checkpoint.encode(data, 1)
    end

    test "raises on invalid max_payload_bytes config" do
      Application.put_env(:durex, :max_payload_bytes, "1mb")

      assert_raise ArgumentError, ~r/must be a positive integer/, fn ->
        Checkpoint.encode(%{"a" => 1}, 1)
      end
    end
  end

  describe "decode/2" do
    test "decodes valid envelope with matching version" do
      payload = Jason.encode!(%{"v" => 1, "d" => %{"count" => 42}})
      assert {:ok, %{"count" => 42}} = Checkpoint.decode(payload, 1)
    end

    test "returns user data without envelope keys" do
      payload = Jason.encode!(%{"v" => 1, "d" => %{"key" => "val"}})
      {:ok, data} = Checkpoint.decode(payload, 1)
      refute Map.has_key?(data, "v")
      assert data == %{"key" => "val"}
    end

    test "returns nil for version mismatch" do
      payload = Jason.encode!(%{"v" => 1, "d" => %{"count" => 42}})

      {result, log} =
        with_log(fn ->
          Checkpoint.decode(payload, 2)
        end)

      assert result == {:ok, nil}
      assert log =~ "Version mismatch"
    end

    test "returns nil for invalid envelope format" do
      payload = Jason.encode!(%{"count" => 42})

      {result, log} =
        with_log(fn ->
          Checkpoint.decode(payload, 1)
        end)

      assert result == {:ok, nil}
      assert log =~ "invalid envelope"
    end

    test "returns nil for corrupted JSON" do
      {result, log} =
        with_log(fn ->
          Checkpoint.decode("not json{{{", 1)
        end)

      assert result == {:ok, nil}
      assert log =~ "Failed to decode"
    end

    test "returns nil for nil input" do
      assert {:ok, nil} = Checkpoint.decode(nil, 1)
    end
  end
end

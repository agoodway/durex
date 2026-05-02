defmodule Durex.Store.RedisTest do
  use ExUnit.Case, async: false

  alias Durex.Store.Redis

  setup do
    conn_name = :"durex_redis_store_test_#{System.unique_integer([:positive])}"
    {:ok, conn} = Redix.start_link(name: conn_name)
    Application.put_env(:durex, Durex.Store.Redis, connection: conn_name)

    test_key = "durex:test:redis:#{System.unique_integer([:positive])}"

    on_exit(fn ->
      if Process.alive?(conn) do
        Redix.command(conn, ["DEL", test_key])
        GenServer.stop(conn)
      end
    end)

    %{test_key: test_key, conn_name: conn_name}
  end

  describe "write/3" do
    test "writes a binary payload", %{test_key: key} do
      assert :ok = Redis.write(key, "hello")
    end

    test "writes with TTL", %{test_key: key, conn_name: conn_name} do
      assert :ok = Redis.write(key, "hello", ttl: 60)

      {:ok, ttl} = Redix.command(conn_name, ["TTL", key])
      assert ttl > 0 and ttl <= 60
    end
  end

  describe "read/1" do
    test "returns {:ok, nil} for missing key" do
      assert {:ok, nil} = Redis.read("durex:test:redis:nonexistent_#{System.unique_integer()}")
    end

    test "returns {:ok, binary} for existing key", %{test_key: key} do
      :ok = Redis.write(key, "stored_value")
      assert {:ok, "stored_value"} = Redis.read(key)
    end
  end

  describe "delete/1" do
    test "deletes an existing key", %{test_key: key} do
      :ok = Redis.write(key, "to_delete")
      assert :ok = Redis.delete(key)
      assert {:ok, nil} = Redis.read(key)
    end

    test "returns :ok for non-existent key" do
      assert :ok = Redis.delete("durex:test:redis:nonexistent_#{System.unique_integer()}")
    end
  end
end

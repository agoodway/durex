defmodule Durex.IntegrationTest do
  use ExUnit.Case, async: false

  alias Durex.Store

  import ExUnit.CaptureLog

  defmodule TestServer do
    @moduledoc false
    use GenServer
    use Durex, store: Durex.Store.Redis, interval: 5_000, ttl: 60, version: 1

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    @impl GenServer
    def init(opts) do
      state = %{user_id: opts[:user_id], counter: 0}
      state = Durex.start_sync(__MODULE__, state)

      case Durex.maybe_restore(__MODULE__, state) do
        {:ok, nil} -> {:ok, state}
        {:ok, restored} -> {:ok, Map.merge(state, restored)}
      end
    end

    @impl GenServer
    def handle_call(:get_state, _from, state) do
      {:reply, Map.delete(state, :__durex__), state}
    end

    @impl GenServer
    def handle_call(:get_full_state, _from, state) do
      {:reply, state, state}
    end

    @impl GenServer
    def handle_call({:set_counter, n}, _from, state) do
      {:reply, :ok, %{state | counter: n}}
    end

    @impl GenServer
    def handle_call(:trigger_sync, _from, state) do
      Durex.checkpoint(__MODULE__, state)
      {:reply, :ok, state}
    end

    @impl GenServer
    def terminate(_reason, state) do
      Durex.checkpoint(__MODULE__, state)
    end

    @impl Durex
    def serialize(state), do: Map.take(state, [:user_id, :counter])

    @impl Durex
    def deserialize(data) do
      Map.new(data, fn {k, v} -> {String.to_existing_atom(k), v} end)
    end

    @impl Durex
    def checkpoint_key(state), do: state.user_id
  end

  defmodule TestServerTigris do
    @moduledoc false
    use GenServer
    use Durex, store: Durex.Store.Tigris, interval: 5_000, ttl: 60, version: 1

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    @impl GenServer
    def init(opts) do
      state = %{user_id: opts[:user_id], counter: 0}
      state = Durex.start_sync(__MODULE__, state)

      case Durex.maybe_restore(__MODULE__, state) do
        {:ok, nil} -> {:ok, state}
        {:ok, restored} -> {:ok, Map.merge(state, restored)}
      end
    end

    @impl GenServer
    def handle_call(:get_state, _from, state) do
      {:reply, Map.delete(state, :__durex__), state}
    end

    @impl GenServer
    def handle_call(:get_full_state, _from, state) do
      {:reply, state, state}
    end

    @impl GenServer
    def handle_call({:set_counter, n}, _from, state) do
      {:reply, :ok, %{state | counter: n}}
    end

    @impl GenServer
    def handle_call(:trigger_sync, _from, state) do
      Durex.checkpoint(__MODULE__, state)
      {:reply, :ok, state}
    end

    @impl Durex
    def serialize(state), do: Map.take(state, [:user_id, :counter])

    @impl Durex
    def deserialize(data) do
      Map.new(data, fn {k, v} -> {String.to_existing_atom(k), v} end)
    end

    @impl Durex
    def checkpoint_key(state), do: state.user_id
  end

  defmodule FailingStore do
    @moduledoc false
    @behaviour Durex.Store

    @impl Durex.Store
    def write(_key, _payload, _opts), do: {:error, :connection_refused}

    @impl Durex.Store
    def read(_key), do: {:error, :timeout}

    @impl Durex.Store
    def delete(_key), do: {:error, :connection_refused}
  end

  defmodule FailingServer do
    @moduledoc false
    use GenServer
    use Durex, store: Durex.IntegrationTest.FailingStore, interval: 5_000, ttl: 60, version: 1

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    @impl GenServer
    def init(opts) do
      state = %{user_id: opts[:user_id], counter: 0}
      state = Durex.start_sync(__MODULE__, state)

      case Durex.maybe_restore(__MODULE__, state) do
        {:ok, nil} -> {:ok, state}
        {:ok, restored} -> {:ok, Map.merge(state, restored)}
      end
    end

    @impl GenServer
    def handle_call(:get_state, _from, state) do
      {:reply, Map.delete(state, :__durex__), state}
    end

    @impl GenServer
    def terminate(_reason, state) do
      Durex.checkpoint(__MODULE__, state)
    end

    @impl Durex
    def serialize(state), do: Map.take(state, [:user_id, :counter])

    @impl Durex
    def deserialize(data) do
      Map.new(data, fn {k, v} -> {String.to_existing_atom(k), v} end)
    end

    @impl Durex
    def checkpoint_key(state), do: state.user_id
  end

  defmodule NonEncodableServer do
    @moduledoc false
    use GenServer
    use Durex, store: Durex.Store.Redis, interval: 5_000, ttl: 60, version: 1

    def start_link(arg) do
      GenServer.start_link(__MODULE__, arg)
    end

    @impl GenServer
    def init(_), do: {:ok, Durex.start_sync(__MODULE__, %{data: "x"})}

    @impl GenServer
    def handle_call(:checkpoint, _from, state) do
      result = Durex.checkpoint(__MODULE__, state)
      {:reply, result, state}
    end

    @impl Durex
    def serialize(_state), do: %{"pid" => self()}

    @impl Durex
    def deserialize(data), do: data

    @impl Durex
    def checkpoint_key(_state), do: "test"
  end

  defmodule RecoveringStore do
    @moduledoc false
    @behaviour Durex.Store

    @impl Durex.Store
    def write(key, payload, _opts) do
      Agent.update(__MODULE__, &Map.put(&1, key, payload))
      :ok
    end

    @impl Durex.Store
    def read(key) do
      case Agent.get(__MODULE__, &Map.get(&1, key)) do
        nil -> {:ok, nil}
        data -> {:ok, data}
      end
    end

    @impl Durex.Store
    def delete(key) do
      Agent.update(__MODULE__, &Map.delete(&1, key))
      :ok
    end
  end

  defmodule RecoveringServer do
    @moduledoc false
    use GenServer
    use Durex, store: Durex.IntegrationTest.RecoveringStore, interval: 5_000, version: 1

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    @impl GenServer
    def init(opts) do
      state = %{user_id: opts[:user_id], counter: 0}
      state = Durex.start_sync(__MODULE__, state)

      case Durex.maybe_restore(__MODULE__, state) do
        {:ok, nil} -> {:ok, state}
        {:ok, restored} -> {:ok, Map.merge(state, restored)}
      end
    end

    @impl GenServer
    def handle_call(:get_state, _from, state) do
      {:reply, Map.delete(state, :__durex__), state}
    end

    @impl Durex
    def restore_conflicted(:missing_checkpoint, _key, _opts), do: %{counter: 99}

    def restore_conflicted({:version_mismatch, _expected, _actual}, _key, _opts),
      do: %{counter: 77}

    def restore_conflicted({:invalid_envelope, _decoded}, _key, _opts), do: %{counter: 66}
    def restore_conflicted({:corrupted_json, _reason}, _key, _opts), do: %{counter: 55}
    def restore_conflicted({:store_read_error, _reason}, _key, _opts), do: %{counter: 44}

    @impl Durex
    def serialize(state), do: Map.take(state, [:user_id, :counter])

    @impl Durex
    def deserialize(data) do
      Map.new(data, fn {k, v} -> {String.to_existing_atom(k), v} end)
    end

    @impl Durex
    def checkpoint_key(state), do: state.user_id
  end

  defmodule NilRecoveringServer do
    @moduledoc false
    use GenServer
    use Durex, store: Durex.IntegrationTest.RecoveringStore, interval: 5_000, version: 1

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl GenServer
    def init(opts) do
      state = %{user_id: opts[:user_id], counter: 0}
      state = Durex.start_sync(__MODULE__, state)

      case Durex.maybe_restore(__MODULE__, state) do
        {:ok, nil} -> {:ok, state}
        {:ok, restored} -> {:ok, Map.merge(state, restored)}
      end
    end

    @impl GenServer
    def handle_call(:get_state, _from, state) do
      {:reply, Map.delete(state, :__durex__), state}
    end

    @impl Durex
    def restore_conflicted(_reason, _key, _opts), do: nil

    @impl Durex
    def serialize(state), do: Map.take(state, [:user_id, :counter])

    @impl Durex
    def deserialize(data) do
      Map.new(data, fn {k, v} -> {String.to_existing_atom(k), v} end)
    end

    @impl Durex
    def checkpoint_key(state), do: state.user_id
  end

  defmodule BadReturnServer do
    @moduledoc false
    use GenServer
    use Durex, store: Durex.IntegrationTest.RecoveringStore, interval: 5_000, version: 1

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl GenServer
    def init(opts) do
      state = %{user_id: opts[:user_id], counter: 0}
      state = Durex.start_sync(__MODULE__, state)

      case Durex.maybe_restore(__MODULE__, state) do
        {:ok, nil} -> {:ok, state}
        {:ok, restored} -> {:ok, Map.merge(state, restored)}
      end
    end

    @impl Durex
    def restore_conflicted(_reason, _key, _opts), do: :bad_value

    @impl Durex
    def serialize(state), do: Map.take(state, [:user_id, :counter])

    @impl Durex
    def deserialize(data) do
      Map.new(data, fn {k, v} -> {String.to_existing_atom(k), v} end)
    end

    @impl Durex
    def checkpoint_key(state), do: state.user_id
  end

  defmodule RecoveringFailingServer do
    @moduledoc false
    use GenServer
    use Durex, store: Durex.IntegrationTest.FailingStore, interval: 5_000, version: 1

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl GenServer
    def init(opts) do
      state = %{user_id: opts[:user_id], counter: 0}
      state = Durex.start_sync(__MODULE__, state)

      case Durex.maybe_restore(__MODULE__, state) do
        {:ok, nil} -> {:ok, state}
        {:ok, restored} -> {:ok, Map.merge(state, restored)}
      end
    end

    @impl GenServer
    def handle_call(:get_state, _from, state) do
      {:reply, Map.delete(state, :__durex__), state}
    end

    @impl Durex
    def restore_conflicted({:store_read_error, _reason}, _key, _opts), do: %{counter: 44}
    def restore_conflicted(_reason, _key, _opts), do: nil

    @impl Durex
    def serialize(state), do: Map.take(state, [:user_id, :counter])

    @impl Durex
    def deserialize(data) do
      Map.new(data, fn {k, v} -> {String.to_existing_atom(k), v} end)
    end

    @impl Durex
    def checkpoint_key(state), do: state.user_id
  end

  defmodule TestServerV2 do
    @moduledoc false
    use GenServer
    use Durex, store: Durex.Store.Redis, interval: 5_000, ttl: 60, version: 2

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    @impl GenServer
    def init(opts) do
      state = %{user_id: opts[:user_id], counter: 0}
      state = Durex.start_sync(__MODULE__, state)

      case Durex.maybe_restore(__MODULE__, state) do
        {:ok, nil} -> {:ok, state}
        {:ok, restored} -> {:ok, Map.merge(state, restored)}
      end
    end

    @impl GenServer
    def handle_call(:get_state, _from, state) do
      {:reply, Map.delete(state, :__durex__), state}
    end

    @impl Durex
    def serialize(state), do: Map.take(state, [:user_id, :counter])

    @impl Durex
    def deserialize(data) do
      Map.new(data, fn {k, v} -> {String.to_existing_atom(k), v} end)
    end

    @impl Durex
    def checkpoint_key(state), do: state.user_id
  end

  setup do
    conn_name = :"durex_integration_#{System.unique_integer([:positive])}"
    {:ok, conn} = Redix.start_link(name: conn_name)
    Application.put_env(:durex, Durex.Store.Redis, connection: conn_name)
    Application.put_env(:durex, :app_name, :durex_test)

    on_exit(fn ->
      if Process.alive?(conn) do
        {:ok, keys} = Redix.command(conn, ["KEYS", "durex:durex_test:*"])
        if keys != [], do: Redix.command(conn, ["DEL" | keys])
        GenServer.stop(conn)
      end
    end)

    %{conn: conn, conn_name: conn_name}
  end

  describe "full lifecycle" do
    test "init restores nil, sync writes checkpoint, restore returns data" do
      user_id = "lifecycle_#{System.unique_integer([:positive])}"
      {:ok, pid} = TestServer.start_link(user_id: user_id)

      state = GenServer.call(pid, :get_state)
      assert state.counter == 0

      GenServer.call(pid, {:set_counter, 42})
      GenServer.call(pid, :trigger_sync)

      GenServer.stop(pid)

      {:ok, pid2} = TestServer.start_link(user_id: user_id)
      state2 = GenServer.call(pid2, :get_state)
      assert state2.counter == 42

      GenServer.stop(pid2)
    end
  end

  describe "tigris lifecycle" do
    test "checkpoint, restore, and delete use the Tigris store contract" do
      {:ok, object_store} = Agent.start_link(fn -> %{} end)

      Application.put_env(:durex, Durex.Store.Tigris,
        bucket: "my-bucket",
        access_key_id: "test-access-key",
        secret_access_key: "test-secret-key",
        req_options: [adapter: tigris_adapter(object_store)]
      )

      user_id = "tigris_#{System.unique_integer([:positive])}"
      {:ok, pid} = TestServerTigris.start_link(user_id: user_id)

      GenServer.call(pid, {:set_counter, 42})
      GenServer.call(pid, :trigger_sync)

      full_state = GenServer.call(pid, :get_full_state)
      GenServer.stop(pid)

      {:ok, pid2} = TestServerTigris.start_link(user_id: user_id)
      state2 = GenServer.call(pid2, :get_state)
      assert state2.counter == 42
      GenServer.stop(pid2)

      assert :ok = Durex.delete(TestServerTigris, full_state)

      {:ok, pid3} = TestServerTigris.start_link(user_id: user_id)
      state3 = GenServer.call(pid3, :get_state)
      assert state3.counter == 0
      GenServer.stop(pid3)

      Agent.stop(object_store)
    end
  end

  describe "handle_info(:__durex_sync__)" do
    test "updates timer_ref and last_checkpoint_at in state" do
      user_id = "sync_state_#{System.unique_integer([:positive])}"
      {:ok, pid} = TestServer.start_link(user_id: user_id)

      full_state = GenServer.call(pid, :get_full_state)
      assert full_state.__durex__.last_checkpoint_at == nil
      initial_ref = full_state.__durex__.timer_ref
      assert is_reference(initial_ref)

      # Trigger the sync via the actual handle_info path
      send(pid, :__durex_sync__)
      _ = GenServer.call(pid, :get_state)

      updated_state = GenServer.call(pid, :get_full_state)
      assert is_integer(updated_state.__durex__.last_checkpoint_at)
      assert is_reference(updated_state.__durex__.timer_ref)
      assert updated_state.__durex__.timer_ref != initial_ref

      GenServer.stop(pid)
    end
  end

  describe "graceful degradation" do
    test "store errors don't crash GenServer" do
      user_id = "failing_#{System.unique_integer([:positive])}"

      log =
        capture_log(fn ->
          {:ok, pid} = FailingServer.start_link(user_id: user_id)

          state = GenServer.call(pid, :get_state)
          assert state.counter == 0

          send(pid, :__durex_sync__)
          _ = GenServer.call(pid, :get_state)

          assert Process.alive?(pid)

          GenServer.stop(pid)
        end)

      assert log =~ "Checkpoint write failed"
    end

    test "checkpoint with non-encodable state logs and returns :ok" do
      {:ok, pid} = NonEncodableServer.start_link(:ok)

      log =
        capture_log(fn ->
          assert :ok = GenServer.call(pid, :checkpoint)
        end)

      assert log =~ "Failed to JSON-encode"

      GenServer.stop(pid)
    end
  end

  describe "version mismatch" do
    test "old checkpoint ignored after version bump via maybe_restore", %{conn_name: conn_name} do
      user_id = "version_#{System.unique_integer([:positive])}"

      # Write a v1 checkpoint under TestServerV2's key
      key = Durex.Key.build(TestServerV2, user_id)
      payload = Jason.encode!(%{"v" => 1, "d" => %{"user_id" => user_id, "counter" => 99}})
      Redix.command(conn_name, ["SET", key, payload])

      log =
        capture_log(fn ->
          {:ok, pid} = TestServerV2.start_link(user_id: user_id)
          state = GenServer.call(pid, :get_state)
          assert state.counter == 0
          GenServer.stop(pid)
        end)

      assert log =~ "Version mismatch"
    end
  end

  describe "terminate checkpoint" do
    test "final write on shutdown" do
      user_id = "terminate_#{System.unique_integer([:positive])}"
      {:ok, pid} = TestServer.start_link(user_id: user_id)

      GenServer.call(pid, {:set_counter, 77})
      GenServer.stop(pid)

      {:ok, pid2} = TestServer.start_link(user_id: user_id)
      state = GenServer.call(pid2, :get_state)
      assert state.counter == 77

      GenServer.stop(pid2)
    end
  end

  describe "delete" do
    test "checkpoint key is removed via Durex.delete/2" do
      user_id = "delete_#{System.unique_integer([:positive])}"
      {:ok, pid} = TestServer.start_link(user_id: user_id)

      GenServer.call(pid, {:set_counter, 55})
      GenServer.call(pid, :trigger_sync)

      full_state = GenServer.call(pid, :get_full_state)
      GenServer.stop(pid)

      assert :ok = Durex.delete(TestServer, full_state)

      {:ok, pid2} = TestServer.start_link(user_id: user_id)
      state2 = GenServer.call(pid2, :get_state)
      assert state2.counter == 0

      GenServer.stop(pid2)
    end

    test "store errors return :ok" do
      log =
        capture_log(fn ->
          result = Durex.delete(FailingServer, %{user_id: "test"})
          assert result == :ok
        end)

      assert log =~ "Checkpoint delete failed"
    end
  end

  describe "start_sync" do
    test "stashes correct bookkeeping in state" do
      user_id = "start_sync_#{System.unique_integer([:positive])}"
      {:ok, pid} = TestServer.start_link(user_id: user_id)

      full_state = GenServer.call(pid, :get_full_state)
      durex = full_state.__durex__

      assert durex.interval == 5_000
      assert is_reference(durex.timer_ref)
      assert durex.last_checkpoint_at == nil

      GenServer.stop(pid)
    end

    test "raises if called twice" do
      assert_raise ArgumentError, ~r/already contains :__durex__/, fn ->
        state = %{user_id: "test"}
        state = Durex.start_sync(TestServer, state)
        Durex.start_sync(TestServer, state)
      end
    end
  end

  describe "connection not configured" do
    test "store returns error when connection config is missing" do
      Application.put_env(:durex, Durex.Store.Redis, [])

      assert {:error, :connection_not_configured} = Store.Redis.read("some_key")
      assert {:error, :connection_not_configured} = Store.Redis.write("some_key", "val")
      assert {:error, :connection_not_configured} = Store.Redis.delete("some_key")
    end
  end

  describe "restore_conflicted callback" do
    setup do
      {:ok, _} = Agent.start_link(fn -> %{} end, name: RecoveringStore)

      on_exit(fn ->
        try do
          if Process.whereis(RecoveringStore), do: Agent.stop(RecoveringStore)
        catch
          :exit, _ -> :ok
        end
      end)

      :ok
    end

    test "callback recovers from missing checkpoint" do
      user_id = "recover_missing_#{System.unique_integer([:positive])}"

      {:ok, pid} = RecoveringServer.start_link(user_id: user_id)
      state = GenServer.call(pid, :get_state)
      assert state.counter == 99
      GenServer.stop(pid)
    end

    test "callback recovers from version mismatch" do
      user_id = "recover_version_#{System.unique_integer([:positive])}"
      key = Durex.Key.build(RecoveringServer, user_id)
      payload = Jason.encode!(%{"v" => 999, "d" => %{"user_id" => user_id, "counter" => 1}})
      Agent.update(RecoveringStore, &Map.put(&1, key, payload))

      log =
        capture_log(fn ->
          {:ok, pid} = RecoveringServer.start_link(user_id: user_id)
          state = GenServer.call(pid, :get_state)
          assert state.counter == 77
          GenServer.stop(pid)
        end)

      assert log =~ "Version mismatch"
    end

    test "callback recovers from invalid envelope" do
      user_id = "recover_envelope_#{System.unique_integer([:positive])}"
      key = Durex.Key.build(RecoveringServer, user_id)
      payload = Jason.encode!(%{"bad" => "envelope"})
      Agent.update(RecoveringStore, &Map.put(&1, key, payload))

      log =
        capture_log(fn ->
          {:ok, pid} = RecoveringServer.start_link(user_id: user_id)
          state = GenServer.call(pid, :get_state)
          assert state.counter == 66
          GenServer.stop(pid)
        end)

      assert log =~ "invalid envelope"
    end

    test "callback recovers from corrupted JSON" do
      user_id = "recover_json_#{System.unique_integer([:positive])}"
      key = Durex.Key.build(RecoveringServer, user_id)
      Agent.update(RecoveringStore, &Map.put(&1, key, "not valid json{{{"))

      log =
        capture_log(fn ->
          {:ok, pid} = RecoveringServer.start_link(user_id: user_id)
          state = GenServer.call(pid, :get_state)
          assert state.counter == 55
          GenServer.stop(pid)
        end)

      assert log =~ "Failed to decode"
    end

    test "callback nil returns preserve {:ok, nil}" do
      user_id = "nil_recover_#{System.unique_integer([:positive])}"

      {:ok, pid} = NilRecoveringServer.start_link(user_id: user_id)
      state = GenServer.call(pid, :get_state)
      assert state.counter == 0
      GenServer.stop(pid)
    end

    test "callback recovers from store read errors" do
      user_id = "recover_store_#{System.unique_integer([:positive])}"

      log =
        capture_log(fn ->
          {:ok, pid} = RecoveringFailingServer.start_link(user_id: user_id)
          state = GenServer.call(pid, :get_state)
          assert state.counter == 44
          GenServer.stop(pid)
        end)

      assert log =~ "Checkpoint read failed"
    end

    test "non-map non-nil callback returns raise ArgumentError" do
      user_id = "bad_return_#{System.unique_integer([:positive])}"
      Process.flag(:trap_exit, true)

      {:error, {%ArgumentError{message: msg}, _}} =
        BadReturnServer.start_link(user_id: user_id)

      assert msg =~ "must return a map or nil"
    end

    test "callback receives fully built key and [] opts" do
      defmodule KeyCapturingServer do
        @moduledoc false
        use GenServer
        use Durex, store: Durex.IntegrationTest.RecoveringStore, interval: 5_000, version: 1

        def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

        @impl GenServer
        def init(opts) do
          state = %{user_id: opts[:user_id], counter: 0, captured: nil}
          state = Durex.start_sync(__MODULE__, state)

          case Durex.maybe_restore(__MODULE__, state) do
            {:ok, nil} -> {:ok, state}
            {:ok, restored} -> {:ok, Map.merge(state, restored)}
          end
        end

        @impl GenServer
        def handle_call(:get_state, _from, state) do
          {:reply, Map.delete(state, :__durex__), state}
        end

        @impl Durex
        def restore_conflicted(reason, key, opts) do
          # Store in process dictionary so we can verify
          Process.put(:captured_args, {reason, key, opts})
          nil
        end

        @impl Durex
        def serialize(state), do: Map.take(state, [:user_id, :counter])

        @impl Durex
        def deserialize(data) do
          Map.new(data, fn {k, v} -> {String.to_existing_atom(k), v} end)
        end

        @impl Durex
        def checkpoint_key(state), do: state.user_id
      end

      user_id = "key_capture_#{System.unique_integer([:positive])}"
      expected_key = Durex.Key.build(KeyCapturingServer, user_id)

      {:ok, pid} = KeyCapturingServer.start_link(user_id: user_id)

      # Verify the key is properly built with module namespace and user_id
      assert expected_key =~ user_id
      assert expected_key =~ "durex:"

      GenServer.stop(pid)
    end
  end

  describe "backward compatibility" do
    test "modules without custom restore_conflicted/3 still work" do
      user_id = "compat_#{System.unique_integer([:positive])}"
      {:ok, pid} = TestServer.start_link(user_id: user_id)

      state = GenServer.call(pid, :get_state)
      assert state.counter == 0
      GenServer.stop(pid)
    end
  end

  describe "telemetry with restore_conflicted" do
    setup do
      {:ok, _} = Agent.start_link(fn -> %{} end, name: RecoveringStore)

      on_exit(fn ->
        try do
          if Process.whereis(RecoveringStore), do: Agent.stop(RecoveringStore)
        catch
          :exit, _ -> :ok
        end
      end)

      :ok
    end

    test "emits [:durex, :restore, :ok] with found: false for recovered conflicts" do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:durex, :restore, :ok]
        ])

      user_id = "telemetry_recover_#{System.unique_integer([:positive])}"
      {:ok, pid} = RecoveringServer.start_link(user_id: user_id)

      assert_received {[:durex, :restore, :ok], ^ref, %{},
                       %{module: RecoveringServer, found: false}}

      GenServer.stop(pid)
    end

    test "emits [:durex, :restore, :failed] for store errors with recovery" do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:durex, :restore, :failed]
        ])

      user_id = "telemetry_store_#{System.unique_integer([:positive])}"

      log =
        capture_log(fn ->
          {:ok, pid} = RecoveringFailingServer.start_link(user_id: user_id)

          assert_received {[:durex, :restore, :failed], ^ref, %{},
                           %{module: RecoveringFailingServer, reason: :timeout}}

          GenServer.stop(pid)
        end)

      assert log =~ "Checkpoint read failed"
    end
  end

  @spec tigris_adapter(Agent.agent()) :: (Req.Request.t() -> {Req.Request.t(), Req.Response.t()})
  defp tigris_adapter(object_store) do
    fn request ->
      {request, tigris_response(object_store, request)}
    end
  end

  @spec tigris_response(Agent.agent(), Req.Request.t()) :: Req.Response.t()
  defp tigris_response(object_store, %{method: :put} = request) do
    headers = Req.Fields.get_list(request.headers)
    Agent.update(object_store, &Map.put(&1, request.url.path, {request.body, headers}))
    Req.Response.new(status: 200)
  end

  defp tigris_response(object_store, %{method: :get} = request) do
    object_store
    |> Agent.get(&Map.get(&1, request.url.path))
    |> tigris_get_response()
  end

  defp tigris_response(object_store, %{method: :delete} = request) do
    Agent.update(object_store, &Map.delete(&1, request.url.path))
    Req.Response.new(status: 204)
  end

  @spec tigris_get_response({binary(), [{String.t(), String.t()}]} | nil) :: Req.Response.t()
  defp tigris_get_response(nil), do: Req.Response.new(status: 404)

  defp tigris_get_response({body, headers}),
    do: Req.Response.new(status: 200, body: body, headers: headers)
end

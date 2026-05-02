defmodule Durex do
  @moduledoc """
  GenServer state checkpointing to external stores.

  Durex extracts crash recovery and node-migration resilience into a reusable
  package with a macro-based API, pluggable storage backends, and built-in
  graceful degradation.

  ## Usage

      defmodule MyApp.SessionServer do
        use GenServer
        use Durex, store: Durex.Store.Redis, interval: 30_000, ttl: 300, version: 1

        def init(args) do
          state = %{session_id: args[:session_id], data: %{}}
          state = Durex.start_sync(__MODULE__, state)

          case Durex.maybe_restore(__MODULE__, state) do
            {:ok, nil} -> {:ok, state}
            {:ok, restored} -> {:ok, Map.merge(state, restored)}
          end
        end

        def terminate(_reason, state) do
          Durex.checkpoint(__MODULE__, state)
        end

        # Callbacks
        @impl Durex
        def serialize(state), do: Map.take(state, [:session_id, :data])

        @impl Durex
        def deserialize(data), do: data

        @impl Durex
        def checkpoint_key(state), do: state.session_id
      end

  ## State Constraint

  State must be a map. The `__durex__` key is reserved for internal bookkeeping
  and is automatically excluded from serialization. The `checkpoint_key/1`
  callback also receives state with `__durex__` stripped.

  ## Deserialization Note

  JSON round-tripping converts atom keys to strings. Your `deserialize/1`
  callback must handle this. Use `String.to_existing_atom/1` (never
  `String.to_atom/1`) to convert keys back safely.

  ## Telemetry Events

  Durex emits the following telemetry events:

  - `[:durex, :checkpoint, :write]` — successful checkpoint write.
    Measurements: `%{duration: native_time}`. Metadata: `%{module: module}`.
  - `[:durex, :checkpoint, :write_failed]` — checkpoint write failed.
    Metadata: `%{module: module, reason: term}`.
  - `[:durex, :checkpoint, :skipped]` — checkpoint skipped (payload too large or encode failed).
    Metadata: `%{module: module, reason: :payload_too_large | :encode_failed}`.
  - `[:durex, :restore, :ok]` — successful restore.
    Metadata: `%{module: module, found: boolean}`.
  - `[:durex, :restore, :failed]` — restore failed.
    Metadata: `%{module: module, reason: term}`.
  """

  require Logger

  @doc """
  Serializes the GenServer state into a map for storage.

  The `__durex__` key is stripped before this callback is invoked.
  """
  @callback serialize(state :: map()) :: map()

  @doc """
  Deserializes stored data back into a form suitable for merging into state.

  Note: JSON round-tripping converts atom keys to strings. Use
  `String.to_existing_atom/1` to safely convert keys back.
  """
  @callback deserialize(data :: map()) :: map()

  @doc """
  Returns a string key identifying this specific process instance.

  Receives state with `__durex__` already stripped. Must return a non-empty binary.
  """
  @callback checkpoint_key(state :: map()) :: String.t()

  defmacro __using__(opts) do
    store = Keyword.get(opts, :store) || raise ArgumentError, "use Durex requires :store option"
    interval = Keyword.get(opts, :interval, 30_000)
    ttl = Keyword.get(opts, :ttl, nil)
    version = Keyword.get(opts, :version, 1)

    if ttl != nil and (not is_integer(ttl) or ttl < 1) do
      raise ArgumentError,
            "use Durex :ttl must be a positive integer or nil, got: #{inspect(ttl)}"
    end

    if not is_integer(interval) or interval < 1 do
      raise ArgumentError,
            "use Durex :interval must be a positive integer, got: #{inspect(interval)}"
    end

    if not is_integer(version) or version < 1 do
      raise ArgumentError,
            "use Durex :version must be a positive integer, got: #{inspect(version)}"
    end

    quote do
      @behaviour Durex

      @__durex_store__ unquote(store)
      @__durex_interval__ unquote(interval)
      @__durex_ttl__ unquote(ttl)
      @__durex_version__ unquote(version)

      @doc false
      @spec __durex_config__() :: keyword()
      def __durex_config__ do
        [
          store: @__durex_store__,
          interval: @__durex_interval__,
          ttl: @__durex_ttl__,
          version: @__durex_version__
        ]
      end

      @doc false
      @impl GenServer
      def handle_info(:__durex_sync__, %{__durex__: _} = state) do
        Durex.checkpoint(__MODULE__, state)

        interval = __durex_config__()[:interval]
        timer_ref = Process.send_after(self(), :__durex_sync__, interval)

        state = put_in(state[:__durex__][:timer_ref], timer_ref)

        state =
          put_in(state[:__durex__][:last_checkpoint_at], System.monotonic_time(:millisecond))

        {:noreply, state}
      end
    end
  end

  @doc """
  Starts periodic sync by stashing bookkeeping in state and scheduling the first timer.

  Must be called from within a module that `use Durex`.

  ## Example

      state = Durex.start_sync(__MODULE__, state)

  """
  @spec start_sync(module(), map()) :: map()
  def start_sync(module, state) when is_map(state) do
    if Map.has_key?(state, :__durex__) do
      raise ArgumentError,
            "Durex.start_sync/2 called but state already contains :__durex__ key. " <>
              "Avoid calling start_sync more than once."
    end

    config = module.__durex_config__()
    interval = config[:interval]
    timer_ref = Process.send_after(self(), :__durex_sync__, interval)

    Map.put(state, :__durex__, %{
      interval: interval,
      timer_ref: timer_ref,
      last_checkpoint_at: nil
    })
  end

  @doc """
  Writes a checkpoint of the current state to the configured store.

  Strips the `__durex__` key, calls `serialize/1`, encodes with versioning,
  and writes to the store. Always returns `:ok` — store errors are logged
  and swallowed.

  Emits `[:durex, :checkpoint, :write]` on success,
  `[:durex, :checkpoint, :write_failed]` on store error, and
  `[:durex, :checkpoint, :skipped]` when payload is too large or encode fails.
  """
  @spec checkpoint(module(), map()) :: :ok
  def checkpoint(module, state) when is_map(state) do
    config = module.__durex_config__()
    store = config[:store]
    version = config[:version]
    ttl = config[:ttl]

    clean_state = strip_durex(state)
    serialized = module.serialize(clean_state)
    key = Durex.Key.build(module, module.checkpoint_key(clean_state))

    case Durex.Checkpoint.encode(serialized, version) do
      {:ok, payload} ->
        opts = if ttl, do: [ttl: ttl], else: []
        start_time = System.monotonic_time()

        case store.write(key, payload, opts) do
          :ok ->
            duration = System.monotonic_time() - start_time

            :telemetry.execute(
              [:durex, :checkpoint, :write],
              %{duration: duration},
              %{module: module}
            )

            :ok

          {:error, reason} ->
            Logger.warning("[Durex] Checkpoint write failed: #{inspect(reason)}")

            :telemetry.execute(
              [:durex, :checkpoint, :write_failed],
              %{},
              %{module: module, reason: reason}
            )

            :ok
        end

      {:error, reason} ->
        :telemetry.execute(
          [:durex, :checkpoint, :skipped],
          %{},
          %{module: module, reason: reason}
        )

        :ok
    end
  end

  @doc """
  Attempts to restore a checkpoint from the configured store.

  Returns `{:ok, deserialized_data}` if a valid checkpoint exists, or
  `{:ok, nil}` if no checkpoint is found, version mismatches, or a store
  error occurs.

  Emits `[:durex, :restore, :ok]` on success (with `found: true/false`),
  `[:durex, :restore, :failed]` on store error.
  """
  @spec maybe_restore(module(), map()) :: {:ok, map() | nil}
  def maybe_restore(module, state) when is_map(state) do
    config = module.__durex_config__()
    store = config[:store]
    version = config[:version]

    clean_state = strip_durex(state)
    key = Durex.Key.build(module, module.checkpoint_key(clean_state))

    case store.read(key) do
      {:ok, nil} ->
        :telemetry.execute([:durex, :restore, :ok], %{}, %{module: module, found: false})
        {:ok, nil}

      {:ok, binary} ->
        case Durex.Checkpoint.decode(binary, version) do
          {:ok, nil} ->
            :telemetry.execute([:durex, :restore, :ok], %{}, %{module: module, found: false})
            {:ok, nil}

          {:ok, data} ->
            :telemetry.execute([:durex, :restore, :ok], %{}, %{module: module, found: true})
            {:ok, module.deserialize(data)}
        end

      {:error, reason} ->
        Logger.warning("[Durex] Checkpoint read failed: #{inspect(reason)}")

        :telemetry.execute(
          [:durex, :restore, :failed],
          %{},
          %{module: module, reason: reason}
        )

        {:ok, nil}
    end
  end

  @doc """
  Deletes the checkpoint for the given module and state from the configured store.

  Always returns `:ok` — store errors are logged and swallowed.
  """
  @spec delete(module(), map()) :: :ok
  def delete(module, state) when is_map(state) do
    config = module.__durex_config__()
    store = config[:store]

    clean_state = strip_durex(state)
    key = Durex.Key.build(module, module.checkpoint_key(clean_state))

    case store.delete(key) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("[Durex] Checkpoint delete failed: #{inspect(reason)}")
        :ok
    end
  end

  @spec strip_durex(map()) :: map()
  defp strip_durex(state) when is_map(state) do
    Map.delete(state, :__durex__)
  end
end

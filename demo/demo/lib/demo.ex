defmodule Demo do
  @moduledoc """
  Interactive demo of Durex GenServer checkpointing with the Tigris store.

  Walks through the full lifecycle: start, modify state, checkpoint,
  crash, restore, and delete.
  """

  @spec run() :: :ok
  def run do
    header("Durex Tigris Store Demo")

    step(1, "Attaching telemetry handlers")
    Demo.TelemetryLogger.attach()

    step(2, "Starting CounterServer (first run — no checkpoint exists)")
    {:ok, pid} = Demo.CounterServer.start_link(id: "demo-1")
    print_state(pid)

    step(3, "Modifying state — incrementing counter 3 times")

    for i <- 1..3 do
      GenServer.call(pid, :increment)
      IO.puts("  Increment #{i}:")
      print_state(pid)
    end

    step(4, "Writing checkpoint to Tigris")
    GenServer.call(pid, :manual_checkpoint)

    step(5, "Simulating a crash (Process.exit :kill — no terminate/2 fires)")
    Process.flag(:trap_exit, true)
    Process.exit(pid, :kill)

    receive do
      {:EXIT, ^pid, :killed} -> IO.puts("  Process #{inspect(pid)} killed.")
    after
      1_000 -> IO.puts("  Timeout waiting for exit signal.")
    end

    step(6, "Restarting CounterServer — restoring state from Tigris")
    {:ok, pid2} = Demo.CounterServer.start_link(id: "demo-1")
    print_state(pid2)

    step(7, "Incrementing once more to prove continuity")
    GenServer.call(pid2, :increment)
    print_state(pid2)

    step(8, "Deleting checkpoint from Tigris")
    GenServer.call(pid2, :delete_checkpoint)
    IO.puts("  Checkpoint deleted.")

    step(9, "Stopping server cleanly")
    GenServer.stop(pid2)
    IO.puts("  Server stopped.")

    header("Demo complete")
    :ok
  end

  @spec header(String.t()) :: :ok
  defp header(text) do
    bar = String.duplicate("=", String.length(text) + 6)
    IO.puts("\n#{IO.ANSI.bright()}#{bar}")
    IO.puts("   #{text}")
    IO.puts("#{bar}#{IO.ANSI.reset()}\n")
  end

  @spec step(pos_integer(), String.t()) :: :ok
  defp step(n, description) do
    IO.puts("\n#{IO.ANSI.bright()}--- Step #{n}: #{description}#{IO.ANSI.reset()}\n")
    Process.sleep(300)
  end

  @spec print_state(pid()) :: :ok
  defp print_state(pid) do
    state = GenServer.call(pid, :get_state)
    IO.puts("  State: #{inspect(state, pretty: true)}")
  end
end

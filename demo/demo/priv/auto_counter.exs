Demo.TelemetryLogger.attach()

IO.puts("\n#{IO.ANSI.bright()}=== Durex Auto Counter Demo ===#{IO.ANSI.reset()}")
IO.puts("  Auto-increments every second, checkpoints to Tigris every 10s.")
IO.puts("  Kill with Ctrl-C, then restart to see state restored.\n")

{:ok, _pid} = Demo.AutoCounter.start_link(id: "auto-counter-1")

Process.sleep(:infinity)

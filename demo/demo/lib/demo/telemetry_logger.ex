defmodule Demo.TelemetryLogger do
  @moduledoc """
  Attaches to Durex telemetry events and prints formatted output.
  """

  @events [
    [:durex, :checkpoint, :write],
    [:durex, :checkpoint, :write_failed],
    [:durex, :checkpoint, :skipped],
    [:durex, :restore, :ok],
    [:durex, :restore, :failed]
  ]

  @spec attach() :: :ok
  def attach do
    :telemetry.attach_many("demo-durex-logger", @events, &handle_event/4, nil)
  end

  @spec handle_event([atom()], map(), map(), nil) :: :ok
  def handle_event([:durex, :checkpoint, :write], measurements, _metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    print(:green, "CHECKPOINT WRITTEN", "duration=#{duration_ms}ms")
  end

  def handle_event([:durex, :checkpoint, :write_failed], _measurements, metadata, _config) do
    print(:red, "CHECKPOINT FAILED", "reason=#{inspect(metadata.reason)}")
  end

  def handle_event([:durex, :checkpoint, :skipped], _measurements, metadata, _config) do
    print(:yellow, "CHECKPOINT SKIPPED", "reason=#{inspect(metadata.reason)}")
  end

  def handle_event([:durex, :restore, :ok], _measurements, metadata, _config) do
    if metadata.found do
      print(:green, "STATE RESTORED", "checkpoint found in Tigris")
    else
      print(:cyan, "NO CHECKPOINT", "starting fresh")
    end
  end

  def handle_event([:durex, :restore, :failed], _measurements, metadata, _config) do
    print(:red, "RESTORE FAILED", "reason=#{inspect(metadata.reason)}")
  end

  @spec print(atom(), String.t(), String.t()) :: :ok
  defp print(color, label, detail) do
    IO.puts(apply(IO.ANSI, color, []) <> "  [telemetry] #{label}: #{detail}" <> IO.ANSI.reset())
  end
end

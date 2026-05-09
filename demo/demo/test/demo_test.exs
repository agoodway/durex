defmodule DemoTest do
  use ExUnit.Case, async: true

  test "CounterServer module is defined" do
    assert Code.ensure_loaded?(Demo.CounterServer)
  end
end

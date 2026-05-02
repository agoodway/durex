defmodule Durex.KeyTest do
  use ExUnit.Case, async: false

  doctest Durex.Key

  setup do
    original = Application.get_env(:durex, :app_name)

    on_exit(fn ->
      if original do
        Application.put_env(:durex, :app_name, original)
      else
        Application.delete_env(:durex, :app_name)
      end
    end)

    :ok
  end

  describe "build/2" do
    test "constructs namespaced key" do
      Application.put_env(:durex, :app_name, :my_app)

      assert Durex.Key.build(MyApp.SessionServer, "session_123") ==
               "durex:my_app:my_app.session_server:session_123"
    end

    test "handles deeply nested modules" do
      Application.put_env(:durex, :app_name, :test_app)

      assert Durex.Key.build(Foo.Bar.BazQux, "key1") ==
               "durex:test_app:foo.bar.baz_qux:key1"
    end

    test "handles single-segment modules" do
      Application.put_env(:durex, :app_name, :test_app)

      assert Durex.Key.build(Worker, "w1") ==
               "durex:test_app:worker:w1"
    end

    test "raises when app_name is not configured" do
      Application.delete_env(:durex, :app_name)

      assert_raise ArgumentError, ~r/missing required config :durex, :app_name/, fn ->
        Durex.Key.build(SomeModule, "key")
      end
    end

    test "raises when user_key is empty" do
      Application.put_env(:durex, :app_name, :test_app)

      assert_raise ArgumentError, ~r/must return a non-empty binary/, fn ->
        Durex.Key.build(SomeModule, "")
      end
    end

    test "raises when user_key is not a binary" do
      Application.put_env(:durex, :app_name, :test_app)

      assert_raise ArgumentError, ~r/must return a non-empty binary/, fn ->
        Durex.Key.build(SomeModule, nil)
      end
    end
  end
end

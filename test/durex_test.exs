defmodule DurexTest do
  use ExUnit.Case

  describe "behaviour" do
    test "defines serialize/1, deserialize/1, checkpoint_key/1 callbacks" do
      callbacks = Durex.behaviour_info(:callbacks)
      assert {:serialize, 1} in callbacks
      assert {:deserialize, 1} in callbacks
      assert {:checkpoint_key, 1} in callbacks
    end
  end

  describe "use Durex" do
    test "raises without :store option" do
      assert_raise ArgumentError, ~r/requires :store option/, fn ->
        defmodule NoStore do
          use GenServer
          use Durex
        end
      end
    end

    test "raises with invalid TTL" do
      assert_raise ArgumentError, ~r/:ttl must be a positive integer/, fn ->
        defmodule BadTTL do
          use GenServer
          use Durex, store: Durex.Store.Redis, ttl: 0
        end
      end
    end

    test "raises with invalid interval" do
      assert_raise ArgumentError, ~r/:interval must be a positive integer/, fn ->
        defmodule BadInterval do
          use GenServer
          use Durex, store: Durex.Store.Redis, interval: -1
        end
      end
    end

    test "raises with invalid version" do
      assert_raise ArgumentError, ~r/:version must be a positive integer/, fn ->
        defmodule BadVersion do
          use GenServer
          use Durex, store: Durex.Store.Redis, version: 0
        end
      end
    end
  end
end

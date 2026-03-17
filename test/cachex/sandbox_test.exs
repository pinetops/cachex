defmodule Cachex.SandboxTest do
  use ExUnit.Case, async: false

  setup_all do
    {:ok, _} = Cachex.start_link(:sandbox_test_cache)
    {:ok, _} = Cachex.Sandbox.start([:sandbox_test_cache], pool_size: 2)
    on_exit(fn -> Cachex.Sandbox.stop() end)
    :ok
  end

  describe "checkout/checkin" do
    test "checkout returns instance map" do
      caches = Cachex.Sandbox.checkout()
      assert is_map(caches)
      assert Map.has_key?(caches, :sandbox_test_cache)
      Cachex.Sandbox.checkin(caches)
    end

    test "checked out caches start empty" do
      caches = Cachex.Sandbox.checkout()
      assert Cachex.get(:sandbox_test_cache, "key") == nil
      Cachex.Sandbox.checkin(caches)
    end
  end

  describe "transparent resolution" do
    test "Cachex calls resolve to sandbox instance" do
      # Put data in the real cache
      Cachex.put(:sandbox_test_cache, "key", "real_value")
      assert Cachex.get(:sandbox_test_cache, "key") == "real_value"

      # Checkout sandbox — should be clean
      caches = Cachex.Sandbox.checkout()
      assert Cachex.get(:sandbox_test_cache, "key") == nil

      # Put in sandbox
      Cachex.put(:sandbox_test_cache, "key", "sandbox_value")
      assert Cachex.get(:sandbox_test_cache, "key") == "sandbox_value"

      # Checkin — real cache still has original value
      Cachex.Sandbox.checkin(caches)
      assert Cachex.get(:sandbox_test_cache, "key") == "real_value"
    end

    test "writes don't leak between checkouts" do
      caches = Cachex.Sandbox.checkout()
      Cachex.put(:sandbox_test_cache, "leaked", "value")
      Cachex.Sandbox.checkin(caches)

      caches = Cachex.Sandbox.checkout()
      assert Cachex.get(:sandbox_test_cache, "leaked") == nil
      Cachex.Sandbox.checkin(caches)
    end
  end
end

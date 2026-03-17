defmodule Cachex.Sandbox.Case do
  @moduledoc """
  ExUnit case template for automatic Cachex test isolation.

  ## Usage

      use ExUnit.Case, async: true
      use Cachex.Sandbox.Case

      test "clean cache per test" do
        Cachex.put(:my_cache, "key", "value")
        # Other concurrent tests don't see this
      end

      test "no stale data" do
        assert {:ok, nil} = Cachex.get(:my_cache, "key")
      end

  The sandbox is activated transparently — `Cachex.get(:my_cache, key)`
  resolves to a per-test instance automatically.
  """

  use ExUnit.CaseTemplate

  setup do
    if Process.whereis(Cachex.Sandbox) do
      caches = Cachex.Sandbox.checkout()
      on_exit(fn -> Cachex.Sandbox.checkin(caches) end)
      %{caches: caches}
    else
      :ok
    end
  end
end

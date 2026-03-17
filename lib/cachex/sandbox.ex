defmodule Cachex.Sandbox do
  @moduledoc """
  Test isolation for Cachex — each test gets its own clean cache instance.

  Works like `Ecto.Adapters.SQL.Sandbox` — application code doesn't change.
  `Cachex.get(:my_cache, key)` transparently resolves to a per-test instance.

  ## Setup

      # test/test_helper.exs
      Cachex.Sandbox.start([:my_cache, :other_cache])

  ## Usage

      use Cachex.Sandbox.Case

      test "isolated cache" do
        # Cachex.get(:my_cache, key) uses a clean, dedicated instance
        Cachex.put(:my_cache, "key", "value")
      end

      test "no leaks from previous test" do
        assert {:ok, nil} = Cachex.get(:my_cache, "key")
      end

  ## How it works

  `start/1` creates a pool of Cachex instances for each cache name.
  `Cachex.Sandbox.Case` checks out an instance set per test, sets
  `Process.put({:cachex_sandbox, name}, instance)` which
  `Cachex.Services.Overseer.lookup/1` uses to transparently resolve
  cache calls to the test's instance.
  """

  use GenServer

  @doc """
  Starts the sandbox pool. Call once in test_helper.exs.

  Options:
    * `:pool_size` — instances per cache name (default: `System.schedulers_online()`)
  """
  def start(cache_names, opts \\ []) do
    pool_size = Keyword.get(opts, :pool_size, System.schedulers_online())
    GenServer.start_link(__MODULE__, {cache_names, pool_size}, name: __MODULE__)
  end

  @doc "Stops the pool."
  def stop do
    if Process.whereis(__MODULE__), do: GenServer.stop(__MODULE__)
  end

  @doc """
  Checks out a set of clean Cachex instances and activates them for
  the current process. Returns `%{name => instance_name}`.

  After checkout, `Cachex.get(name, key)` in this process transparently
  resolves to the checked-out instance.
  """
  def checkout(timeout \\ 5_000) do
    caches = GenServer.call(__MODULE__, :checkout, timeout)

    for {name, instance} <- caches do
      Process.put({:cachex_sandbox, name}, instance)
    end

    caches
  end

  @doc """
  Returns instances to the pool and clears the process sandbox mappings.
  """
  def checkin(caches) do
    for {name, _instance} <- caches do
      Process.delete({:cachex_sandbox, name})
    end

    GenServer.call(__MODULE__, {:checkin, caches})
  end

  # GenServer

  @impl true
  def init({cache_names, pool_size}) do
    instances =
      for i <- 1..pool_size do
        for name <- cache_names, into: %{} do
          instance_name = :"#{name}_sandbox_#{i}"
          {:ok, _} = Cachex.start_link(instance_name)
          {name, instance_name}
        end
      end

    {:ok, %{available: instances, waiting: :queue.new()}}
  end

  @impl true
  def handle_call(:checkout, _from, %{available: [instance | rest]} = state) do
    clear_all(instance)
    {:reply, instance, %{state | available: rest}}
  end

  def handle_call(:checkout, from, %{available: []} = state) do
    waiting = :queue.in(from, state.waiting)
    {:noreply, %{state | waiting: waiting}}
  end

  def handle_call({:checkin, caches}, _from, state) do
    case :queue.out(state.waiting) do
      {{:value, waiter}, waiting} ->
        clear_all(caches)
        GenServer.reply(waiter, caches)
        {:reply, :ok, %{state | waiting: waiting}}

      {:empty, _} ->
        {:reply, :ok, %{state | available: [caches | state.available]}}
    end
  end

  defp clear_all(instance_map) do
    for {_name, instance} <- instance_map, do: Cachex.clear(instance)
  end
end

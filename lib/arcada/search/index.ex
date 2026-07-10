defmodule Arcada.Search.Index do
  @moduledoc """
  In-memory index for semantic search (issue #27): a public ETS table of
  `{summary_id, act_id, vector}`, loaded from the DB on boot and kept fresh on
  write (`Arcada.Summarizer.embed_summary/1`). No pgvector — brute-force
  cosine over this table is plenty at this scale (low thousands of rows).

  Also owns a small LRU cache of `query text -> embedding`, since the
  debounced search box re-sends overlapping queries as the user types.

  ## Concurrency (issue #69)

  The embeddings HTTP call runs in the **caller's** process, not inside this
  GenServer: a single serializing process meant one slow/hung embeddings
  request blocked every concurrent search, and queued callers hit the
  `GenServer.call` timeout — an *exit* that crashed the visitor's LiveView.

  This process now only does fast, non-blocking bookkeeping: the public ETS
  caches (read lock-free by callers) and a **bounded concurrency semaphore**.
  A caller acquires a slot (O(1) call), embeds over the network itself, then
  releases. When the box is saturated a caller degrades to `{:error, :busy}`
  instead of queueing. Slots are tied to the holder via a monitor, so a caller
  that is killed mid-request (e.g. `Task.shutdown` on a search timeout) frees
  its slot instead of wedging the pool.
  """
  use GenServer
  require Logger

  import Ecto.Query

  alias Arcada.Repo
  alias Arcada.Register.Summary
  alias Arcada.Summarizer.Embeddings

  @table __MODULE__
  @cache Module.concat(__MODULE__, Cache)
  @cache_limit 200
  @default_max_concurrent 8

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Every indexed `{summary_id, act_id, vector}` row."
  def all, do: :ets.tab2list(@table)

  @doc "Test helper: empty the index. Never called by the app itself."
  def clear, do: :ets.delete_all_objects(@table)

  @doc "(Re)index one summary's embedding — called after it's generated/regenerated."
  def put(summary_id, act_id, vector), do: :ets.insert(@table, {summary_id, act_id, vector})

  @doc """
  (Re)load every summary embedding from the DB. Runs as a plain query in the
  *caller's* process (no GenServer round-trip), so tests can call it directly
  right after seeding fixtures, and a boot-time failure (DB/sandbox not ready)
  can't wedge the index for the rest of the process's life.
  """
  def reload do
    from(s in Summary, where: not is_nil(s.embedding), select: {s.id, s.act_id, s.embedding})
    |> Repo.all()
    |> Enum.each(fn {id, act_id, vector} -> put(id, act_id, vector) end)
  end

  @doc """
  Embed `query` for search, through the bounded LRU cache. `cfg` is the
  effective `Arcada.Summarizer.Embeddings` config (`Arcada.Admin.embeddings_config/0`).

  Returns `{:ok, vector}`, `{:error, reason}` from the embeddings server, or
  `{:error, :busy}` when the bounded embed concurrency is saturated — callers
  treat any error as "no semantic leg" and degrade to FTS-only.
  """
  def embed_query(query, cfg) do
    case cache_lookup(query) do
      {:ok, vector} ->
        GenServer.cast(__MODULE__, {:touch, query})
        {:ok, vector}

      :error ->
        embed_uncached(query, cfg)
    end
  end

  # Cache miss: take a concurrency slot, then do the network embed *here* (the
  # caller's process) so a slow request never blocks the shared GenServer.
  defp embed_uncached(query, cfg) do
    case GenServer.call(__MODULE__, :acquire) do
      :busy ->
        {:error, :busy}

      {:ok, ref} ->
        try do
          do_embed(query, cfg)
        after
          GenServer.cast(__MODULE__, {:release, ref})
        end
    end
  end

  defp do_embed(query, cfg) do
    # Another caller may have filled the cache while we waited for a slot.
    case cache_lookup(query) do
      {:ok, vector} ->
        {:ok, vector}

      :error ->
        prefixed = (cfg[:query_prefix] || "") <> query

        case Embeddings.embed([prefixed], cfg) do
          {:ok, [vector]} ->
            :ets.insert(@cache, {query, vector})
            GenServer.cast(__MODULE__, {:remember, query})
            {:ok, vector}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp cache_lookup(query) do
    case :ets.lookup(@cache, query) do
      [{^query, vector}] -> {:ok, vector}
      [] -> :error
    end
  end

  defp max_concurrent do
    Application.get_env(:arcada, __MODULE__, [])[:max_concurrent_embeds] ||
      @default_max_concurrent
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@cache, [:set, :named_table, :public, read_concurrency: true])

    try do
      reload()
    rescue
      e -> Logger.warning("Search index boot load skipped: #{Exception.message(e)}")
    end

    {:ok, %{order: [], slots: %{}}}
  end

  @impl true
  def handle_call(:acquire, {pid, _tag}, %{slots: slots} = state) do
    if map_size(slots) < max_concurrent() do
      ref = Process.monitor(pid)
      {:reply, {:ok, ref}, %{state | slots: Map.put(slots, ref, pid)}}
    else
      {:reply, :busy, state}
    end
  end

  @impl true
  def handle_cast({:release, ref}, state), do: {:noreply, free_slot(state, ref)}
  def handle_cast({:remember, query}, state), do: {:noreply, remember(state, query)}
  def handle_cast({:touch, query}, state), do: {:noreply, bump(state, query)}

  # A slot holder died (killed mid-embed, e.g. Task.shutdown on a search
  # timeout). Free its slot so the pool doesn't leak capacity.
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {:noreply, free_slot(state, ref)}
  end

  defp free_slot(%{slots: slots} = state, ref) do
    case Map.pop(slots, ref) do
      {nil, _} ->
        state

      {_pid, rest} ->
        Process.demonitor(ref, [:flush])
        %{state | slots: rest}
    end
  end

  # LRU bookkeeping. Vectors live in the `@cache` ETS table (read lock-free by
  # callers); `order` tracks recency and drives eviction. A new entry
  # (`remember`) or a cache hit (`bump`) moves the query to the front; over the
  # limit we evict the tail from ETS too.
  defp remember(state, query) do
    trim(%{state | order: [query | List.delete(state.order, query)]})
  end

  defp bump(state, query) do
    if query in state.order do
      %{state | order: [query | List.delete(state.order, query)]}
    else
      state
    end
  end

  defp trim(%{order: order} = state) do
    if length(order) > @cache_limit do
      {keep, drop} = Enum.split(order, @cache_limit)
      Enum.each(drop, &:ets.delete(@cache, &1))
      %{state | order: keep}
    else
      state
    end
  end
end

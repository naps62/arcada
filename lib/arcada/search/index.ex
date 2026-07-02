defmodule Arcada.Search.Index do
  @moduledoc """
  In-memory index for semantic search (issue #27): a public ETS table of
  `{summary_id, act_id, vector}`, loaded from the DB on boot and kept fresh on
  write (`Arcada.Summarizer.embed_summary/1`). No pgvector — brute-force
  cosine over this table is plenty at this scale (low thousands of rows).

  Also owns a small LRU cache of `query text -> embedding`, since the
  debounced search box re-sends overlapping queries as the user types.
  """
  use GenServer
  require Logger

  import Ecto.Query

  alias Arcada.Repo
  alias Arcada.Register.Summary
  alias Arcada.Summarizer.Embeddings

  @table __MODULE__
  @cache_limit 200

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
  """
  def embed_query(query, cfg), do: GenServer.call(__MODULE__, {:embed_query, query, cfg}, 30_000)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])

    try do
      reload()
    rescue
      e -> Logger.warning("Search index boot load skipped: #{Exception.message(e)}")
    end

    {:ok, %{cache: %{}, order: []}}
  end

  @impl true
  def handle_call({:embed_query, query, cfg}, _from, state) do
    case Map.fetch(state.cache, query) do
      {:ok, vector} -> {:reply, {:ok, vector}, remember(state, query, vector)}
      :error -> do_embed(query, cfg, state)
    end
  end

  defp do_embed(query, cfg, state) do
    prefixed = (cfg[:query_prefix] || "") <> query

    case Embeddings.embed([prefixed], cfg) do
      {:ok, [vector]} -> {:reply, {:ok, vector}, remember(state, query, vector)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  # Most-recently-used first; trims the tail once over `@cache_limit`.
  defp remember(state, query, vector) do
    cache = Map.put(state.cache, query, vector)
    order = [query | List.delete(state.order, query)]

    if length(order) > @cache_limit do
      {keep, drop} = Enum.split(order, @cache_limit)
      %{cache: Map.drop(cache, drop), order: keep}
    else
      %{cache: cache, order: order}
    end
  end
end

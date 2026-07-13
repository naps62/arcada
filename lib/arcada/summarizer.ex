defmodule Arcada.Summarizer do
  @moduledoc """
  Produces 🤖 summaries for acts. Dispatches to an adapter by the
  `Provider` kind (`:anthropic | :openai | :ssh`) and writes via an **async path**
  (an Oban job, never inline with the scrape). The active provider+model
  (`Arcada.Admin`) drives auto-summarize; manual runs pass an explicit one.
  """

  alias Arcada.Repo
  alias Arcada.Admin
  alias Arcada.Providers.Provider
  alias Arcada.Register
  alias Arcada.Register.{Act, Summary}
  alias Arcada.Search.Index
  alias Arcada.Summarizer.{Embeddings, Extractor, PlainText, Prompt, SummarizeWorker, TextBudget}

  require Logger
  alias Arcada.Summarizer.Adapters.{Api, OpenAI, Ssh}

  # Provider kind → adapter module.
  @adapters %{anthropic: Api, openai: OpenAI, ssh: Ssh}

  # The shared system prompt + output shape + reply parsing now live in
  # `Arcada.Summarizer.Prompt` — adapters build on it directly. Text budgeting /
  # section ranking lives in `Arcada.Summarizer.TextBudget`.

  @doc """
  Effective **safety cap** (chars) on act text fed to the summarizer prompt — the
  overflow ceiling. Pass the target `model` for the adaptive per-model default
  (larger context → larger cap); omit it for the conservative default window.
  """
  def max_text_chars(model \\ nil), do: Admin.max_text_chars(model)

  @doc """
  Effective **cost target** (chars): the budget the embeddings ranker trims an act
  down to (operative sections in, annexes out), even when the act fits under the
  safety cap. Much smaller than `max_text_chars/1` — the cap is the ceiling, this
  is the target (issue #41). Falls back to the cap when unset, so callers without
  ranking behave exactly as before.
  """
  def target_text_chars(model \\ nil), do: Admin.target_text_chars(model)

  @doc """
  Prepare act text for the summarizer prompt, capped at `max_chars` (the
  configured cap by default). Thin convenience over `TextBudget.prepare/4` that
  drops the strategy; the actual budget/ranking logic lives in
  `Arcada.Summarizer.TextBudget`.

  May perform a network call to the embeddings server; intended for the async
  summarize job, not request paths.
  """
  def prepare_text(text, max_chars \\ nil),
    do: TextBudget.prepare(PlainText.from_html(text), max_chars || max_text_chars()) |> elem(0)

  @doc "The adapter module for a provider kind (`:anthropic | :openai | :ssh`)."
  def adapter_for(kind) when is_atom(kind), do: Map.fetch!(@adapters, kind)

  @doc """
  Enqueue an async summarization job. With no opts it uses the active
  provider+model; pass `provider_id:`/`model:` for a manual run on a specific one,
  and `text_strategy:` (`:rank | :truncate | :auto`) to force how an oversized
  act's text is prepared (for the per-act ranking comparison).

  Job-level opts (used by `SummarySweeper` to drain the backlog gently):

    * `priority:` — Oban priority (`0` highest). The sweeper enqueues backlog
      summaries at a low priority so freshly-ingested daily acts jump ahead.
    * `unique: true` — dedupe on `act_id` while a job for that act is still
      pending/running, so repeated sweeper ticks never pile duplicates onto the
      same act. Manual/daily enqueues omit it (regeneration is allowed).
  """
  def enqueue(act, opts \\ [])
  def enqueue(%Act{id: id}, opts), do: enqueue(id, opts)

  def enqueue(act_id, opts) when is_integer(act_id) do
    %{act_id: act_id}
    |> put_opt(opts, :provider_id)
    |> put_opt(opts, :model)
    |> put_opt(opts, :text_strategy)
    |> SummarizeWorker.new(job_opts(opts))
    |> Oban.insert()
  end

  defp put_opt(args, opts, key) do
    case Keyword.get(opts, key) do
      nil -> args
      v -> Map.put(args, to_string(key), v)
    end
  end

  # Translate caller opts into Oban job options.
  defp job_opts(opts) do
    []
    |> maybe_priority(opts)
    |> maybe_unique(opts)
  end

  defp maybe_priority(job_opts, opts) do
    case Keyword.get(opts, :priority) do
      nil -> job_opts
      priority -> Keyword.put(job_opts, :priority, priority)
    end
  end

  # Dedupe against any not-yet-finished job for the same act. `period: :infinity`
  # + the non-terminal state filter means uniqueness lasts exactly as long as a
  # job for that act is still in flight, not a fixed time window.
  defp maybe_unique(job_opts, opts) do
    if Keyword.get(opts, :unique) do
      Keyword.put(job_opts, :unique,
        keys: [:act_id],
        period: :infinity,
        states: [:available, :scheduled, :executing, :retryable]
      )
    else
      job_opts
    end
  end

  @doc """
  Summarize `act` with the **active** provider+model and persist the result.
  `{:async, :no_active_provider}` if none is configured (acts wait for a manual
  run or a configured active provider).
  """
  def summarize(%Act{} = act) do
    case Admin.active_provider() do
      %Provider{} = provider -> pin_first(act, summarize(act, provider, Admin.active_model()))
      nil -> {:async, :no_active_provider}
    end
  end

  # Automated path only: a new act's first summary becomes the canonical one so a
  # later regeneration can't silently replace it (public pages otherwise show the
  # newest generated). No-op once the act is already pinned — that's what lets a
  # backfill create unpinned candidates for review. Manual per-act runs
  # (`summarize/4`) don't pin; the admin publishes those explicitly.
  defp pin_first(%Act{id: id}, {:ok, %Summary{id: sid}} = result) do
    Register.pin_summary_if_unset(id, sid)
    result
  end

  defp pin_first(_act, result), do: result

  @doc """
  Summarize `act` with a specific provider + model; persist linked to the
  provider. `opts[:text_strategy]` (`:auto` default) forces how an oversized act
  is prepared. The text is prepared here (once) and handed to the adapter, which
  only talks to its backend — the cap/ranking decision lives in one place.
  """
  def summarize(%Act{} = act, %Provider{} = provider, model, opts \\ []) do
    model = model || List.first(provider.models)
    requested = opts |> Keyword.get(:text_strategy, :auto) |> normalize_strategy()
    clean = PlainText.from_html(act.full_text) || act.title

    {text, strategy} =
      TextBudget.prepare(clean, max_text_chars(model), requested, target_text_chars(model))

    # Only ranking actually uses the embedder; record which one preprocessed it.
    ranker_model = if strategy == :rank, do: Embeddings.model(Admin.embeddings_config())

    cond do
      # Force rank: never persist an auto head-truncated summary — its text is just
      # the opening, which can't represent an oversized diploma (issue #89). This
      # only fires when the ranker was unavailable for an over-cap act (typically a
      # transient embeddings-server failure), so we error and let the Oban job
      # retry. Explicit `:truncate` (the per-act A/B comparison) is still honoured.
      strategy == :truncate and requested != :truncate ->
        {:error, :ranker_unavailable}

      # Omnibus act + an extractor configured: the strong model lists the concrete
      # changes and amalia renders them (issue #90). Falls back to the umbrella
      # summary if the extractor is unavailable or fails. Explicit `:truncate`
      # (A/B) skips this and takes the plain path below.
      strategy == :rank and requested != :truncate and extractor_configured?() ->
        extract_render(act, clean, provider, model, ranker_model)

      true ->
        summarize_with(act, provider, model, text, strategy, ranker_model)
    end
  end

  # An extractor is usable when a provider is configured with a resolvable model.
  defp extractor_configured?, do: extractor_selection() != nil

  # `{provider, model}` for the configured extractor, or nil (feature off).
  defp extractor_selection do
    with %Provider{} = provider <- Admin.extractor_provider(),
         model when is_binary(model) <- Admin.extractor_model() || List.first(provider.models) do
      {provider, model}
    else
      _ -> nil
    end
  end

  # Extract/render path for omnibus acts (issue #90). The extractor reads a
  # generously-trimmed view (its own large budget, not the renderer cap) and
  # returns changes + a headline; amalia renders the changes into the house voice
  # (mode: :render) and the extractor's headline is used verbatim. Any extractor
  # failure degrades to the umbrella summary so a big act always gets summarized.
  defp extract_render(act, clean, renderer, renderer_model, ranker_model) do
    {ext_provider, ext_model} = extractor_selection()
    budget = Admin.extractor_text_chars()
    {ext_text, _} = TextBudget.prepare(clean, budget, :auto, budget)

    case Extractor.extract(act, ext_text, ext_provider, ext_model) do
      {:ok, %{headline: headline, changes: changes}} ->
        render_text = Prompt.render_changes(changes)

        with {:ok, attrs} <-
               adapter_for(renderer.kind).summarize(act, renderer, renderer_model, render_text,
                 mode: :render,
                 strategy: :rank
               ) do
          create_summary(
            act,
            attrs
            |> Map.new()
            |> Map.merge(%{
              provider_id: renderer.id,
              # The extractor supplies the headline (amalia hallucinates short titles).
              headline: headline,
              truncated: String.length(ext_text) < String.length(clean),
              text_strategy: "extract",
              ranker_model: ranker_model,
              extractor_model: ext_model
            })
          )
        end

      {:error, reason} ->
        Logger.info(
          "extractor unavailable (#{inspect(reason)}); umbrella fallback for act #{act.id}"
        )

        {text, _} =
          TextBudget.prepare(
            clean,
            max_text_chars(renderer_model),
            :auto,
            target_text_chars(renderer_model)
          )

        summarize_with(act, renderer, renderer_model, text, :rank, ranker_model)
    end
  end

  defp summarize_with(act, provider, model, text, strategy, ranker_model) do
    case adapter_for(provider.kind).summarize(act, provider, model, text, strategy: strategy) do
      {:ok, attrs} ->
        create_summary(
          act,
          attrs
          |> Map.new()
          |> Map.merge(%{
            provider_id: provider.id,
            truncated: strategy != :full,
            text_strategy: to_string(strategy),
            ranker_model: ranker_model
          })
        )

      {:async, ref} ->
        {:async, ref}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Insert a summary for an act. Used both by the async write path and by the
  manual backfill (console/SSH). Stamps `generated_at`. Embeds `plain_text`
  for semantic search (issue #27) right
  after insert; a disabled/unreachable embeddings server never blocks the
  summary itself — the row is simply left without an embedding.
  """
  def create_summary(%Act{id: act_id}, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put_new(:act_id, act_id)
      |> Map.put_new(:generated_at, now())

    case %Summary{} |> Summary.changeset(attrs) |> Repo.insert() do
      {:ok, summary} ->
        case embed_summary(summary) do
          {:ok, embedded} -> {:ok, embedded}
          {:error, _reason} -> {:ok, summary}
        end

      error ->
        error
    end
  end

  @doc """
  (Re)compute and persist a summary's `embedding` from its `plain_text`,
  refreshing the search index (`Arcada.Search.Index`). `{:error, reason}`
  when the embeddings server is disabled or unreachable — used by
  `create_summary/2` (which tolerates it) and by the admin "Generate
  embedding" action (which surfaces it).
  """
  def embed_summary(%Summary{} = summary) do
    cfg = Admin.embeddings_config()

    with true <- Embeddings.enabled?(cfg),
         {:ok, [vector]} <- Embeddings.embed([embed_text(summary, cfg)], cfg) do
      persist_embedding(summary, vector)
    else
      false -> {:error, :embeddings_disabled}
      {:error, reason} -> {:error, reason}
    end
  end

  defp embed_text(summary, cfg),
    do: (cfg[:document_prefix] || "") <> Summary.strip_terms(summary.plain_text)

  defp persist_embedding(summary, vector) do
    case summary |> Summary.changeset(%{embedding: vector}) |> Repo.update() do
      {:ok, updated} ->
        Index.put(updated.id, updated.act_id, vector)
        {:ok, updated}

      error ->
        error
    end
  end

  # Accept the strategy as an atom (direct calls) or string (decoded job args).
  defp normalize_strategy(s) when s in [:auto, :rank, :truncate], do: s
  defp normalize_strategy("rank"), do: :rank
  defp normalize_strategy("truncate"), do: :truncate
  defp normalize_strategy(_), do: :auto

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end

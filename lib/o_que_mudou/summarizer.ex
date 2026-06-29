defmodule OQueMudou.Summarizer do
  @moduledoc """
  Produces 🤖 unreviewed summaries for acts. Dispatches to an adapter by the
  `Provider` kind (`:anthropic | :openai | :ssh`) and writes via an **async path**
  (an Oban job, never inline with the scrape). The active provider+model
  (`OQueMudou.Admin`) drives auto-summarize; manual runs pass an explicit one.
  """

  alias OQueMudou.Repo
  alias OQueMudou.Admin
  alias OQueMudou.Providers.Provider
  alias OQueMudou.Register.{Act, Summary}
  alias OQueMudou.Summarizer.{Embeddings, Sections, SummarizeWorker}
  alias OQueMudou.Summarizer.Adapters.{Api, OpenAI, Ssh}

  # Provider kind → adapter module.
  @adapters %{anthropic: Api, openai: OpenAI, ssh: Ssh}

  # Appended whenever some act content was dropped from the prompt.
  @truncation_marker "\n\n[...texto truncado para efeitos de resumo...]"

  # What the section ranker treats as "relevant": sections whose meaning is
  # closest to this query are kept first. Overridable via the Embeddings config.
  @relevance_query "Que mudanças concretas este diploma introduz: novas regras, " <>
                     "obrigações, alterações, revogações, prazos e quem fica afetado."

  # Shared system prompt for every LLM adapter (api, ssh). The style rules — plain
  # everyday Portuguese, short active sentences, no bureaucratic filler, no inline
  # statute citations — are the single lever for how readable the summaries feel,
  # so they live here once. Each adapter appends only its output-format wiring.
  @base_system """
  És um jornalista que explica diplomas do Diário da República a um amigo, em \
  português do dia-a-dia.

  Escreve um resumo curto (2 a 4 frases) que diga, por esta ordem: o que muda, em \
  concreto; para quem (quem fica afetado); e a partir de quando, se o diploma o \
  indicar. Classifica também o diploma em um ou mais domínios de vida.

  Regras de escrita:
  - Começa pela própria mudança, não pela instituição que a emitiu. Não nomeies o \
  emissor (ministério, tribunal, secretaria, etc.) a não ser que seja essencial \
  para perceber o que mudou.
  - Frases curtas e diretas, uma ideia de cada vez. Usa voz ativa.
  - Linguagem comum. Evita jargão jurídico e fórmulas burocráticas como "ao abrigo \
  de", "nos termos do", "sem prejuízo de" ou "no âmbito de".
  - Não cites números de diplomas nem artigos no corpo do texto — a fonte oficial já \
  os tem. Refere uma lei pelo nome apenas se for mesmo o assunto.
  - Vai direto ao que importa: corta enchimento, rodeios e repetições.
  - Sê factual. Não dês opinião nem aconselhamento jurídico.
  """

  @doc "Shared system prompt (writing + classification rules) for the LLM adapters."
  def base_system_prompt, do: @base_system

  @doc "Effective cap (chars) on act text fed to the summarizer prompt."
  def max_text_chars, do: Admin.max_text_chars()

  @doc """
  Prepare act text for the summarizer prompt, capped at `max_chars` (the
  configured cap by default).

  When the text fits, it's returned untouched. When it's oversized and the
  embeddings ranker is configured, the diploma is split into sections and only
  the most change-relevant ones (in document order) are kept — so the operative
  articles aren't crowded out by trailing annex tables. Otherwise it falls back
  to head-truncation (`cap_text/2`). Either way a marker flags dropped content.

  May perform a network call to the embeddings server; intended for the async
  summarize job, not request paths.
  """
  def prepare_text(text, max_chars \\ nil), do: prepare(text, max_chars) |> elem(0)

  @doc """
  Like `prepare_text/2` but returns `{prepared_text, effective_strategy}` where
  the strategy is what *actually* happened:

    * `:full`     — fit under the cap, sent whole
    * `:rank`     — oversized; most change-relevant sections kept (embeddings)
    * `:truncate` — oversized; opening kept (head-truncation)

  `requested` (`:auto | :rank | :truncate`) is the caller's preference. `:auto`
  and `:rank` both attempt ranking and fall back to truncation when it isn't
  available (ranker off, unstructured text, embed failure, nothing fits);
  `:truncate` forces head-truncation even when ranking is available — used by the
  per-act comparison to A/B the two strategies on the same model.
  """
  def prepare(text, max_chars \\ nil, requested \\ :auto)

  def prepare(text, max_chars, requested) when is_binary(text) do
    max_chars = max_chars || max_text_chars()

    cond do
      String.length(text) <= max_chars -> {text, :full}
      requested == :truncate -> {cap_text(text, max_chars), :truncate}
      true -> ranked_or_truncated(text, max_chars)
    end
  end

  def prepare(other, _max_chars, _requested), do: {other, :full}

  defp ranked_or_truncated(text, max_chars) do
    case select_relevant(text, max_chars) do
      nil -> {cap_text(text, max_chars), :truncate}
      selected -> {selected, :rank}
    end
  end

  # Returns assembled most-relevant sections, or nil to signal "fall back to
  # head-truncation" (ranker disabled, unstructured text, embed failure, or
  # nothing fit the budget).
  defp select_relevant(text, max_chars) do
    cfg = Admin.embeddings_config()
    sections = Sections.split(text)

    with true <- Embeddings.enabled?(cfg),
         true <- length(sections) > 1,
         {:ok, [query_vec | section_vecs]} <- Embeddings.embed(embed_inputs(sections, cfg), cfg),
         true <- length(section_vecs) == length(sections) do
      sections
      |> rank(section_vecs, query_vec)
      |> pick_within_budget(max_chars)
      |> assemble(length(sections))
    else
      _ -> nil
    end
  end

  # Pair each section (with its document position) to its relevance score.
  defp rank(sections, section_vecs, query_vec) do
    sections
    |> Enum.zip(section_vecs)
    |> Enum.with_index()
    |> Enum.map(fn {{section, vec}, index} ->
      {index, section, Embeddings.cosine(query_vec, vec)}
    end)
  end

  # Greedily take the highest-scoring sections that fit the char budget
  # (reserving room for the marker). Returns `[{index, section}]`.
  defp pick_within_budget(scored, max_chars) do
    budget = max_chars - String.length(@truncation_marker)

    scored
    |> Enum.sort_by(fn {_i, _s, score} -> score end, :desc)
    |> Enum.reduce({[], 0}, fn {index, section, _score}, {picked, used} ->
      # +2 for the "\n\n" joiner between sections.
      len = String.length(section.text) + 2

      if used + len <= budget,
        do: {[{index, section} | picked], used + len},
        else: {picked, used}
    end)
    |> elem(0)
  end

  defp assemble([], _total), do: nil

  defp assemble(picked, total) do
    body =
      picked
      |> Enum.sort_by(fn {index, _section} -> index end)
      |> Enum.map_join("\n\n", fn {_index, section} -> section.text end)

    if length(picked) < total, do: body <> @truncation_marker, else: body
  end

  # nomic-embed and similar models want task prefixes (search_query: / search_document:)
  # for good retrieval; bge-m3 and plain setups leave them empty. Applied only to the
  # text scored by the model — never to the sections assembled into the prompt.
  defp embed_inputs(sections, cfg) do
    query_prefix = cfg[:query_prefix] || ""
    doc_prefix = cfg[:document_prefix] || ""
    [query_prefix <> relevance_query(cfg) | Enum.map(sections, &(doc_prefix <> &1.text))]
  end

  defp relevance_query(cfg), do: cfg[:query] || @relevance_query

  @doc """
  Cap act text for the summarizer prompt so oversized diplomas (huge annexes)
  don't exceed the model's context limit. Appends a truncation marker.
  """
  def cap_text(text, max_chars) when is_binary(text) do
    if String.length(text) > max_chars do
      String.slice(text, 0, max_chars) <> @truncation_marker
    else
      text
    end
  end

  def cap_text(other, _max_chars), do: other

  @doc """
  Whether `cap_text/2` would truncate this text — i.e. the act text exceeds the
  cap and the resulting summary only reflects the opening of the diploma.
  Recorded per summary (`truncated`) so the UI can flag partial summaries.
  """
  def truncated?(text, max_chars) when is_binary(text), do: String.length(text) > max_chars
  def truncated?(_other, _max_chars), do: false

  @doc "The adapter module for a provider kind (`:anthropic | :openai | :ssh`)."
  def adapter_for(kind) when is_atom(kind), do: Map.fetch!(@adapters, kind)

  @doc """
  Enqueue an async summarization job. With no opts it uses the active
  provider+model; pass `provider_id:`/`model:` for a manual run on a specific one,
  and `text_strategy:` (`:rank | :truncate | :auto`) to force how an oversized
  act's text is prepared (for the per-act ranking comparison).
  """
  def enqueue(act, opts \\ [])
  def enqueue(%Act{id: id}, opts), do: enqueue(id, opts)

  def enqueue(act_id, opts) when is_integer(act_id) do
    %{act_id: act_id}
    |> put_opt(opts, :provider_id)
    |> put_opt(opts, :model)
    |> put_opt(opts, :text_strategy)
    |> SummarizeWorker.new()
    |> Oban.insert()
  end

  defp put_opt(args, opts, key) do
    case Keyword.get(opts, key) do
      nil -> args
      v -> Map.put(args, to_string(key), v)
    end
  end

  @doc """
  Summarize `act` with the **active** provider+model and persist the result.
  `{:async, :no_active_provider}` if none is configured (acts wait for a manual
  run or a configured active provider).
  """
  def summarize(%Act{} = act) do
    case Admin.active_provider() do
      %Provider{} = provider -> summarize(act, provider, Admin.active_model())
      nil -> {:async, :no_active_provider}
    end
  end

  @doc """
  Summarize `act` with a specific provider + model; persist linked to the
  provider. `opts[:text_strategy]` (`:auto` default) forces how an oversized act
  is prepared. The text is prepared here (once) and handed to the adapter, which
  only talks to its backend — the cap/ranking decision lives in one place.
  """
  def summarize(%Act{} = act, %Provider{} = provider, model, opts \\ []) do
    model = model || List.first(provider.models)
    requested = opts |> Keyword.get(:text_strategy, :auto) |> normalize_strategy()
    {text, strategy} = prepare(act.full_text || act.title, max_text_chars(), requested)

    case adapter_for(provider.kind).summarize(act, provider, model, text) do
      {:ok, attrs} ->
        create_summary(
          act,
          attrs
          |> Map.new()
          |> Map.merge(%{
            provider_id: provider.id,
            truncated: strategy != :full,
            text_strategy: to_string(strategy)
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
  manual backfill (console/SSH). Defaults `status: :unreviewed` and stamps
  `generated_at`.
  """
  def create_summary(%Act{id: act_id}, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put_new(:act_id, act_id)
      |> Map.put_new(:generated_at, now())

    %Summary{}
    |> Summary.changeset(attrs)
    |> Repo.insert()
  end

  # Accept the strategy as an atom (direct calls) or string (decoded job args).
  defp normalize_strategy(s) when s in [:auto, :rank, :truncate], do: s
  defp normalize_strategy("rank"), do: :rank
  defp normalize_strategy("truncate"), do: :truncate
  defp normalize_strategy(_), do: :auto

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end

defmodule Arcada.Summarizer.TextBudget do
  @moduledoc """
  Decides **what act text reaches the model**. Given a diploma's full text and a
  two-budget window, it returns the string to summarize plus the strategy that
  produced it:

    * `:full`     — fit under the cost target, sent whole
    * `:rank`     — over target; most change-relevant sections kept (embeddings)
    * `:truncate` — over target with no ranker; opening kept (head-truncation)

  Two budgets (issue #41): `target` is the cost budget the ranker trims down to;
  `cap` is the safety ceiling. When ranking is unavailable and the act still fits
  under `cap`, it's sent **whole** rather than head-truncated — only genuine
  giants past the ceiling truncate. `target` defaults to `cap`, so a single-budget
  call behaves exactly as before.

  Lifted out of `Arcada.Summarizer` (issue #48): the summarizer orchestrates the
  write path, while the greedy budget-fill, relevance-floor gating and
  document-order reassembly concentrate here — one home for budget/ranking bugs,
  directly testable without going through `summarize/4`. Sits alongside `Sections`
  (which it consumes).

  May perform a network call to the embeddings server; intended for the async
  summarize job, not request paths.
  """

  alias Arcada.Admin
  alias Arcada.Summarizer.{Embeddings, Sections}

  # Appended whenever some act content was dropped from the prompt.
  @truncation_marker "\n\n[...texto truncado para efeitos de resumo...]"

  # What the section ranker treats as "relevant": sections whose meaning is
  # closest to this query are kept first. Overridable via the Embeddings config.
  @relevance_query "Que mudanças concretas este diploma introduz: novas regras, " <>
                     "obrigações, alterações, revogações, prazos e quem fica afetado."

  @doc "The marker appended to any prompt text that had content dropped."
  def truncation_marker, do: @truncation_marker

  @doc """
  Prepare act text for the summarizer prompt, returning `{prepared_text,
  effective_strategy}` where the strategy is what *actually* happened (`:full |
  :rank | :truncate`, see the moduledoc).

  When the text fits under `target` it's returned untouched (`:full`). When it's
  oversized and the embeddings ranker is configured, the diploma is split into
  sections and only the most change-relevant ones (in document order) are kept
  (`:rank`) — so the operative articles aren't crowded out by trailing annex
  tables. Otherwise it falls back to head-truncation (`cap_text/2`, `:truncate`).
  Either way a marker flags dropped content.

  `requested` (`:auto | :rank | :truncate`) is the caller's preference. `:auto`
  and `:rank` both attempt ranking and fall back as above; `:truncate` forces
  head-truncation to `target` even when ranking is available — used by the per-act
  comparison to A/B the two strategies on the same model + budget.
  """
  def prepare(text, cap, requested \\ :auto, target \\ nil)

  def prepare(text, cap, requested, target) when is_binary(text) do
    target = target || cap

    cond do
      String.length(text) <= target -> {text, :full}
      requested == :truncate -> {cap_text(text, target), :truncate}
      true -> ranked_or_truncated(text, target, cap)
    end
  end

  def prepare(other, _cap, _requested, _target), do: {other, :full}

  # Ranking trims to `target`; if the ranker is unavailable keep the whole act
  # when it still fits the safety ceiling (`cap`, issue #18) and only head-truncate
  # the genuine giants that overflow it.
  defp ranked_or_truncated(text, target, cap) do
    case select_relevant(text, target) do
      nil ->
        if String.length(text) <= cap, do: {text, :full}, else: {cap_text(text, cap), :truncate}

      selected ->
        {selected, :rank}
    end
  end

  # Returns assembled most-relevant sections (within `budget`), or nil to signal
  # "fall back" (ranker disabled, unstructured text, embed failure, or nothing fit
  # the budget / cleared the relevance floor).
  defp select_relevant(text, budget) do
    cfg = Admin.embeddings_config()
    sections = Sections.split(text)

    with true <- Embeddings.enabled?(cfg),
         true <- length(sections) > 1,
         {:ok, [query_vec | section_vecs]} <- Embeddings.embed(embed_inputs(sections, cfg), cfg),
         true <- length(section_vecs) == length(sections) do
      sections
      |> rank(section_vecs, query_vec)
      |> pick_within_budget(budget, cfg[:min_relevance_score])
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
  # (reserving room for the marker). Sections below `floor` cosine similarity are
  # dropped even when the budget has room — an optional relevance gate (nil = off)
  # that trims obviously-irrelevant chunks for cost (issue #41). Returns
  # `[{index, section}]`.
  defp pick_within_budget(scored, budget, floor) do
    budget = budget - String.length(@truncation_marker)

    scored
    |> Enum.filter(fn {_i, _s, score} -> is_nil(floor) or score >= floor end)
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
end

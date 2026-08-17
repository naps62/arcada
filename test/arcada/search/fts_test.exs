defmodule Arcada.Search.FTSTest do
  use Arcada.DataCase, async: true

  alias Arcada.Register.{Act, Edition, Summary}
  alias Arcada.Search.FTS

  defp insert_act(attrs) do
    n = System.unique_integer([:positive])

    edition =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "f-#{n}/2026", date: ~D[2026-06-24]})
      |> Repo.insert!()

    %Act{}
    |> Act.changeset(Map.merge(%{edition_id: edition.id, dre_id: "f-#{n}"}, attrs))
    |> Repo.insert!()
  end

  defp insert_summary(act, attrs) do
    %Summary{}
    |> Summary.changeset(Map.merge(%{act_id: act.id}, attrs))
    |> Repo.insert!()
  end

  defp act_with_summary(act_attrs, plain_text) do
    act = insert_act(act_attrs)
    insert_summary(act, %{plain_text: plain_text})
    act
  end

  test "tokenizes and matches a law number in the act title" do
    act =
      act_with_summary(%{title: "Lei n.º 23/2023 das finanças"}, "resumo em linguagem simples")

    _other = act_with_summary(%{title: "Decreto-Lei n.º 1/2020"}, "outro resumo")

    assert FTS.ranked_ids("Lei 23/2023") == [act.id]
    assert FTS.ranked_ids("23/2023") == [act.id]
  end

  test "matches the summary body with the portuguese dictionary (stemming)" do
    act = act_with_summary(%{title: "Sem pistas no título"}, "Novos apoios ao arrendamento jovem")

    # `apoios` stems to the same root as `apoio`.
    assert FTS.ranked_ids("apoio") == [act.id]
  end

  test "dedupes an act with several matching summaries to a single id" do
    act = act_with_summary(%{title: "Portaria 5/2026"}, "primeiro resumo com arrendamento")
    insert_summary(act, %{plain_text: "segundo resumo com arrendamento"})

    assert FTS.ranked_ids("arrendamento") == [act.id]
  end

  test "returns [] for a blank, non-binary, or stopword-only query" do
    act_with_summary(%{title: "Algum diploma"}, "algum texto")

    assert FTS.ranked_ids("") == []
    assert FTS.ranked_ids("   ") == []
    assert FTS.ranked_ids(nil) == []
    # Only stopwords/punctuation → empty tsquery → no matches, no crash.
    assert FTS.ranked_ids("de o a") == []
  end

  test "returns [] when nothing matches" do
    act_with_summary(%{title: "Um título"}, "um corpo de resumo")
    assert FTS.ranked_ids("palavra-que-nao-existe") == []
  end

  # --- header-field coverage: the acts-side tsvector spans title/tipo/emitter ---

  test "matches a term in the act tipo (header)" do
    act = act_with_summary(%{tipo: "Portaria", title: "sem termo relevante"}, "corpo neutro")
    assert FTS.ranked_ids("portaria") == [act.id]
  end

  test "matches a term in the act emitter (header)" do
    act =
      act_with_summary(
        %{emitter: "Assembleia da República", title: "sem termo relevante"},
        "corpo neutro"
      )

    assert FTS.ranked_ids("Assembleia") == [act.id]
  end

  # --- body-field coverage: the summaries-side tsvector spans plain_text/headline ---

  test "matches a term only in the summary headline (body)" do
    act = insert_act(%{title: "sem termo relevante"})
    insert_summary(act, %{plain_text: "corpo neutro", headline: "arrendamento jovem"})

    assert FTS.ranked_ids("arrendamento") == [act.id]
  end

  # --- OR / join semantics ---

  test "returns an act on a header match even when its summary does not match" do
    act = act_with_summary(%{title: "Lei 5/2026 sobre arrendamento"}, "corpo totalmente neutro")
    assert FTS.ranked_ids("arrendamento") == [act.id]
  end

  test "an act whose header matches but has no summaries is not returned" do
    # Inner join on :summaries — a summary-less act is invisible to search.
    _no_summary = insert_act(%{title: "Xyzzytoken decreto"})
    assert FTS.ranked_ids("Xyzzytoken") == []
  end

  # --- ranking / ordering ---

  test "orders a stronger (header+body) match before a body-only match" do
    strong = act_with_summary(%{title: "arrendamento urgente"}, "arrendamento e apoio")
    weak = act_with_summary(%{title: "diploma sem o termo"}, "arrendamento")

    assert FTS.ranked_ids("arrendamento") == [strong.id, weak.id]
  end

  test "breaks rank ties by act id ascending" do
    a = act_with_summary(%{title: "arrendamento"}, "corpo neutro")
    b = act_with_summary(%{title: "arrendamento"}, "corpo neutro")

    assert a.id < b.id
    assert FTS.ranked_ids("arrendamento") == [a.id, b.id]
  end

  # --- result cap (#72) ---

  defp set_fts_cfg(kw) do
    prev = Application.get_env(:arcada, FTS, [])
    Application.put_env(:arcada, FTS, kw)
    on_exit(fn -> Application.put_env(:arcada, FTS, prev) end)
  end

  test "caps the result set at the configured limit, keeping the top-ranked (#72)" do
    set_fts_cfg(limit: 3)

    # Five matching acts with strictly increasing rank via header term frequency
    # (more repetitions of the term → higher ts_rank; the body is neutral).
    acts =
      for k <- 1..5, into: %{} do
        title = String.duplicate("arrendamento ", k) <> "diploma #{k}"
        {k, act_with_summary(%{title: title}, "corpo neutro")}
      end

    ids = FTS.ranked_ids("arrendamento")

    assert length(ids) == 3
    # The three strongest survive; the two weakest are dropped by the cap.
    assert Enum.all?([5, 4, 3], fn k -> acts[k].id in ids end)
    refute acts[1].id in ids
    refute acts[2].id in ids
  end

  test "returns every match when there are fewer than the limit (#72)" do
    set_fts_cfg(limit: 500)
    a = act_with_summary(%{title: "arrendamento um"}, "corpo")
    b = act_with_summary(%{title: "arrendamento dois"}, "corpo")

    assert Enum.sort(FTS.ranked_ids("arrendamento")) == Enum.sort([a.id, b.id])
  end

  # --- chronological order (#104) ---

  # An act on a specific edition date. Titles carry the search term so ts_rank
  # can be varied independently of the date.
  defp dated_act(date, title, plain_text \\ "corpo neutro") do
    n = System.unique_integer([:positive])

    edition =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "c-#{n}/2026", date: date})
      |> Repo.insert!()

    act =
      %Act{}
      |> Act.changeset(%{edition_id: edition.id, dre_id: "c-#{n}", title: title})
      |> Repo.insert!()

    insert_summary(act, %{plain_text: plain_text})
    act
  end

  test "orders by edition date, newest first, whatever the rank says" do
    strong_but_old = dated_act(~D[2026-01-10], "arrendamento arrendamento arrendamento")
    weak_but_new = dated_act(~D[2026-08-10], "diploma sobre arrendamento")

    # Ranking puts the term-dense act first; chronological puts the fresh one first.
    assert FTS.ranked_ids("arrendamento") == [strong_but_old.id, weak_but_new.id]

    assert FTS.chronological_ids("arrendamento", limit: 10) ==
             [weak_but_new.id, strong_but_old.id]
  end

  test "reaches matches the ranked top-N cap would have cut" do
    set_fts_cfg(limit: 1)

    old = dated_act(~D[2026-01-10], "arrendamento arrendamento arrendamento")
    new = dated_act(~D[2026-08-10], "diploma sobre arrendamento")

    # The cap keeps only the top-ranked act...
    assert FTS.ranked_ids("arrendamento") == [old.id]
    # ...but chronological is uncapped, so the recent weak match is still reachable.
    assert FTS.chronological_ids("arrendamento", limit: 10) == [new.id, old.id]
  end

  test "keyset pages through a single busy day without repeating or skipping" do
    # Same date for all three: only the id tiebreak separates them, which is
    # exactly the case a date-only cursor would get wrong.
    a = dated_act(~D[2026-08-10], "arrendamento a")
    b = dated_act(~D[2026-08-10], "arrendamento b")
    c = dated_act(~D[2026-08-10], "arrendamento c")

    assert a.id < b.id and b.id < c.id

    page1 = FTS.chronological_ids("arrendamento", limit: 2)
    assert page1 == [c.id, b.id]

    page2 = FTS.chronological_ids("arrendamento", limit: 2, before: {~D[2026-08-10], b.id})
    assert page2 == [a.id]
  end

  test "keyset pages across a date boundary" do
    newer = dated_act(~D[2026-08-10], "arrendamento novo")
    older = dated_act(~D[2026-07-01], "arrendamento velho")

    assert FTS.chronological_ids("arrendamento", limit: 1) == [newer.id]

    assert FTS.chronological_ids("arrendamento", limit: 5, before: {~D[2026-08-10], newer.id}) ==
             [older.id]
  end

  test "a summary-less act stays invisible, as in ranked search" do
    _no_summary = insert_act(%{title: "Xyzzytoken decreto"})

    assert FTS.chronological_ids("Xyzzytoken", limit: 10) == []
  end

  test "returns [] for a blank or non-binary query" do
    dated_act(~D[2026-08-10], "arrendamento")

    assert FTS.chronological_ids("", limit: 10) == []
    assert FTS.chronological_ids("   ", limit: 10) == []
    assert FTS.chronological_ids(nil, limit: 10) == []
  end
end

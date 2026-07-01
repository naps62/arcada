defmodule OQueMudou.Search.FTSTest do
  use OQueMudou.DataCase, async: true

  alias OQueMudou.Register.{Act, Edition, Summary}
  alias OQueMudou.Search.FTS

  defp act_with_summary(act_attrs, plain_text) do
    n = System.unique_integer([:positive])

    edition =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "f-#{n}/2026", date: ~D[2026-06-24]})
      |> Repo.insert!()

    act =
      %Act{}
      |> Act.changeset(Map.merge(%{edition_id: edition.id, dre_id: "f-#{n}"}, act_attrs))
      |> Repo.insert!()

    %Summary{}
    |> Summary.changeset(%{act_id: act.id, plain_text: plain_text})
    |> Repo.insert!()

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

    %Summary{}
    |> Summary.changeset(%{act_id: act.id, plain_text: "segundo resumo com arrendamento"})
    |> Repo.insert!()

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
end

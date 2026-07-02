defmodule Arcada.Summarizer.TextBudgetTest do
  use Arcada.DataCase, async: false

  alias Arcada.Summarizer.{Embeddings, TextBudget}

  # `prepare/4` is the whole test surface: the budget/ranking truth table that
  # used to be reachable only through `Summarizer.summarize/4` (issue #48).

  describe "prepare/4 (fits / ranks / truncates)" do
    test "returns text unchanged when it fits" do
      assert {"curto", :full} = TextBudget.prepare("curto", 1_000)
    end

    test "head-truncates when the ranker is disabled" do
      set_embeddings([])
      text = String.duplicate("a", 500)
      {out, :truncate} = TextBudget.prepare(text, 100)
      assert out == TextBudget.cap_text(text, 100)
      assert String.contains?(out, "truncado")
    end

    test "keeps change-relevant sections and drops the annex when ranking is on" do
      set_embeddings(embed_fn: relevance_embed())

      {out, :rank} = TextBudget.prepare(diploma(800), 400)

      assert String.contains?(out, "Artigo 1.º")
      assert String.contains?(out, "Artigo 2.º")
      refute String.contains?(out, "999999")
      assert String.contains?(out, "truncado")
    end

    test "preserves document order of kept sections" do
      set_embeddings(embed_fn: relevance_embed())
      {out, :rank} = TextBudget.prepare(diploma(800), 400)
      assert :binary.match(out, "Artigo 1.º") < :binary.match(out, "Artigo 2.º")
    end

    test "falls back to head-truncation when the embed call fails" do
      set_embeddings(embed_fn: fn _ -> {:error, :boom} end)
      text = diploma(800)
      {out, :truncate} = TextBudget.prepare(text, 400)
      assert out == TextBudget.cap_text(text, 400)
    end

    test "falls back to head-truncation for unstructured oversized text" do
      set_embeddings(embed_fn: relevance_embed())
      text = String.duplicate("texto sem cabecalhos ", 60)
      {out, :truncate} = TextBudget.prepare(text, 100)
      assert out == TextBudget.cap_text(text, 100)
    end

    test "auto ranks when possible" do
      set_embeddings(embed_fn: relevance_embed())
      assert {_out, :rank} = TextBudget.prepare(diploma(800), 400, :auto)
    end
  end

  describe "prepare/4 requested strategy" do
    test "a fitting act is :full, untouched" do
      assert {"curto", :full} = TextBudget.prepare("curto", 1_000, :auto)
    end

    test ":truncate forces head-truncation even when ranking is available" do
      set_embeddings(embed_fn: relevance_embed())
      {out, strategy} = TextBudget.prepare(diploma(800), 400, :truncate)
      assert strategy == :truncate
      assert out == TextBudget.cap_text(diploma(800), 400)
    end

    test ":rank keeps relevant sections and reports :rank" do
      set_embeddings(embed_fn: relevance_embed())
      {out, strategy} = TextBudget.prepare(diploma(800), 400, :rank)
      assert strategy == :rank
      assert String.contains?(out, "Artigo 1.º")
      refute String.contains?(out, "999999")
    end

    test ":rank falls back to :truncate when the ranker is unavailable" do
      set_embeddings([])
      assert {_out, :truncate} = TextBudget.prepare(diploma(800), 400, :rank)
    end

    test "ranks paragraph chunks for headingless oversized text (acórdão-style)" do
      set_embeddings(embed_fn: relevance_embed())
      # No Artigo/Anexo headings — the paragraph-chunk fallback must kick in so
      # ranking still engages instead of head-truncating.
      text =
        Enum.map_join(1..40, "\n\n", fn n ->
          "Parágrafo #{n}. " <> String.duplicate("conteúdo ", 60)
        end)

      {out, strategy} = TextBudget.prepare(text, 5_000, :rank)
      assert strategy == :rank
      assert String.length(out) <= 5_000
    end
  end

  describe "prepare/4 cost target vs safety cap (issue #41)" do
    test "ranks down to the target even when the act fits under the cap" do
      set_embeddings(embed_fn: relevance_embed())
      text = diploma(800)

      # Fits the huge cap, but exceeds the small target → ranking still trims it.
      {out, strategy} = TextBudget.prepare(text, 1_000_000, :auto, 400)
      assert strategy == :rank
      assert String.contains?(out, "Artigo 1.º")
      refute String.contains?(out, "999999")

      # Same cap, target ≥ length → sent whole (annex included).
      assert {^text, :full} = TextBudget.prepare(text, 1_000_000, :auto, 1_000_000)
    end

    test "ranker off + fits the cap → sent whole, not head-truncated (issue #18 preserved)" do
      set_embeddings([])
      text = diploma(800)

      assert {^text, :full} = TextBudget.prepare(text, 1_000_000, :auto, 400)
      refute String.contains?(text, "truncado")
    end

    test "ranker off + exceeds the cap → head-truncated to the cap" do
      set_embeddings([])
      text = diploma(800)

      {out, strategy} = TextBudget.prepare(text, 400, :auto, 200)
      assert strategy == :truncate
      assert out == TextBudget.cap_text(text, 400)
    end

    test "min_relevance_score drops low-score sections even when the budget has room" do
      art1 = "Artigo 1.º\n" <> String.duplicate("A", 1_500)
      art2 = "Artigo 2.º\n" <> String.duplicate("B", 1_500)
      annex = "ANEXO I\n" <> String.duplicate("9", 300)
      text = art1 <> "\n\n" <> art2 <> "\n\n" <> annex

      # Budget fits Artigo 1.º (relevant) then has room for the small annex
      # (irrelevant), but not the second big article.
      set_embeddings(embed_fn: relevance_embed())
      {without_floor, :rank} = TextBudget.prepare(text, 1_000_000, :auto, 1_948)
      assert String.contains?(without_floor, "9999")

      # With a floor the annex (cosine 0) is dropped despite the spare budget.
      set_embeddings(embed_fn: relevance_embed(), min_relevance_score: 0.5)
      {with_floor, :rank} = TextBudget.prepare(text, 1_000_000, :auto, 1_948)
      refute String.contains?(with_floor, "9")
      assert String.contains?(with_floor, "AAAA")
    end
  end

  describe "prepare/4 embedding task prefixes" do
    test "applies task prefixes to scored text only, never to the assembled prompt" do
      test_pid = self()

      capturing_embed = fn texts ->
        send(test_pid, {:embed_inputs, texts})

        {:ok,
         Enum.map(texts, fn t ->
           if String.contains?(t, "ANEXO"), do: [0.0, 1.0], else: [1.0, 0.0]
         end)}
      end

      set_embeddings(
        embed_fn: capturing_embed,
        query_prefix: "search_query: ",
        document_prefix: "search_document: "
      )

      {out, :rank} = TextBudget.prepare(diploma(800), 400)

      assert_received {:embed_inputs, [query | docs]}
      assert String.starts_with?(query, "search_query: ")
      assert Enum.all?(docs, &String.starts_with?(&1, "search_document: "))

      # Prefixes are a retrieval detail — they must not leak into the LLM prompt.
      refute String.contains?(out, "search_document:")
      refute String.contains?(out, "search_query:")
      assert String.contains?(out, "Artigo 1.º")
    end
  end

  defp set_embeddings(kw) do
    prev = Application.get_env(:arcada, Embeddings, [])
    Application.put_env(:arcada, Embeddings, kw)
    on_exit(fn -> Application.put_env(:arcada, Embeddings, prev) end)
  end

  # Vectors orthogonal to the query for annex text, aligned for everything else,
  # so the ranker keeps the articles and drops the annex.
  defp relevance_embed do
    fn texts ->
      vecs =
        Enum.map(texts, fn t ->
          if String.contains?(t, "ANEXO"), do: [0.0, 1.0], else: [1.0, 0.0]
        end)

      {:ok, vecs}
    end
  end

  defp diploma(annex_size) do
    """
    Preâmbulo curto a explicar o objeto.

    Artigo 1.º
    Cria uma nova obrigação para os contribuintes.

    Artigo 2.º
    Produz efeitos a partir de janeiro de 2027.

    ANEXO I
    #{String.duplicate("9", annex_size)}
    """
  end
end

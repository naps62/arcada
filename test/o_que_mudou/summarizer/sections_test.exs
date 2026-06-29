defmodule OQueMudou.Summarizer.SectionsTest do
  use ExUnit.Case, async: true

  alias OQueMudou.Summarizer.Sections

  test "splits a diploma into preamble, articles and annex" do
    text = """
    Preâmbulo a explicar o objeto do diploma.

    Artigo 1.º
    Objeto. Estabelece novas regras.

    Artigo 2.º
    Produz efeitos a partir de janeiro.

    ANEXO I
    Tabela com muitos valores.
    """

    labels = Sections.split(text) |> Enum.map(& &1.label)

    assert :preamble in labels
    assert "Artigo 1.º" in labels
    assert "Artigo 2.º" in labels
    assert "ANEXO I" in labels
  end

  test "the article section carries its body up to the next heading" do
    text = "Artigo 1.º\nPrimeira regra.\nAinda a primeira.\nArtigo 2.º\nSegunda regra."

    [art1, art2] = Sections.split(text)
    assert art1.text =~ "Primeira regra."
    assert art1.text =~ "Ainda a primeira."
    refute art1.text =~ "Segunda regra."
    assert art2.text =~ "Segunda regra."
  end

  test "short unstructured text yields a single chunk" do
    assert [%{text: text}] = Sections.split("Sem cabeçalhos nenhuns aqui.")
    assert text == "Sem cabeçalhos nenhuns aqui."
  end

  test "does not treat prose mentioning an article as a heading" do
    text = "O disposto no artigo anterior mantém-se, conforme o artigo 5.º referido acima."
    assert [%{text: ^text}] = Sections.split(text)
  end

  test "empty/whitespace-only sections are dropped" do
    assert Sections.split("") == []
    assert Sections.split("   \n\n  ") == []
  end

  describe "paragraph-chunk fallback (no diploma headings)" do
    test "an acórdão-style doc with paragraphs is split into multiple chunks" do
      # No Artigo/Anexo headings — paragraphs separated by blank lines. Each para
      # is ~600 chars so they merge toward the ~2k target into several chunks.
      para = fn n -> "Parágrafo #{n}. " <> String.duplicate("texto do acórdão ", 35) end
      text = Enum.map_join(1..30, "\n\n", para)

      sections = Sections.split(text)
      assert length(sections) > 1
      # round-trips the content (order preserved, nothing dropped)
      assert sections |> Enum.map(& &1.text) |> Enum.join(" ") =~ "Parágrafo 1."
      assert sections |> Enum.map(& &1.text) |> Enum.join(" ") =~ "Parágrafo 30."
    end

    test "a single huge paragraph (no breaks) is windowed into multiple chunks" do
      text = String.duplicate("a", 10_000)
      sections = Sections.split(text)
      assert length(sections) > 1
      assert sections |> Enum.map(&String.length(&1.text)) |> Enum.sum() == 10_000
    end

    test "heading segmentation still wins when ≥2 headings are present" do
      text = "Artigo 1.º\nUm.\n\nArtigo 2.º\nDois."
      assert ["Artigo 1.º", "Artigo 2.º"] = Sections.split(text) |> Enum.map(& &1.label)
    end
  end
end

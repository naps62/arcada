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

  test "unstructured text yields a single section" do
    assert [%{label: :preamble, text: text}] = Sections.split("Sem cabeçalhos nenhuns aqui.")
    assert text == "Sem cabeçalhos nenhuns aqui."
  end

  test "does not treat prose mentioning an article as a heading" do
    text = "O disposto no artigo anterior mantém-se, conforme o artigo 5.º referido acima."
    assert [%{label: :preamble}] = Sections.split(text)
  end

  test "empty/whitespace-only sections are dropped" do
    assert Sections.split("") == []
    assert Sections.split("   \n\n  ") == []
  end
end

defmodule Arcada.Summarizer.PlainTextTest do
  use ExUnit.Case, async: true

  alias Arcada.Summarizer.PlainText
  alias Arcada.Summarizer.Sections

  test "strips tags and decodes entities" do
    html =
      ~s(<p class="paragraph-title">Artigo 5.&ordm;</p><p>O acesso &agrave; categoria&nbsp;3</p>)

    assert PlainText.from_html(html) == "Artigo 5.º\nO acesso à categoria 3"
  end

  test "block boundaries become newlines so headings land at line start" do
    html =
      ~s(<p>Preâmbulo.</p><p>Artigo 1.º</p><p>Regra nova.</p><br><a href='/x'>Decreto-Lei n.º 433/82</a>)

    cleaned = PlainText.from_html(html)

    # Every heading now starts its own line — the glued "Regra novaDecreto" bug is gone.
    assert cleaned =~ "\nArtigo 1.º\n"
    refute cleaned =~ ~r/[^\n>]Artigo 1/
  end

  test "cleaned HTML makes Sections segment on the articulado again" do
    html =
      ~s(<p>Preâmbulo a explicar.</p>) <>
        ~s(<p>Artigo 1.º</p><p>Objeto. Novas regras.</p>) <>
        ~s(<p>Artigo 2.º</p><p>Produz efeitos em janeiro.</p>)

    labels = html |> PlainText.from_html() |> Sections.split() |> Enum.map(& &1.label)

    assert "Artigo 1.º" in labels
    assert "Artigo 2.º" in labels
  end

  test "plain text without tags is returned unchanged (bar whitespace)" do
    text = "Artigo 1.º\nUma regra simples."

    assert PlainText.from_html(text) == text
  end

  test "collapses runs of whitespace and blank lines" do
    html = "<p>Uma    frase.</p>\n\n\n\n<p>Outra.</p>"

    assert PlainText.from_html(html) == "Uma frase.\n\nOutra."
  end

  test "passes non-binaries through untouched" do
    assert PlainText.from_html(nil) == nil
    assert PlainText.from_html(42) == 42
  end
end

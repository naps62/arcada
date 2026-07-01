defmodule OQueMudouWeb.AboutLiveTest do
  use OQueMudouWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "renders the about page with the name story and credited photo", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/sobre")

    assert html =~ "Sobre a Arcada"
    assert html =~ "Diário da República"
    assert html =~ "Praça da República"
    # Transparent about the AI processing and the provenance seals.
    assert html =~ "Como usamos inteligência artificial"
    assert html =~ "🤖"
    # The Braga photo is embedded and its CC attribution is present.
    assert html =~ "/images/arcada-braga.jpg"
    assert html =~ "CC BY-SA 4.0"
  end
end

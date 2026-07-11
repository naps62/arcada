defmodule ArcadaWeb.ErrorHTMLTest do
  use ArcadaWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template

  test "renders a branded, noindexed 404.html" do
    html = render_to_string(ArcadaWeb.ErrorHTML, "404", "html", [])
    assert html =~ ~s(<meta name="robots" content="noindex, follow")
    assert html =~ "Página não encontrada"
    assert html =~ ~s(<a href="/")
  end

  test "renders 500.html" do
    assert render_to_string(ArcadaWeb.ErrorHTML, "500", "html", []) == "Internal Server Error"
  end
end

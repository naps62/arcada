defmodule Arcada.Scraper.ParserTest do
  use ExUnit.Case, async: true

  alias Arcada.Scraper.Parser

  @list_fixture Path.join([__DIR__, "..", "..", "support", "fixtures", "dre_list_2026-06-24.json"])

  defp list_json, do: @list_fixture |> File.read!() |> Jason.decode!()

  describe "parse_editions/1 (real DRE fixture, 2026-06-24)" do
    setup do
      [editions: Parser.parse_editions(list_json())]
    end

    test "returns one Série I edition numbered 120/2026", %{editions: editions} do
      assert [edition] = editions
      assert edition.serie == "I"
      assert edition.number == "120/2026"
      assert edition.date == ~D[2026-06-24]
    end

    test "parses all 17 acts with the skeleton fields", %{editions: [edition]} do
      assert length(edition.acts) == 17

      act = Enum.find(edition.acts, &(&1.dre_id == "1138160247"))
      assert act.tipo == "Decreto do Presidente da República"
      assert act.emitter == "Presidência da República"
      assert act.title == "Decreto do Presidente da República n.º 84/2026"
      assert act.published_at == ~D[2026-06-24]
      # enrichment fields are nil until the detail pass
      assert act.full_text == nil
      assert act.pdf_url == nil
    end

    test "absolutizes act source_url from LinkSitemap", %{editions: [edition]} do
      act = Enum.find(edition.acts, &(&1.dre_id == "1138160247"))

      assert act.source_url ==
               "https://diariodarepublica.pt/dr/detalhe/decreto-presidente-republica/84-2026-1138160247"
    end

    test "every act has a non-empty dre_id", %{editions: [edition]} do
      assert Enum.all?(edition.acts, &(is_binary(&1.dre_id) and &1.dre_id != ""))
    end
  end

  test "parse_editions/1 tolerates an unexpected shape" do
    assert Parser.parse_editions(%{"data" => %{}}) == []
    assert Parser.parse_editions(%{}) == []
  end

  describe "split_link_sitemap/1" do
    test "splits a path" do
      assert Parser.split_link_sitemap(
               "/dr/detalhe/decreto-presidente-republica/84-2026-1138160247"
             ) ==
               {:ok, "decreto-presidente-republica", "84-2026-1138160247"}
    end

    test "splits a full URL" do
      assert Parser.split_link_sitemap(
               "https://diariodarepublica.pt/dr/detalhe/portaria/200-2026-1138160300"
             ) == {:ok, "portaria", "200-2026-1138160300"}
    end

    test "errors on junk" do
      assert Parser.split_link_sitemap("/nope") == :error
      assert Parser.split_link_sitemap(nil) == :error
    end
  end

  describe "parse_crf/1" do
    test "extracts crf from a decoded nr2Users value" do
      assert Parser.parse_crf("crf=T6C+9iB49TLra4jEsMeSckDMNhQ=;uid=0;unm=") ==
               "T6C+9iB49TLra4jEsMeSckDMNhQ="
    end

    test "url-decodes percent-encoded values" do
      assert Parser.parse_crf("crf%3dABC%3d%3buid%3d0") == "ABC="
    end

    test "nil-safe" do
      assert Parser.parse_crf(nil) == nil
    end
  end

  describe "parse_detail/1" do
    test "pulls full_text + pdf_url from a detail payload" do
      payload = %{
        "versionInfo" => %{"hasApiVersionChanged" => false},
        "data" => %{
          "DetalheConteudo" => %{
            "Texto" => "corpo simples",
            "TextoFormatado" => "<p>corpo</p>",
            "URL_PDF" => "https://files.diariodarepublica.pt/1s/2026/06/12000/0000300003.pdf"
          }
        }
      }

      assert {:ok, attrs} = Parser.parse_detail(payload)
      assert attrs.full_text == "<p>corpo</p>"
      assert attrs.pdf_url =~ "files.diariodarepublica.pt"
    end

    test "a rotated (empty-data) body reads as :empty — rotation is Client/Session's concern" do
      assert Parser.parse_detail(%{
               "versionInfo" => %{"hasApiVersionChanged" => true},
               "data" => %{}
             }) == {:error, :empty}
    end

    test "treats empty data as :empty" do
      assert Parser.parse_detail(%{"data" => %{}}) == {:error, :empty}
    end
  end
end

defmodule OQueMudou.ScraperTest do
  use OQueMudou.DataCase, async: true

  alias OQueMudou.Repo
  alias OQueMudou.Scraper
  alias OQueMudou.Scraper.Client
  alias OQueMudou.Register.{Edition, Act}

  @list_fixture Path.join([__DIR__, "..", "support", "fixtures", "dre_list_2026-06-24.json"])

  @detail_payload %{
    "versionInfo" => %{"hasApiVersionChanged" => false},
    "data" => %{
      "DetalheConteudo" => %{
        "TextoFormatado" => "<p>texto integral do diploma</p>",
        "URL_PDF" => "https://files.diariodarepublica.pt/1s/2026/06/12000/0000300003.pdf"
      }
    }
  }

  # A bootstrapped client whose HTTP is stubbed with Req.Test, routing by path.
  defp stub_client(opts \\ []) do
    enrich_detail = Keyword.get(opts, :detail, @detail_payload)
    fixture = @list_fixture |> File.read!() |> Jason.decode!()

    Req.Test.stub(OQueMudou.DREStub, fn conn ->
      cond do
        String.contains?(conn.request_path, "WB_Serie1_List") ->
          Req.Test.json(conn, fixture)

        String.contains?(conn.request_path, "Conteudo_Detalhe") ->
          Req.Test.json(conn, enrich_detail)

        true ->
          Req.Test.json(conn, %{})
      end
    end)

    %{
      Client.new(req_options: [plug: {Req.Test, OQueMudou.DREStub}])
      | module_version: "test-mv",
        crf: "test-crf",
        cookie: "nr1Users=x; nr2Users=y"
    }
  end

  test "ingest_date/2 populates editions and acts" do
    assert {:ok, summary} = Scraper.ingest_date(~D[2026-06-24], client: stub_client())

    assert summary.editions == 1
    assert summary.acts == 17
    assert summary.enriched == 17

    assert Repo.aggregate(Edition, :count) == 1
    assert Repo.aggregate(Act, :count) == 17

    edition = Repo.one!(Edition)
    assert edition.number == "120/2026"
    assert edition.scraped_at

    act = Repo.get_by!(Act, dre_id: "1138160247")
    assert act.edition_id == edition.id
    assert act.emitter == "Presidência da República"
    assert act.full_text == "<p>texto integral do diploma</p>"
    assert act.pdf_url =~ "files.diariodarepublica.pt"
  end

  test "ingest_date/2 is idempotent on re-run" do
    assert {:ok, _} = Scraper.ingest_date(~D[2026-06-24], client: stub_client())
    assert {:ok, _} = Scraper.ingest_date(~D[2026-06-24], client: stub_client())

    assert Repo.aggregate(Edition, :count) == 1
    assert Repo.aggregate(Act, :count) == 17
  end

  test "a later skeleton-only scrape does not clobber enrichment" do
    assert {:ok, _} = Scraper.ingest_date(~D[2026-06-24], client: stub_client())
    # re-scrape without enrichment (full_text/pdf_url would be nil in attrs)
    assert {:ok, _} = Scraper.ingest_date(~D[2026-06-24], client: stub_client(), enrich: false)

    act = Repo.get_by!(Act, dre_id: "1138160247")
    assert act.full_text == "<p>texto integral do diploma</p>"
    assert act.pdf_url =~ "files.diariodarepublica.pt"
  end

  test "ingest tolerates a rotated detail apiVersion (acts still persisted, un-enriched)" do
    rotated = %{"versionInfo" => %{"hasApiVersionChanged" => true}, "data" => %{}}

    assert {:ok, summary} =
             Scraper.ingest_date(~D[2026-06-24], client: stub_client(detail: rotated))

    assert summary.acts == 17
    assert summary.enriched == 0

    act = Repo.get_by!(Act, dre_id: "1138160247")
    assert act.full_text == nil
    assert act.pdf_url == nil
  end
end

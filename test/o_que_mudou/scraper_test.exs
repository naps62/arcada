defmodule OQueMudou.ScraperTest do
  use OQueMudou.DataCase, async: true

  alias OQueMudou.Repo
  alias OQueMudou.Scraper
  alias OQueMudou.Scraper.Client
  alias OQueMudou.Register.{Edition, Act}

  @list_fixture Path.join([__DIR__, "..", "support", "fixtures", "dre_list_2026-06-24.json"])

  # Fresh apiVersions the (stubbed) mvc.js bundles advertise. They differ from
  # the compile-time config defaults, so any test that makes screenservices
  # require them exercises the full self-heal (re-derive + retry) path.
  @healed_list "healed-list-abc123"
  @healed_detail "healed-detail-def456"

  @detail_payload %{
    "versionInfo" => %{"hasApiVersionChanged" => false},
    "data" => %{
      "DetalheConteudo" => %{
        "TextoFormatado" => "<p>texto integral do diploma</p>",
        "URL_PDF" => "https://files.diariodarepublica.pt/1s/2026/06/12000/0000300003.pdf"
      }
    }
  }

  @version_changed %{"versionInfo" => %{"hasApiVersionChanged" => true}, "data" => %{}}

  # A bootstrapped client whose HTTP is stubbed with Req.Test, routing by path.
  #
  # Opts (default: everything succeeds without needing a heal):
  #   * `:detail` — the detail screenservices payload (default `@detail_payload`)
  #   * `:list_current` / `:detail_current` — when set, that screenservices path
  #     only returns real data if the request's `apiVersion` matches this value
  #     (else `hasApiVersionChanged: true`), simulating a rotated hash.
  #   * `:manifest` — set `false` to make the OutSystems manifest unreachable, so
  #     re-derivation can't run and the act degrades un-enriched.
  defp stub_client(opts \\ []) do
    fixture = @list_fixture |> File.read!() |> Jason.decode!()
    detail = Keyword.get(opts, :detail, @detail_payload)
    list_current = Keyword.get(opts, :list_current)
    detail_current = Keyword.get(opts, :detail_current)
    manifest? = Keyword.get(opts, :manifest, true)

    Req.Test.stub(OQueMudou.DREStub, fn conn ->
      path = conn.request_path

      cond do
        String.contains?(path, "moduleservices/moduleinfo") ->
          Req.Test.json(conn, if(manifest?, do: manifest(), else: %{}))

        String.contains?(path, "WB_Serie1_List.mvc.js") ->
          send_js(conn, "DataActionGetDataAndApplicationSettings", @healed_list)

        String.contains?(path, "Conteudo_Detalhe.mvc.js") ->
          send_js(conn, "DataActionGetAllConteudoDetalheData", @healed_detail)

        String.contains?(path, "WB_Serie1_List") ->
          serve_versioned(conn, list_current, fixture)

        String.contains?(path, "Conteudo_Detalhe") ->
          serve_versioned(conn, detail_current, detail)

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

  defp manifest do
    %{
      "manifest" => %{
        "urlVersions" => %{
          "/dr/scripts/dr.Home.WB_Serie1_List.mvc.js" => "?listhash",
          "/dr/scripts/dr.Legislacao_Conteudos.Conteudo_Detalhe.mvc.js" => "?detailhash"
        }
      }
    }
  end

  defp send_js(conn, action, version) do
    js = ~s|x callDataAction("#{action}", "screenservices/#{action}", "#{version}", function (b|
    Plug.Conn.send_resp(conn, 200, js)
  end

  defp serve_versioned(conn, nil, payload), do: Req.Test.json(conn, payload)

  defp serve_versioned(conn, current, payload) do
    {:ok, raw, conn} = Plug.Conn.read_body(conn)
    sent = get_in(Jason.decode!(raw), ["versionInfo", "apiVersion"])

    if sent == current,
      do: Req.Test.json(conn, payload),
      else: Req.Test.json(conn, @version_changed)
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

  test "self-heals a rotated detail apiVersion (re-derives, retries, enriches)" do
    # The detail action rejects the stale config hash and only serves data for
    # the freshly-derived one — so enrichment only succeeds via self-heal.
    assert {:ok, summary} =
             Scraper.ingest_date(~D[2026-06-24],
               client: stub_client(detail_current: @healed_detail)
             )

    assert summary.acts == 17
    assert summary.enriched == 17

    act = Repo.get_by!(Act, dre_id: "1138160247")
    assert act.full_text == "<p>texto integral do diploma</p>"
    assert act.pdf_url =~ "files.diariodarepublica.pt"
  end

  test "self-heals a rotated list apiVersion (re-derives, retries)" do
    assert {:ok, summary} =
             Scraper.ingest_date(~D[2026-06-24], client: stub_client(list_current: @healed_list))

    assert summary.editions == 1
    assert summary.acts == 17
  end

  test "degrades gracefully when re-derivation is unavailable" do
    # Detail hash rotated AND the manifest is unreachable → can't re-derive, so
    # acts persist un-enriched rather than failing the scrape.
    assert {:ok, summary} =
             Scraper.ingest_date(~D[2026-06-24],
               client: stub_client(detail_current: "never-matches", manifest: false)
             )

    assert summary.acts == 17
    assert summary.enriched == 0

    act = Repo.get_by!(Act, dre_id: "1138160247")
    assert act.full_text == nil
    assert act.pdf_url == nil
  end
end

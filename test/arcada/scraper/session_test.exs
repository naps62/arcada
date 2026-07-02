defmodule Arcada.Scraper.SessionTest do
  # Exercises the detect → heal → retry loop directly, without the DB/ingest path.
  use ExUnit.Case, async: true

  alias Arcada.Scraper.{Client, Session}

  # Fresh apiVersions the (stubbed) mvc.js bundles advertise — different from the
  # config defaults a plain client carries, so any action that requires them
  # exercises the full self-heal.
  @healed_list "healed-list-abc123"
  @healed_detail "healed-detail-def456"

  @list_payload %{
    "versionInfo" => %{"hasApiVersionChanged" => false},
    "data" => %{"DiarioByDiaList" => %{"List" => []}}
  }

  @detail_payload %{
    "versionInfo" => %{"hasApiVersionChanged" => false},
    "data" => %{
      "DetalheConteudo" => %{
        "TextoFormatado" => "<p>texto</p>",
        "URL_PDF" => "https://files.diariodarepublica.pt/x.pdf"
      }
    }
  }

  @version_changed %{"versionInfo" => %{"hasApiVersionChanged" => true}, "data" => %{}}

  # Same stub shape as ScraperTest, minus the list fixture. Opts:
  #   * `:list_current` / `:detail_current` — that action only serves data when
  #     the request's apiVersion matches (else reports rotation).
  #   * `:manifest` — false makes re-derivation impossible (degrade path).
  defp start_session(opts \\ []) do
    list_current = Keyword.get(opts, :list_current)
    detail_current = Keyword.get(opts, :detail_current)
    manifest? = Keyword.get(opts, :manifest, true)

    Req.Test.stub(__MODULE__, fn conn ->
      path = conn.request_path

      cond do
        String.contains?(path, "moduleservices/moduleinfo") ->
          Req.Test.json(conn, if(manifest?, do: manifest(), else: %{}))

        String.contains?(path, "WB_Serie1_List.mvc.js") ->
          send_js(conn, "DataActionGetDataAndApplicationSettings", @healed_list)

        String.contains?(path, "Conteudo_Detalhe.mvc.js") ->
          send_js(conn, "DataActionGetAllConteudoDetalheData", @healed_detail)

        String.contains?(path, "WB_Serie1_List") ->
          serve_versioned(conn, list_current, @list_payload)

        String.contains?(path, "Conteudo_Detalhe") ->
          serve_versioned(conn, detail_current, @detail_payload)

        true ->
          Req.Test.json(conn, %{})
      end
    end)

    client = %{
      Client.new(req_options: [plug: {Req.Test, __MODULE__}])
      | module_version: "test-mv",
        crf: "test-crf",
        cookie: "nr1Users=x; nr2Users=y"
    }

    {:ok, session} = Session.start_link(client: client)
    on_exit(fn -> if Process.alive?(session), do: Session.stop(session) end)
    session
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

  test "list_editions/2 returns the raw body, no apiVersion in sight" do
    session = start_session()

    assert {:ok, %{"data" => %{"DiarioByDiaList" => _}}} =
             Session.list_editions(session, ~D[2026-06-24])
  end

  test "act_detail/3 returns parsed enrichment" do
    session = start_session()

    assert {:ok,
            %{full_text: "<p>texto</p>", pdf_url: "https://files.diariodarepublica.pt/x.pdf"}} =
             Session.act_detail(session, "portaria", "1-2026-1")
  end

  test "self-heals a rotated detail apiVersion and enriches on retry" do
    session = start_session(detail_current: @healed_detail)

    assert {:ok, %{full_text: "<p>texto</p>"}} =
             Session.act_detail(session, "portaria", "1-2026-1")
  end

  test "self-heals a rotated list apiVersion" do
    session = start_session(list_current: @healed_list)

    assert {:ok, %{"data" => %{"DiarioByDiaList" => _}}} =
             Session.list_editions(session, ~D[2026-06-24])
  end

  test "reuses the healed apiVersion for later calls (heals once)" do
    session = start_session(detail_current: @healed_detail)
    assert {:ok, _} = Session.act_detail(session, "portaria", "1-2026-1")
    # A second call succeeds against the already-healed hash (no rotation served).
    assert {:ok, %{full_text: "<p>texto</p>"}} =
             Session.act_detail(session, "portaria", "2-2026-2")
  end

  test "degrades to :empty when re-derivation is unavailable" do
    session = start_session(detail_current: "never-matches", manifest: false)
    assert {:error, :empty} = Session.act_detail(session, "portaria", "1-2026-1")
  end
end

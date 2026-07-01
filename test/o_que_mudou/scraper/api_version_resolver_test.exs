defmodule OQueMudou.Scraper.ApiVersionResolverTest do
  use ExUnit.Case, async: true

  alias OQueMudou.Scraper.{ApiVersionResolver, Client}

  defp client, do: Client.new(req_options: [plug: {Req.Test, __MODULE__}])

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

  defp mvc(action, version) do
    # Mimic the minified bundle: callDataAction(name, path, apiVersion, cb, …).
    ~s|a("x");callDataAction("#{action}", "screenservices/dr/X/#{action}", "#{version}", function (b) {})|
  end

  test "derives the live apiVersion from the manifest + mvc.js bundles" do
    Req.Test.stub(__MODULE__, fn conn ->
      cond do
        String.contains?(conn.request_path, "moduleservices/moduleinfo") ->
          Req.Test.json(conn, manifest())

        String.contains?(conn.request_path, "WB_Serie1_List.mvc.js") ->
          Plug.Conn.send_resp(conn, 200, mvc("DataActionGetDataAndApplicationSettings", "LIST-9"))

        String.contains?(conn.request_path, "Conteudo_Detalhe.mvc.js") ->
          Plug.Conn.send_resp(conn, 200, mvc("DataActionGetAllConteudoDetalheData", "DET-9"))
      end
    end)

    assert {:ok, %{list: "LIST-9", detail: "DET-9"}} = ApiVersionResolver.resolve(client())
  end

  test "resolves a single requested key" do
    Req.Test.stub(__MODULE__, fn conn ->
      cond do
        String.contains?(conn.request_path, "moduleservices/moduleinfo") ->
          Req.Test.json(conn, manifest())

        String.contains?(conn.request_path, "Conteudo_Detalhe.mvc.js") ->
          Plug.Conn.send_resp(conn, 200, mvc("DataActionGetAllConteudoDetalheData", "DET-42"))
      end
    end)

    assert {:ok, %{detail: "DET-42"}} = ApiVersionResolver.resolve(client(), [:detail])
  end

  test "returns nil for an action whose script is missing from the manifest" do
    Req.Test.stub(__MODULE__, fn conn ->
      # Manifest present but with no urlVersions entries → script path unresolved.
      Req.Test.json(conn, %{"manifest" => %{"urlVersions" => %{}}})
    end)

    assert {:ok, %{detail: nil}} = ApiVersionResolver.resolve(client(), [:detail])
  end

  test "errors when the manifest itself is unreachable" do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{}) end)

    assert {:error, :manifest_shape} = ApiVersionResolver.resolve(client())
  end
end

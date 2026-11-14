defmodule Arcada.Summarizer.Adapters.ApiTest do
  use Arcada.DataCase, async: false

  import Arcada.SummarizerHelpers

  alias Arcada.Register.Act
  alias Arcada.Summarizer.Adapters.Api

  defp act, do: %Act{id: 1, tipo: "Lei", emitter: "AR", title: "Lei n.º 1/2026", full_text: "x"}

  defp reply,
    do: Jason.encode!(%{"plain_text" => "Resumo.", "headline" => "Título", "domains" => []})

  test "summarizes via the Messages API with structured output and prices the usage" do
    stub_claude_api(fn conn ->
      assert ["test-key"] = Plug.Conn.get_req_header(conn, "x-api-key")
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(raw)
      assert body["model"] == "claude-opus-5-5"
      assert body["output_config"]["format"]["type"] == "json_schema"
      assert body["messages"] |> hd() |> Map.get("content") =~ "texto do diploma"
      Req.Test.json(conn, claude_response(reply()))
    end)

    assert {:ok, result} =
             Api.summarize(act(), anthropic_provider(), "claude-opus-5-5", "texto do diploma")

    assert result.plain_text == "Resumo."
    assert result.headline == "Título"
    assert result.model == "claude-opus-5-5"
    assert result.input_tokens == 1_000
    assert result.cost_source == "api"
    # 1000 × $4/M + 200 × $20/M
    assert Decimal.equal?(result.cost_usd, Decimal.new("0.008"))
  end

  test "a non-200 is an http_status error" do
    stub_claude_api(fn conn ->
      conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => %{"type" => "x"}})
    end)

    assert {:error, {:http_status, 400}} =
             Api.summarize(act(), anthropic_provider(), "claude-opus-5-5", "t")
  end

  test "a refusal is an error, not a summary" do
    stub_claude_api(fn conn ->
      Req.Test.json(conn, claude_response("", %{"stop_reason" => "refusal"}))
    end)

    assert {:error, :refusal} = Api.summarize(act(), anthropic_provider(), "claude-opus-5-5", "t")
  end

  test "cost uses the longest matching price prefix" do
    assert Decimal.equal?(Api.cost("claude-opus-4-8", 1_000_000, 0), Decimal.new("5.0"))
    assert Decimal.equal?(Api.cost("claude-opus-5-5", 1_000_000, 0), Decimal.new("4.0"))
    assert Decimal.equal?(Api.cost("claude-sonnet-4-6", 1_000_000, 0), Decimal.new("3.0"))
    assert Decimal.equal?(Api.cost("claude-sonnet-5-5", 1_000_000, 0), Decimal.new("2.0"))
    assert Api.cost("some-other-model", 1, 1) == nil
  end
end

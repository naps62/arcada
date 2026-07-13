defmodule Arcada.Summarizer.ExtractorTest do
  use Arcada.DataCase, async: false

  import Arcada.SummarizerHelpers

  alias Arcada.Summarizer.Extractor
  alias Arcada.Register.Act

  defp act, do: %Act{id: 1, tipo: "Lei", emitter: "AR", title: "Lei n.º 1/2026", full_text: "x"}

  test "parses a valid extractor reply into headline + changes" do
    stub_extractor(fn ctx ->
      assert ctx.text == "texto"
      {:ok, Jason.encode!(%{"headline" => "Título", "changes" => ["muda A", "muda B"]})}
    end)

    assert {:ok, %{headline: "Título", changes: ["muda A", "muda B"]}} =
             Extractor.extract(act(), "texto", openai_provider(), "glm-x")
  end

  test "an unparseable reply is an error (caller falls back)" do
    stub_extractor(fn _ -> {:ok, "definitely not json"} end)

    assert {:error, :unparseable_extraction} =
             Extractor.extract(act(), "t", openai_provider(), "m")
  end

  test "a runner/transport error propagates as an error" do
    stub_extractor(fn _ -> {:error, :timeout} end)
    assert {:error, :timeout} = Extractor.extract(act(), "t", openai_provider(), "m")
  end

  test "a non-openai provider is unsupported (no runner stub)" do
    assert {:error, :unsupported_extractor} = Extractor.extract(act(), "t", ssh_provider(), "m")
  end
end

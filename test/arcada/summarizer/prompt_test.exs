defmodule Arcada.Summarizer.PromptTest do
  @moduledoc """
  The single test surface for how every adapter's reply is parsed and how domains
  are validated — the prompt-and-parse contract used by all three backends.
  """
  use ExUnit.Case, async: true

  alias Arcada.Register
  alias Arcada.Summarizer.Prompt

  defp act do
    %Arcada.Register.Act{
      tipo: "Decreto-Lei",
      emitter: "Finanças",
      title: "Decreto-Lei n.º 1/2026"
    }
  end

  defp reply(fields), do: Jason.encode!(fields)

  describe "parse/1" do
    test "returns the summary fields with domains as taxonomy atoms" do
      raw =
        reply(%{
          "plain_text" => "Muda o IRS.",
          "headline" => "IRS muda",
          "domains" => ["fiscal", "trabalho"]
        })

      assert {:ok, attrs} = Prompt.parse(raw)
      assert attrs.plain_text == "Muda o IRS."
      assert attrs.headline == "IRS muda"
      assert attrs.domains == [:fiscal, :trabalho]
    end

    test "drops domains outside the fixed taxonomy, deduping the rest" do
      raw = reply(%{"plain_text" => "x", "domains" => ["fiscal", "cripto", "saúde", "fiscal"]})
      assert {:ok, %{domains: [:fiscal, :saúde]}} = Prompt.parse(raw)
    end

    test "tolerates ```json code fences around the reply" do
      inner = reply(%{"plain_text" => "y", "domains" => []})

      assert {:ok, %{plain_text: "y", headline: nil, domains: []}} =
               Prompt.parse("```json\n" <> inner <> "\n```")
    end

    test "a missing headline is nil, not an error" do
      assert {:ok, %{headline: nil}} =
               Prompt.parse(reply(%{"plain_text" => "z", "domains" => []}))
    end

    # AMALIA-9B reproducibly emits a valid object, then keeps talking: a markdown
    # `**Nota:**`, a self-correction, and a second object. We take the first
    # object and drop the trailing chatter (observed on act 164, RCM 128/2026).
    test "recovers the first object when the model appends prose and a second object" do
      first = reply(%{"plain_text" => "Apoio militar à Ucrânia.", "domains" => ["fiscal"]})
      second = reply(%{"plain_text" => "corrigido", "domains" => ["saúde"]})
      raw = first <> "\r\n\r\n**Nota:** o domínio não se aplica. Vou corrigir:\r\n\r\n" <> second

      assert {:ok, %{plain_text: "Apoio militar à Ucrânia.", domains: [:fiscal]}} =
               Prompt.parse(raw)
    end

    test "ignores braces inside string values when finding the object" do
      raw =
        ~s({"plain_text": "usa {chavetas} e \\"aspas\\" no texto", "domains": []}) <>
          "\n\ntrailing junk }"

      assert {:ok, %{plain_text: "usa {chavetas} e \"aspas\" no texto"}} = Prompt.parse(raw)
    end

    test "non-list domains become an empty list" do
      assert {:ok, %{domains: []}} =
               Prompt.parse(reply(%{"plain_text" => "z", "domains" => "fiscal"}))
    end

    test "errors when the reply is not JSON" do
      assert {:error, :unparseable_reply} = Prompt.parse("not json at all")
    end

    test "errors when plain_text is missing or not a string" do
      assert {:error, :unparseable_reply} =
               Prompt.parse(reply(%{"headline" => "h", "domains" => []}))

      assert {:error, :unparseable_reply} =
               Prompt.parse(reply(%{"plain_text" => 42, "domains" => []}))
    end

    test "errors on a non-binary input" do
      assert {:error, :unparseable_reply} = Prompt.parse(nil)
    end
  end

  describe "valid_domains/1" do
    test "keeps taxonomy members and drops the rest" do
      assert Prompt.valid_domains(["fiscal", "nope", "saúde"]) == [:fiscal, :saúde]
    end

    test "non-lists yield []" do
      assert Prompt.valid_domains(nil) == []
      assert Prompt.valid_domains("fiscal") == []
    end
  end

  describe "decode/1" do
    test "decodes fenced and plain JSON, errors on junk" do
      assert {:ok, %{"a" => 1}} = Prompt.decode(~s({"a": 1}))
      assert {:ok, %{"a" => 1}} = Prompt.decode("```json\n" <> ~s({"a": 1}) <> "\n```")
      assert {:ok, %{"a" => 1}} = Prompt.decode(~s({"a": 1}) <> "\n\ntrailing prose")
      assert {:error, _} = Prompt.decode("garbage")
      assert {:error, :not_a_string} = Prompt.decode(nil)
    end
  end

  describe "schema/0" do
    test "constrains domains to the fixed taxonomy and requires the three fields" do
      schema = Prompt.schema()
      assert schema["required"] == ["plain_text", "headline", "domains"]
      assert schema["properties"]["domains"]["items"]["enum"] == Register.life_domains()
    end
  end

  describe "prompt building" do
    test "system/0 carries the writing rules" do
      assert Prompt.system() =~ "jornalista"
    end

    test "system/1 appends the omnibus note for :rank and :truncate, not :full" do
      base = Prompt.system()
      note = "altera várias coisas ao mesmo tempo"

      refute base =~ note
      refute Prompt.system(strategy: :full) =~ note
      assert Prompt.system(strategy: :rank) =~ note
      assert Prompt.system(strategy: :truncate) =~ note
      # still carries the base rules, just extended
      assert Prompt.system(strategy: :rank) =~ "jornalista"
    end

    test "act_body/2 lays out the metadata and the prepared text" do
      body = Prompt.act_body(act(), "TEXTO-XYZ")
      assert body =~ "Tipo: Decreto-Lei"
      assert body =~ "Emissor: Finanças"
      assert body =~ "Título: Decreto-Lei n.º 1/2026"
      assert body =~ "TEXTO-XYZ"
    end

    test "instructed_prompt/2 wraps the act body with the JSON instruction and taxonomy" do
      prompt = Prompt.instructed_prompt(act(), "TEXTO-XYZ")
      assert prompt =~ "objeto JSON válido"
      assert prompt =~ Enum.join(Register.life_domains(), ", ")
      assert prompt =~ "TEXTO-XYZ"
    end
  end
end

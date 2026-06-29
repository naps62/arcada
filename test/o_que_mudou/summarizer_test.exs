defmodule OQueMudou.SummarizerTest do
  use OQueMudou.DataCase, async: false
  use Oban.Testing, repo: OQueMudou.Repo

  import OQueMudou.SummarizerHelpers

  alias OQueMudou.{Admin, Repo}
  alias OQueMudou.Register.{Edition, Act, Summary}
  alias OQueMudou.Summarizer
  alias OQueMudou.Summarizer.{Embeddings, SummarizeWorker}

  defp act_fixture do
    edition =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "120/2026", date: ~D[2026-06-24]})
      |> Repo.insert!()

    %Act{}
    |> Act.changeset(%{
      edition_id: edition.id,
      dre_id: "1138160247",
      title: "Decreto-Lei n.º 1/2026"
    })
    |> Repo.insert!()
  end

  describe "summarize/3 (explicit provider+model)" do
    test "persists the result linked to the provider" do
      stub_ssh_runner(fn _ -> {:ok, claude_envelope("Muda o IRS.", ["fiscal", "trabalho"])} end)
      provider = ssh_provider()

      assert {:ok, summary} = Summarizer.summarize(act_fixture(), provider, "claude-cli")
      assert summary.plain_text == "Muda o IRS."
      assert summary.domains == [:fiscal, :trabalho]
      assert summary.model == "claude-cli"
      assert summary.provider_id == provider.id
      assert summary.status == :unreviewed
      assert summary.generated_at
    end

    test "propagates adapter errors" do
      stub_ssh_runner(fn _ -> {:error, {:ssh_exit, 7}} end)
      assert {:error, _} = Summarizer.summarize(act_fixture(), ssh_provider(), "claude-cli")
    end
  end

  describe "summarize/1 (active provider)" do
    test "defers when no active provider is set" do
      assert {:async, :no_active_provider} = Summarizer.summarize(act_fixture())
      assert Repo.aggregate(Summary, :count) == 0
    end

    test "uses the active provider+model" do
      stub_ssh_runner(fn _ -> {:ok, claude_envelope("x", ["fiscal"])} end)
      provider = ssh_provider()

      {:ok, _} =
        Admin.update_settings(%{
          "active_provider_id" => provider.id,
          "active_model" => "claude-cli"
        })

      assert {:ok, summary} = Summarizer.summarize(act_fixture())
      assert summary.provider_id == provider.id
      assert summary.model == "claude-cli"
    end
  end

  describe "enqueue/2" do
    test "encodes a manual provider+model run into the job args" do
      act = act_fixture()
      assert {:ok, %Oban.Job{args: args}} = Summarizer.enqueue(act, provider_id: 7, model: "m")
      assert args["provider_id"] == 7
      assert args["model"] == "m"
    end
  end

  describe "SummarizeWorker" do
    test "runs the active provider inline" do
      stub_ssh_runner(fn _ -> {:ok, claude_envelope("y", [])} end)
      provider = ssh_provider()

      {:ok, _} =
        Admin.update_settings(%{
          "active_provider_id" => provider.id,
          "active_model" => "claude-cli"
        })

      act = act_fixture()

      assert :ok = perform_job(SummarizeWorker, %{act_id: act.id})
      assert Repo.one!(Summary).provider_id == provider.id
    end

    test "a pinned provider_id overrides the active one" do
      stub_ssh_runner(fn _ -> {:ok, claude_envelope("z", [])} end)
      provider = ssh_provider()
      act = act_fixture()

      assert :ok =
               perform_job(SummarizeWorker, %{
                 act_id: act.id,
                 provider_id: provider.id,
                 model: "claude-cli"
               })

      assert Repo.one!(Summary).provider_id == provider.id
    end

    test "missing act is a no-op success" do
      assert :ok = perform_job(SummarizeWorker, %{act_id: 999_999})
    end
  end

  describe "create_summary/2 (manual backfill)" do
    test "inserts and stamps generated_at" do
      act = act_fixture()

      assert {:ok, summary} =
               Summarizer.create_summary(act, %{
                 plain_text: "Resumo manual.",
                 domains: [:habitação]
               })

      assert summary.act_id == act.id
      assert summary.generated_at
    end
  end

  defp set_embeddings(kw) do
    prev = Application.get_env(:o_que_mudou, Embeddings, [])
    Application.put_env(:o_que_mudou, Embeddings, kw)
    on_exit(fn -> Application.put_env(:o_que_mudou, Embeddings, prev) end)
  end

  # Vectors orthogonal to the query for annex text, aligned for everything else,
  # so the ranker keeps the articles and drops the annex.
  defp relevance_embed do
    fn texts ->
      vecs =
        Enum.map(texts, fn t ->
          if String.contains?(t, "ANEXO"), do: [0.0, 1.0], else: [1.0, 0.0]
        end)

      {:ok, vecs}
    end
  end

  defp diploma(annex_size) do
    """
    Preâmbulo curto a explicar o objeto.

    Artigo 1.º
    Cria uma nova obrigação para os contribuintes.

    Artigo 2.º
    Produz efeitos a partir de janeiro de 2027.

    ANEXO I
    #{String.duplicate("9", annex_size)}
    """
  end

  describe "max_text_chars/0" do
    test "defaults to 80k, honours the DB setting" do
      assert Summarizer.max_text_chars() == 80_000

      {:ok, _} = Admin.update_settings(%{"max_text_chars" => "120000"})
      assert Summarizer.max_text_chars() == 120_000
    end
  end

  describe "prepare_text/2" do
    test "returns text unchanged when it fits" do
      assert Summarizer.prepare_text("curto", 1_000) == "curto"
    end

    test "head-truncates when the ranker is disabled" do
      set_embeddings([])
      text = String.duplicate("a", 500)
      out = Summarizer.prepare_text(text, 100)
      assert out == Summarizer.cap_text(text, 100)
      assert String.contains?(out, "truncado")
    end

    test "keeps change-relevant sections and drops the annex when ranking is on" do
      set_embeddings(embed_fn: relevance_embed())

      out = Summarizer.prepare_text(diploma(800), 400)

      assert String.contains?(out, "Artigo 1.º")
      assert String.contains?(out, "Artigo 2.º")
      refute String.contains?(out, "999999")
      assert String.contains?(out, "truncado")
    end

    test "preserves document order of kept sections" do
      set_embeddings(embed_fn: relevance_embed())
      out = Summarizer.prepare_text(diploma(800), 400)
      assert :binary.match(out, "Artigo 1.º") < :binary.match(out, "Artigo 2.º")
    end

    test "falls back to head-truncation when the embed call fails" do
      set_embeddings(embed_fn: fn _ -> {:error, :boom} end)
      text = diploma(800)
      assert Summarizer.prepare_text(text, 400) == Summarizer.cap_text(text, 400)
    end

    test "falls back to head-truncation for unstructured oversized text" do
      set_embeddings(embed_fn: relevance_embed())
      text = String.duplicate("texto sem cabecalhos ", 60)
      assert Summarizer.prepare_text(text, 100) == Summarizer.cap_text(text, 100)
    end
  end
end

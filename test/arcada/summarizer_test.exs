defmodule Arcada.SummarizerTest do
  use Arcada.DataCase, async: false
  use Oban.Testing, repo: Arcada.Repo

  import Arcada.SummarizerHelpers

  alias Arcada.{Admin, Repo}
  alias Arcada.Register.{Edition, Act, Summary}
  alias Arcada.Search.Index
  alias Arcada.Summarizer
  alias Arcada.Summarizer.{ContextWindow, Embeddings, SummarizeWorker}

  setup do
    Index.clear()
    :ok
  end

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

  defp oversized_act(full_text) do
    n = System.unique_integer([:positive])

    edition =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "121-#{n}/2026", date: ~D[2026-06-25]})
      |> Repo.insert!()

    %Act{}
    |> Act.changeset(%{
      edition_id: edition.id,
      dre_id: "long-#{n}",
      title: "x",
      full_text: full_text
    })
    |> Repo.insert!()
  end

  describe "summarize/3 (explicit provider+model)" do
    test "persists the result linked to the provider" do
      stub_ssh_runner(fn _ ->
        {:ok,
         claude_envelope("Muda o IRS.", ["fiscal", "trabalho"], %{}, "IRS muda para autónomos")}
      end)

      provider = ssh_provider()

      assert {:ok, summary} = Summarizer.summarize(act_fixture(), provider, "claude-cli")
      assert summary.plain_text == "Muda o IRS."
      assert summary.headline == "IRS muda para autónomos"
      assert summary.domains == [:fiscal, :trabalho]
      assert summary.model == "claude-cli"
      assert summary.provider_id == provider.id
      assert summary.generated_at
    end

    test "persists token usage + cost reported by the adapter" do
      extra = %{
        "total_cost_usd" => 0.0123,
        "usage" => %{"input_tokens" => 1200, "output_tokens" => 300},
        "duration_ms" => 1500
      }

      stub_ssh_runner(fn _ -> {:ok, claude_envelope("ok", [], extra)} end)

      assert {:ok, summary} = Summarizer.summarize(act_fixture(), ssh_provider(), "claude-cli")
      assert summary.input_tokens == 1200
      assert summary.output_tokens == 300
      assert summary.cost_source == "subscription"
      assert summary.duration_ms == 1500
      assert Decimal.equal?(summary.cost_usd, Decimal.from_float(0.0123) |> Decimal.round(6))
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

  describe "auto-pin canonical (automated path)" do
    setup do
      stub_ssh_runner(fn _ -> {:ok, claude_envelope("x", [])} end)
      provider = ssh_provider()

      {:ok, _} =
        Admin.update_settings(%{
          "active_provider_id" => provider.id,
          "active_model" => "claude-cli"
        })

      :ok
    end

    test "pins a new act's first summary as canonical" do
      act = act_fixture()
      assert {:ok, summary} = Summarizer.summarize(act)
      assert Repo.get(Act, act.id).published_summary_id == summary.id
    end

    test "a later automated run does not move an existing pin" do
      act = act_fixture()
      {:ok, first} = Summarizer.summarize(act)
      assert Repo.get(Act, act.id).published_summary_id == first.id

      # regenerate via the automated path — the pin must stay on `first`.
      assert {:ok, second} = Summarizer.summarize(Repo.get(Act, act.id))
      assert second.id != first.id
      assert Repo.get(Act, act.id).published_summary_id == first.id
    end

    test "a manual per-act run never pins" do
      act = act_fixture()
      assert {:ok, _} = Summarizer.summarize(act, ssh_provider(), "claude-cli")
      assert Repo.get(Act, act.id).published_summary_id == nil
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

    test "snoozes when the provider is at its concurrency limit" do
      provider = ssh_provider()
      act = act_fixture()

      # One job already executing for this (limit-1 SSH) provider, ahead of ours.
      Repo.insert!(%Oban.Job{
        worker: "Arcada.Summarizer.SummarizeWorker",
        queue: "summarize",
        state: "executing",
        args: %{"act_id" => act.id, "provider_id" => provider.id}
      })

      job = %Oban.Job{
        id: 100_000_000,
        args: %{"act_id" => act.id, "provider_id" => provider.id}
      }

      assert {:snooze, _} = SummarizeWorker.perform(job)
      assert Repo.aggregate(Summary, :count) == 0
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

  describe "create_summary/2 embedding (issue #27)" do
    test "embeds plain_text and indexes it when the embeddings server is configured" do
      set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 2.0] end)} end)
      act = act_fixture()

      assert {:ok, summary} =
               Summarizer.create_summary(act, %{plain_text: "Resumo pesquisável."})

      assert summary.embedding == [1.0, 2.0]
      assert {summary.id, act.id, [1.0, 2.0]} in Index.all()
    end

    test "leaves embedding nil when the embeddings server is disabled — never blocks the summary" do
      set_embeddings([])
      act = act_fixture()

      assert {:ok, summary} = Summarizer.create_summary(act, %{plain_text: "Resumo."})
      assert summary.embedding == nil
    end

    test "leaves embedding nil when the embed call fails — never blocks the summary" do
      set_embeddings(embed_fn: fn _ -> {:error, :boom} end)
      act = act_fixture()

      assert {:ok, summary} = Summarizer.create_summary(act, %{plain_text: "Resumo."})
      assert summary.embedding == nil
    end
  end

  describe "embed_summary/1" do
    test "computes and persists the embedding, applying the document_prefix" do
      test_pid = self()

      set_embeddings(
        document_prefix: "search_document: ",
        embed_fn: fn texts ->
          send(test_pid, {:embed_inputs, texts})
          {:ok, Enum.map(texts, fn _ -> [3.0] end)}
        end
      )

      act = act_fixture()
      {:ok, summary} = Summarizer.create_summary(act, %{plain_text: "Original."})

      assert {:ok, updated} = Summarizer.embed_summary(summary)
      assert updated.embedding == [3.0]
      assert_received {:embed_inputs, ["search_document: Original."]}
    end

    test "{:error, :embeddings_disabled} when no server is configured" do
      set_embeddings([])
      act = act_fixture()
      {:ok, summary} = Summarizer.create_summary(act, %{plain_text: "x"})

      assert {:error, :embeddings_disabled} = Summarizer.embed_summary(summary)
    end
  end

  defp set_embeddings(kw) do
    prev = Application.get_env(:arcada, Embeddings, [])
    Application.put_env(:arcada, Embeddings, kw)
    on_exit(fn -> Application.put_env(:arcada, Embeddings, prev) end)
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

  describe "max_text_chars/1" do
    test "defaults to the adaptive per-model cap, honours the DB setting" do
      # No DB override → derived from the model's context window (issue #18).
      assert Summarizer.max_text_chars() == ContextWindow.cap_for(nil)
      assert Summarizer.max_text_chars("claude-cli") == ContextWindow.cap_for("claude-cli")
      # A big-context model yields a larger cap than the conservative default.
      assert Summarizer.max_text_chars("claude-cli") > Summarizer.max_text_chars()

      # An explicit DB cap wins over the adaptive default, for any model.
      {:ok, _} = Admin.update_settings(%{"max_text_chars" => "120000"})
      assert Summarizer.max_text_chars() == 120_000
      assert Summarizer.max_text_chars("claude-cli") == 120_000
    end
  end

  describe "target_text_chars/1 (cost target, issue #41)" do
    test "defaults to 120k, well under the safety cap" do
      assert Summarizer.target_text_chars() == 120_000
      assert Summarizer.target_text_chars() < Summarizer.max_text_chars()
    end

    test "honours the DB setting" do
      {:ok, _} = Admin.update_settings(%{"target_text_chars" => "50000"})
      assert Summarizer.target_text_chars() == 50_000
    end

    test "is clamped to the cap so it can never disable ranking" do
      # A target left larger than the ceiling collapses to the ceiling.
      {:ok, _} =
        Admin.update_settings(%{"max_text_chars" => "40000", "target_text_chars" => "999999"})

      assert Summarizer.target_text_chars() == 40_000
    end
  end

  # The budget/ranking truth table lives in Arcada.Summarizer.TextBudgetTest
  # (issue #48). Here we only check the thin convenience delegate.
  describe "prepare_text/2 (delegates to TextBudget)" do
    test "returns text unchanged when it fits" do
      assert Summarizer.prepare_text("curto", 1_000) == "curto"
    end

    test "returns just the prepared string (drops the strategy)" do
      set_embeddings(embed_fn: relevance_embed())
      out = Summarizer.prepare_text(diploma(800), 400)
      assert is_binary(out)
      assert String.contains?(out, "Artigo 1.º")
      refute String.contains?(out, "999999")
    end
  end

  describe "summarize/4 strategy bookkeeping" do
    test "records the effective strategy (rank) and truncated flag" do
      {:ok, _} = Admin.update_settings(%{"max_text_chars" => "400"})
      set_embeddings(embed_fn: relevance_embed())
      stub_ssh_runner(fn _ -> {:ok, claude_envelope("resumo", ["fiscal"])} end)

      assert {:ok, %{text_strategy: "rank", truncated: true}} =
               Summarizer.summarize(oversized_act(diploma(800)), ssh_provider(), "claude-cli")
    end

    test "extract/render: strong model lists changes, renderer writes them (#90)" do
      {:ok, _} = Admin.update_settings(%{"max_text_chars" => "400"})
      set_embeddings(embed_fn: relevance_embed())
      ext = openai_provider()

      {:ok, _} =
        Admin.update_settings(%{"extractor_provider_id" => ext.id, "extractor_model" => "glm-x"})

      stub_extractor(fn _ctx ->
        {:ok,
         Jason.encode!(%{"headline" => "Título do extractor", "changes" => ["muda A", "muda B"]})}
      end)

      # The renderer (ssh) writes from the change list; its headline is discarded.
      stub_ssh_runner(fn prompt ->
        send(self(), {:render_prompt, prompt})
        {:ok, claude_envelope("Muda A. Muda B.", ["fiscal"], %{}, "headline-da-amalia")}
      end)

      assert {:ok, summary} =
               Summarizer.summarize(oversized_act(diploma(800)), ssh_provider(), "claude-cli")

      assert summary.text_strategy == "extract"
      assert summary.extractor_model == "glm-x"
      # headline comes from the extractor, body from the renderer.
      assert summary.headline == "Título do extractor"
      assert summary.plain_text == "Muda A. Muda B."
      # the renderer was fed the extracted changes, in the render prompt.
      assert_received {:render_prompt, prompt}
      assert prompt =~ "muda A"
      assert prompt =~ "muda B"
    end

    test "extract/render falls back to the umbrella summary when the extractor fails (#90)" do
      {:ok, _} = Admin.update_settings(%{"max_text_chars" => "400"})
      set_embeddings(embed_fn: relevance_embed())
      ext = openai_provider()

      {:ok, _} =
        Admin.update_settings(%{"extractor_provider_id" => ext.id, "extractor_model" => "glm-x"})

      stub_extractor(fn _ctx -> {:error, :boom} end)
      stub_ssh_runner(fn _ -> {:ok, claude_envelope("resumo umbrella", [])} end)

      assert {:ok, summary} =
               Summarizer.summarize(oversized_act(diploma(800)), ssh_provider(), "claude-cli")

      # degrades to the plain ranked path — no extractor provenance.
      assert summary.text_strategy == "rank"
      assert summary.extractor_model == nil
      assert summary.plain_text == "resumo umbrella"
    end

    test "no extractor configured keeps the plain ranked path (#90)" do
      {:ok, _} = Admin.update_settings(%{"max_text_chars" => "400"})
      set_embeddings(embed_fn: relevance_embed())
      stub_ssh_runner(fn _ -> {:ok, claude_envelope("resumo", [])} end)

      assert {:ok, summary} =
               Summarizer.summarize(oversized_act(diploma(800)), ssh_provider(), "claude-cli")

      assert summary.text_strategy == "rank"
      assert summary.extractor_model == nil
    end

    test "force rank: an auto run errors instead of persisting a head-truncated summary" do
      {:ok, _} = Admin.update_settings(%{"max_text_chars" => "400"})
      # No set_embeddings -> ranker unavailable, so an over-cap act would otherwise
      # fall back to :truncate. Force-rank (#89) turns that into a retryable error.
      stub_ssh_runner(fn _ -> {:ok, claude_envelope("resumo", [])} end)

      assert {:error, :ranker_unavailable} =
               Summarizer.summarize(oversized_act(diploma(800)), ssh_provider(), "claude-cli")
    end

    test "honours a forced :truncate run" do
      {:ok, _} = Admin.update_settings(%{"max_text_chars" => "400"})
      set_embeddings(embed_fn: relevance_embed())
      stub_ssh_runner(fn _ -> {:ok, claude_envelope("resumo", [])} end)

      assert {:ok, %{text_strategy: "truncate"}} =
               Summarizer.summarize(oversized_act(diploma(800)), ssh_provider(), "claude-cli",
                 text_strategy: :truncate
               )
    end

    test "a fitting act is recorded as full / not truncated" do
      stub_ssh_runner(fn _ -> {:ok, claude_envelope("resumo", [])} end)

      assert {:ok, %{text_strategy: "full", truncated: false}} =
               Summarizer.summarize(oversized_act("curto"), ssh_provider(), "claude-cli")
    end

    test "records the embeddings model that ranked (preprocessor), on rank only" do
      {:ok, _} = Admin.update_settings(%{"max_text_chars" => "400"})
      set_embeddings(embed_fn: relevance_embed(), model: "bge-m3")
      stub_ssh_runner(fn _ -> {:ok, claude_envelope("resumo", [])} end)

      assert {:ok, %{text_strategy: "rank", ranker_model: "bge-m3"}} =
               Summarizer.summarize(oversized_act(diploma(800)), ssh_provider(), "claude-cli")

      # truncate and full leave it nil — the embedder did nothing.
      assert {:ok, %{ranker_model: nil}} =
               Summarizer.summarize(oversized_act(diploma(800)), ssh_provider(), "claude-cli",
                 text_strategy: :truncate
               )

      assert {:ok, %{ranker_model: nil}} =
               Summarizer.summarize(oversized_act("curto"), ssh_provider(), "claude-cli")
    end

    test "normalizes a string strategy from decoded job args" do
      {:ok, _} = Admin.update_settings(%{"max_text_chars" => "400"})
      set_embeddings(embed_fn: relevance_embed())
      stub_ssh_runner(fn _ -> {:ok, claude_envelope("resumo", [])} end)

      assert {:ok, %{text_strategy: "truncate"}} =
               Summarizer.summarize(oversized_act(diploma(800)), ssh_provider(), "claude-cli",
                 text_strategy: "truncate"
               )
    end
  end
end

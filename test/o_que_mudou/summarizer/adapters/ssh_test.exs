defmodule OQueMudou.Summarizer.Adapters.SshTest do
  use OQueMudou.DataCase, async: false

  alias OQueMudou.Repo
  alias OQueMudou.Register.{Edition, Act, Summary}
  alias OQueMudou.Summarizer
  alias OQueMudou.Summarizer.Adapters.Ssh

  # Build the `claude -p --output-format json` envelope whose `result` is our JSON.
  defp claude_envelope(plain_text, domains) do
    inner = Jason.encode!(%{"plain_text" => plain_text, "domains" => domains})
    Jason.encode!(%{"type" => "result", "subtype" => "success", "result" => inner})
  end

  defp set_runner(fun) do
    prev = Application.get_env(:o_que_mudou, Ssh, [])
    Application.put_env(:o_que_mudou, Ssh, Keyword.put(prev, :runner, fun))
    on_exit(fn -> Application.put_env(:o_que_mudou, Ssh, prev) end)
  end

  defp act do
    %Act{
      tipo: "Decreto-Lei",
      emitter: "Finanças",
      title: "Decreto-Lei n.º 1/2026",
      full_text: "..."
    }
  end

  test "parses claude envelope into the summary contract" do
    set_runner(fn _prompt -> {:ok, claude_envelope("Muda o IRS.", ["fiscal", "trabalho"])} end)

    assert {:ok, attrs} = Ssh.summarize(act())
    assert attrs.plain_text == "Muda o IRS."
    assert attrs.domains == [:fiscal, :trabalho]
    assert attrs.model == "claude-cli"
    assert is_binary(attrs.prompt_version)
  end

  test "flags truncated when the act text exceeds the cap" do
    set_runner(fn _ -> {:ok, claude_envelope("x", [])} end)

    short = %{act() | full_text: "curto"}
    assert {:ok, %{truncated: false}} = Ssh.summarize(short)

    huge = %{act() | full_text: String.duplicate("a", 80_001)}
    assert {:ok, %{truncated: true}} = Ssh.summarize(huge)
  end

  test "drops domains outside the fixed taxonomy" do
    set_runner(fn _ -> {:ok, claude_envelope("x", ["fiscal", "cripto", "saúde"])} end)
    assert {:ok, %{domains: [:fiscal, :saúde]}} = Ssh.summarize(act())
  end

  test "tolerates code-fenced JSON from the model" do
    inner = "```json\n" <> Jason.encode!(%{"plain_text" => "y", "domains" => []}) <> "\n```"
    envelope = Jason.encode!(%{"result" => inner})
    set_runner(fn _ -> {:ok, envelope} end)
    assert {:ok, %{plain_text: "y", domains: []}} = Ssh.summarize(act())
  end

  test "surfaces ssh failures" do
    set_runner(fn _ -> {:error, {:ssh_exit, 255, "Permission denied (publickey)."}} end)
    assert {:error, {:ssh_exit, 255, _}} = Ssh.summarize(act())
  end

  test "unparseable output is an error" do
    set_runner(fn _ -> {:ok, "not json at all"} end)
    assert {:error, :unparseable_output} = Ssh.summarize(act())
  end

  test "missing host (no runner injected) errors instead of shelling out" do
    # default config has no :host; ensure no :runner either
    prev = Application.get_env(:o_que_mudou, Ssh, [])
    Application.put_env(:o_que_mudou, Ssh, Keyword.drop(prev, [:runner, :host]))
    on_exit(fn -> Application.put_env(:o_que_mudou, Ssh, prev) end)

    assert {:error, :missing_ssh_host} = Ssh.summarize(act())
  end

  describe "via Summarizer with adapter: :ssh" do
    setup do
      prev = Application.get_env(:o_que_mudou, Summarizer, [])
      Application.put_env(:o_que_mudou, Summarizer, Keyword.put(prev, :adapter, :ssh))
      on_exit(fn -> Application.put_env(:o_que_mudou, Summarizer, prev) end)
      :ok
    end

    test "writes a summary through the async path" do
      set_runner(fn _ -> {:ok, claude_envelope("resumo via ssh", ["habitação"])} end)
      assert Summarizer.adapter() == Ssh

      edition =
        %Edition{}
        |> Edition.changeset(%{serie: "I", number: "120/2026", date: ~D[2026-06-24]})
        |> Repo.insert!()

      persisted =
        %Act{}
        |> Act.changeset(%{edition_id: edition.id, dre_id: "1", title: "x"})
        |> Repo.insert!()

      assert {:ok, summary} = Summarizer.summarize(persisted)
      assert summary.plain_text == "resumo via ssh"
      assert summary.domains == [:habitação]
      assert summary.model == "claude-cli"
      assert summary.status == :unreviewed
      assert Repo.aggregate(Summary, :count) == 1
    end
  end
end

defmodule OQueMudou.Summarizer.Adapters.SshTest do
  use OQueMudou.DataCase, async: false

  import OQueMudou.SummarizerHelpers

  alias OQueMudou.Register.Act
  alias OQueMudou.Summarizer.Adapters.Ssh

  defp act do
    %Act{
      tipo: "Decreto-Lei",
      emitter: "Finanças",
      title: "Decreto-Lei n.º 1/2026",
      full_text: "..."
    }
  end

  defp run(act \\ act(), model \\ "claude-cli"),
    do: Ssh.summarize(act, ssh_provider(), model, act.full_text || act.title)

  test "parses claude envelope into the summary contract" do
    stub_ssh_runner(fn _ -> {:ok, claude_envelope("Muda o IRS.", ["fiscal", "trabalho"])} end)

    assert {:ok, attrs} = run()
    assert attrs.plain_text == "Muda o IRS."
    assert attrs.domains == [:fiscal, :trabalho]
    assert attrs.model == "claude-cli"
    assert is_binary(attrs.prompt_version)
  end

  test "embeds the already-prepared text into the prompt verbatim" do
    parent = self()

    stub_ssh_runner(fn prompt ->
      send(parent, {:prompt, prompt})
      {:ok, claude_envelope("x", [])}
    end)

    assert {:ok, _} = Ssh.summarize(act(), ssh_provider(), "claude-cli", "TEXTO-PREPARADO-XYZ")
    assert_received {:prompt, prompt}
    assert prompt =~ "TEXTO-PREPARADO-XYZ"
  end

  test "drops domains outside the fixed taxonomy" do
    stub_ssh_runner(fn _ -> {:ok, claude_envelope("x", ["fiscal", "cripto", "saúde"])} end)
    assert {:ok, %{domains: [:fiscal, :saúde]}} = run()
  end

  test "tolerates code-fenced JSON from the model" do
    inner = "```json\n" <> Jason.encode!(%{"plain_text" => "y", "domains" => []}) <> "\n```"
    stub_ssh_runner(fn _ -> {:ok, Jason.encode!(%{"result" => inner})} end)
    assert {:ok, %{plain_text: "y", domains: []}} = run()
  end

  test "surfaces ssh failures" do
    stub_ssh_runner(fn _ -> {:error, {:ssh_exit, 255}} end)
    assert {:error, {:ssh_exit, 255}} = run()
  end

  test "unparseable output is an error" do
    stub_ssh_runner(fn _ -> {:ok, "not json at all"} end)
    assert {:error, :unparseable_output} = run()
  end

  test "a provider without a host errors instead of shelling out" do
    # no runner injected → real path; provider has no ssh_host
    provider = %OQueMudou.Providers.Provider{kind: :ssh, ssh_host: nil}
    assert {:error, :missing_ssh_host} = Ssh.summarize(act(), provider, "claude-cli", "texto")
  end

  describe "remote_claude_cmd/2 — model passthrough" do
    @base "claude -p --output-format json"

    test "forwards a real model to --model, shell-quoted" do
      assert Ssh.remote_claude_cmd(@base, "opus") == ~s(#{@base} --model 'opus')
      assert Ssh.remote_claude_cmd(@base, "claude-sonnet-4-6") =~ "--model 'claude-sonnet-4-6'"
    end

    test "leaves the CLI default for the claude-cli sentinel, nil, or blank" do
      assert Ssh.remote_claude_cmd(@base, "claude-cli") == @base
      assert Ssh.remote_claude_cmd(@base, nil) == @base
      assert Ssh.remote_claude_cmd(@base, "") == @base
    end

    test "does not double-set a model already pinned in the command" do
      assert Ssh.remote_claude_cmd("claude -p --model opus", "sonnet") == "claude -p --model opus"
      assert Ssh.remote_claude_cmd("claude -p -m opus", "sonnet") == "claude -p -m opus"
    end

    test "escapes shell metacharacters in the model" do
      assert Ssh.remote_claude_cmd(@base, "a'; rm -rf /") ==
               ~s(#{@base} --model 'a'\\''; rm -rf /')
    end
  end
end

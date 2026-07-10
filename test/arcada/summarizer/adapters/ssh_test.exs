defmodule Arcada.Summarizer.Adapters.SshTest do
  use Arcada.DataCase, async: false

  import Arcada.SummarizerHelpers

  alias Arcada.Register.Act
  alias Arcada.Summarizer.Adapters.Ssh

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
    stub_ssh_runner(fn _ ->
      {:ok,
       claude_envelope(
         "Muda o IRS.",
         ["fiscal", "trabalho"],
         %{},
         "IRS muda para quem trabalha por conta própria"
       )}
    end)

    assert {:ok, attrs} = run()
    assert attrs.plain_text == "Muda o IRS."
    assert attrs.headline == "IRS muda para quem trabalha por conta própria"
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

  test "captures token usage + notional cost from the envelope" do
    extra = %{
      "total_cost_usd" => 0.0123,
      "usage" => %{"input_tokens" => 1200, "output_tokens" => 300},
      "duration_ms" => 1500
    }

    stub_ssh_runner(fn _ -> {:ok, claude_envelope("x", [], extra)} end)

    assert {:ok, attrs} = run()
    assert attrs.input_tokens == 1200
    assert attrs.output_tokens == 300
    assert attrs.cost_source == "subscription"
    assert attrs.duration_ms == 1500
    assert Decimal.equal?(attrs.cost_usd, Decimal.from_float(0.0123) |> Decimal.round(6))
  end

  test "leaves cost/usage nil when the envelope omits them" do
    stub_ssh_runner(fn _ -> {:ok, claude_envelope("x", [])} end)

    assert {:ok, attrs} = run()
    assert attrs.cost_usd == nil
    assert attrs.cost_source == nil
    assert attrs.input_tokens == nil
  end

  test "drops domains outside the fixed taxonomy" do
    stub_ssh_runner(fn _ -> {:ok, claude_envelope("x", ["fiscal", "cripto", "saúde"])} end)
    assert {:ok, %{domains: [:fiscal, :saúde]}} = run()
  end

  test "tolerates code-fenced JSON from the model" do
    inner = "```json\n" <> Jason.encode!(%{"plain_text" => "y", "domains" => []}) <> "\n```"
    stub_ssh_runner(fn _ -> {:ok, Jason.encode!(%{"result" => inner})} end)
    assert {:ok, %{plain_text: "y", headline: nil, domains: []}} = run()
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
    provider = %Arcada.Providers.Provider{kind: :ssh, ssh_host: nil}
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

  describe "ssh_command/3 — shell-quoting of connection fields (issue #59)" do
    alias Arcada.Providers.Provider

    test "single-quotes the user@host destination and identity file" do
      p = %Provider{ssh_user: "claude", ssh_host: "box.internal", ssh_identity_file: "/k/id"}
      cmd = Ssh.ssh_command(p, "/tmp/prompt", "claude-cli")

      assert cmd =~ "-i '/k/id' "
      assert cmd =~ " 'claude@box.internal' "
      assert cmd =~ " < '/tmp/prompt'"
    end

    test "neutralizes shell injection in ssh_host" do
      p = %Provider{ssh_host: "h; touch /pwned", ssh_user: "claude"}
      cmd = Ssh.ssh_command(p, "/tmp/prompt", "claude-cli")

      # the whole user@host is one single-quoted token → the metacharacters are inert
      assert cmd =~ "'claude@h; touch /pwned'"
      refute cmd =~ "; touch /pwned "
    end

    test "neutralizes shell injection in ssh_user and identity file" do
      p = %Provider{ssh_host: "box", ssh_user: "u'; id #", ssh_identity_file: "/k; rm -rf /"}
      cmd = Ssh.ssh_command(p, "/tmp/p", "claude-cli")

      refute cmd =~ "; rm -rf / "
      refute cmd =~ "; id # "
      # identity single-quoted with the POSIX close/escape/reopen for the inner quote
      assert cmd =~ "-i '/k; rm -rf /'"
    end

    test "leaves ssh_claude_cmd unquoted (remote command by design)" do
      p = %Provider{ssh_host: "box", ssh_claude_cmd: "claude -p --output-format json"}
      cmd = Ssh.ssh_command(p, "/tmp/p", "claude-cli")

      assert cmd =~ " claude -p --output-format json < "
    end
  end
end

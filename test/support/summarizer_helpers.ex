defmodule OQueMudou.SummarizerHelpers do
  @moduledoc "Test helpers: create providers and stub the SSH adapter offline."

  alias OQueMudou.Providers
  alias OQueMudou.Summarizer.Adapters.Ssh

  @doc "The `claude -p --output-format json` envelope wrapping our inner JSON."
  def claude_envelope(plain_text, domains) do
    inner = Jason.encode!(%{"plain_text" => plain_text, "domains" => domains})
    Jason.encode!(%{"type" => "result", "subtype" => "success", "result" => inner})
  end

  @doc "Create an `:ssh` provider (testable offline via the runner stub)."
  def ssh_provider(attrs \\ %{}) do
    base = %{
      "name" => "ssh-#{System.unique_integer([:positive])}",
      "kind" => "ssh",
      "ssh_host" => "h",
      "models" => "claude-cli"
    }

    {:ok, provider} = Providers.create_provider(Map.merge(base, attrs))
    provider
  end

  @doc "Inject the SSH runner so the adapter returns `fun.(prompt)` instead of SSHing."
  def stub_ssh_runner(fun) do
    prev = Application.get_env(:o_que_mudou, Ssh, [])
    Application.put_env(:o_que_mudou, Ssh, Keyword.put(prev, :runner, fun))
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:o_que_mudou, Ssh, prev) end)
  end
end

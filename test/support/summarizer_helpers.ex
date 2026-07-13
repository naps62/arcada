defmodule Arcada.SummarizerHelpers do
  @moduledoc "Test helpers: create providers and stub the SSH adapter offline."

  alias Arcada.Providers
  alias Arcada.Summarizer.Adapters.Ssh
  alias Arcada.Summarizer.Extractor

  @doc """
  The `claude -p --output-format json` envelope wrapping our inner JSON. `extra`
  merges envelope-level fields (e.g. `total_cost_usd`, `usage`, `duration_ms`).
  `headline` defaults to a placeholder so existing call sites that don't care
  about it still get a valid inner payload.
  """
  def claude_envelope(plain_text, domains, extra \\ %{}, headline \\ "Título de teste") do
    inner =
      Jason.encode!(%{"plain_text" => plain_text, "headline" => headline, "domains" => domains})

    %{"type" => "result", "subtype" => "success", "result" => inner}
    |> Map.merge(extra)
    |> Jason.encode!()
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
    prev = Application.get_env(:arcada, Ssh, [])
    Application.put_env(:arcada, Ssh, Keyword.put(prev, :runner, fun))
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:arcada, Ssh, prev) end)
  end

  @doc "Create an `:openai` provider (used as the extract/render extractor in tests)."
  def openai_provider(attrs \\ %{}) do
    base = %{
      "name" => "glm-#{System.unique_integer([:positive])}",
      "kind" => "openai",
      "base_url" => "https://api.example.test/v1",
      "models" => "test-strong-model"
    }

    {:ok, provider} = Providers.create_provider(Map.merge(base, attrs))
    provider
  end

  @doc """
  Inject the extractor runner so `Extractor` returns `fun.(ctx)` instead of an HTTP
  call. `fun` receives `%{provider, model, act, text}` and returns
  `{:ok, raw_json}` (parsed by `Prompt.parse_extraction/1`) or `{:error, reason}`.
  """
  def stub_extractor(fun) do
    prev = Application.get_env(:arcada, Extractor, [])
    Application.put_env(:arcada, Extractor, Keyword.put(prev, :runner, fun))
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:arcada, Extractor, prev) end)
  end
end

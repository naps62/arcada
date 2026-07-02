defmodule Arcada.Summarizer.Adapters.Ssh do
  @moduledoc """
  Summarize by SSHing to a host that has a CLI like `claude -p` and running it —
  `provider.kind == :ssh`. Needs no API key in the app (auth lives on the remote
  host). Connection comes from the provider: `ssh_host`, `ssh_user`,
  `ssh_identity_file`, `ssh_claude_cmd` (default `claude -p --output-format json`).

  Robustness: the prompt is written to a temp file and piped to the remote command
  over SSH stdin (`ssh … <cmd> < tmpfile`). No act content is ever interpolated
  into a command line — no injection, no MAX_ARG_STRLEN limit for long diplomas.
  Tests inject `:runner` via `Application.put_env(:arcada, __MODULE__, ...)`.

  Model selection: a real selected model is forwarded to the remote CLI's
  `--model` flag (shell-quoted). The sentinel `#{"claude-cli"}` and a nil model
  mean "let the CLI use its own default" — nothing is passed. A `--model`/`-m`
  already pinned in `ssh_claude_cmd` is left untouched.

  Pure transport: the prompt shape and reply parsing live in
  `Arcada.Summarizer.Prompt`; this module only shells out over SSH and unwraps
  the CLI's JSON envelope.
  """
  @behaviour Arcada.Summarizer.Adapter

  require Logger

  alias Arcada.Register.Act
  alias Arcada.Providers.Provider
  alias Arcada.Summarizer.Prompt

  @prompt_version "2026-07-01.ssh.1"
  @default_model "claude-cli"
  @default_claude_cmd "claude -p --output-format json"

  @default_ssh_extra [
    "-o",
    "StrictHostKeyChecking=accept-new",
    "-o",
    "BatchMode=yes",
    "-o",
    "UserKnownHostsFile=/dev/null"
  ]

  @impl true
  def summarize(%Act{} = act, %Provider{} = provider, model, text) do
    with {:ok, stdout} <- run(build_prompt(act, text), provider, model),
         {:ok, attrs} <- parse(stdout, model || @default_model) do
      {:ok, attrs}
    end
  end

  defp build_prompt(act, text) do
    """
    #{Prompt.system()}
    #{Prompt.instructed_prompt(act, text)}\
    """
  end

  # `:runner` (test injection) takes precedence over a real SSH call.
  defp run(prompt, provider, model) do
    case Application.get_env(:arcada, __MODULE__, [])[:runner] do
      fun when is_function(fun, 1) -> fun.(prompt)
      _ -> default_run(prompt, provider, model)
    end
  end

  defp default_run(prompt, %Provider{ssh_host: host} = provider, model)
       when is_binary(host) and host != "" do
    run_via_ssh(provider, prompt, model)
  end

  defp default_run(_prompt, _provider, _model), do: {:error, :missing_ssh_host}

  defp run_via_ssh(provider, prompt, model) do
    tmp = Path.join(System.tmp_dir!(), "oqm_prompt_#{System.unique_integer([:positive])}")
    File.write!(tmp, prompt)

    try do
      case System.cmd("sh", ["-c", ssh_command(provider, tmp, model)], stderr_to_stdout: false) do
        {out, 0} ->
          {:ok, out}

        {out, code} ->
          Logger.warning("ssh summarizer exit #{code}: #{String.slice(out, 0, 600)}")
          {:error, {:ssh_exit, code}}
      end
    after
      File.rm(tmp)
    end
  end

  defp ssh_command(%Provider{} = p, tmpfile, model) do
    user = p.ssh_user || "claude"
    claude_cmd = remote_claude_cmd(p.ssh_claude_cmd || @default_claude_cmd, model)
    identity = if f = p.ssh_identity_file, do: "-i #{f} ", else: ""
    extra = Enum.join(@default_ssh_extra, " ")
    "ssh #{identity}#{extra} #{user}@#{p.ssh_host} #{claude_cmd} < #{tmpfile}"
  end

  @doc """
  Build the remote `claude` invocation, forwarding a real selected `model` to the
  CLI's `--model` flag. The `#{@default_model}` sentinel and a nil/blank model are
  left to the CLI's own default; an existing `--model`/`-m` in `base` is kept.
  Public only so the model wiring is unit-testable.
  """
  def remote_claude_cmd(base, model)
      when is_binary(model) and model not in ["", @default_model] do
    if Regex.match?(~r/(^|\s)(--model|-m)(=|\s)/, base) do
      base
    else
      "#{base} --model #{shell_quote(model)}"
    end
  end

  def remote_claude_cmd(base, _model), do: base

  # Single-quote for POSIX sh: wrap in '…', and close/escape/reopen each literal '.
  defp shell_quote(s), do: "'" <> String.replace(s, "'", "'\\''") <> "'"

  # `claude -p --output-format json` wraps the response in an envelope whose
  # `result` field is our JSON string. Unwrap the envelope (transport-specific),
  # then hand the inner reply to `Prompt.parse/1` like every other adapter. The
  # `result`-defaults-to-stdout fallback tolerates a CLI that emits the bare reply
  # without the envelope. Code fences around either layer are stripped by `Prompt`.
  defp parse(stdout, model) do
    with {:ok, envelope} <- Prompt.decode(stdout),
         result when is_binary(result) <- Map.get(envelope, "result", stdout),
         {:ok, attrs} <- Prompt.parse(result) do
      {:ok,
       attrs
       |> Map.merge(%{model: model, prompt_version: @prompt_version})
       |> Map.merge(usage_attrs(envelope))}
    else
      _ ->
        Logger.warning(
          "ssh summarizer: could not parse claude output: #{String.slice(stdout, 0, 300)}"
        )

        {:error, :unparseable_output}
    end
  end

  # `claude -p --output-format json` reports its own usage + cost in the
  # envelope. The cost is *notional* — these runs are covered by the remote
  # host's Claude subscription, not billed per-token — so it's tagged
  # "subscription" rather than presented as real spend. Missing on a raw-stdout
  # fallback (envelope isn't the CLI shape), so every field is best-effort.
  defp usage_attrs(envelope) when is_map(envelope) do
    usage = (is_map(envelope["usage"]) && envelope["usage"]) || %{}

    %{
      input_tokens: usage["input_tokens"],
      output_tokens: usage["output_tokens"],
      cost_usd: to_decimal(envelope["total_cost_usd"]),
      cost_source: if(is_number(envelope["total_cost_usd"]), do: "subscription"),
      duration_ms: envelope["duration_ms"]
    }
  end

  defp usage_attrs(_), do: %{}

  defp to_decimal(n) when is_float(n), do: n |> Decimal.from_float() |> Decimal.round(6)
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(_), do: nil
end

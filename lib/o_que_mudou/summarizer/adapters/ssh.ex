defmodule OQueMudou.Summarizer.Adapters.Ssh do
  @moduledoc """
  Summarize by SSHing to a host that has the `claude` CLI and running
  `claude -p` — the SSH-driven escape hatch from `docs/PLAN.md`. An alternative
  to the `:api` adapter that needs no `ANTHROPIC_API_KEY` in the app (auth lives
  on the remote machine where `claude` is already logged in).

  One call yields both the plain-language summary and the life-domain
  classification, constrained to strict JSON (parsed from `claude -p
  --output-format json`).

  Config (`config/runtime.exs`, env-driven):

      config :o_que_mudou, OQueMudou.Summarizer.Adapters.Ssh,
        host: "10.6.10.x",            # SUMMARIZER_SSH_HOST
        user: "claude",              # SUMMARIZER_SSH_USER
        identity_file: "/app/.ssh/id_ed25519",
        claude_cmd: "claude -p --output-format json",
        model: "claude-cli",
        ssh_extra: ["-o", "StrictHostKeyChecking=accept-new", "-o", "BatchMode=yes"]

  Safety/robustness: the prompt is written to a temp file and piped to the remote
  `claude` over SSH stdin (`ssh … claude -p < tmpfile`). No act content is ever
  interpolated into a command line, so there's no injection risk and no command
  argument-length limit (long diplomas previously blew MAX_ARG_STRLEN).
  """
  @behaviour OQueMudou.Summarizer.Adapter

  require Logger

  alias OQueMudou.Register
  alias OQueMudou.Register.Act

  @prompt_version "2026-06-28.ssh.2"
  @default_model "claude-cli"
  @default_claude_cmd "claude -p --output-format json"
  # Cap the act text so giant diplomas (huge annexes/tables — some run to ~1M+
  # tokens) don't exceed the model's context limit. The operative content of a
  # diploma is near the start; the tail is typically annexes.
  @max_text_chars 80_000

  # Output-format wiring appended to the shared system prompt. `claude -p` has no
  # structured-output mode, so we ask for raw JSON and validate on parse.
  @json_format """
  Responde APENAS com um objeto JSON válido, sem texto antes ou depois, no formato:
  {"plain_text": "<resumo>", "domains": ["<dominio>", ...]}
  Os domínios válidos são EXATAMENTE: #{Enum.join(OQueMudou.Register.life_domains(), ", ")}.
  """

  @impl true
  def summarize(%Act{} = act) do
    with {:ok, stdout} <- run(build_prompt(act)),
         {:ok, attrs} <- parse(stdout) do
      truncated = OQueMudou.Summarizer.truncated?(act.full_text || act.title, @max_text_chars)
      {:ok, Map.put(attrs, :truncated, truncated)}
    end
  end

  defp build_prompt(act) do
    """
    #{OQueMudou.Summarizer.base_system_prompt()}
    #{@json_format}
    ---
    Tipo: #{act.tipo}
    Emissor: #{act.emitter}
    Título: #{act.title}

    Texto:
    #{OQueMudou.Summarizer.cap_text(act.full_text || act.title, @max_text_chars)}
    """
  end

  # Run the prompt and return `{:ok, raw_stdout}` | `{:error, reason}`.
  # Tests inject `:runner` to avoid a real SSH.
  defp run(prompt) do
    case config()[:runner] do
      fun when is_function(fun, 1) -> fun.(prompt)
      _ -> default_run(prompt)
    end
  end

  @default_ssh_extra [
    "-o",
    "StrictHostKeyChecking=accept-new",
    "-o",
    "BatchMode=yes",
    "-o",
    "UserKnownHostsFile=/dev/null"
  ]

  defp default_run(prompt) do
    cfg = config()

    case cfg[:host] do
      host when is_binary(host) and host != "" -> run_via_ssh(cfg, host, prompt)
      _ -> {:error, :missing_ssh_host}
    end
  end

  # Pipe the prompt over SSH stdin (not the command line). Embedding it as an
  # argument blew Linux's single-argument size limit (MAX_ARG_STRLEN ~128KB) for
  # long diplomas — the remote shell failed to exec, yielding an empty exit 7.
  # The prompt is written to a temp file and redirected into ssh; no act content
  # ever appears in any command line (no injection, no size limit).
  defp run_via_ssh(cfg, host, prompt) do
    tmp = Path.join(System.tmp_dir!(), "oqm_prompt_#{System.unique_integer([:positive])}")
    File.write!(tmp, prompt)

    try do
      case System.cmd("sh", ["-c", ssh_command(cfg, host, tmp)], stderr_to_stdout: false) do
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

  defp ssh_command(cfg, host, tmpfile) do
    user = cfg[:user] || "claude"
    claude_cmd = cfg[:claude_cmd] || @default_claude_cmd
    identity = if f = cfg[:identity_file], do: "-i #{f} ", else: ""
    extra = Enum.join(cfg[:ssh_extra] || @default_ssh_extra, " ")
    # claude_cmd / flags / paths are operator config (no untrusted content); the
    # prompt is in tmpfile, piped via stdin.
    "ssh #{identity}#{extra} #{user}@#{host} #{claude_cmd} < #{tmpfile}"
  end

  # `claude -p --output-format json` wraps the response in an envelope whose
  # `result` field is our JSON string. Tolerate code fences around either layer.
  defp parse(stdout) do
    with {:ok, envelope} <- decode_json(stdout),
         result when is_binary(result) <- Map.get(envelope, "result", stdout),
         {:ok, obj} <- decode_json(result),
         text when is_binary(text) <- obj["plain_text"] do
      {:ok,
       %{
         plain_text: text,
         domains: valid_domains(obj["domains"]),
         model: model(),
         prompt_version: @prompt_version
       }}
    else
      _ ->
        Logger.warning(
          "ssh summarizer: could not parse claude output: #{String.slice(stdout, 0, 300)}"
        )

        {:error, :unparseable_output}
    end
  end

  defp decode_json(str) when is_binary(str) do
    str |> strip_fences() |> Jason.decode()
  end

  defp decode_json(_), do: :error

  defp strip_fences(str) do
    str
    |> String.trim()
    |> String.replace(~r/^```(?:json)?\s*/i, "")
    |> String.replace(~r/\s*```$/, "")
    |> String.trim()
  end

  defp valid_domains(domains) when is_list(domains) do
    domains
    |> Enum.flat_map(fn d ->
      case Register.fetch_domain(d) do
        {:ok, atom} -> [atom]
        :error -> []
      end
    end)
    |> Enum.uniq()
  end

  defp valid_domains(_), do: []

  defp model, do: config()[:model] || @default_model
  # Env config overlaid with runtime admin overrides (host, user, claude_cmd, model).
  defp config, do: OQueMudou.Admin.adapter_config(__MODULE__)
end

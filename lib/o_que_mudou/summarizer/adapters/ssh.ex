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

  Safety: the act text is base64-encoded and piped to the remote `claude` via
  `echo <b64> | base64 -d | claude …`, so no act content is ever interpolated
  into a shell command (no injection, no quoting hazards).
  """
  @behaviour OQueMudou.Summarizer.Adapter

  require Logger

  alias OQueMudou.Register
  alias OQueMudou.Register.Act

  @prompt_version "2026-06-28.ssh.1"
  @default_model "claude-cli"
  @default_claude_cmd "claude -p --output-format json"

  @system """
  És um assistente que resume diplomas legais do Diário da República em português \
  claro e acessível, para uma pessoa comum perceber o que mudou, para quem, e a \
  partir de quando. Não dês aconselhamento jurídico. Sê conciso (2-4 frases) e \
  factual, e classifica o diploma em um ou mais domínios de vida.

  Responde APENAS com um objeto JSON válido, sem texto antes ou depois, no formato:
  {"plain_text": "<resumo>", "domains": ["<dominio>", ...]}
  Os domínios válidos são EXATAMENTE: #{Enum.join(OQueMudou.Register.life_domains(), ", ")}.
  """

  @impl true
  def summarize(%Act{} = act) do
    with {:ok, stdout} <- run(build_prompt(act)),
         {:ok, attrs} <- parse(stdout) do
      {:ok, attrs}
    end
  end

  defp build_prompt(act) do
    """
    #{@system}

    ---
    Tipo: #{act.tipo}
    Emissor: #{act.emitter}
    Título: #{act.title}

    Texto:
    #{act.full_text || act.title}
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

  defp default_run(prompt) do
    cfg = config()

    case cfg[:host] do
      host when is_binary(host) and host != "" ->
        args = ssh_args(cfg, host, prompt)

        # Don't merge stderr — ssh diagnostics (e.g. known_hosts warnings) would
        # otherwise pollute stdout and break JSON parsing. stdout is claude's
        # JSON envelope; stderr is dropped (exit code carries failure).
        case System.cmd("ssh", args, stderr_to_stdout: false) do
          {out, 0} ->
            {:ok, out}

          {out, code} ->
            # `claude` may exit non-zero while still printing a JSON error envelope
            # to stdout — surface it so failures are diagnosable.
            Logger.warning("ssh summarizer exit #{code}: #{String.slice(out, 0, 600)}")
            {:error, {:ssh_exit, code}}
        end

      _ ->
        {:error, :missing_ssh_host}
    end
  end

  defp ssh_args(cfg, host, prompt) do
    user = cfg[:user] || "claude"
    claude_cmd = cfg[:claude_cmd] || @default_claude_cmd
    b64 = Base.encode64(prompt)
    remote = "echo #{b64} | base64 -d | #{claude_cmd}"

    identity = if f = cfg[:identity_file], do: ["-i", f], else: []

    extra =
      cfg[:ssh_extra] ||
        [
          "-o",
          "StrictHostKeyChecking=accept-new",
          "-o",
          "BatchMode=yes",
          "-o",
          "UserKnownHostsFile=/dev/null"
        ]

    identity ++ extra ++ ["#{user}@#{host}", remote]
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
  defp config, do: Application.get_env(:o_que_mudou, __MODULE__, [])
end

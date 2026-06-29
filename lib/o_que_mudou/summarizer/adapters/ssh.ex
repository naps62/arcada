defmodule OQueMudou.Summarizer.Adapters.Ssh do
  @moduledoc """
  Summarize by SSHing to a host that has a CLI like `claude -p` and running it —
  `provider.kind == :ssh`. Needs no API key in the app (auth lives on the remote
  host). Connection comes from the provider: `ssh_host`, `ssh_user`,
  `ssh_identity_file`, `ssh_claude_cmd` (default `claude -p --output-format json`).

  Robustness: the prompt is written to a temp file and piped to the remote command
  over SSH stdin (`ssh … <cmd> < tmpfile`). No act content is ever interpolated
  into a command line — no injection, no MAX_ARG_STRLEN limit for long diplomas.
  Tests inject `:runner` via `Application.put_env(:o_que_mudou, __MODULE__, ...)`.
  """
  @behaviour OQueMudou.Summarizer.Adapter

  require Logger

  alias OQueMudou.Register
  alias OQueMudou.Register.Act
  alias OQueMudou.Providers.Provider

  @prompt_version "2026-06-28.ssh.2"
  @default_model "claude-cli"
  @default_claude_cmd "claude -p --output-format json"

  @json_format """
  Responde APENAS com um objeto JSON válido, sem texto antes ou depois, no formato:
  {"plain_text": "<resumo>", "domains": ["<dominio>", ...]}
  Os domínios válidos são EXATAMENTE: #{Enum.join(OQueMudou.Register.life_domains(), ", ")}.
  """

  @default_ssh_extra [
    "-o",
    "StrictHostKeyChecking=accept-new",
    "-o",
    "BatchMode=yes",
    "-o",
    "UserKnownHostsFile=/dev/null"
  ]

  @impl true
  def summarize(%Act{} = act, %Provider{} = provider, model) do
    with {:ok, stdout} <- run(build_prompt(act), provider),
         {:ok, attrs} <- parse(stdout, model || @default_model) do
      truncated =
        OQueMudou.Summarizer.truncated?(
          act.full_text || act.title,
          OQueMudou.Summarizer.max_text_chars()
        )

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
    #{OQueMudou.Summarizer.prepare_text(act.full_text || act.title)}
    """
  end

  # `:runner` (test injection) takes precedence over a real SSH call.
  defp run(prompt, provider) do
    case Application.get_env(:o_que_mudou, __MODULE__, [])[:runner] do
      fun when is_function(fun, 1) -> fun.(prompt)
      _ -> default_run(prompt, provider)
    end
  end

  defp default_run(prompt, %Provider{ssh_host: host} = provider)
       when is_binary(host) and host != "" do
    run_via_ssh(provider, prompt)
  end

  defp default_run(_prompt, _provider), do: {:error, :missing_ssh_host}

  defp run_via_ssh(provider, prompt) do
    tmp = Path.join(System.tmp_dir!(), "oqm_prompt_#{System.unique_integer([:positive])}")
    File.write!(tmp, prompt)

    try do
      case System.cmd("sh", ["-c", ssh_command(provider, tmp)], stderr_to_stdout: false) do
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

  defp ssh_command(%Provider{} = p, tmpfile) do
    user = p.ssh_user || "claude"
    claude_cmd = p.ssh_claude_cmd || @default_claude_cmd
    identity = if f = p.ssh_identity_file, do: "-i #{f} ", else: ""
    extra = Enum.join(@default_ssh_extra, " ")
    "ssh #{identity}#{extra} #{user}@#{p.ssh_host} #{claude_cmd} < #{tmpfile}"
  end

  # `claude -p --output-format json` wraps the response in an envelope whose
  # `result` field is our JSON string. Tolerate code fences around either layer.
  defp parse(stdout, model) do
    with {:ok, envelope} <- decode_json(stdout),
         result when is_binary(result) <- Map.get(envelope, "result", stdout),
         {:ok, obj} <- decode_json(result),
         text when is_binary(text) <- obj["plain_text"] do
      {:ok,
       %{
         plain_text: text,
         domains: valid_domains(obj["domains"]),
         model: model,
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

  defp decode_json(str) when is_binary(str), do: str |> strip_fences() |> Jason.decode()
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
end

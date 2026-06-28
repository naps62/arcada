defmodule OQueMudou.Summarizer do
  @moduledoc """
  Produces 🤖 unreviewed summaries for acts, via a pluggable adapter
  (`api | local | manual`, selected by config) and an **async write path** —
  summaries are written by an Oban job, never inline with the scrape.

  Config:

      config :o_que_mudou, OQueMudou.Summarizer, adapter: :manual
  """

  alias OQueMudou.Repo
  alias OQueMudou.Register.{Act, Summary}
  alias OQueMudou.Summarizer.{SummarizeWorker}
  alias OQueMudou.Summarizer.Adapters.{Api, Local, Manual, Ssh}

  @adapters %{api: Api, local: Local, manual: Manual, ssh: Ssh}

  # Shared system prompt for every LLM adapter (api, ssh). The style rules — plain
  # everyday Portuguese, short active sentences, no bureaucratic filler, no inline
  # statute citations — are the single lever for how readable the summaries feel,
  # so they live here once. Each adapter appends only its output-format wiring.
  @base_system """
  És um jornalista que explica diplomas do Diário da República a um amigo, em \
  português do dia-a-dia.

  Escreve um resumo curto (2 a 4 frases) que diga, por esta ordem: o que muda, em \
  concreto; para quem (quem fica afetado); e a partir de quando, se o diploma o \
  indicar. Classifica também o diploma em um ou mais domínios de vida.

  Regras de escrita:
  - Começa pela própria mudança, não pela instituição que a emitiu. Não nomeies o \
  emissor (ministério, tribunal, secretaria, etc.) a não ser que seja essencial \
  para perceber o que mudou.
  - Frases curtas e diretas, uma ideia de cada vez. Usa voz ativa.
  - Linguagem comum. Evita jargão jurídico e fórmulas burocráticas como "ao abrigo \
  de", "nos termos do", "sem prejuízo de" ou "no âmbito de".
  - Não cites números de diplomas nem artigos no corpo do texto — a fonte oficial já \
  os tem. Refere uma lei pelo nome apenas se for mesmo o assunto.
  - Vai direto ao que importa: corta enchimento, rodeios e repetições.
  - Sê factual. Não dês opinião nem aconselhamento jurídico.
  """

  @doc "Shared system prompt (writing + classification rules) for the LLM adapters."
  def base_system_prompt, do: @base_system

  @doc """
  Cap act text for the summarizer prompt so oversized diplomas (huge annexes)
  don't exceed the model's context limit. Appends a truncation marker.
  """
  def cap_text(text, max_chars) when is_binary(text) do
    if String.length(text) > max_chars do
      String.slice(text, 0, max_chars) <> "\n\n[...texto truncado para efeitos de resumo...]"
    else
      text
    end
  end

  def cap_text(other, _max_chars), do: other

  @doc """
  Whether `cap_text/2` would truncate this text — i.e. the act text exceeds the
  cap and the resulting summary only reflects the opening of the diploma.
  Recorded per summary (`truncated`) so the UI can flag partial summaries.
  """
  def truncated?(text, max_chars) when is_binary(text), do: String.length(text) > max_chars
  def truncated?(_other, _max_chars), do: false

  @doc """
  The configured adapter module (default: `Manual`). Resolves the effective
  adapter via `OQueMudou.Admin` (DB override ?? env default); accepts either a
  known key (`:api | :local | :manual | :ssh`) or an explicit module (tests).
  """
  def adapter do
    case OQueMudou.Admin.summarizer_adapter() do
      key when is_map_key(@adapters, key) -> Map.fetch!(@adapters, key)
      mod when is_atom(mod) -> mod
    end
  end

  @doc "Enqueue an async summarization job for an act (the normal entry point)."
  def enqueue(%Act{id: id}), do: enqueue(id)

  def enqueue(act_id) when is_integer(act_id) do
    %{act_id: act_id} |> SummarizeWorker.new() |> Oban.insert()
  end

  @doc """
  Run the configured adapter for `act` and persist the result.
  Returns `{:ok, summary}` on a synchronous adapter result, `{:async, ref}` if
  the adapter defers (manual backfill), or `{:error, reason}`.
  """
  def summarize(%Act{} = act) do
    case adapter().summarize(act) do
      {:ok, attrs} -> create_summary(act, attrs)
      {:async, ref} -> {:async, ref}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Insert a summary for an act. Used both by the async write path and by the
  manual backfill (console/SSH). Defaults `status: :unreviewed` and stamps
  `generated_at`.
  """
  def create_summary(%Act{id: act_id}, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put_new(:act_id, act_id)
      |> Map.put_new(:generated_at, now())

    %Summary{}
    |> Summary.changeset(attrs)
    |> Repo.insert()
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end

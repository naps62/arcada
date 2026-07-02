defmodule Arcada.Summarizer do
  @moduledoc """
  Produces 🤖 summaries for acts. Dispatches to an adapter by the
  `Provider` kind (`:anthropic | :openai | :ssh`) and writes via an **async path**
  (an Oban job, never inline with the scrape). The active provider+model
  (`Arcada.Admin`) drives auto-summarize; manual runs pass an explicit one.
  """

  alias Arcada.Repo
  alias Arcada.Admin
  alias Arcada.Providers.Provider
  alias Arcada.Register.{Act, Summary}
  alias Arcada.Search.Index
  alias Arcada.Summarizer.{Embeddings, SummarizeWorker, TextBudget}
  alias Arcada.Summarizer.Adapters.{Api, OpenAI, Ssh}

  # Provider kind → adapter module.
  @adapters %{anthropic: Api, openai: OpenAI, ssh: Ssh}

  # Shared system prompt for every LLM adapter (api, ssh). The style rules — plain
  # everyday Portuguese, short active sentences, no bureaucratic filler, no inline
  # statute citations — are the single lever for how readable the summaries feel,
  # so they live here once. Each adapter appends only its output-format wiring.
  @base_system """
  És um jornalista que explica diplomas do Diário da República a um amigo sem \
  formação jurídica, em português do dia-a-dia.

  Escreve um resumo curto (2 a 4 frases) que diga, por esta ordem: o que muda, em \
  concreto; para quem (quem fica afetado); e a partir de quando, se o diploma o \
  indicar. Classifica também o diploma em um ou mais domínios de vida.

  Escreve também um título curto (6 a 10 palavras) que diga, em linguagem simples, \
  o que muda — não a designação formal do diploma (não repitas "Decreto-Lei n.º \
  .../2026" nem o nome do emissor). É o título que substitui a designação formal na \
  interface; deve fazer sentido sozinho, sem ler o resumo.

  Regras de escrita:
  - Escreve para um adulto sem formação jurídica. Se uma frase só se percebe com \
  conhecimento de Direito, reformula-a. A primeira frase deve dizer, sozinha, o que \
  muda na prática.
  - Começa pela própria mudança, não pela instituição que a emitiu. Não nomeies o \
  emissor (ministério, tribunal, secretaria, etc.) a não ser que seja essencial \
  para perceber o que mudou.
  - Frases curtas e diretas, uma ideia de cada vez, voz ativa. Evita frases com mais \
  de ~20 palavras.
  - Linguagem comum. Evita jargão jurídico e fórmulas burocráticas como "ao abrigo \
  de", "nos termos do", "sem prejuízo de" ou "no âmbito de". Prefere palavras \
  simples: "recusa" ou "rejeição" em vez de "indeferimento"; "multa" em vez de \
  "coima"; "da responsabilidade de" em vez de "imputável a"; "fixar uma regra igual \
  para todos os tribunais" em vez de "uniformizar jurisprudência".
  - Se um termo técnico for mesmo inevitável (porque é o próprio assunto e não \
  existe palavra comum equivalente), mantém-no mas marca-o entre parênteses retos \
  duplos, assim: [[reclamação graciosa]]. Marca apenas o termo, sem o explicares no \
  texto — a definição é acrescentada mais tarde. Não marques palavras comuns. Usa a \
  marca no máximo 1 a 2 vezes por resumo; se conseguires dizer a mesma coisa em \
  linguagem comum, não marques nada.
  - Não cites números de diplomas nem artigos no corpo do texto — a fonte oficial já \
  os tem. Refere uma lei pelo nome apenas se for mesmo o assunto.
  - Simplifica o vocabulário e a estrutura, nunca a substância. Mantém as condições, \
  exceções e prazos que mudam quem é afetado ou quando (por exemplo, "de forma \
  expressa ou tácita"). Entre mais simples e mais exato, escolhe exato.
  - Vai direto ao que importa: corta enchimento, rodeios e repetições.
  - Sê factual. Não dês opinião nem aconselhamento jurídico.
  """

  @doc "Shared system prompt (writing + classification rules) for the LLM adapters."
  def base_system_prompt, do: @base_system

  @doc """
  Effective **safety cap** (chars) on act text fed to the summarizer prompt — the
  overflow ceiling. Pass the target `model` for the adaptive per-model default
  (larger context → larger cap); omit it for the conservative default window.
  """
  def max_text_chars(model \\ nil), do: Admin.max_text_chars(model)

  @doc """
  Effective **cost target** (chars): the budget the embeddings ranker trims an act
  down to (operative sections in, annexes out), even when the act fits under the
  safety cap. Much smaller than `max_text_chars/1` — the cap is the ceiling, this
  is the target (issue #41). Falls back to the cap when unset, so callers without
  ranking behave exactly as before.
  """
  def target_text_chars(model \\ nil), do: Admin.target_text_chars(model)

  @doc """
  Prepare act text for the summarizer prompt, capped at `max_chars` (the
  configured cap by default). Thin convenience over `TextBudget.prepare/4` that
  drops the strategy; the actual budget/ranking logic lives in
  `Arcada.Summarizer.TextBudget`.

  May perform a network call to the embeddings server; intended for the async
  summarize job, not request paths.
  """
  def prepare_text(text, max_chars \\ nil),
    do: TextBudget.prepare(text, max_chars || max_text_chars()) |> elem(0)

  @doc "The adapter module for a provider kind (`:anthropic | :openai | :ssh`)."
  def adapter_for(kind) when is_atom(kind), do: Map.fetch!(@adapters, kind)

  @doc """
  Enqueue an async summarization job. With no opts it uses the active
  provider+model; pass `provider_id:`/`model:` for a manual run on a specific one,
  and `text_strategy:` (`:rank | :truncate | :auto`) to force how an oversized
  act's text is prepared (for the per-act ranking comparison).
  """
  def enqueue(act, opts \\ [])
  def enqueue(%Act{id: id}, opts), do: enqueue(id, opts)

  def enqueue(act_id, opts) when is_integer(act_id) do
    %{act_id: act_id}
    |> put_opt(opts, :provider_id)
    |> put_opt(opts, :model)
    |> put_opt(opts, :text_strategy)
    |> SummarizeWorker.new()
    |> Oban.insert()
  end

  defp put_opt(args, opts, key) do
    case Keyword.get(opts, key) do
      nil -> args
      v -> Map.put(args, to_string(key), v)
    end
  end

  @doc """
  Summarize `act` with the **active** provider+model and persist the result.
  `{:async, :no_active_provider}` if none is configured (acts wait for a manual
  run or a configured active provider).
  """
  def summarize(%Act{} = act) do
    case Admin.active_provider() do
      %Provider{} = provider -> summarize(act, provider, Admin.active_model())
      nil -> {:async, :no_active_provider}
    end
  end

  @doc """
  Summarize `act` with a specific provider + model; persist linked to the
  provider. `opts[:text_strategy]` (`:auto` default) forces how an oversized act
  is prepared. The text is prepared here (once) and handed to the adapter, which
  only talks to its backend — the cap/ranking decision lives in one place.
  """
  def summarize(%Act{} = act, %Provider{} = provider, model, opts \\ []) do
    model = model || List.first(provider.models)
    requested = opts |> Keyword.get(:text_strategy, :auto) |> normalize_strategy()

    {text, strategy} =
      TextBudget.prepare(
        act.full_text || act.title,
        max_text_chars(model),
        requested,
        target_text_chars(model)
      )

    # Only ranking actually uses the embedder; record which one preprocessed it.
    ranker_model = if strategy == :rank, do: Embeddings.model(Admin.embeddings_config())

    case adapter_for(provider.kind).summarize(act, provider, model, text) do
      {:ok, attrs} ->
        create_summary(
          act,
          attrs
          |> Map.new()
          |> Map.merge(%{
            provider_id: provider.id,
            truncated: strategy != :full,
            text_strategy: to_string(strategy),
            ranker_model: ranker_model
          })
        )

      {:async, ref} ->
        {:async, ref}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Insert a summary for an act. Used both by the async write path and by the
  manual backfill (console/SSH). Stamps `generated_at`. Embeds `plain_text`
  for semantic search (issue #27) right
  after insert; a disabled/unreachable embeddings server never blocks the
  summary itself — the row is simply left without an embedding.
  """
  def create_summary(%Act{id: act_id}, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put_new(:act_id, act_id)
      |> Map.put_new(:generated_at, now())

    case %Summary{} |> Summary.changeset(attrs) |> Repo.insert() do
      {:ok, summary} ->
        case embed_summary(summary) do
          {:ok, embedded} -> {:ok, embedded}
          {:error, _reason} -> {:ok, summary}
        end

      error ->
        error
    end
  end

  @doc """
  (Re)compute and persist a summary's `embedding` from its `plain_text`,
  refreshing the search index (`Arcada.Search.Index`). `{:error, reason}`
  when the embeddings server is disabled or unreachable — used by
  `create_summary/2` (which tolerates it) and by the admin "Generate
  embedding" action (which surfaces it).
  """
  def embed_summary(%Summary{} = summary) do
    cfg = Admin.embeddings_config()

    with true <- Embeddings.enabled?(cfg),
         {:ok, [vector]} <- Embeddings.embed([embed_text(summary, cfg)], cfg) do
      persist_embedding(summary, vector)
    else
      false -> {:error, :embeddings_disabled}
      {:error, reason} -> {:error, reason}
    end
  end

  defp embed_text(summary, cfg),
    do: (cfg[:document_prefix] || "") <> Summary.strip_terms(summary.plain_text)

  defp persist_embedding(summary, vector) do
    case summary |> Summary.changeset(%{embedding: vector}) |> Repo.update() do
      {:ok, updated} ->
        Index.put(updated.id, updated.act_id, vector)
        {:ok, updated}

      error ->
        error
    end
  end

  # Accept the strategy as an atom (direct calls) or string (decoded job args).
  defp normalize_strategy(s) when s in [:auto, :rank, :truncate], do: s
  defp normalize_strategy("rank"), do: :rank
  defp normalize_strategy("truncate"), do: :truncate
  defp normalize_strategy(_), do: :auto

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end

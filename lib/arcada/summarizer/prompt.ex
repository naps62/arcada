defmodule Arcada.Summarizer.Prompt do
  @moduledoc """
  The one place the summarizer's prompt-and-parse contract lives. Owns:

    * the shared **system prompt** (writing + classification rules)
    * the **output shape** in both forms — a strict JSON `schema/0` for
      structured-output backends (Anthropic) and a plain-language
      `json_instruction/0` for text-only ones (OpenAI-compatible, SSH CLI)
    * the **act body** (`Tipo`/`Emissor`/`Título`/`Texto`)
    * **reply parsing** (`parse/1`): fence-stripping, JSON decode, and
      domain validation against the fixed taxonomy

  The three `Arcada.Summarizer.Adapter`s reduce to pure transport: each builds a
  request for its backend (Claude HTTP / OpenAI HTTP / CLI-over-SSH), gets raw
  text back, and hands it to `parse/1`. The prompt shape never forks per adapter,
  so a single test surface covers how every reply is parsed and validated.
  """

  alias Arcada.Register

  # Shared system prompt for every LLM adapter. The style rules — plain everyday
  # Portuguese, short active sentences, no bureaucratic filler, no inline statute
  # citations — are the single lever for how readable the summaries feel, so they
  # live here once. Each adapter appends only its output-format wiring (`schema/0`
  # for structured outputs, `json_instruction/0` for text-only backends).
  @system """
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

  # Plain-language JSON instruction for text-only backends (OpenAI-compatible and
  # the SSH CLI) whose structured-output support is absent or unreliable. The
  # taxonomy is spelled out inline; `parse/1` still validates it after the fact.
  @json_instruction """
  Responde APENAS com um objeto JSON válido, sem texto antes ou depois, no formato:
  {"plain_text": "<resumo>", "headline": "<título>", "domains": ["<dominio>", ...]}
  Os domínios válidos são EXATAMENTE: #{Enum.join(Register.life_domains(), ", ")}.
  """

  # Appended to the system prompt for **omnibus** diplomas — ones too big to fit
  # whole, so the text was section-ranked (`:rank`) or head-truncated (`:truncate`,
  # A/B only). These change many things at once with no single dominant point, and
  # a small model, forced to pick one, confidently surfaces the wrong one (issue
  # #88). The note tells it to summarize at the theme level instead. Deliberately
  # conditional ("se nenhuma mudança se destacar") so a genuinely single-topic long
  # act still gets a specific summary; it does NOT force enumeration (that made the
  # model go vague-wrong). Never appended to `:full` acts — they stay specific.
  @omnibus_note """


  Este diploma é extenso e altera várias coisas ao mesmo tempo. Se nenhuma mudança \
  se destacar claramente como a principal, resume ao nível do tema — diz que mudam \
  várias regras sobre o assunto e para quem — em vez de escolheres uma só mudança e \
  a apresentares como a mais importante. Não inventes um "ponto principal" que o \
  texto não tem. Mantém-te factual e geral; não precisas de listar tudo.\
  """

  # System prompt for the **extractor** (issue #90): a strong model reads an
  # omnibus act and lists its concrete changes + a plain headline. This is the
  # judgment step amalia can't do — it surfaces buried operative changes (e.g. a
  # frequency grant tucked in a "Norma transitória") that ranking + a small model
  # both miss. Output is validated by `parse_extraction/1`.
  @extraction_system """
  És um analista jurídico. Recebes o texto (integral ou quase) de um diploma do \
  Diário da República e identificas o que muda, em concreto, para as pessoas.

  Extrai as mudanças concretas mais importantes para o cidadão comum, no máximo 6, \
  ordenadas da mais importante para a menos importante. Cada mudança numa frase \
  factual e específica: o que passa a poder ou não poder fazer-se, novas categorias, \
  novas faixas ou limites, novos prazos, o que é revogado. Inclui normas \
  transitórias quando concedem algo que passa a valer já. Ignora definições e \
  trâmites puramente administrativos.

  Escreve também um título curto (6 a 10 palavras) em linguagem simples sobre o \
  tema geral do que muda — não a designação formal do diploma.

  Responde APENAS com um objeto JSON válido, sem texto antes ou depois:
  {"headline": "<título>", "changes": ["<mudança>", "<mudança>", ...]}
  """

  # System prompt for the **renderer** (issue #90): amalia turns the extractor's
  # already-identified changes into the house voice. It only *writes* — no judging,
  # no dropping. A slightly longer form (4-6 sentences, one change each) so every
  # extracted change survives; markdown bullets are avoided (the small model can't
  # format them). The headline comes from the extractor, not from here.
  @render_system """
  És um jornalista que explica diplomas do Diário da República a um amigo sem \
  formação jurídica, em português do dia-a-dia.

  Recebes uma lista de mudanças concretas já identificadas neste diploma. Reescreve-as \
  num resumo de 4 a 6 frases curtas, uma mudança por frase. Mantém TODAS as mudanças \
  da lista — não juntes duas numa só nem descartes nenhuma.

  Regras de escrita:
  - Linguagem comum, frases curtas e diretas, voz ativa. Evita jargão jurídico.
  - Não cites números de diplomas nem de artigos no corpo do texto.
  - Sê factual, sem opinião. Simplifica o vocabulário, nunca a substância: mantém \
  prazos, categorias, faixas e limites tal como estão na lista.
  - Se um termo técnico for mesmo inevitável, marca-o entre parênteses retos duplos \
  assim [[termo]], no máximo 1 a 2 vezes.

  Classifica também o diploma em um ou mais domínios de vida.
  """

  @doc """
  Shared system prompt (writing + classification rules) for every adapter.

  `opts` tunes it:

    * `mode: :render` — the extract/render path (issue #90): return the renderer
      prompt (`@render_system`), which rewrites already-extracted changes rather
      than summarizing raw act text.
    * `strategy:` (`:full | :rank | :truncate`) — otherwise, an omnibus act
      (`:rank`/`:truncate`) gets the `@omnibus_note` appended so the model
      summarizes at the theme level; `:full`/nil gets the base prompt unchanged.
  """
  def system(opts \\ []) do
    cond do
      opts[:mode] == :render -> @render_system
      omnibus?(opts[:strategy]) -> @system <> @omnibus_note
      true -> @system
    end
  end

  # Big acts (didn't fit whole) get the omnibus note; `:full`/nil don't.
  defp omnibus?(strategy), do: strategy in [:rank, :truncate]

  @doc "System prompt for the extractor (strong model): lists concrete changes + headline."
  def extraction_system, do: @extraction_system

  @doc """
  User prompt for the extractor — the act metadata plus its (coarse-trimmed) text.
  The instructions + JSON shape ride in `extraction_system/0` (sent as the system
  role), so the user message is just the act body.
  """
  def extraction_prompt(act, text), do: act_body(act, text)

  @doc """
  The renderer's input: the extractor's changes formatted as a plain list, fed as
  the act text so amalia rewrites them. `headline` is carried separately (the
  extractor supplies it), so only `changes` appear here.
  """
  def render_changes(changes) when is_list(changes) do
    "Mudanças concretas identificadas neste diploma:\n" <>
      Enum.map_join(changes, "\n", &"- #{&1}")
  end

  @doc """
  Parse the extractor reply into `%{headline, changes}`. Reuses the tolerant
  `decode/1` (fenced JSON + trailing chatter). `{:error, :unparseable_extraction}`
  when it isn't the object we asked for (no string `headline`, or `changes` not a
  non-empty list of strings).
  """
  def parse_extraction(raw) when is_binary(raw) do
    with {:ok, obj} <- decode(raw),
         headline when is_binary(headline) <- obj["headline"],
         changes when is_list(changes) <- obj["changes"],
         [_ | _] = changes <- Enum.filter(changes, &is_binary/1) do
      {:ok, %{headline: headline, changes: changes}}
    else
      _ -> {:error, :unparseable_extraction}
    end
  end

  def parse_extraction(_), do: {:error, :unparseable_extraction}

  @doc """
  Plain-language JSON-output instruction for text-only backends. Structured-output
  backends use `schema/0` instead and never see this.
  """
  def json_instruction, do: @json_instruction

  @doc """
  Strict JSON schema for structured-output backends (Anthropic). Constrains
  `domains` to the fixed taxonomy so the response can't drift out of it.
  """
  def schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["plain_text", "headline", "domains"],
      "properties" => %{
        "plain_text" => %{"type" => "string"},
        "headline" => %{"type" => "string"},
        "domains" => %{
          "type" => "array",
          "items" => %{"type" => "string", "enum" => Register.life_domains()}
        }
      }
    }
  end

  @doc """
  The act-specific prompt body: metadata plus the already-prepared act text. Fed
  as the user message by structured-output backends (which carry the format in
  `schema/0`); text-only backends wrap it with `instructed_prompt/2`.
  """
  def act_body(act, text) do
    """
    Tipo: #{act.tipo}
    Emissor: #{act.emitter}
    Título: #{act.title}

    Texto:
    #{text}
    """
  end

  @doc """
  User prompt for text-only backends: the JSON instruction followed by the act
  body. The SSH adapter prepends `system/0`; the OpenAI adapter sends `system/0`
  as a separate role.
  """
  def instructed_prompt(act, text) do
    """
    #{json_instruction()}---
    #{act_body(act, text)}\
    """
  end

  @doc """
  Parse a raw model reply (possibly code-fenced JSON) into the summary fields the
  `Summary` schema stores — `plain_text`, `headline`, and taxonomy-validated
  `domains`. Every adapter routes its reply through here.

  `{:error, :unparseable_reply}` when the reply isn't the JSON object we asked
  for (not JSON, or missing a string `plain_text`). Usage/cost and `model`/
  `prompt_version` are the adapter's to merge — they're transport-specific.
  """
  def parse(raw) when is_binary(raw) do
    with {:ok, obj} <- decode(raw),
         text when is_binary(text) <- obj["plain_text"] do
      {:ok,
       %{
         plain_text: text,
         headline: obj["headline"],
         domains: valid_domains(obj["domains"])
       }}
    else
      _ -> {:error, :unparseable_reply}
    end
  end

  def parse(_), do: {:error, :unparseable_reply}

  @doc """
  Decode possibly-fenced JSON text into a map. Used by `parse/1` for the reply
  and by the SSH adapter for its CLI envelope (the outer layer wrapping the
  reply). `{:ok, map}` or `{:error, reason}`.

  Small local models (AMALIA-9B in particular) ignore the "reply with JSON only"
  instruction and append prose after the object — a `**Nota:** …` justification,
  a self-correction, even a second JSON object. `response_format: json_object`
  is only advisory on llama.cpp, so this arrives often. When a whole-string
  decode fails we fall back to the first brace-balanced `{…}` object in the text,
  which is the JSON we asked for; the trailing chatter is dropped.
  """
  def decode(raw) when is_binary(raw) do
    stripped = strip_fences(raw)

    case Jason.decode(stripped) do
      {:ok, _} = ok ->
        ok

      {:error, _} = err ->
        case first_json_object(stripped) do
          nil -> err
          obj -> Jason.decode(obj)
        end
    end
  end

  def decode(_), do: {:error, :not_a_string}

  # First brace-balanced JSON object embedded in `str`, as a binary, or nil.
  # String-aware so braces inside "..." values don't throw off the depth count.
  defp first_json_object(str) do
    case :binary.match(str, "{") do
      :nomatch ->
        nil

      {start, _} ->
        head = binary_part(str, start, byte_size(str) - start)

        case scan(head, 0, false, false) do
          nil -> nil
          len -> binary_part(head, 0, len)
        end
    end
  end

  # Walk the binary tracking brace depth; return the byte length up to and
  # including the `}` that closes the object opened at byte 0, or nil if it never
  # balances. Non-ASCII bytes (UTF-8 continuation bytes in accented text) fall
  # through the default branch untouched — only structural ASCII chars matter.
  defp scan(<<>>, _depth, _in_str, _esc), do: nil

  defp scan(<<c, rest::binary>>, depth, in_str, esc) do
    {depth, in_str, esc} = advance(c, depth, in_str, esc)

    if depth == 0 and not in_str do
      1
    else
      case scan(rest, depth, in_str, esc) do
        nil -> nil
        n -> n + 1
      end
    end
  end

  defp advance(_c, depth, in_str, true), do: {depth, in_str, false}
  defp advance(?\\, depth, true, false), do: {depth, true, true}
  defp advance(?", depth, in_str, false), do: {depth, not in_str, false}
  defp advance(_c, depth, true, false), do: {depth, true, false}
  defp advance(?{, depth, false, false), do: {depth + 1, false, false}
  defp advance(?}, depth, false, false), do: {depth - 1, false, false}
  defp advance(_c, depth, false, false), do: {depth, false, false}

  @doc "Strip ```` ```json ```` code fences a model may wrap its JSON reply in."
  def strip_fences(str) do
    str
    |> String.trim()
    |> String.replace(~r/^```(?:json)?\s*/i, "")
    |> String.replace(~r/\s*```$/, "")
    |> String.trim()
  end

  @doc """
  Keep only the domains that belong to the fixed taxonomy (as atoms), deduped.
  Anything the model invented is dropped. Non-lists become `[]`.
  """
  def valid_domains(domains) when is_list(domains) do
    domains
    |> Enum.flat_map(fn d ->
      case Register.fetch_domain(d) do
        {:ok, atom} -> [atom]
        :error -> []
      end
    end)
    |> Enum.uniq()
  end

  def valid_domains(_), do: []
end

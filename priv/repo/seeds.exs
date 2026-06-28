# Dev seed data for the register UI.
#
#     mix run priv/repo/seeds.exs
#
# Idempotent: re-running replaces the seed summaries (tagged prompt_version
# "seed-v1") and upserts the demo edition. The plain-language summaries here are
# illustrative dev fixtures, not real editorial output — they exist so the UI has
# representative content (every provenance rung, domain tags, "por gerar", and a
# second date group) to be built and reviewed against.

import Ecto.Query

alias OQueMudou.Repo
alias OQueMudou.Register
alias OQueMudou.Register.{Act, Summary}

now = DateTime.utc_now() |> DateTime.truncate(:second)
hours_ago = fn h -> DateTime.add(now, -h * 3600, :second) end

# ── Clean previous seed summaries so re-runs stay idempotent ─────────────────
Repo.delete_all(from(s in Summary, where: s.prompt_version == "seed-v1"))

# ── A second, older edition so the register shows more than one day ──────────
{:ok, ed2} =
  Register.upsert_edition(%{
    serie: "I",
    number: "119/2026",
    date: ~D[2026-06-23],
    sumario_url: "https://diariodarepublica.pt/dr/detalhe/edicao/i-119-2026"
  })

demo_acts = [
  %{
    dre_id: "seed-119-educacao",
    tipo: "Lei",
    emitter: "Assembleia da República",
    title: "Lei n.º 30/2026",
    source_url: "https://diariodarepublica.pt/dr/detalhe/lei/30-2026",
    pdf_url: "https://diariodarepublica.pt/dr/detalhe/lei/30-2026.pdf"
  },
  %{
    dre_id: "seed-119-saude",
    tipo: "Portaria",
    emitter: "Saúde",
    title: "Portaria n.º 270/2026",
    source_url: "https://diariodarepublica.pt/dr/detalhe/portaria/270-2026"
  }
]

for attrs <- demo_acts do
  Register.upsert_act(Map.put(attrs, :edition_id, ed2.id))
end

# ── Summaries keyed by act title (works on the real scraped acts + demo acts) ─
acts_by_title = Repo.all(Act) |> Map.new(&{&1.title, &1})

summarize = fn title, attrs ->
  case Map.get(acts_by_title, title) do
    nil ->
      IO.puts("  · skipped (no act): #{title}")

    act ->
      base = %{
        act_id: act.id,
        model: "claude-opus-4",
        prompt_version: "seed-v1",
        status: :unreviewed,
        generated_at: now
      }

      %Summary{}
      |> Summary.changeset(Map.merge(base, attrs))
      |> Repo.insert!()
  end
end

# Most recent edition (2026-06-24) — the real scraped acts.
summarize.("Decreto-Lei n.º 123/2026", %{
  plain_text:
    "Alarga o apoio público ao arrendamento a agregados com rendimentos até ao 4.º escalão e cria um teto de renda nas zonas de maior pressão. Quem já recebe apoio não precisa de voltar a candidatar-se; o novo valor é aplicado automaticamente a partir de 1 de julho de 2026.",
  domains: [:habitação, :fiscal],
  generated_at: hours_ago.(2)
})

summarize.("Resolução do Conselho de Ministros n.º 133/2026", %{
  plain_text:
    "Aprova o plano de investimento na rede ferroviária regional, com prioridade para as ligações entre cidades médias do interior. Define metas anuais mas ainda não fixa datas de conclusão das obras.",
  domains: [:transportes],
  generated_at: hours_ago.(3)
})

summarize.("Resolução do Conselho de Ministros n.º 134/2026", %{
  plain_text:
    "Estabelece novas regras de licenciamento ambiental para projetos de energia solar, encurtando os prazos de decisão e exigindo consulta pública obrigatória acima de uma certa dimensão.",
  domains: [:ambiente],
  status: :community_reviewed,
  generated_at: hours_ago.(5)
})

summarize.("Portaria n.º 273/2026/1", %{
  plain_text:
    "Atualiza as tabelas de retenção na fonte de IRS para a segunda metade de 2026, refletindo a descida aprovada no Orçamento. A maioria dos trabalhadores por conta de outrem verá um desconto mensal ligeiramente menor já no salário de julho.",
  domains: [:fiscal, :trabalho],
  validated_at: hours_ago.(1),
  generated_at: hours_ago.(6)
})

summarize.("Resolução da Assembleia da República n.º 158/2026", %{
  plain_text:
    "Recomenda ao Governo o reforço dos cuidados de saúde mental no Serviço Nacional de Saúde, com foco no acesso de jovens. É uma recomendação política, sem força de lei.",
  domains: [:saúde],
  generated_at: hours_ago.(7)
})

summarize.("Resolução da Assembleia da República n.º 160/2026", %{
  plain_text:
    "Determina a criação de uma comissão para rever os prazos da justiça cível. O objetivo declarado é reduzir o tempo médio de espera por uma decisão em tribunal.",
  domains: [:justiça],
  status: :verified,
  generated_at: hours_ago.(8)
})

summarize.("Resolução da Assembleia da República n.º 162/2026", %{
  plain_text:
    "Recomenda alargar a licença parental e reforçar a fiscalização do teletrabalho. Pede ainda um relatório anual sobre a aplicação destas regras nas empresas, mas não altera, por si só, o Código do Trabalho.",
  domains: [:trabalho, :família],
  generated_at: hours_ago.(9)
})

summarize.("Declaração de Retificação n.º 1/2026/A/1", %{
  plain_text:
    "Corrige um erro material num diploma anterior da Região Autónoma dos Açores. Não muda o conteúdo da decisão — apenas acerta o texto publicado.",
  domains: [:administração],
  generated_at: hours_ago.(10)
})

# Older edition (2026-06-23) — the demo acts.
summarize.("Lei n.º 30/2026", %{
  plain_text:
    "Torna gratuitos os manuais escolares até ao 12.º ano e cria um apoio para material escolar das famílias com menores rendimentos, a partir do próximo ano letivo.",
  domains: [:educação, :família],
  generated_at: hours_ago.(26)
})

summarize.("Portaria n.º 270/2026", %{
  plain_text:
    "Inclui novos medicamentos na lista de comparticipação do Estado e reduz o valor pago pelos utentes em alguns tratamentos crónicos.",
  domains: [:saúde],
  status: :community_reviewed,
  generated_at: hours_ago.(28)
})

count = Repo.aggregate(from(s in Summary, where: s.prompt_version == "seed-v1"), :count)
IO.puts("Seeded #{count} demo summaries.")

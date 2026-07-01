defmodule OQueMudouWeb.AboutLive do
  @moduledoc """
  Sobre — explains what the Arcada does, where the name comes from, and the
  trust posture (a civic signpost, never an authority). The historical notes on
  Braga's Arcada are sourced from pt.wikipedia.org/wiki/Arcada_(Braga).
  """
  use OQueMudouWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Sobre")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <article class="mx-auto max-w-reading py-12 sm:py-16">
      <h1 class="sr-only">Sobre a Arcada</h1>

      <div class="space-y-5 font-serif text-[1.0625rem] leading-relaxed text-ink">
        <p>
          A Arcada pega no <em>Diário da República, Série I</em>
          e reconta-o em linguagem simples: o que muda, para quem, e quando.
        </p>
        <p>
          Isto é só um resumo. Não substitui o Diário original, que fica sempre a
          um clique, nem serve de aconselhamento jurídico.
        </p>
        <p>
          O ponto de partida é o Diário da República. A ideia é, com o tempo, fazer
          o mesmo às câmaras municipais, juntas de freguesia e a outras entidades públicas.
        </p>
      </div>

      <h2 class="mt-11 font-display text-[1.375rem] font-semibold leading-tight text-ink">
        Como é usada a inteligência artificial
      </h2>
      <div class="mt-4 space-y-5 font-serif text-[1.0625rem] leading-relaxed text-ink">
        <p>
          Sim, a Arcada usa modelos de linguagem para escrever os resumos. É o tipo de
          trabalho que faz sentido entregar a uma máquina: pegar todos os dias em
          diplomas densos e reescrevê-los, um a um, em português simples.
        </p>
        <p>
          Mas não é só pedir a um modelo que resuma. Por trás há um pipeline:
          parte-se do texto oficial, divide-se em secções e escolhem-se as
          relevantes com embeddings; o modelo gera o título e o resumo e classifica
          o diploma por área; no fim, indexa-se tudo para pesquisa semântica.
        </p>
        <p>
          Os modelos também erram. Por isso o texto oficial fica sempre a um clique,
          para confirmar o que quiser.
        </p>
      </div>

      <h2 class="mt-11 font-display text-[1.375rem] font-semibold leading-tight text-ink">
        O nome
      </h2>
      <div class="mt-4 space-y-5 font-serif text-[1.0625rem] leading-relaxed text-ink">
        <p>
          <em>Arcada</em>
          é a galeria de arcos da praça central de Braga — o lugar coberto onde,
          desde o século XVI, se fazia o mercado e se juntava a cidade. A arcada
          que lhe dá o nome é setecentista. Em 1910, com a implantação da
          República, a praça passou a chamar-se <strong>Praça da República</strong> —
          e é assim que partilha o nome com o Diário que aqui se resume.
        </p>
        <p>
          O nome foi escolhido por isso mesmo: uma arcada é uma praça, um sítio onde
          as pessoas se juntam e se fala claro.
        </p>
      </div>

      <figure class="mt-8">
        <img
          src={~p"/images/arcada-braga.jpg"}
          width="1280"
          height="910"
          loading="lazy"
          alt="A Arcada e a Igreja da Lapa, ao anoitecer, na Praça da República em Braga."
          class="w-full rounded-[3px] border border-border"
        />
        <figcaption class="mt-2 text-center text-xs text-muted">
          A Arcada, na Praça da República, em Braga.
          <span aria-hidden="true">·</span>
          <a
            href="https://commons.wikimedia.org/wiki/File:Arcada_in_Braga_03.jpg"
            rel="noopener"
            class="hover:text-primary hover:underline"
          >
            Foto: Krzysztof Golik, CC BY-SA 4.0
          </a>
        </figcaption>
      </figure>

      <h2 class="mt-11 font-display text-[1.375rem] font-semibold leading-tight text-ink">
        Contacto
      </h2>
      <p class="mt-4 font-serif text-[1.0625rem] leading-relaxed text-ink">
        Feito por Miguel Palhas (<a
          href="https://naps.pt"
          rel="noopener"
          class="text-primary hover:underline"
        >naps.pt</a>). Dúvidas, erros ou sugestões:
        <a href="mailto:arcada@naps62.com" class="text-primary hover:underline">
          arcada@naps62.com
        </a>.
      </p>

      <div class="mt-11 border-t border-border pt-6">
        <.link
          navigate="/"
          class="inline-flex items-center gap-1 text-sm font-medium text-primary hover:underline"
        >
          <.icon name="hero-arrow-left-micro" class="size-4" /> Voltar ao registo
        </.link>
      </div>
    </article>
    """
  end
end

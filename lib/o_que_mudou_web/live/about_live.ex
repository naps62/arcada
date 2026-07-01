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
      <h1 class="text-balance text-center font-display text-[2rem] font-semibold leading-tight text-ink sm:text-[2.625rem]">
        Sobre a Arcada
      </h1>

      <div class="mt-6 space-y-5 font-serif text-[1.0625rem] leading-relaxed text-ink">
        <p>
          A Arcada pega no <em>Diário da República, Série I</em>
          e reconta-o em linguagem simples: o que muda, para quem, e quando. É um
          sinal de confiança pública — nunca uma autoridade, nunca aconselhamento
          jurídico. A fonte oficial fica sempre a um toque de distância.
        </p>
        <p>
          Começamos pelo Diário da República. Com o tempo, queremos trazer a mesma
          clareza a câmaras municipais, juntas de freguesia e outras entidades
          públicas — a lei de todos, em português de toda a gente.
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
          e é assim que partilha o nome com o Diário que aqui resumimos.
        </p>
        <p>
          Escolhemo-lo pelo que uma arcada sempre foi: uma praça pública, aberta a
          todos, onde as coisas de todos se dizem em voz clara.
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

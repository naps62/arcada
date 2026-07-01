defmodule OQueMudouWeb.FaqLive do
  @moduledoc """
  Perguntas frequentes — plain answers to the questions a first-time reader
  arrives with: what this is, where the summaries come from, the caveat that it
  is never legal advice, and who is behind it. Each item is a native
  `<details>`: only the questions show by default, answers open on tap/Enter —
  keyboard-accessible and works without JS, per the plain-interaction principle.
  """
  use OQueMudouWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Perguntas frequentes")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <article class="mx-auto max-w-reading py-12 sm:py-16">
      <h1 class="text-balance text-center font-display text-[2rem] font-semibold leading-tight text-ink sm:text-[2.625rem]">
        Perguntas frequentes
      </h1>
      <p class="mx-auto mt-4 max-w-reading text-balance text-center font-serif text-[1.0625rem] leading-relaxed text-muted">
        As dúvidas mais comuns sobre o que a Arcada faz — e o que não faz.
      </p>

      <div class="mt-11 border-t border-border">
        <.faq_item id="faq-o-que" question="O que é a Arcada?">
          <p>
            Pegamos no <em>Diário da República, Série I</em>
            e reescrevemo-lo em linguagem simples: o que muda, para quem, e a
            partir de quando. Em vez de ler o texto legal por inteiro, lê um
            resumo curto e honesto — com ligação ao original a um clique.
          </p>
        </.faq_item>

        <.faq_item id="faq-juridico" question="Isto substitui aconselhamento jurídico?">
          <p>
            A Arcada ajuda-o a estar a par da lei, numa linguagem que todos
            entendemos, sem ter de folhear páginas e páginas de burocracia.
          </p>
          <p>
            Não é um parecer jurídico e não deve ser usada como tal. É um ponto de
            partida: para decisões que dependam da lei, consulte o Diário original
            e, se necessário, um profissional.
          </p>
        </.faq_item>

        <.faq_item id="faq-fontes-resumos" question="De onde vêm os resumos?">
          <p>
            Cada resumo é feito a partir do próprio diploma publicado no
            <em>Diário da República</em>, com citações ao nível do artigo. A ligação
            para o texto oficial está sempre presente — a ideia é que possa
            confirmar tudo por si, na fonte.
          </p>
        </.faq_item>

        <.faq_item id="faq-erros" question="Os resumos podem estar errados?">
          <p>
            Podem. São resumos gerados de forma automática e, como qualquer
            tradução, podem escorregar num detalhe. É por isso que mostramos sempre
            a ligação para o Diário original: perante qualquer dúvida, o texto
            oficial é que manda.
          </p>
        </.faq_item>

        <.faq_item id="faq-fontes" question="Que fontes cobrem?">
          <p>
            Começamos pelo <em>Diário da República, Série I</em>. A ideia é, com o
            tempo, fazer o mesmo às câmaras municipais, juntas de freguesia e a
            outras entidades públicas — trazer o mesmo trabalho de tradução para
            linguagem simples a mais fontes oficiais.
          </p>
        </.faq_item>

        <.faq_item id="faq-quem" question="Quem fez isto?">
          <p>
            A Arcada é um projeto independente de <a
              href="https://naps.pt"
              target="_blank"
              rel="noopener noreferrer"
              class="font-medium text-primary hover:underline"
            >Miguel Palhas</a>, sem ligação a qualquer organismo oficial. Nasceu de
            uma ideia simples: a lei é de todos, mas está escrita de uma forma que
            afasta a maioria das pessoas — e isso dá para mudar.
          </p>
        </.faq_item>
      </div>

      <div class="mt-11 border-t border-border pt-6">
        <p class="font-serif text-[1.0625rem] leading-relaxed text-muted">
          Ficou por responder? Saiba mais em <.link
            navigate="/sobre"
            class="font-medium text-primary hover:underline"
          >Sobre a Arcada</.link>.
        </p>
        <.link
          navigate="/"
          class="mt-6 inline-flex items-center gap-1 text-sm font-medium text-primary hover:underline"
        >
          <.icon name="hero-arrow-left-micro" class="size-4" /> Voltar ao registo
        </.link>
      </div>
    </article>
    """
  end

  # One collapsible FAQ entry. Native <details>, so it opens on click or Enter
  # and works with JS off; the Collapsible hook adds a smooth height animation
  # on top (and steps aside under prefers-reduced-motion). The chevron flips via
  # the group-open state.
  attr :id, :string, required: true
  attr :question, :string, required: true
  slot :inner_block, required: true

  defp faq_item(assigns) do
    ~H"""
    <details id={@id} phx-hook="Collapsible" class="group border-b border-border">
      <summary class="flex cursor-pointer list-none items-center justify-between gap-4 rounded-[3px] py-4 font-display text-[1.1875rem] font-semibold text-ink marker:hidden focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/60 [&::-webkit-details-marker]:hidden">
        {@question}
        <.icon
          name="hero-chevron-down-mini"
          class="size-5 shrink-0 text-muted transition-transform duration-200 group-open:rotate-180 motion-reduce:transition-none"
        />
      </summary>
      <div
        data-collapsible-content
        class="space-y-4 pb-5 font-serif text-[1.0625rem] leading-relaxed text-ink"
      >
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end
end

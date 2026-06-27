defmodule OQueMudouWeb.ActLive do
  @moduledoc """
  Act detail: plain-language summary + life-domains, with the official source,
  PDF citation, and full legal text always one click away — plus the private
  "marcar como validado" toggle (the human safety net before anything is trusted).
  See `docs/PLAN.md` build order #4.
  """
  use OQueMudouWeb, :live_view

  alias OQueMudou.Register

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    act = Register.get_act!(id)
    {:ok, assign(socket, act: act, summary: latest_summary(act), show_full: false)}
  end

  @impl true
  def handle_event("toggle_validated", _params, socket) do
    case socket.assigns.summary do
      nil ->
        {:noreply, socket}

      summary ->
        {:ok, updated} = Register.set_validated(summary, is_nil(summary.validated_at))
        {:noreply, assign(socket, summary: updated)}
    end
  end

  def handle_event("toggle_full", _params, socket) do
    {:noreply, assign(socket, show_full: !socket.assigns.show_full)}
  end

  defp latest_summary(%{summaries: summaries}) do
    summaries |> Enum.sort_by(& &1.generated_at, {:desc, DateTime}) |> List.first()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl px-4 py-8">
      <.link navigate={~p"/"} class="text-sm text-zinc-500 hover:underline">&larr; Voltar ao registo</.link>

      <header class="mt-4">
        <p :if={@act.tipo} class="text-xs uppercase tracking-wide text-zinc-400">{@act.tipo}</p>
        <h1 class="text-2xl font-bold text-zinc-900">{@act.title || @act.tipo}</h1>
        <p class="mt-1 text-sm text-zinc-500">
          {@act.emitter}
          <span :if={@act.published_at}> · {@act.published_at}</span>
        </p>
      </header>

      <section class="mt-6 rounded-lg border border-zinc-200 p-4">
        <div class="mb-2 flex items-center justify-between">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-500">Resumo</h2>
          <.validation_control summary={@summary} />
        </div>

        <p :if={@summary} class="text-zinc-800">{@summary.plain_text}</p>
        <p :if={is_nil(@summary)} class="italic text-zinc-400">Ainda sem resumo.</p>

        <div :if={@summary && @summary.domains != []} class="mt-3 flex flex-wrap gap-1">
          <span
            :for={d <- @summary.domains}
            class="rounded bg-zinc-100 px-2 py-0.5 text-xs text-zinc-600"
          >
            {d}
          </span>
        </div>

        <p :if={@summary} class="mt-3 text-xs text-zinc-400">
          {model_line(@summary)}
        </p>
      </section>

      <section class="mt-4 flex flex-wrap gap-3 text-sm">
        <a
          :if={@act.source_url}
          href={@act.source_url}
          target="_blank"
          class="rounded border border-zinc-300 px-3 py-1.5 text-zinc-700 hover:bg-zinc-50"
        >
          Fonte oficial ↗
        </a>
        <a
          :if={@act.pdf_url}
          href={@act.pdf_url}
          target="_blank"
          class="rounded border border-zinc-300 px-3 py-1.5 text-zinc-700 hover:bg-zinc-50"
        >
          PDF (citação) ↗
        </a>
        <button
          :if={@act.full_text}
          phx-click="toggle_full"
          class="rounded border border-zinc-300 px-3 py-1.5 text-zinc-700 hover:bg-zinc-50"
        >
          {if @show_full, do: "Ocultar texto integral", else: "Ver texto integral"}
        </button>
      </section>

      <section :if={@show_full && @act.full_text} class="mt-4 rounded-lg bg-zinc-50 p-4">
        <div class="prose prose-sm max-w-none text-zinc-800">{raw(@act.full_text)}</div>
      </section>
    </div>
    """
  end

  attr :summary, :map, default: nil

  defp validation_control(%{summary: nil} = assigns), do: ~H""

  defp validation_control(assigns) do
    ~H"""
    <button
      phx-click="toggle_validated"
      class={[
        "rounded-full px-3 py-1 text-xs font-medium transition",
        @summary.validated_at && "bg-green-100 text-green-800 hover:bg-green-200",
        !@summary.validated_at && "bg-amber-100 text-amber-800 hover:bg-amber-200"
      ]}
    >
      {if @summary.validated_at, do: "✓ validado", else: "🤖 marcar como validado"}
    </button>
    """
  end

  defp model_line(%{model: model, prompt_version: pv}) when is_binary(model),
    do: "Gerado por #{model} · prompt #{pv}"

  defp model_line(_), do: "Resumo manual"
end

defmodule OQueMudouWeb.AdminActLive do
  @moduledoc """
  Admin view for one act (`/admin/acts/:id`): compare every summary (with its
  provider/model), publish one as canonical, and trigger a new run against any
  provider+model. See issue #20.
  """
  use OQueMudouWeb, :live_view_admin

  alias OQueMudou.{Providers, Register, Summarizer}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(providers: Providers.enabled_providers(), trigger_id: nil)
     |> load(id)}
  end

  defp load(socket, id) do
    act = Register.get_act!(id)

    assign(socket,
      act: act,
      summaries: sorted(act.summaries),
      published_id: act.published_summary_id
    )
  end

  defp sorted(summaries),
    do: Enum.sort_by(summaries, & &1.generated_at, {:desc, DateTime})

  @impl true
  def handle_event("publish", %{"id" => sid}, socket) do
    summary = Enum.find(socket.assigns.summaries, &(&1.id == String.to_integer(sid)))
    {:ok, _} = Register.set_published(socket.assigns.act, summary)
    {:noreply, socket |> put_flash(:info, "Summary published.") |> load(socket.assigns.act.id)}
  end

  def handle_event("pick_provider", %{"provider_id" => pid}, socket) do
    {:noreply, assign(socket, trigger_id: parse_id(pid))}
  end

  def handle_event("trigger", %{"provider_id" => pid, "model" => model} = params, socket) do
    case parse_id(pid) do
      nil ->
        {:noreply, put_flash(socket, :error, "Pick a provider.")}

      id ->
        Summarizer.enqueue(socket.assigns.act.id,
          provider_id: id,
          model: emptyish(model),
          text_strategy: emptyish(params["text_strategy"])
        )

        {:noreply, put_flash(socket, :info, "Run queued — refresh in a moment.")}
    end
  end

  defp parse_id(p) when p in ["", nil], do: nil
  defp parse_id(p), do: String.to_integer(p)
  defp emptyish(""), do: nil
  defp emptyish(v), do: v

  defp trigger_provider(providers, id), do: Enum.find(providers, &(&1.id == id))

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :tp, trigger_provider(assigns.providers, assigns.trigger_id))

    ~H"""
    <nav aria-label="Breadcrumb" class="flex items-center justify-between gap-4 text-[0.8125rem]">
      <div class="min-w-0 text-muted">
        <.link navigate={~p"/admin"} class="hover:text-primary hover:underline">Admin</.link>
        <span aria-hidden="true" class="mx-1.5 text-border">/</span>
        <span class="text-ink">Act</span>
      </div>
      <a
        href={~p"/acts/#{@act.id}"}
        class="inline-flex shrink-0 items-center gap-1 font-medium text-muted hover:text-primary hover:underline"
      >
        View public page <.icon name="hero-arrow-top-right-on-square-micro" class="size-3.5" />
      </a>
    </nav>

    <h1 class="mt-4 border-b-2 border-rule-strong pb-3 font-display text-xl font-semibold leading-snug text-ink">
      {@act.title || @act.tipo}
    </h1>

    <section class="mt-6 rounded-md border border-border bg-surface p-4">
      <h2 class="text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">
        Run a summary
      </h2>
      <form
        phx-change="pick_provider"
        phx-submit="trigger"
        class="mt-3 flex flex-wrap items-end gap-3"
      >
        <div>
          <label class="block text-xs text-muted">Provider</label>
          <select
            name="provider_id"
            class="mt-1 rounded-md border border-border bg-bg px-2 py-1.5 text-sm text-ink focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
          >
            <option value="">—</option>
            <option :for={p <- @providers} value={p.id} selected={@trigger_id == p.id}>
              {p.name} ({p.kind})
            </option>
          </select>
        </div>
        <div>
          <label class="block text-xs text-muted">Model</label>
          <select
            name="model"
            class="mt-1 rounded-md border border-border bg-bg px-2 py-1.5 text-sm text-ink focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
          >
            <option value="">(default)</option>
            <option :for={m <- (@tp && @tp.models) || []} value={m}>{m}</option>
          </select>
        </div>
        <div>
          <label class="block text-xs text-muted">Text (long acts)</label>
          <select
            name="text_strategy"
            class="mt-1 rounded-md border border-border bg-bg px-2 py-1.5 text-sm text-ink focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
          >
            <option value="auto">Automatic</option>
            <option value="rank">Relevant sections</option>
            <option value="truncate">Start (truncate)</option>
          </select>
        </div>
        <button
          type="submit"
          class="rounded-md bg-primary px-3 py-1.5 text-sm font-semibold text-primary-fg transition-colors duration-150 ease-out-quart hover:bg-primary-hover"
        >
          Run
        </button>
      </form>
    </section>

    <section class="mt-8">
      <h2 class="border-b-2 border-rule-strong pb-2 text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">
        Summaries
        <span :if={@summaries != []} class="ml-1 font-normal tabular-nums">{length(@summaries)}</span>
      </h2>
      <p :if={@summaries == []} class="mt-4 text-sm text-muted">No summaries yet.</p>

      <article
        :for={s <- @summaries}
        class={[
          "mt-4 rounded-md border p-4",
          (@published_id == s.id && "border-primary bg-surface") || "border-border"
        ]}
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="flex flex-wrap items-center gap-2 text-xs text-muted">
            <span class="font-semibold text-ink">{provider_name(s)}</span>
            <span>· {s.model || "—"}</span>
            <span :if={strategy_label(s)}>· {strategy_label(s)}</span>
            <.provenance_badge summary={s} />
            <.partial_summary_badge summary={s} />
          </div>
          <button
            :if={@published_id != s.id}
            phx-click="publish"
            phx-value-id={s.id}
            class="rounded-md border border-border px-2.5 py-1 text-xs font-medium text-ink transition-colors duration-150 ease-out-quart hover:bg-surface-inset"
          >
            Publish
          </button>
          <span
            :if={@published_id == s.id}
            class="inline-flex items-center gap-1 text-xs font-semibold text-primary"
          >
            <.icon name="hero-check-circle-micro" class="size-4" /> published
          </span>
        </div>
        <p class="mt-3 font-serif text-[1.0625rem] leading-relaxed text-ink">{s.plain_text}</p>
        <div :if={s.domains != []} class="mt-2 flex flex-wrap gap-1.5">
          <.domain_tag :for={d <- s.domains} label={to_string(d)} />
        </div>
      </article>
    </section>
    """
  end

  defp provider_name(%{provider: %{name: name}}), do: name
  defp provider_name(_), do: "—"

  # How an oversized act's text was prepared for this summary (nil when the act
  # fit whole — nothing worth labelling). Lets you eyeball ranked vs truncated;
  # ranked rows also name the embeddings model that preprocessed the input.
  defp strategy_label(%{text_strategy: "rank", ranker_model: m}) when is_binary(m),
    do: "relevant sections · #{m}"

  defp strategy_label(%{text_strategy: "rank"}), do: "relevant sections"
  defp strategy_label(%{text_strategy: "truncate"}), do: "start"
  defp strategy_label(_), do: nil
end

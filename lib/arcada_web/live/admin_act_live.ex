defmodule ArcadaWeb.AdminActLive do
  @moduledoc """
  Admin view for one act (`/admin/acts/:id`): compare every summary (with its
  provider/model), publish one as canonical, and trigger a new run against any
  provider+model. See issue #20.
  """
  use ArcadaWeb, :live_view_admin

  alias Arcada.{Providers, Register, Summarizer}

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

  def handle_event("embed", %{"id" => sid}, socket) do
    summary = Enum.find(socket.assigns.summaries, &(&1.id == String.to_integer(sid)))

    case Summarizer.embed_summary(summary) do
      {:ok, _updated} ->
        {:noreply,
         socket |> put_flash(:info, "Embedding generated.") |> load(socket.assigns.act.id)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Embedding failed: #{inspect(reason)}")}
    end
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
    <div class="max-w-3xl">
      <nav aria-label="Breadcrumb" class="flex items-center justify-between gap-4 text-[0.8125rem]">
        <div class="min-w-0 text-muted">
          <.link navigate={~p"/admin"} class="hover:text-primary hover:underline">Admin</.link>
          <span aria-hidden="true" class="mx-1.5 text-border">/</span>
          <span class="text-ink">Act</span>
        </div>
        <a
          href={ArcadaWeb.SEO.act_path(@act)}
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
          id="run-summary"
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
    </div>

    <section class="mt-8">
      <h2 class="max-w-3xl border-b-2 border-rule-strong pb-2 text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">
        Summaries
        <span :if={@summaries != []} class="ml-1 font-normal tabular-nums">{length(@summaries)}</span>
      </h2>
      <p :if={@summaries == []} class="mt-4 max-w-3xl text-sm text-muted">No summaries yet.</p>

      <%!-- Two or more: lay them out as side-by-side columns so the prose can be
           read against each other. The strip spans the full console width (not the
           max-w-3xl reading column) so it uses the space to its right before it
           ever scrolls — three columns fit on a laptop without a scrollbar. --%>
      <div :if={length(@summaries) >= 2} class="mt-4 flex gap-4 overflow-x-auto pb-3">
        <.summary_column :for={s <- @summaries} summary={s} published_id={@published_id} />
      </div>

      <%!-- One (or zero): a single card at reading width beats a lone column. --%>
      <div :if={length(@summaries) < 2} class="max-w-3xl">
        <.summary_card :for={s <- @summaries} summary={s} published_id={@published_id} />
      </div>
    </section>
    """
  end

  # A single full-width summary card — used when an act has just one summary.
  attr :summary, :any, required: true
  attr :published_id, :any, default: nil

  defp summary_card(assigns) do
    ~H"""
    <article class={[
      "mt-4 rounded-md border p-4",
      (@published_id == @summary.id && "border-primary bg-surface") || "border-border"
    ]}>
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="flex flex-wrap items-center gap-2 text-xs text-muted">
          <span class="font-semibold text-ink">{provider_name(@summary)}</span>
          <span>· {@summary.model || "—"}</span>
          <span :if={strategy_label(@summary)}>· {strategy_label(@summary)}</span>
          <span :if={tokens_label(@summary)} class="tabular-nums">· {tokens_label(@summary)}</span>
          <span :if={cost_label(@summary)} class="tabular-nums">· {cost_label(@summary)}</span>
          <span :if={duration_label(@summary)} class="tabular-nums">· {duration_label(@summary)}</span>
        </div>
        <div class="flex items-center gap-2">
          <span :if={@summary.embedding} class="text-xs text-muted">embedded</span>
          <button
            phx-click="embed"
            phx-value-id={@summary.id}
            class="rounded-md border border-border px-2.5 py-1 text-xs font-medium text-ink transition-colors duration-150 ease-out-quart hover:bg-surface-inset"
          >
            {if @summary.embedding, do: "Regenerate embedding", else: "Generate embedding"}
          </button>
          <button
            :if={@published_id != @summary.id}
            phx-click="publish"
            phx-value-id={@summary.id}
            class="rounded-md border border-border px-2.5 py-1 text-xs font-medium text-ink transition-colors duration-150 ease-out-quart hover:bg-surface-inset"
          >
            Publish
          </button>
          <span
            :if={@published_id == @summary.id}
            class="inline-flex items-center gap-1 text-xs font-semibold text-primary"
          >
            <.icon name="hero-check-circle-micro" class="size-4" /> published
          </span>
        </div>
      </div>
      <p :if={@summary.headline} class="mt-3 font-display text-base font-semibold text-ink">
        {@summary.headline}
      </p>
      <p class={[
        "font-serif text-[1.0625rem] leading-relaxed text-ink",
        if(@summary.headline, do: "mt-2", else: "mt-3")
      ]}>
        {@summary.plain_text}
      </p>
      <div :if={@summary.domains != []} class="mt-2 flex flex-wrap gap-1.5">
        <.domain_tag :for={d <- @summary.domains} label={to_string(d)} />
      </div>
    </article>
    """
  end

  # One column of the side-by-side comparison. Header stacks the run's metadata
  # vertically (there's no room for a horizontal strip); body carries the prose.
  attr :summary, :any, required: true
  attr :published_id, :any, default: nil

  defp summary_column(assigns) do
    assigns = assign(assigns, :published?, assigns.published_id == assigns.summary.id)

    ~H"""
    <article class={[
      "flex w-80 shrink-0 flex-col rounded-md border p-4",
      (@published? && "border-primary bg-surface") || "border-border"
    ]}>
      <header class="border-b border-border pb-3">
        <div class="flex items-baseline justify-between gap-2">
          <span class="font-semibold text-ink">{provider_name(@summary)}</span>
          <span
            :if={@published?}
            class="inline-flex items-center gap-1 text-xs font-semibold text-primary"
          >
            <.icon name="hero-check-circle-micro" class="size-4" /> published
          </span>
        </div>
        <dl class="mt-2 space-y-0.5 text-xs text-muted">
          <div><span class="text-ink">{@summary.model || "—"}</span></div>
          <div :if={strategy_label(@summary)}>{strategy_label(@summary)}</div>
          <div :if={tokens_label(@summary)} class="tabular-nums">{tokens_label(@summary)}</div>
          <div :if={cost_label(@summary)} class="tabular-nums">{cost_label(@summary)}</div>
          <div :if={duration_label(@summary)} class="tabular-nums">{duration_label(@summary)}</div>
          <div :if={generated_label(@summary)} class="tabular-nums">{generated_label(@summary)}</div>
        </dl>
        <div :if={@summary.domains != []} class="mt-2 flex flex-wrap items-center gap-1.5">
          <.domain_tag :for={d <- @summary.domains} label={to_string(d)} />
        </div>
        <button
          :if={not @published?}
          phx-click="publish"
          phx-value-id={@summary.id}
          class="mt-3 w-full rounded-md border border-border px-2.5 py-1.5 text-xs font-medium text-ink transition-colors duration-150 ease-out-quart hover:bg-surface-inset"
        >
          Make canonical
        </button>
      </header>
      <p :if={@summary.headline} class="mt-3 font-display text-sm font-semibold text-ink">
        {@summary.headline}
      </p>
      <p class={[
        "font-serif text-[0.9375rem] leading-relaxed text-ink",
        if(@summary.headline, do: "mt-2", else: "mt-3")
      ]}>
        {@summary.plain_text}
      </p>
    </article>
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

  # Prompt → completion token counts for the run (nil when the backend didn't
  # report usage, e.g. a stubbed test run or legacy row).
  defp tokens_label(%{input_tokens: i, output_tokens: o}) when is_integer(i) and is_integer(o),
    do: "#{i} → #{o} tok"

  defp tokens_label(_), do: nil

  # Dollar cost. The SSH path's cost is notional (covered by a Claude
  # subscription), so it's flagged rather than shown as real spend.
  defp cost_label(%{cost_usd: nil}), do: nil

  defp cost_label(%{cost_usd: c, cost_source: "subscription"}) when not is_nil(c),
    do: "$#{fmt_cost(c)} (subscription)"

  defp cost_label(%{cost_usd: c}) when not is_nil(c), do: "$#{fmt_cost(c)}"
  defp cost_label(_), do: nil

  defp fmt_cost(%Decimal{} = c), do: c |> Decimal.round(4) |> Decimal.to_string(:normal)
  defp fmt_cost(c), do: to_string(c)

  defp duration_label(%{duration_ms: ms}) when is_integer(ms) and ms > 0 do
    if ms >= 1000, do: "#{Float.round(ms / 1000, 1)}s", else: "#{ms}ms"
  end

  defp duration_label(_), do: nil

  # When the run finished, to the minute — the comparison columns show it so runs
  # can be ordered by recency at a glance.
  defp generated_label(%{generated_at: %DateTime{} = dt}),
    do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp generated_label(_), do: nil
end

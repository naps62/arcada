defmodule OQueMudouWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as modals, tables, and
  forms. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component
  use Gettext, backend: OQueMudouWeb.Gettext

  # `~p` verified routes, needed by `act_entry/1` (shared between RegisterLive
  # and SearchLive).
  use Phoenix.VerifiedRoutes,
    endpoint: OQueMudouWeb.Endpoint,
    router: OQueMudouWeb.Router,
    statics: OQueMudouWeb.static_paths()

  alias Phoenix.LiveView.JS

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        This is a modal.
      </.modal>

  JS commands may be passed to the `:on_cancel` to configure
  the closing/cancel event, for example:

      <.modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
        This is another modal.
      </.modal>

  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="bg-zinc-50/90 fixed inset-0 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-3xl p-4 sm:p-6 lg:py-8">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white p-14 shadow-lg ring-1 transition"
            >
              <div class="absolute top-6 right-5">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="-m-3 flex-none p-3 opacity-20 hover:opacity-40"
                  aria-label={gettext("close")}
                >
                  <.icon name="hero-x-mark-solid" class="h-5 w-5" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed right-4 top-4 z-50 w-[calc(100vw-2rem)] max-w-96 rounded-md border bg-surface p-4 pr-10 shadow-floating",
        @kind == :info && "border-border text-ink",
        @kind == :error && "border-state-error-ink/35 text-ink"
      ]}
      {@rest}
    >
      <p :if={@title} class="flex items-center gap-1.5 text-sm font-semibold leading-5">
        <.icon
          :if={@kind == :info}
          name="hero-information-circle-mini"
          class="size-4 shrink-0 text-primary"
        />
        <.icon
          :if={@kind == :error}
          name="hero-exclamation-triangle-mini"
          class="size-4 shrink-0 text-state-error-ink"
        />
        <span class={[@kind == :error && "text-state-error-ink"]}>{@title}</span>
      </p>
      <p class="mt-1.5 text-sm leading-5 text-muted">{msg}</p>
      <button
        type="button"
        class="group absolute right-1.5 top-1.5 rounded p-2 text-muted hover:text-ink"
        aria-label={gettext("fechar")}
      >
        <.icon name="hero-x-mark-mini" class="size-4" />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} title={gettext("Feito")} flash={@flash} />
      <.flash kind={:error} title={gettext("Erro")} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("Sem ligação")}
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        {gettext("A tentar reconectar")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Algo correu mal")}
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        {gettext("Aguarde enquanto repomos o serviço")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the data structure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="mt-10 space-y-8">
        {render_slot(@inner_block, f)}
        <div :for={action <- @actions} class="mt-2 flex items-center justify-between gap-6">
          {render_slot(action, f)}
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 rounded-md bg-primary hover:bg-primary-hover py-2 px-3",
        "text-sm font-semibold leading-6 text-primary-fg active:opacity-90",
        "transition-colors duration-150 ease-out-quart",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               range search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div>
      <label class="flex items-center gap-4 text-sm leading-6 text-ink">
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="rounded border-border bg-surface text-primary focus:ring-primary"
          {@rest}
        />
        {@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <select
        id={@id}
        name={@name}
        class={[
          "mt-1.5 block w-full rounded-md border bg-surface px-3 py-2 text-sm text-ink shadow-sm focus:outline-none focus:ring-1",
          @errors == [] && "border-border focus:border-primary focus:ring-primary",
          @errors != [] &&
            "border-state-error-ink focus:border-state-error-ink focus:ring-state-error-ink"
        ]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "mt-1.5 block min-h-[6rem] w-full rounded-md border bg-surface px-3 py-2 text-sm text-ink placeholder:text-muted/60 focus:outline-none focus:ring-1",
          @errors == [] && "border-border focus:border-primary focus:ring-primary",
          @errors != [] &&
            "border-state-error-ink focus:border-state-error-ink focus:ring-state-error-ink"
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "mt-1.5 block w-full rounded-md border bg-surface px-3 py-2 text-sm text-ink placeholder:text-muted/60 focus:outline-none focus:ring-1",
          @errors == [] && "border-border focus:border-primary focus:ring-primary",
          @errors != [] &&
            "border-state-error-ink focus:border-state-error-ink focus:ring-state-error-ink"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-semibold leading-6 text-ink">
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-3 flex gap-3 text-sm leading-6 text-state-error-ink">
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", @class]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-ink">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-muted">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-y-auto px-4 sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-11 sm:w-full">
        <thead class="text-sm text-left leading-6 text-zinc-500">
          <tr>
            <th :for={col <- @col} class="p-0 pb-4 pr-6 font-normal">{col[:label]}</th>
            <th :if={@action != []} class="relative p-0 pb-4">
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="relative divide-y divide-zinc-100 border-t border-zinc-200 text-sm leading-6 text-zinc-700"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="group hover:bg-zinc-50">
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["relative p-0", @row_click && "hover:cursor-pointer"]}
            >
              <div class="block py-4 pr-6">
                <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-zinc-50 sm:rounded-l-xl" />
                <span class={["relative", i == 0 && "font-semibold text-zinc-900"]}>
                  {render_slot(col, @row_item.(row))}
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative w-14 p-0">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-medium">
                <span class="absolute -inset-y-px -right-4 left-0 group-hover:bg-zinc-50 sm:rounded-r-xl" />
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                >
                  {render_slot(action, @row_item.(row))}
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-zinc-100">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="w-1/4 flex-none text-zinc-500">{item.title}</dt>
          <dd class="text-zinc-700">{render_slot(item)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div class="mt-16">
      <.link
        navigate={@navigate}
        class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
      >
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" />
        {render_slot(@inner_block)}
      </.link>
    </div>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  The provenance badge — the one place color carries meaning on the page.

  Resolves a summary to one rung of the provenance ladder and renders it as
  icon + word + color (never color alone). A human `validated_at` stamp is the
  strongest trust signal and reads as verified; otherwise the summary's `status`
  drives it. A nil summary renders nothing (the caller shows a "por gerar" note).
  """
  attr :summary, :any, default: nil
  attr :class, :string, default: nil

  def provenance_badge(assigns) do
    assigns = assign(assigns, :state, provenance_state(assigns.summary))

    ~H"""
    <span
      :if={@state}
      title={provenance_title(@state)}
      class={[
        "inline-flex shrink-0 items-center gap-1 rounded-[3px] px-2 py-0.5 text-[0.6875rem] font-semibold uppercase tracking-[0.06em]",
        @state == :unreviewed && "bg-state-unreviewed-bg text-state-unreviewed-ink",
        @state == :community && "bg-state-community-bg text-state-community-ink",
        @state == :verified && "bg-state-verified-bg text-state-verified-ink",
        @class
      ]}
    >
      <.icon name={provenance_icon(@state)} class="size-3.5" />
      {provenance_label(@state)}
    </span>
    """
  end

  @doc "Resolve a summary to a provenance rung: `:unreviewed | :community | :verified | nil`."
  def provenance_state(nil), do: nil
  def provenance_state(%{validated_at: %DateTime{}}), do: :verified
  def provenance_state(%{status: :verified}), do: :verified
  def provenance_state(%{status: :community_reviewed}), do: :community
  def provenance_state(_summary), do: :unreviewed

  defp provenance_icon(:unreviewed), do: "hero-cpu-chip-micro"
  defp provenance_icon(:community), do: "hero-users-micro"
  defp provenance_icon(:verified), do: "hero-check-badge-micro"

  defp provenance_label(:unreviewed), do: "não revisto"
  defp provenance_label(:community), do: "comunidade"
  defp provenance_label(:verified), do: "verificado"

  defp provenance_title(:unreviewed),
    do: "Resumo gerado por modelo, ainda não revisto por uma pessoa."

  defp provenance_title(:community), do: "Revisto pela comunidade."
  defp provenance_title(:verified), do: "Verificado por um revisor."

  @doc """
  Theme-aware form field (the default `input` hardcodes bg-white/zinc, which
  breaks dark mode). Uses the app's semantic tokens. Pass `field` (a FormField)
  or an explicit `name`. For a select, set `type="select"` and provide options
  as the inner block of `<option>`s.
  """
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :name, :string, default: nil
  attr :id, :string, default: nil
  attr :value, :string, default: nil
  attr :hint, :string, default: nil
  attr :rest, :global, include: ~w(placeholder autocomplete rows)
  slot :inner_block

  def admin_field(assigns) do
    assigns =
      assigns
      |> assign(:name, assigns.name || (assigns.field && assigns.field.name))
      |> assign(:id, assigns.id || (assigns.field && assigns.field.id))
      |> assign(
        :resolved_value,
        if(is_nil(assigns.value) and assigns.field, do: assigns.field.value, else: assigns.value)
      )

    ~H"""
    <div>
      <label for={@id} class="block text-sm font-medium text-ink">{@label}</label>
      <p :if={@hint} class="text-xs text-muted">{@hint}</p>
      <select :if={@type == "select"} id={@id} name={@name} class={admin_input_class()} {@rest}>
        {render_slot(@inner_block)}
      </select>
      <textarea
        :if={@type == "textarea"}
        id={@id}
        name={@name}
        class={admin_input_class()}
        {@rest}
      >{@resolved_value}</textarea>
      <input
        :if={@type not in ["select", "textarea"]}
        type={@type}
        id={@id}
        name={@name}
        value={@resolved_value}
        class={admin_input_class()}
        {@rest}
      />
    </div>
    """
  end

  defp admin_input_class do
    "mt-1.5 block w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-ink " <>
      "placeholder:text-muted/60 focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
  end

  @pt_months ~w(janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro)

  @doc ~S(Portuguese long date, e.g. `~D[2026-06-27]` → "27 de junho de 2026".)
  def format_pt_date(%Date{} = d),
    do: "#{d.day} de #{Enum.at(@pt_months, d.month - 1)} de #{d.year}"

  @doc "A life-domain tag — quiet, neutral, never a status color."
  attr :label, :string, required: true
  attr :class, :string, default: nil

  def domain_tag(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-[3px] bg-surface-inset px-1.5 py-0.5 text-[0.6875rem] font-medium uppercase tracking-[0.04em] text-muted",
      @class
    ]}>
      {@label}
    </span>
    """
  end

  @doc """
  One act's entry in a list of acts (register front page, search results):
  title, provenance badge, summary, domain tags, source links. Shared so both
  places render the same card. A nil `summary` renders a quiet one-line brief
  instead (nothing to show yet).

  `date` (a `Date`) adds a dateline — search results aren't grouped under a date
  header the way the front-page feed is, so each result carries its own.
  """
  attr :act, :map, required: true
  attr :summary, :map, default: nil
  attr :date, :any, default: nil

  def act_entry(%{summary: nil} = assigns) do
    ~H"""
    <.link
      navigate={~p"/acts/#{@act.id}"}
      class="group flex items-baseline justify-between gap-4 py-3"
    >
      <span class="min-w-0 font-display text-[0.9375rem] text-ink group-hover:text-primary">
        {@act.title || @act.tipo}
      </span>
      <span class="shrink-0 text-[0.625rem] uppercase tracking-[0.09em] text-muted">
        por gerar
      </span>
    </.link>
    """
  end

  def act_entry(assigns) do
    ~H"""
    <article class="py-5">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <p class="text-[0.6875rem] font-semibold uppercase tracking-[0.09em] text-muted">
            {@act.emitter || @act.tipo}
          </p>
          <h3 class="mt-1.5 text-pretty font-display text-xl font-semibold leading-snug text-ink sm:text-[1.375rem]">
            <.link navigate={~p"/acts/#{@act.id}"} class="rounded-sm hover:text-primary">
              {@summary.headline || @act.title || @act.tipo}
            </.link>
          </h3>
          <p :if={@summary.headline} class="mt-1 text-xs text-muted">
            {@act.title || @act.tipo}
          </p>
        </div>
        <div class="mt-0.5 flex shrink-0 flex-col items-end gap-1">
          <.provenance_badge summary={@summary} />
        </div>
      </div>

      <p class="mt-2.5 max-w-reading text-pretty font-serif text-[1.0625rem] leading-relaxed text-ink">
        {@summary.plain_text}
      </p>

      <div class="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1.5">
        <time
          :if={@date}
          datetime={Date.to_iso8601(@date)}
          class="text-[0.6875rem] font-semibold uppercase tracking-[0.09em] text-muted"
        >
          {format_pt_date(@date)}
        </time>
        <div :if={@summary.domains != []} class="flex flex-wrap gap-1.5">
          <.domain_tag :for={d <- @summary.domains} label={to_string(d)} />
        </div>
        <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-[0.8125rem]">
          <a
            :if={@act.source_url}
            href={@act.source_url}
            target="_blank"
            rel="noopener"
            class="inline-flex items-center gap-1 text-muted hover:text-primary hover:underline"
          >
            <.icon name="hero-arrow-top-right-on-square-micro" class="size-3.5" /> fonte oficial
          </a>
          <a
            :if={@act.pdf_url}
            href={@act.pdf_url}
            target="_blank"
            rel="noopener"
            class="inline-flex items-center gap-1 text-muted hover:text-primary hover:underline"
          >
            <.icon name="hero-document-text-micro" class="size-3.5" /> PDF
          </a>
        </div>
      </div>
    </article>
    """
  end

  @doc """
  A broadsheet placeholder for pages still to be written (FAQ, About). Renders a
  headline, a standfirst teaching what's coming, a quiet "Em breve" mark, and a
  way back to the register.
  """
  attr :title, :string, required: true
  slot :inner_block, required: true

  def page_placeholder(assigns) do
    ~H"""
    <article class="mx-auto max-w-reading py-12 text-center sm:py-20">
      <h1 class="text-balance font-display text-[2rem] font-semibold leading-tight text-ink sm:text-[2.625rem]">
        {@title}
      </h1>
      <p class="mx-auto mt-5 max-w-reading text-pretty font-serif text-[1.0625rem] leading-relaxed text-ink">
        {render_slot(@inner_block)}
      </p>
      <p class="mt-7 inline-flex items-center gap-1.5 rounded-[3px] border border-border px-2.5 py-1 text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">
        Em breve
      </p>
      <div class="mt-9 border-t border-border pt-6">
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

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      time: 300,
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(OQueMudouWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(OQueMudouWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end

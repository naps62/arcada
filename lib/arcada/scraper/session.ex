defmodule Arcada.Scraper.Session do
  @moduledoc """
  A scrape session over the DRE `screenservices` endpoints. Owns the one bit of
  transport state that mutates mid-run — the self-healing `apiVersion` — so the
  rest of the pipeline never has to carry it.

  The session wraps a bootstrapped `Client` in an `Agent`. Each data-action goes
  through detect → heal → retry **once**:

    * a request runs against the current `apiVersion`;
    * if DRE reports the hash rotated (`hasApiVersionChanged`), we re-derive the
      fresh one via `ApiVersionResolver`, swap it into the held client, and retry;
    * the healed hash then sticks for every subsequent call this run.

  Because the healed version lives in the session process, callers get a stable
  interface and never see (or thread) the `apiVersion`:

      Session.list_editions(session, date) :: {:ok, raw} | {:error, reason}
      Session.act_detail(session, tipo, key) :: {:ok, enrichment} | {:error, reason}

  This is the single place "version rotated" is detected and healed — `Client`
  is now a dumb transport and `Parser` a pure mapper, so neither references the
  other and the old `Client` ↔ `ApiVersionResolver` cycle is broken.
  """

  require Logger

  alias Arcada.Scraper.{ApiVersionResolver, Client, Parser}

  @doc """
  Start a session, building/bootstrapping a `Client` from `opts`:

    * `:client` — a pre-built `Client` (tests inject a stubbed one); bootstrapped
      first if it hasn't been. When absent, one is built from config.

  Returns `{:ok, pid}` or `{:error, reason}` if bootstrap fails. Links to the
  caller — pair with `stop/1` (or let the caller's exit clean it up).
  """
  def start_link(opts \\ []) do
    with {:ok, client} <- build_client(opts) do
      Agent.start_link(fn -> client end)
    end
  end

  @doc "Stop the session process."
  def stop(session), do: Agent.stop(session)

  @doc "List the Série I edition(s) (with acts) published on `date`. Returns `{:ok, raw_json}`."
  def list_editions(session, %Date{} = date) do
    heal_and_retry(session, :list, &Client.list(&1, date))
  end

  @doc """
  Fetch an act's detail enrichment (`full_text`/`pdf_url`) by `tipo` + `key`.
  Returns `{:ok, enrichment}` or `{:error, reason}` (callers treat any error as
  "no enrichment" rather than failing the scrape).
  """
  def act_detail(session, tipo, key) do
    with {:ok, raw} <- heal_and_retry(session, :detail, &Client.detail(&1, tipo, key)) do
      Parser.parse_detail(raw)
    end
  end

  defp build_client(opts) do
    case Keyword.get(opts, :client) do
      nil -> Client.new() |> Client.bootstrap()
      %Client{module_version: nil} = c -> Client.bootstrap(c)
      %Client{} = c -> {:ok, c}
    end
  end

  # Run `req` against the held client; on a rotated apiVersion, heal that action's
  # hash once and retry. The healed client is written back into the session so the
  # fresh hash is reused for the rest of the run. HTTP runs in the caller (the
  # scrape is sequential — one caller per session — so the read/swap needn't be
  # atomic, and this keeps process-scoped test mocks working).
  defp heal_and_retry(session, key, req) do
    client = Agent.get(session, & &1)

    case req.(client) do
      {:ok, raw} ->
        {:ok, raw}

      {:rotated, raw} ->
        case heal(client, key) do
          {:ok, healed} ->
            Agent.update(session, fn _ -> healed end)
            retry(req, healed, raw)

          :error ->
            {:ok, raw}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Retry once against the healed client. A still-rotated body degrades to the
  # (empty-data) response — the caller's parser reads it as "nothing here".
  defp retry(req, healed, first_raw) do
    case req.(healed) do
      {:ok, raw} -> {:ok, raw}
      {:rotated, _raw} -> {:ok, first_raw}
      {:error, reason} -> {:error, reason}
    end
  end

  # Re-derive one action's live apiVersion. Returns `{:ok, client}` with the
  # fresh hash only if it actually differs from the current one (otherwise a
  # retry would fail identically), else `:error`.
  defp heal(client, key) do
    current = Client.api_version(client, key)

    case ApiVersionResolver.resolve(client, [key]) do
      {:ok, %{^key => fresh}} when is_binary(fresh) and fresh != current ->
        Logger.info("scraper: re-derived #{key} apiVersion #{current} -> #{fresh}")
        {:ok, Client.put_api_version(client, key, fresh)}

      other ->
        Logger.warning("scraper: could not re-derive #{key} apiVersion (#{inspect(other)})")
        :error
    end
  end
end

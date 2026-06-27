defmodule OQueMudou.Scraper.Parser do
  @moduledoc """
  Pure parsing/mapping helpers — turn raw DRE `screenservices` JSON into the
  attribute maps our `Register` schemas expect. No I/O, so this is the part we
  unit-test against captured fixtures (`test/support/fixtures`).

  Parsing is deliberately tolerant: DRE responses carry ~80 fields per act and
  the shape drifts on redeploys, so we read the handful we need and ignore the
  rest. See `docs/endpoints.md`.
  """

  @serie "I"

  @doc """
  Parse a `WB_Serie1_List` response into a list of edition maps, each with its
  `:acts` (the register skeleton). Accepts the decoded JSON (string keys).
  """
  def parse_editions(%{"data" => %{"DiarioByDiaList" => %{"List" => editions}}}) do
    Enum.map(editions, &parse_edition/1)
  end

  def parse_editions(_), do: []

  defp parse_edition(ed) do
    date = parse_date(ed["DataPublicacao"])
    year = if date, do: date.year, else: nil
    numero = to_string(ed["Numero"])

    %{
      serie: @serie,
      number: edition_number(numero, year),
      date: date,
      sumario_url: blank_to_nil(ed["LinkSitemap"]) |> absolutize(),
      acts: ed |> get_in(["DiplomaLegiList", "List"]) |> List.wrap() |> Enum.map(&parse_act/1)
    }
  end

  defp parse_act(act) do
    link = blank_to_nil(act["LinkSitemap"])

    %{
      dre_id: to_string(act["DbId"]),
      tipo: blank_to_nil(act["Tipo"]),
      emitter: blank_to_nil(act["Emissor"]),
      title: act["ConteudoTitle"] |> blank_to_nil() |> trim(),
      source_url: absolutize(link),
      published_at: parse_date(act["DataPublicacao"]),
      # filled in by the detail pass when available
      full_text: nil,
      pdf_url: nil
    }
  end

  @doc """
  Parse an act-detail (`GetAllConteudoDetalheData`) response into the
  enrichment attrs (`full_text`, `pdf_url`). Returns `{:ok, attrs}`, or
  `{:error, :api_version_changed}` / `{:error, :empty}` when DRE rotated the
  data-action version (the caller degrades gracefully).
  """
  def parse_detail(%{"versionInfo" => %{"hasApiVersionChanged" => true}}),
    do: {:error, :api_version_changed}

  def parse_detail(%{"data" => data}) when is_map(data) and map_size(data) > 0 do
    case find_detalhe(data) do
      nil ->
        {:error, :empty}

      d ->
        {:ok,
         %{
           full_text: blank_to_nil(d["TextoFormatado"]) || blank_to_nil(d["Texto"]),
           pdf_url: blank_to_nil(d["URL_PDF"])
         }}
    end
  end

  def parse_detail(_), do: {:error, :empty}

  # The detalhe object is whichever data var carries the full text / PDF.
  defp find_detalhe(data) do
    Enum.find_value(data, fn {_k, v} ->
      if is_map(v) and (Map.has_key?(v, "URL_PDF") or Map.has_key?(v, "Texto")), do: v
    end)
  end

  @doc """
  Split an act's `LinkSitemap` into the `{tipo_slug, key}` pair the detail
  data-action needs, e.g.
  `/dr/detalhe/decreto-presidente-republica/84-2026-1138160247` →
  `{"decreto-presidente-republica", "84-2026-1138160247"}`.
  """
  def split_link_sitemap(nil), do: :error

  def split_link_sitemap(link) when is_binary(link) do
    path = URI.parse(link).path || link

    case path |> String.trim_leading("/") |> String.split("/") do
      ["dr", "detalhe", tipo, key] -> {:ok, tipo, key}
      _ -> :error
    end
  end

  @doc "Extract the OutSystems CSRF token from a decoded `nr2Users` cookie value (`crf=...;uid=...`)."
  def parse_crf(nil), do: nil

  def parse_crf(nr2users) when is_binary(nr2users) do
    nr2users
    |> URI.decode()
    |> String.split(";")
    |> Enum.find_value(fn part ->
      case String.split(part, "=", parts: 2) do
        ["crf", v] -> v
        _ -> nil
      end
    end)
  end

  # Editions are identified as e.g. "120/2026".
  defp edition_number(numero, nil), do: numero
  defp edition_number(numero, year), do: "#{numero}/#{year}"

  defp parse_date(nil), do: nil

  defp parse_date(str) when is_binary(str) do
    case str |> String.slice(0, 10) |> Date.from_iso8601() do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp absolutize(nil), do: nil
  defp absolutize("http" <> _ = url), do: url
  defp absolutize("/" <> _ = path), do: "https://diariodarepublica.pt" <> path
  defp absolutize(other), do: other

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v) when is_binary(v), do: v
  defp blank_to_nil(v), do: to_string(v)

  defp trim(nil), do: nil
  defp trim(s), do: String.trim(s)
end

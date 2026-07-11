defmodule Arcada.OgImage do
  @moduledoc """
  Per-act social share cards (1200×630 PNG) — the act's plain-language headline
  baked into the image, so X/Twitter (which renders the image alone, dropping
  title/description on `summary_large_image`) still shows what the act is.

  A card is built as an SVG in the site's type + palette, then rasterised with
  `rsvg-convert` (librsvg). Fonts ship in `priv/render_fonts` and are installed
  into the container's fontconfig (see Dockerfile). Cards aren't cached in the
  app: og:image is fetched by link scrapers, not on normal pageviews, so HTTP +
  edge caching (long `Cache-Control` + Cloudflare) covers the volume.

  Falls back to the static default card when an act has no summary yet.
  """

  alias Arcada.Register
  alias Arcada.Register.{Act, Summary}

  @width 1200
  @height 630

  # Palette (sRGB from the app's oklch tokens) — keep in sync with
  # priv/static/images/og-default.svg.
  @bg "#F6F3ED"
  @ink "#211C17"
  @muted "#5B544D"
  @accent "#FD4F00"

  @months ~w(janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro)

  @doc "PNG bytes of `act`'s share card. Uses the act's canonical summary."
  @spec png(Act.t()) :: {:ok, binary} | {:error, term}
  def png(%Act{} = act), do: act |> svg(Register.published_summary(act)) |> rasterize()

  @doc "The card SVG for `act` + `summary` (`summary` may be nil)."
  def svg(%Act{} = act, summary) do
    {font, lines} = layout(headline_text(act, summary))
    leading = round(font * 1.06)
    # Vertically centre the headline block in a fixed band (200..545) below the
    # masthead + tipo chip, above the footer rule.
    block_h = length(lines) * leading
    block_top = 200 + max(0, div(345 - block_h, 2))
    first_baseline = block_top + font

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@width}" height="#{@height}" viewBox="0 0 #{@width} #{@height}">
      <rect width="#{@width}" height="#{@height}" fill="#{@bg}"/>
      <rect x="0" y="0" width="#{@width}" height="10" fill="#{@ink}"/>
      <g transform="translate(80,70)">
        <g transform="scale(2.15)">
          <path fill="#{@accent}" fill-rule="evenodd" d="M6 27V13a10 10 0 0 1 20 0v14h-5V14a5 5 0 0 0-10 0v13H6Z"/>
          <rect x="4" y="27" width="24" height="2.5" rx="1.25" fill="#{@accent}"/>
        </g>
        <text x="92" y="52" font-family="Fraunces-600" font-size="52" fill="#{@ink}" letter-spacing="-0.5">Arcada</text>
      </g>
      #{tipo_chip(act)}
      <text font-family="Fraunces-600" font-size="#{font}" fill="#{@ink}" letter-spacing="-1.5">
        #{headline_tspans(lines, first_baseline, leading)}
      </text>
      <rect x="80" y="578" width="1040" height="3" fill="#{@accent}"/>
      <text x="80" y="614" font-family="Inter-600" font-size="27" fill="#{@ink}">arcada.naps.pt</text>
      #{date_text(act)}
    </svg>
    """
  end

  # --- content ---------------------------------------------------------------

  defp headline_text(act, summary) do
    (summary && Summary.strip_terms(summary.headline)) || act.title || act.tipo || "Ato"
  end

  # Pick the largest type tier whose greedy word-wrap fits its line budget, so
  # the wrap width and the render size always agree. Longest headlines fall
  # through to the smallest size, hard-capped at 4 lines with an ellipsis.
  # Char-width is estimated (Fraunces is proportional); ~0.53·font-size per
  # glyph is a safe average for the 1040px content width.
  defp layout(text) do
    Enum.find_value([{96, 2}, {80, 3}, {66, 4}], fn {size, budget} ->
      lines = wrap(text, max_chars(size))
      if length(lines) <= budget, do: {size, lines}
    end) || {66, text |> wrap(max_chars(66)) |> cap_lines(4)}
  end

  defp max_chars(size), do: max(8, trunc(1040 / (0.53 * size)))

  defp wrap(text, max_chars) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reduce([], fn word, acc ->
      case acc do
        [] ->
          [word]

        [cur | rest] ->
          cand = cur <> " " <> word

          if String.length(cand) > max_chars,
            do: [word, cur | rest],
            else: [cand | rest]
      end
    end)
    |> Enum.reverse()
  end

  defp cap_lines(lines, max) when length(lines) <= max, do: lines

  defp cap_lines(lines, max) do
    kept = Enum.take(lines, max)
    List.update_at(kept, max - 1, &(String.trim_trailing(&1) <> "…"))
  end

  defp headline_tspans(lines, first_baseline, leading) do
    lines
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {line, i} ->
      y = first_baseline + i * leading
      ~s(<tspan x="80" y="#{y}">#{esc(line)}</tspan>)
    end)
  end

  # Fixed position just under the masthead — independent of headline length.
  defp tipo_chip(%Act{tipo: tipo}) when is_binary(tipo) and tipo != "" do
    ~s(<text x="82" y="158" font-family="Inter-600" font-size="26" fill="#{@accent}" letter-spacing="2">#{esc(String.upcase(tipo))}</text>)
  end

  defp tipo_chip(_act), do: ""

  defp date_text(%Act{published_at: %Date{} = d}) do
    label = "#{d.day} #{Enum.at(@months, d.month - 1)} #{d.year}"

    ~s(<text x="1120" y="614" text-anchor="end" font-family="Newsreader-420" font-size="24" fill="#{@muted}">#{esc(label)}</text>)
  end

  defp date_text(_act), do: ""

  defp esc(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  # --- rasterise -------------------------------------------------------------

  defp rasterize(svg) do
    base = Path.join(System.tmp_dir!(), "og-#{:erlang.unique_integer([:positive])}")
    svg_path = base <> ".svg"
    png_path = base <> ".png"
    File.write!(svg_path, svg)

    try do
      args = [
        "--width",
        "#{@width}",
        "--height",
        "#{@height}",
        "--format",
        "png",
        "--output",
        png_path,
        svg_path
      ]

      case System.cmd(rsvg_bin(), args, stderr_to_stdout: true) do
        {_, 0} -> {:ok, File.read!(png_path)}
        {out, code} -> {:error, {:rsvg_convert, code, out}}
      end
    rescue
      e in ErlangError -> {:error, e}
    after
      File.rm(svg_path)
      File.rm(png_path)
    end
  end

  defp rsvg_bin, do: System.get_env("RSVG_CONVERT") || "rsvg-convert"
end

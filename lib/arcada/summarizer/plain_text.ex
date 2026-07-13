defmodule Arcada.Summarizer.PlainText do
  @moduledoc """
  Turn a Diário da República act's stored `full_text` — scraped as raw HTML
  (`TextoFormatado`: `<p class=...>`, `<a href=...>`, `<br>`) — into clean text
  before it reaches the summarizer pipeline.

  The HTML hurts every downstream step (issue #87):

    * the section splitter (`Arcada.Summarizer.Sections`) keys headings off line
      starts (`^Artigo 5.º`), but in the HTML every `Artigo` sits mid-line inside
      a `<p>` tag, so heading segmentation never fires and the act falls back to
      blind fixed-size chunks;
    * the embeddings ranker (bge-m3) scores markup alongside prose, flattening
      the relevance signal;
    * the LLM prompt carries tags it has to see past.

  `from_html/1` strips the tags but first converts block-level boundaries
  (`</p>`, `<br>`, `</div>`, `</li>`, `</h1-6>`, …) to newlines so headings land
  at line start and `Sections` can segment on the *articulado* again. HTML
  entities are decoded (`&ordm;` → `º`, `&nbsp;` → space) by `strip_tags/1`.

  Best-effort and idempotent on plain text: input with no tags is returned
  unchanged (bar whitespace normalization), so already-clean acts are untouched.
  """

  # Closing/void block-level tags that mark a line break in the rendered act.
  # Replaced with "\n" before tag stripping so the text keeps its paragraph and
  # heading structure (glued-together text otherwise: "Artigo 5.ºO acesso…").
  @block_break ~r/<\s*(?:br\s*\/?|\/\s*(?:p|div|li|tr|h[1-6]|section|article|blockquote))\s*>/i

  # Any tag at all — cheap check to skip plain-text acts entirely.
  @has_tag ~r/<\/?[a-zA-Z][^>]*>/

  @doc """
  Clean an act's `full_text` for summarization. Returns plain text with paragraph
  breaks preserved. Non-binaries and tag-free strings pass through (the latter
  only whitespace-normalized).
  """
  def from_html(text) when is_binary(text) do
    if Regex.match?(@has_tag, text) do
      text
      |> String.replace(@block_break, "\n")
      |> HtmlSanitizeEx.strip_tags()
      |> normalize_whitespace()
    else
      normalize_whitespace(text)
    end
  end

  def from_html(other), do: other

  # Collapse runs of horizontal whitespace (incl. the `&nbsp;` U+00A0 that DRE
  # markup is littered with), strip trailing space per line, and cap blank runs
  # at one empty line (a paragraph break) so `Sections` sees clean chunks.
  defp normalize_whitespace(text) do
    text
    |> String.replace(~r/[ \t\x{00A0}]+/u, " ")
    |> String.replace(~r/ *\n/, "\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end
end

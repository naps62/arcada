defmodule Arcada.Summarizer.Sections do
  @moduledoc """
  Split a Diário da República act into sections so the summarizer can rank the
  change-bearing parts of an oversized act instead of blindly truncating its
  opening.

  Two strategies, tried in order:

    1. **Headings.** Diplomas (leis, decretos-leis, portarias) follow a
       predictable shape: an opening *preâmbulo*, the *articulado* (`Artigo 1.º`,
       `Artigo 2.º`, …), and trailing *anexos*. We segment on those headings —
       each starts a section carrying its heading line plus the body up to the
       next heading; text before the first heading is the `:preamble` section.

    2. **Paragraph chunks (fallback).** Acts without those headings — acórdãos,
       avisos, declarações — would otherwise be one big section (ranking can't
       help, so it head-truncates). When heading splitting yields fewer than two
       sections we instead break the text into paragraph-sized chunks (merging
       small paragraphs, windowing huge ones) so the ranker still has something
       to choose from. The court ruling's *Decisão* can then outrank pages of
       recitals.

  Best-effort: a short or empty input simply yields one (or zero) sections.
  """

  @typedoc "A slice of an act, in document order."
  @type section :: %{label: String.t() | :preamble, text: String.t()}

  # A line that *starts* a heading-based section. Anchored to line start; requires
  # a number or roman numeral after the keyword so prose like "no artigo anterior"
  # isn't mistaken for a heading. Case-insensitive + unicode.
  @heading_re ~r/^\s*(?:ANEXO\b|AP[ÊE]NDICE\b|CAP[ÍI]TULO\s+[IVXLCDM]+|SEC[ÇC][ÃA]O\s+[IVXLCDM]+|SUBSEC[ÇC][ÃA]O\s+[IVXLCDM]+|Artigo\s+(?:\d+|[ÚU]nico))/iu

  # Target size for fallback chunks (characters). ~500 tokens — small enough to
  # rank meaningfully, large enough to keep an 80k+ act to a few dozen chunks.
  @chunk_chars 2_000

  @doc """
  Split `text` into ordered sections. Empty (whitespace-only) sections are
  dropped. Returns `[%{label: ..., text: ...}]` — uses heading segmentation when
  the act has ≥2 recognizable headings, else paragraph-chunk fallback.
  """
  @spec split(binary) :: [section]
  def split(text) when is_binary(text) do
    case heading_split(text) do
      [_, _ | _] = sections -> sections
      _ -> paragraph_chunks(text)
    end
  end

  def split(_), do: []

  ## Strategy 1 — headings

  defp heading_split(text) do
    text
    |> String.split("\n")
    |> Enum.reduce({[], nil}, &fold_line/2)
    |> close()
    |> Enum.reverse()
    |> Enum.map(&finish_section/1)
    |> Enum.reject(&(String.trim(&1.text) == ""))
  end

  defp fold_line(line, {done, current}) do
    cond do
      heading?(line) ->
        {push(done, current), %{label: String.trim(line), lines: [line]}}

      is_nil(current) ->
        # Content before the first heading → the preâmbulo.
        {done, %{label: :preamble, lines: [line]}}

      true ->
        {done, %{current | lines: [line | current.lines]}}
    end
  end

  defp close({done, current}), do: push(done, current)

  defp push(done, nil), do: done
  defp push(done, section), do: [section | done]

  defp finish_section(%{label: label, lines: lines}) do
    %{label: label, text: lines |> Enum.reverse() |> Enum.join("\n")}
  end

  defp heading?(line), do: Regex.match?(@heading_re, line)

  ## Strategy 2 — paragraph chunks

  defp paragraph_chunks(text) do
    text
    |> String.split(~r/\n[ \t]*\n/, trim: true)
    |> Enum.flat_map(&window/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> merge_to_chunks()
    |> Enum.with_index(1)
    |> Enum.map(fn {text, i} -> %{label: "trecho #{i}", text: text} end)
  end

  # Break a paragraph that's much larger than the target into fixed windows, so
  # an act that's one giant blob (no paragraph breaks) still yields many chunks.
  defp window(paragraph) do
    if String.length(paragraph) > @chunk_chars * 2 do
      paragraph
      |> String.graphemes()
      |> Enum.chunk_every(@chunk_chars)
      |> Enum.map(&Enum.join/1)
    else
      [paragraph]
    end
  end

  # Greedily concatenate consecutive parts until each chunk reaches the target,
  # so a run of short paragraphs doesn't explode into hundreds of tiny sections.
  defp merge_to_chunks(parts) do
    {chunks, current} =
      Enum.reduce(parts, {[], ""}, fn part, {chunks, current} ->
        candidate = if current == "", do: part, else: current <> "\n\n" <> part

        if String.length(candidate) >= @chunk_chars,
          do: {[candidate | chunks], ""},
          else: {chunks, candidate}
      end)

    chunks = if current == "", do: chunks, else: [current | chunks]
    Enum.reverse(chunks)
  end
end

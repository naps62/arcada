defmodule OQueMudou.Summarizer.Sections do
  @moduledoc """
  Split a Diário da República diploma into structural sections so the summarizer
  can pick the change-bearing parts of an oversized act instead of blindly
  truncating its opening.

  Diplomas follow a predictable shape: an opening *preâmbulo*, the *articulado*
  (`Artigo 1.º`, `Artigo 2.º`, …), and trailing *anexos* (often huge tables).
  We segment on those headings — each heading starts a new section that carries
  the heading line plus the body up to the next heading. Text before the first
  heading becomes the `:preamble` section.

  Best-effort by design: an act with no recognizable headings yields a single
  section (the whole text), and the caller falls back to head-truncation.
  """

  @typedoc "A structural slice of a diploma, in document order."
  @type section :: %{label: String.t() | :preamble, text: String.t()}

  # A line that *starts* a new section. Anchored to line start; requires a number
  # or roman numeral after the structural keyword so prose like "no artigo
  # anterior" isn't mistaken for a heading. Case-insensitive + unicode.
  @heading_re ~r/^\s*(?:ANEXO\b|AP[ÊE]NDICE\b|CAP[ÍI]TULO\s+[IVXLCDM]+|SEC[ÇC][ÃA]O\s+[IVXLCDM]+|SUBSEC[ÇC][ÃA]O\s+[IVXLCDM]+|Artigo\s+(?:\d+|[ÚU]nico))/iu

  @doc """
  Split `text` into ordered sections. Empty (whitespace-only) sections are
  dropped. Returns `[%{label: ..., text: ...}]` — at least one section for any
  non-empty input.
  """
  @spec split(binary) :: [section]
  def split(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.reduce({[], nil}, &fold_line/2)
    |> close()
    |> Enum.reverse()
    |> Enum.map(&finish_section/1)
    |> Enum.reject(&(String.trim(&1.text) == ""))
  end

  def split(_), do: []

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
end

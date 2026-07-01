defmodule OQueMudou.Register.Embedding do
  @moduledoc """
  Ecto type for a summary's embedding vector.

  Stored as packed `bytea` (little-endian float32s — 1024 dims ≈ 4KB/row for
  bge-m3), cast/loaded as a plain list of floats so callers (`Summarizer`,
  `Search`) never touch the binary packing. See issue #27; no pgvector.
  """
  use Ecto.Type

  @impl true
  def type, do: :binary

  @impl true
  def cast(list) when is_list(list), do: {:ok, list}
  def cast(_other), do: :error

  @impl true
  def dump(list) when is_list(list) do
    {:ok, for(f <- list, into: <<>>, do: <<f::float-32-little>>)}
  end

  def dump(_other), do: :error

  @impl true
  def load(bin) when is_binary(bin) do
    {:ok, for(<<f::float-32-little <- bin>>, do: f)}
  end
end

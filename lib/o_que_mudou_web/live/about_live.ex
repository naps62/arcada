defmodule OQueMudouWeb.AboutLive do
  @moduledoc """
  Sobre — placeholder. Explains the project's purpose and provenance model once
  written; for now it teaches what the page will hold and links home.
  """
  use OQueMudouWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Sobre")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_placeholder title="Sobre o projecto">
      Em breve, a história por trás do registo: porque transformamos o
      <em>Diário da República, Série I</em>
      em linguagem simples, como funciona a
      escada de proveniência e quem está por detrás disto. Um sinal de confiança
      pública — nunca uma autoridade.
    </.page_placeholder>
    """
  end
end

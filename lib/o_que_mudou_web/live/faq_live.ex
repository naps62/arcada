defmodule OQueMudouWeb.FaqLive do
  @moduledoc """
  Perguntas frequentes — placeholder. Content lands once the public build is
  ready; for now it teaches what the page will hold and links home.
  """
  use OQueMudouWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Perguntas frequentes")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_placeholder title="Perguntas frequentes">
      Estamos a preparar respostas claras às dúvidas mais comuns: como lemos o <em>Diário da República</em>, o que significam os selos de proveniência
      (🤖 não revisto, 👥 comunidade, ✓ verificado) e por que razão isto nunca
      substitui aconselhamento jurídico.
    </.page_placeholder>
    """
  end
end

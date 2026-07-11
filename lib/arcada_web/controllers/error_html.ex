defmodule ArcadaWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use ArcadaWeb, :html

  # 404 is a real branded, noindexed page (error pages render layout: false, so
  # the template is a self-contained document). Every other status falls through
  # to the plain-text status message below.
  embed_templates "error_html/*"

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

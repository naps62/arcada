defmodule OQueMudou.Register.ActAdmin do
  @moduledoc """
  Kaffy resource-admin for `OQueMudou.Register.Act`.

  Schemas are otherwise auto-discovered (no `resources` config), but Kaffy still
  picks up a `<Schema>Admin` module by naming convention and merges its
  callbacks. This one exists solely to host the sidebar back-link into the app's
  admin console — Kaffy's own chrome only links to its own dashboard.

  `collect_links/2` concatenates `custom_links/1` across *all* resource admins,
  so the back-link must live on exactly one module (this one) to avoid
  duplicates.
  """

  def custom_links(_schema) do
    [
      %{
        name: "← Admin console",
        url: "/admin",
        location: :top,
        icon: "arrow-left",
        target: "_self",
        order: 0
      }
    ]
  end
end

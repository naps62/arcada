defmodule OQueMudouWeb.KaffyTheme do
  @moduledoc """
  Kaffy extension that restyles the raw-DB admin (`/admin/db`) to match our
  admin palette and to run at a much denser layout than stock Kaffy.

  Kaffy ships a Bootstrap-flavoured "Star Admin" template with a foreign blue
  palette and generous whitespace. This module injects an override stylesheet at
  the end of `<head>` (via the `stylesheets/1` extension hook, wired up in
  `config/config.exs`), so our rules always win on cascade order.

  The Kaffy page is served standalone — it does not load the app's `app.css` —
  so the design tokens are inlined here rather than referenced from `:root`.
  Kaffy's `<html>` carries no `data-theme` attribute (that is set by the app's
  pre-paint JS), so dark mode follows the OS via `prefers-color-scheme` only.
  Values mirror the light/dark tokens in `assets/css/app.css`; keep them in sync.

  CSS-first and upgrade-safe: no template overrides, only class-name overrides
  against Star Admin's Bootstrap markup.
  """

  @doc "Injected after Kaffy's own stylesheets so these overrides win."
  def stylesheets(_conn) do
    [{:safe, ~s(<style id="oqm-kaffy-theme">#{css()}</style>)}]
  end

  defp css do
    """
    :root {
      /* Newsprint — mirrors the light tokens in assets/css/app.css. */
      --oqm-bg: oklch(0.965 0.008 85);
      --oqm-surface: oklch(0.945 0.01 85);
      --oqm-surface-inset: oklch(0.925 0.011 85);
      --oqm-ink: oklch(0.23 0.012 60);
      --oqm-muted: oklch(0.45 0.014 65);
      --oqm-border: oklch(0.84 0.012 80);
      --oqm-primary: oklch(0.46 0.12 255);
      --oqm-primary-hover: oklch(0.4 0.12 255);
      --oqm-on-primary: oklch(0.97 0.008 85);
      --oqm-ok-bg: oklch(0.93 0.05 150);
      --oqm-ok-ink: oklch(0.35 0.10 150);
      --oqm-warn-bg: oklch(0.93 0.06 80);
      --oqm-warn-ink: oklch(0.42 0.11 60);
      --oqm-err-bg: oklch(0.93 0.05 27);
      --oqm-err-ink: oklch(0.47 0.16 27);

      /* Coupled dimensions — Star Admin hard-codes 4.375rem / 16.25rem across
         several calc()s; drive them from one place so they stay consistent. */
      --oqm-navbar-h: 3rem;
      --oqm-sidebar-w: 13.5rem;
    }

    @media (prefers-color-scheme: dark) {
      :root {
        /* Evening edition — mirrors the dark tokens in assets/css/app.css. */
        --oqm-bg: oklch(0.18 0.006 70);
        --oqm-surface: oklch(0.22 0.008 70);
        --oqm-surface-inset: oklch(0.25 0.009 70);
        --oqm-ink: oklch(0.92 0.01 85);
        --oqm-muted: oklch(0.68 0.012 80);
        --oqm-border: oklch(0.32 0.01 75);
        --oqm-primary: oklch(0.74 0.11 250);
        --oqm-primary-hover: oklch(0.82 0.1 250);
        --oqm-on-primary: oklch(0.18 0.006 70);
        --oqm-ok-bg: oklch(0.32 0.05 152 / 0.55);
        --oqm-ok-ink: oklch(0.83 0.1 155);
        --oqm-warn-bg: oklch(0.32 0.05 70 / 0.6);
        --oqm-warn-ink: oklch(0.85 0.1 80);
        --oqm-err-bg: oklch(0.33 0.07 27 / 0.6);
        --oqm-err-ink: oklch(0.81 0.13 27);
      }
    }

    /* ── Palette: page shell ─────────────────────────────────────────────── */
    body,
    .content-wrapper,
    .container-scroller,
    .main-panel {
      background: var(--oqm-bg) !important;
      color: var(--oqm-ink) !important;
    }
    body {
      font-family: "Inter", ui-sans-serif, system-ui, sans-serif !important;
      font-size: 0.85rem !important;
      line-height: 1.4 !important;
    }
    a { color: var(--oqm-primary); }
    a:hover, a:focus { color: var(--oqm-primary-hover); }

    /* ── Navbar (top bar) ────────────────────────────────────────────────── */
    .navbar,
    .navbar .navbar-menu-wrapper {
      height: var(--oqm-navbar-h) !important;
      min-height: var(--oqm-navbar-h) !important;
      background: var(--oqm-surface) !important;
      color: var(--oqm-ink) !important;
      box-shadow: none !important;
      border-bottom: 1px solid var(--oqm-border) !important;
    }
    .navbar .navbar-menu-wrapper {
      padding-left: 1rem !important;
      padding-right: 1rem !important;
    }
    .navbar .navbar-brand-wrapper {
      height: var(--oqm-navbar-h) !important;
      width: var(--oqm-sidebar-w) !important;
      background: var(--oqm-surface) !important;
      border-bottom: 1px solid var(--oqm-border) !important;
    }
    .navbar .navbar-brand-wrapper .navbar-brand img { max-height: 1.85rem !important; }
    .navbar .navbar-toggler .fa-bars,
    .navbar .navbar-menu-wrapper { color: var(--oqm-ink) !important; }
    /* Push content below the now-shorter fixed navbar. */
    .navbar.fixed-top + .page-body-wrapper { padding-top: var(--oqm-navbar-h) !important; }

    /* ── Sidebar ─────────────────────────────────────────────────────────── */
    .sidebar {
      width: var(--oqm-sidebar-w) !important;
      min-height: calc(100vh - var(--oqm-navbar-h)) !important;
      background: var(--oqm-surface) !important;
      border-right: 1px solid var(--oqm-border) !important;
    }
    .main-panel { width: calc(100% - var(--oqm-sidebar-w)) !important; }

    .sidebar .nav .nav-item .nav-link,
    .sidebar .nav .nav-item .nav-link i.menu-icon,
    .sidebar .nav .nav-item .nav-link i.menu-arrow {
      color: var(--oqm-muted) !important;
    }
    .sidebar .nav .nav-item .nav-link {
      padding: 0.4rem 1.25rem !important;
      font-size: 0.82rem !important;
    }
    .sidebar .nav .nav-item .nav-link .menu-title { font-size: 0.82rem !important; }
    .sidebar .nav .nav-item:hover > .nav-link,
    .sidebar .nav .nav-item:hover > .nav-link i {
      color: var(--oqm-ink) !important;
      background: var(--oqm-surface-inset) !important;
    }
    .sidebar .nav .nav-item.active > .nav-link,
    .sidebar .nav .nav-item.active > .nav-link i,
    .sidebar .nav .nav-item .nav-link.active {
      color: var(--oqm-primary) !important;
      font-weight: 600 !important;
    }
    .sidebar .nav.sub-menu .nav-item .nav-link {
      padding: 0.3rem 1.25rem 0.3rem 2.25rem !important;
      font-size: 0.8rem !important;
    }

    /* ── Cards ───────────────────────────────────────────────────────────── */
    .card {
      background: var(--oqm-surface) !important;
      border: 1px solid var(--oqm-border) !important;
      border-radius: 4px !important;
      box-shadow: none !important;
      margin-bottom: 0.75rem !important;
    }
    .card-body { padding: 0.85rem 1rem !important; }
    .card-title { font-size: 0.95rem !important; margin-bottom: 0.6rem !important; }

    /* ── Content headers / breadcrumb ────────────────────────────────────── */
    .content-wrapper { padding: 1rem 1.25rem !important; }
    .page-header { margin: 0 0 0.75rem 0 !important; }
    .page-title { font-size: 1.1rem !important; }
    .breadcrumb {
      background: transparent !important;
      padding: 0.25rem 0 !important;
      margin-bottom: 0.5rem !important;
      font-size: 0.8rem !important;
    }

    /* ── Tables ──────────────────────────────────────────────────────────── */
    .table { color: var(--oqm-ink) !important; margin-bottom: 0.5rem !important; }
    .table th,
    .table td {
      padding: 0.35rem 0.6rem !important;
      border-top: 1px solid var(--oqm-border) !important;
      vertical-align: middle !important;
    }
    .table thead th {
      color: var(--oqm-muted) !important;
      border-bottom: 2px solid var(--oqm-border) !important;
      font-size: 0.75rem !important;
      text-transform: uppercase !important;
      letter-spacing: 0.03em !important;
    }
    .table-hover tbody tr:hover { background: var(--oqm-surface-inset) !important; }
    .table a { color: var(--oqm-primary) !important; }

    /* ── Forms ───────────────────────────────────────────────────────────── */
    .form-control,
    .form-control:focus,
    select.form-control,
    textarea.form-control {
      height: auto !important;
      min-height: 2.1rem !important;
      padding: 0.35rem 0.6rem !important;
      font-size: 0.83rem !important;
      color: var(--oqm-ink) !important;
      background: var(--oqm-bg) !important;
      border: 1px solid var(--oqm-border) !important;
      border-radius: 4px !important;
    }
    textarea.form-control { min-height: 4rem !important; }
    .form-control:focus { border-color: var(--oqm-primary) !important; box-shadow: none !important; }
    .form-group { margin-bottom: 0.6rem !important; }
    label { margin-bottom: 0.25rem !important; color: var(--oqm-muted) !important; font-size: 0.8rem !important; }

    /* ── Buttons ─────────────────────────────────────────────────────────── */
    .btn {
      padding: 0.35rem 0.75rem !important;
      font-size: 0.82rem !important;
      border-radius: 4px !important;
    }
    .btn-primary,
    .btn-success,
    .btn-info {
      background: var(--oqm-primary) !important;
      border-color: var(--oqm-primary) !important;
      color: var(--oqm-on-primary) !important;
    }
    .btn-primary:hover,
    .btn-success:hover,
    .btn-info:hover {
      background: var(--oqm-primary-hover) !important;
      border-color: var(--oqm-primary-hover) !important;
    }
    .btn-secondary,
    .btn-light,
    .btn-outline-secondary {
      background: var(--oqm-surface-inset) !important;
      border-color: var(--oqm-border) !important;
      color: var(--oqm-ink) !important;
    }

    /* ── Alerts ──────────────────────────────────────────────────────────── */
    .alert {
      padding: 0.5rem 0.75rem !important;
      margin-bottom: 0.6rem !important;
      border: 1px solid transparent !important;
      border-radius: 4px !important;
      font-size: 0.83rem !important;
    }
    .alert-success { background: var(--oqm-ok-bg) !important; color: var(--oqm-ok-ink) !important; }
    .alert-info { background: var(--oqm-surface-inset) !important; color: var(--oqm-ink) !important; }
    .alert-warning { background: var(--oqm-warn-bg) !important; color: var(--oqm-warn-ink) !important; }
    .alert-danger { background: var(--oqm-err-bg) !important; color: var(--oqm-err-ink) !important; }

    /* ── Misc chrome ─────────────────────────────────────────────────────── */
    .footer {
      background: var(--oqm-surface) !important;
      color: var(--oqm-muted) !important;
      border-top: 1px solid var(--oqm-border) !important;
      padding: 0.4rem 1.25rem !important;
      font-size: 0.78rem !important;
    }
    .pagination .page-link {
      color: var(--oqm-primary) !important;
      background: var(--oqm-surface) !important;
      border-color: var(--oqm-border) !important;
      padding: 0.25rem 0.6rem !important;
    }
    .pagination .page-item.active .page-link {
      background: var(--oqm-primary) !important;
      border-color: var(--oqm-primary) !important;
      color: var(--oqm-on-primary) !important;
    }

    /* ── Stray Bootstrap blues → our primary ─────────────────────────────── */
    .text-primary { color: var(--oqm-primary) !important; }
    .navbar-brand,
    .navbar-brand:hover,
    .navbar-brand:focus { color: var(--oqm-ink) !important; }
    .breadcrumb-item a { color: var(--oqm-primary) !important; }
    .breadcrumb-item.active,
    .breadcrumb-item + .breadcrumb-item::before { color: var(--oqm-muted) !important; }

    .btn-outline-primary {
      color: var(--oqm-primary) !important;
      border-color: var(--oqm-primary) !important;
      background: transparent !important;
    }
    .btn-outline-primary:hover,
    .btn-outline-primary:focus {
      color: var(--oqm-on-primary) !important;
      background: var(--oqm-primary) !important;
    }
    .btn-link { color: var(--oqm-primary) !important; }
    .btn-link:hover { color: var(--oqm-primary-hover) !important; }
    .btn-danger {
      background: var(--oqm-err-ink) !important;
      border-color: var(--oqm-err-ink) !important;
      color: var(--oqm-bg) !important;
    }

    /* Checkbox / radio checked state (Star Admin uses #007bff). */
    .custom-control-input:checked ~ .custom-control-label::before {
      background: var(--oqm-primary) !important;
      border-color: var(--oqm-primary) !important;
    }
    .custom-control-label::before { border-color: var(--oqm-border) !important; }

    /* ── Stray white / near-white surfaces → our surfaces ────────────────── */
    .bg-light { background: var(--oqm-surface) !important; }
    .card-header {
      background: var(--oqm-surface-inset) !important;
      border-bottom: 1px solid var(--oqm-border) !important;
      color: var(--oqm-ink) !important;
      padding: 0.5rem 1rem !important;
    }
    .table-striped tbody tr:nth-of-type(odd),
    .table-striped tbody tr:nth-of-type(odd) > td,
    .table-striped tbody tr:nth-of-type(odd) > th {
      background: var(--oqm-surface-inset) !important;
    }
    .custom-select {
      background-color: var(--oqm-bg) !important;
      color: var(--oqm-ink) !important;
      border: 1px solid var(--oqm-border) !important;
      height: auto !important;
      min-height: 2.1rem !important;
      padding: 0.35rem 1.75rem 0.35rem 0.6rem !important;
      font-size: 0.83rem !important;
    }
    .input-group-text {
      background: var(--oqm-surface-inset) !important;
      color: var(--oqm-muted) !important;
      border: 1px solid var(--oqm-border) !important;
      padding: 0.35rem 0.6rem !important;
    }
    .dropdown-menu {
      background: var(--oqm-surface) !important;
      border: 1px solid var(--oqm-border) !important;
    }
    .dropdown-item { color: var(--oqm-ink) !important; }
    .dropdown-item:hover,
    .dropdown-item:focus {
      background: var(--oqm-surface-inset) !important;
      color: var(--oqm-ink) !important;
    }
    .modal-content {
      background: var(--oqm-surface) !important;
      border: 1px solid var(--oqm-border) !important;
      color: var(--oqm-ink) !important;
    }
    .modal-header,
    .modal-footer { border-color: var(--oqm-border) !important; }

    /* ── Badges ──────────────────────────────────────────────────────────── */
    .badge-secondary {
      background: var(--oqm-surface-inset) !important;
      color: var(--oqm-ink) !important;
    }

    /* ── Tighter vertical rhythm ─────────────────────────────────────────── */
    .grid-margin { margin-bottom: 0.85rem !important; }
    .card-description { margin-bottom: 0.6rem !important; color: var(--oqm-muted) !important; }
    .text-muted { color: var(--oqm-muted) !important; }

    /* ── Sidebar: kill the stock blue active bar + submenu blues ─────────── */
    .sidebar .nav .nav-item.active { background: var(--oqm-surface-inset) !important; }
    .sidebar .nav .nav-item.active > .nav-link .menu-title,
    .sidebar .nav .nav-item.active > .nav-link i { color: var(--oqm-primary) !important; }
    .sidebar .nav .nav-item .nav-link .menu-arrow,
    .sidebar .nav .nav-item .nav-link .menu-arrow::before { color: var(--oqm-muted) !important; }

    .sidebar .nav.sub-menu { margin-bottom: 0.4rem !important; }
    .sidebar .nav.sub-menu .nav-item .nav-link { color: var(--oqm-muted) !important; }
    .sidebar .nav.sub-menu .nav-item .nav-link::before { color: var(--oqm-border) !important; }
    .sidebar .nav.sub-menu .nav-item .nav-link:hover { color: var(--oqm-ink) !important; background: transparent !important; }
    .sidebar .nav.sub-menu .nav-item .nav-link.active { color: var(--oqm-primary) !important; }

    /* Table sort-links in the header read as headers, not body links. */
    .table thead th a,
    .table thead th a:hover,
    a.kaffy-order-field,
    a.kaffy-order-field:hover { color: var(--oqm-muted) !important; }

    /* ── Brand: swap the stock blue Kaffy logo for our wordmark ──────────── */
    .navbar-brand.brand-logo img,
    .navbar-brand.brand-logo-mini img { display: none !important; }
    .navbar-brand.brand-logo::after {
      content: "o-que-mudou";
      font-family: Georgia, "Times New Roman", serif;
      font-weight: 600;
      font-size: 1rem;
      letter-spacing: -0.01em;
      color: var(--oqm-ink);
    }
    .navbar-brand.brand-logo-mini::after {
      content: "oqm";
      font-family: Georgia, "Times New Roman", serif;
      font-weight: 700;
      font-size: 1rem;
      color: var(--oqm-ink);
    }
    """
  end
end

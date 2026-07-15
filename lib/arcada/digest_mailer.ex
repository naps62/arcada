defmodule Arcada.DigestMailer do
  @moduledoc """
  Bulk mailer for act digests — the recurring "what changed for you" mail.

  Deliberately separate from `Arcada.Mailer` (account verification + password
  reset). Digests are the mail that collects spam complaints; account mail is
  the mail that must always arrive or people cannot get into their account.
  Keeping them on distinct mailers means the adapter, sender address and
  retry behaviour of one can change without touching the other.

  Adapter is set per-environment: `Swoosh.Adapters.Local` in dev (the
  `/dev/mailbox` preview), `Swoosh.Adapters.Test` in test, `Swoosh.Adapters.Scaleway`
  in prod (credentials via env, see `config/runtime.exs`). The `from` address
  comes from the `:digest_mailer_from` app config.
  """
  use Swoosh.Mailer, otp_app: :arcada
end

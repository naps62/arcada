defmodule Arcada.Mailer do
  @moduledoc """
  Transactional mailer for public user accounts (verification + password reset).

  Bulk digest mail goes through `Arcada.DigestMailer` instead — see its
  moduledoc for why the two are kept apart.

  Adapter is set per-environment: `Swoosh.Adapters.Local` in dev/test (the
  `/dev/mailbox` preview), `Swoosh.Adapters.Scaleway` in prod (credentials via
  env, see `config/runtime.exs`). Swoosh's HTTP calls go through Req — no extra
  hackney/Finch dependency — configured in `config/config.exs`.
  """
  use Swoosh.Mailer, otp_app: :arcada
end

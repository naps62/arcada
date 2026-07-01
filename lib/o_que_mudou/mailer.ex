defmodule OQueMudou.Mailer do
  @moduledoc """
  Application mailer for public user accounts (verification + password reset).

  Adapter is set per-environment: `Swoosh.Adapters.Local` in dev/test (the
  `/dev/mailbox` preview), `Swoosh.Adapters.Resend` in prod (API key via env,
  see `config/runtime.exs`). Swoosh's HTTP calls go through Req — no extra
  hackney/Finch dependency — configured in `config/config.exs`.
  """
  use Swoosh.Mailer, otp_app: :o_que_mudou
end

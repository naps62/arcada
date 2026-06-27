defmodule OQueMudou.Repo do
  use Ecto.Repo,
    otp_app: :o_que_mudou,
    adapter: Ecto.Adapters.Postgres
end

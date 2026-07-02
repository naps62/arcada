defmodule Arcada.Repo do
  use Ecto.Repo,
    otp_app: :arcada,
    adapter: Ecto.Adapters.Postgres
end

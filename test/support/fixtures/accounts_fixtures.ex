defmodule Arcada.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Arcada.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  @doc """
  A registered *and confirmed* user — the only state that can hold a session,
  now that login rejects unverified accounts. This is the default because a
  logged-in unverified user is no longer a state the app produces.

  Tests that need the unverified state want `unconfirmed_user_fixture/1`.
  """
  def user_fixture(attrs \\ %{}) do
    attrs
    |> unconfirmed_user_fixture()
    |> Arcada.Accounts.User.confirm_changeset()
    |> Arcada.Repo.update!()
  end

  @doc """
  A registered user who has not confirmed their email — cannot log in.
  """
  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Arcada.Accounts.register_user()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end

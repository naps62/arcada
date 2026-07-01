defmodule OQueMudou.Accounts.UserNotifier do
  @moduledoc """
  Account emails for public users — verification and password reset — in plain
  Portuguese. Delivered via `OQueMudou.Mailer` (Resend in prod, mailbox preview
  in dev). The `from` address comes from the `:mailer_from` app config.
  """
  import Swoosh.Email

  alias OQueMudou.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    from =
      Application.get_env(
        :o_que_mudou,
        :mailer_from,
        {"O que mudou", "nao-responder@o-que-mudou.local"}
      )

    email =
      new()
      |> to(recipient)
      |> from(from)
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirme a sua conta", """

    Olá,

    Recebemos um pedido para criar uma conta em O que mudou com este endereço.

    Para a activar, confirme a conta neste endereço:

    #{url}

    Se não foi você a criar esta conta, ignore este email.
    """)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Repor a palavra-passe", """

    Olá,

    Recebemos um pedido para repor a palavra-passe da sua conta em O que mudou.

    Para escolher uma nova palavra-passe, siga este endereço:

    #{url}

    Se não foi você a fazer este pedido, ignore este email — a palavra-passe
    actual mantém-se.
    """)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Confirme o novo endereço de email", """

    Olá,

    Recebemos um pedido para alterar o endereço de email da sua conta em
    O que mudou para este.

    Para confirmar a alteração, siga este endereço:

    #{url}

    Se não foi você a fazer este pedido, ignore este email.
    """)
  end
end

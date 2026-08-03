defmodule Arcada.Accounts.UserNotifier do
  @moduledoc """
  Account emails for public users — verification and password reset — in plain
  Portuguese. Delivered via `Arcada.Mailer` (Scaleway TEM in prod, mailbox
  preview in dev). The `from` address comes from the `:mailer_from` app config.

  Multipart: a branded HTML part (`Arcada.EmailHTML`) over the plain-text
  body, which stays the baseline for text-only clients and screen readers.
  """
  import Swoosh.Email

  alias Arcada.{EmailHTML, Mailer}
  alias ArcadaWeb.SEO

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, text, html) do
    from =
      Application.get_env(
        :arcada,
        :mailer_from,
        {"Arcada", "nao-responder@arcada.local"}
      )

    email =
      new()
      |> to(recipient)
      |> from(from)
      |> subject(subject)
      |> text_body(text)
      |> html_body(html)
      |> maybe_reply_to()

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  # We send from a no-reply address. When `:mailer_reply_to` is configured
  # (MAILER_REPLY_TO env), point replies at a real, monitored inbox so people
  # who reply anyway are heard. Unset → no Reply-To (plain no-reply).
  #
  # Set as a raw header, not via Swoosh's `reply_to/2`: the Scaleway adapter
  # drops the struct's `reply_to` field on the floor (`prepare_reply_to/2` is a
  # no-op) and only forwards `headers` as `additional_headers`. Using
  # `reply_to/2` here fails silently — the mail sends, the header just isn't
  # there.
  defp maybe_reply_to(email) do
    case Application.get_env(:arcada, :mailer_reply_to) do
      addr when is_binary(addr) and addr != "" -> header(email, "Reply-To", addr)
      _ -> email
    end
  end

  # The one-action account email: heading, lead, button + URL fallback, and
  # the "wasn't you? ignore this" closing line.
  defp action_html(title, lead, button_label, url, closing) do
    content =
      EmailHTML.heading(title) <>
        EmailHTML.paragraph(EmailHTML.escape(lead)) <>
        EmailHTML.button(button_label, url) <>
        EmailHTML.url_fallback(url) <>
        EmailHTML.paragraph(EmailHTML.escape(closing), muted: true)

    footer =
      EmailHTML.footer_line(
        EmailHTML.link("Arcada", SEO.home_url()) <>
          " — o Diário da República em linguagem simples."
      )

    EmailHTML.layout(lead, content, footer)
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    text = """

    Olá,

    Recebemos um pedido para criar uma conta na Arcada com este endereço.

    Para a activar, confirme a conta neste endereço:

    #{url}

    Se não foi você a criar esta conta, ignore este email.
    """

    html =
      action_html(
        "Confirme a sua conta",
        "Recebemos um pedido para criar uma conta na Arcada com este endereço.",
        "Confirmar a conta",
        url,
        "Se não foi você a criar esta conta, ignore este email."
      )

    deliver(user.email, "Confirme a sua conta", text, html)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    text = """

    Olá,

    Recebemos um pedido para repor a palavra-passe da sua conta na Arcada.

    Para escolher uma nova palavra-passe, siga este endereço:

    #{url}

    Se não foi você a fazer este pedido, ignore este email — a palavra-passe
    actual mantém-se.
    """

    html =
      action_html(
        "Repor a palavra-passe",
        "Recebemos um pedido para repor a palavra-passe da sua conta na Arcada.",
        "Escolher nova palavra-passe",
        url,
        "Se não foi você a fazer este pedido, ignore este email — a palavra-passe actual mantém-se."
      )

    deliver(user.email, "Repor a palavra-passe", text, html)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    text = """

    Olá,

    Recebemos um pedido para alterar o endereço de email da sua conta na
    Arcada para este.

    Para confirmar a alteração, siga este endereço:

    #{url}

    Se não foi você a fazer este pedido, ignore este email.
    """

    html =
      action_html(
        "Confirme o novo endereço de email",
        "Recebemos um pedido para alterar o endereço de email da sua conta na Arcada para este.",
        "Confirmar a alteração",
        url,
        "Se não foi você a fazer este pedido, ignore este email."
      )

    deliver(user.email, "Confirme o novo endereço de email", text, html)
  end
end

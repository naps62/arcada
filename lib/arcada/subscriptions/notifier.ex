defmodule Arcada.Subscriptions.Notifier do
  @moduledoc """
  The subscription emails: "what's new about X" and the periodic digest.

  Delivered through `Arcada.DigestMailer`, never `Arcada.Mailer` — this is the
  bulk mail that attracts spam complaints, and it must not be able to poison the
  reputation of verification and password-reset mail.

  Multipart: a branded HTML part (`Arcada.EmailHTML`, the site's broadsheet in
  email-safe markup) over the plain-text body, which stays the baseline for
  text-only clients and screen readers. No tracking pixel in either part.
  """
  import Swoosh.Email

  alias Arcada.{DigestMailer, EmailHTML, Register, Subscriptions}
  alias Arcada.Register.Act
  alias Arcada.Subscriptions.Subscription
  alias ArcadaWeb.SEO

  # Longest standfirst shown per story in the HTML digest; the full summary
  # lives behind the headline link.
  @standfirst_max 240

  @doc """
  Mail `acts` to the subscription's owner. `window` is the `{from, to}` the acts
  were drawn from; `total` is how many exist in that window (a capped digest
  says how many it left out). Returns `{:ok, email}` or `{:error, reason}`.
  """
  def deliver(%Subscription{} = subscription, user, acts, window, total \\ nil) do
    unsubscribe_url =
      subscription
      |> Subscriptions.unsubscribe_token()
      |> SEO.unsubscribe_url()

    email =
      new()
      |> to(user.email)
      |> from(sender())
      |> subject(subject_line(subscription, acts))
      |> text_body(body(subscription, acts, window, total, unsubscribe_url))
      |> html_body(html(subscription, acts, window, total, unsubscribe_url))
      # Lets a mail client offer its own unsubscribe control, which people reach
      # for instead of the spam button. Bulk mail without it gets filtered.
      |> header("List-Unsubscribe", "<#{unsubscribe_url}>")

    with {:ok, _metadata} <- DigestMailer.deliver(email) do
      {:ok, email}
    end
  end

  defp sender do
    Application.get_env(:arcada, :digest_mailer_from, {"Arcada", "noticias@arcada.local"})
  end

  defp subject_line(%Subscription{query: nil, period: period}, acts) do
    "Arcada · resumo #{String.downcase(Subscriptions.period_label(period))} — #{count(acts, "diploma", "diplomas")}"
  end

  defp subject_line(%Subscription{query: query}, acts) do
    "Arcada · «#{query}» — #{count(acts, "novidade", "novidades")}"
  end

  defp body(subscription, acts, {window_from, window_to}, total, unsubscribe_url) do
    """

    Olá,

    #{intro(subscription, acts, window_from, window_to)}

    #{acts |> Enum.map(&entry/1) |> Enum.join("\n")}
    #{remainder(subscription, acts, total)}
    A Arcada resume em linguagem simples; a versão oficial de cada diploma está
    ligada acima, no Diário da República. Isto não é aconselhamento jurídico.

    --
    #{reason(subscription)}
    Cancelar esta subscrição: #{unsubscribe_url}
    Gerir as suas subscrições: #{SEO.subscriptions_url()}
    """
  end

  defp intro(%Subscription{query: nil}, acts, window_from, window_to) do
    "Saíram #{count(acts, "diploma", "diplomas")} #{period_phrase(window_from, window_to)}:"
  end

  defp intro(%Subscription{query: query}, acts, window_from, window_to) do
    "Encontrámos #{count(acts, "diploma", "diplomas")} sobre «#{query}» #{period_phrase(window_from, window_to)}:"
  end

  defp period_phrase(window_from, window_to) do
    if Date.compare(window_from, window_to) == :eq do
      "em #{Register.long_date(window_to)}"
    else
      "entre #{Register.long_date(window_from)} e #{Register.long_date(window_to)}"
    end
  end

  defp entry(%Act{} = act) do
    """
      #{headline(act)}
      #{date_line(act)}#{SEO.act_url(act)}
    """
  end

  # The plain-language headline when the act has been summarised, the act's own
  # formal designation when it hasn't — never a blank line.
  defp headline(%Act{} = act) do
    case Register.published_summary(act) do
      %{headline: headline} when is_binary(headline) and headline != "" -> headline
      _ -> act.title || act.tipo || "Diploma"
    end
  end

  defp date_line(%Act{published_at: %Date{} = date}), do: "#{Register.long_date(date)} · "
  defp date_line(_act), do: ""

  # A digest is capped (see Arcada.Subscriptions.Matcher); say so rather than
  # silently presenting a slice as the whole window.
  defp remainder(%Subscription{query: nil}, acts, total)
       when is_integer(total) and total > length(acts) do
    "\nE mais #{total - length(acts)}. Veja tudo em #{SEO.home_url()}\n"
  end

  defp remainder(_subscription, _acts, _total), do: ""

  defp reason(%Subscription{query: nil, period: period}) do
    "Recebe este email porque subscreveu o resumo #{String.downcase(Subscriptions.period_label(period))} de tudo o que sai na Arcada."
  end

  defp reason(%Subscription{query: query, period: period}) do
    "Recebe este email porque subscreveu «#{query}» na Arcada, com frequência #{String.downcase(Subscriptions.period_label(period))}."
  end

  defp count(acts, singular, plural) do
    case length(acts) do
      1 -> "1 #{singular}"
      n -> "#{n} #{plural}"
    end
  end

  # -- HTML part --------------------------------------------------------------

  defp html(subscription, acts, {window_from, window_to}, total, unsubscribe_url) do
    intro = intro(subscription, acts, window_from, window_to)

    content =
      EmailHTML.paragraph(EmailHTML.escape(intro)) <>
        Enum.map_join(acts, &entry_html/1) <>
        remainder_html(subscription, acts, total)

    EmailHTML.layout(intro, content, digest_footer(subscription, unsubscribe_url))
  end

  # Kicker (date · issuing body) → plain-language headline → standfirst,
  # mirroring the site's story entry.
  defp entry_html(%Act{} = act) do
    EmailHTML.entry(entry_kicker(act), headline(act), SEO.act_url(act), standfirst(act))
  end

  defp entry_kicker(%Act{} = act) do
    [date_kicker(act), act.emitter || act.tipo]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp date_kicker(%Act{published_at: %Date{} = date}), do: Register.long_date(date)
  defp date_kicker(_act), do: nil

  # The opening of the plain-language summary, capped on a word boundary; the
  # act without a summary gets none (the site's quiet "brief" row).
  defp standfirst(%Act{} = act) do
    case Register.published_summary(act) do
      %{plain_text: text} when is_binary(text) and text != "" -> excerpt(text)
      _ -> nil
    end
  end

  defp excerpt(text) do
    first = text |> String.split("\n", parts: 2) |> hd() |> String.trim()

    if String.length(first) <= @standfirst_max do
      first
    else
      first
      |> String.slice(0, @standfirst_max)
      |> String.replace(~r/\s+\S*$/u, "")
      |> Kernel.<>("…")
    end
  end

  defp remainder_html(%Subscription{query: nil}, acts, total)
       when is_integer(total) and total > length(acts) do
    EmailHTML.paragraph(
      "E mais #{total - length(acts)}. " <>
        EmailHTML.link("Veja tudo na Arcada", SEO.home_url()) <> "."
    )
  end

  defp remainder_html(_subscription, _acts, _total), do: ""

  defp digest_footer(subscription, unsubscribe_url) do
    EmailHTML.footer_line(EmailHTML.escape(reason(subscription))) <>
      EmailHTML.footer_line(
        EmailHTML.link("Cancelar esta subscrição", unsubscribe_url) <>
          " · " <>
          EmailHTML.link("Gerir as suas subscrições", SEO.subscriptions_url())
      ) <>
      EmailHTML.footer_line(
        EmailHTML.escape(
          "A Arcada resume em linguagem simples; a versão oficial de cada diploma " <>
            "está ligada acima, no Diário da República. Isto não é aconselhamento jurídico."
        )
      )
  end
end

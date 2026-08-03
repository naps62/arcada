defmodule Arcada.EmailHTML do
  @moduledoc """
  The shared HTML shell for Arcada emails: the site's newsprint broadsheet
  (DESIGN.md) translated to what mail clients actually render — table layout,
  inline styles, system font stacks (Georgia for the serif voices, Arial for
  furniture), no images, no webfonts, no tracking pixels.

  Every email stays multipart: callers pair this HTML with a plain-text body,
  which remains the accessibility and deliverability baseline.

  Anything interpolated into markup MUST go through `escape/1` first — act
  titles, summaries and search queries are free text.
  """

  alias ArcadaWeb.SEO

  # DESIGN.md color tokens flattened to hex; email clients don't parse oklch.
  @paper "#F6F3ED"
  @ink "#211C17"
  @muted "#5B544D"
  @border "#CFCAC2"
  @primary "#225899"

  # Fraunces/Newsreader don't load in mail clients; these are the DESIGN.md
  # fallback stacks for the display/reading and furniture voices.
  @serif "Georgia, 'Times New Roman', serif"
  @sans "'Helvetica Neue', Helvetica, Arial, sans-serif"

  @doc "HTML-escape free text for interpolation into markup."
  def escape(nil), do: ""

  def escape(text) do
    text |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end

  @doc """
  The full document: hidden preheader, masthead (kicker · nameplate · heavy
  rule), the caller's `content`, and a hairline-ruled `footer`. `preheader` is
  the snippet mail clients show after the subject line — plain text, escaped
  here.
  """
  def layout(preheader, content, footer) do
    """
    <!DOCTYPE html>
    <html lang="pt" xmlns="http://www.w3.org/1999/xhtml">
    <head>
      <meta charset="utf-8"/>
      <meta name="viewport" content="width=device-width, initial-scale=1"/>
      <meta name="color-scheme" content="light"/>
      <meta name="supported-color-schemes" content="light"/>
      <title>Arcada</title>
    </head>
    <body style="margin:0;padding:0;background-color:#{@paper};">
      <div style="display:none;max-height:0;overflow:hidden;mso-hide:all;">#{escape(preheader)}</div>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#{@paper};">
        <tr>
          <td align="center" style="padding:32px 20px 40px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;">
              <tr><td>#{masthead()}</td></tr>
              <tr><td style="padding:26px 0 10px;">#{content}</td></tr>
              <tr><td style="border-top:1px solid #{@border};padding:18px 0 0;">#{footer}</td></tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """
  end

  # The site's nameplate: kicker above, serif wordmark, 2px rule-strong below.
  defp masthead do
    """
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr>
        <td align="center" style="padding-bottom:8px;#{kicker_style()}">Di&aacute;rio da Rep&uacute;blica &middot; S&eacute;rie I</td>
      </tr>
      <tr>
        <td align="center" style="padding-bottom:16px;border-bottom:2px solid #{@ink};font-family:#{@serif};font-size:40px;font-weight:900;line-height:1;letter-spacing:-1px;color:#{@ink};">
          <a href="#{escape(SEO.home_url())}" style="color:#{@ink};text-decoration:none;">Arcada</a>
        </td>
      </tr>
    </table>
    """
  end

  @doc "The story/section headline voice: serif, bold, ink."
  def heading(text) do
    ~s(<h1 style="margin:0 0 14px;font-family:#{@serif};font-size:23px;font-weight:bold;line-height:1.25;color:#{@ink};">#{escape(text)}</h1>)
  end

  @doc "Reading prose. `html` is already-escaped/authored markup, not free text."
  def paragraph(html, opts \\ []) do
    color = if opts[:muted], do: @muted, else: @ink

    ~s(<p style="margin:0 0 16px;font-family:#{@serif};font-size:17px;line-height:1.6;color:#{color};">#{html}</p>)
  end

  defp kicker_style do
    "font-family:#{@sans};font-size:11px;font-weight:bold;line-height:1.3;letter-spacing:1px;text-transform:uppercase;color:#{@muted};"
  end

  @doc "Primary action: ink-blue block button (table-based, renders everywhere)."
  def button(label, url) do
    """
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:6px 0 18px;">
      <tr>
        <td style="background-color:#{@primary};border-radius:8px;">
          <a href="#{escape(url)}" style="display:inline-block;padding:13px 26px;font-family:#{@sans};font-size:16px;font-weight:bold;color:#{@paper};text-decoration:none;">#{escape(label)}</a>
        </td>
      </tr>
    </table>
    """
  end

  @doc "The plain URL under a button, for clients that block or mangle links."
  def url_fallback(url) do
    """
    <p style="margin:0 0 16px;font-family:#{@sans};font-size:13px;line-height:1.5;color:#{@muted};">
      Se o bot&atilde;o n&atilde;o funcionar, copie este endere&ccedil;o para o navegador:<br/>
      <a href="#{escape(url)}" style="color:#{@primary};word-break:break-all;">#{escape(url)}</a>
    </p>
    """
  end

  @doc "An inline ink-blue text link. `label` is escaped here."
  def link(label, url) do
    ~s(<a href="#{escape(url)}" style="color:#{@primary};">#{escape(label)}</a>)
  end

  @doc "A footer line: small furniture text. `html` is authored markup."
  def footer_line(html) do
    ~s(<p style="margin:0 0 8px;font-family:#{@sans};font-size:13px;line-height:1.5;color:#{@muted};">#{html}</p>)
  end

  @doc "A story entry, ruled not carded: hairline above, kicker → headline → standfirst."
  def entry(kicker_text, headline, url, standfirst) do
    standfirst_html =
      if standfirst do
        ~s(<div style="margin-top:6px;font-family:#{@serif};font-size:16px;line-height:1.55;color:#{@ink};">#{escape(standfirst)}</div>)
      else
        ""
      end

    """
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr>
        <td style="padding:18px 0;border-top:1px solid #{@border};">
          <div style="margin-bottom:6px;#{kicker_style()}">#{escape(kicker_text)}</div>
          <a href="#{escape(url)}" style="font-family:#{@serif};font-size:20px;font-weight:bold;line-height:1.3;color:#{@primary};text-decoration:none;">#{escape(headline)}</a>
          #{standfirst_html}
        </td>
      </tr>
    </table>
    """
  end
end

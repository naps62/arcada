defmodule Arcada.Subscriptions.NotifierTest do
  use Arcada.DataCase, async: true

  import Arcada.AccountsFixtures
  import Arcada.RegisterFixtures
  import Arcada.SubscriptionsFixtures

  alias Arcada.Register
  alias Arcada.Subscriptions.Notifier

  defp deliver(subscription, user, acts, total \\ nil) do
    window = {Date.utc_today(), Date.utc_today()}
    {:ok, email} = Notifier.deliver(subscription, user, acts, window, total)
    email
  end

  defp with_summaries(act), do: Register.get_act_by_dre_id!(act.dre_id)

  test "renders a multipart digest: text baseline plus branded HTML" do
    user = user_fixture()
    subscription = subscription_fixture(user, %{query: nil, period: :semanal})
    act = act_fixture(%{title: "Portaria n.º 9/2026", emitter: "Finanças"})

    email = deliver(subscription, user, [with_summaries(act)])

    assert email.text_body =~ "Portaria n.º 9/2026"
    assert email.html_body =~ "Portaria n.º 9/2026"
    # The story entry carries the site's kicker: date · issuing body.
    assert email.html_body =~ "Finanças"
    # Both parts carry the unsubscribe link.
    assert email.text_body =~ "/subscricoes/cancelar/"
    assert email.html_body =~ "/subscricoes/cancelar/"
  end

  test "escapes free text in the HTML part" do
    user = user_fixture()
    subscription = subscription_fixture(user, %{query: "IRS & IVA <2026>"})
    act = act_fixture(%{title: "Lei <mar> & rios"})

    email = deliver(subscription, user, [with_summaries(act)])

    assert email.html_body =~ "Lei &lt;mar&gt; &amp; rios"
    refute email.html_body =~ "Lei <mar>"
    assert email.html_body =~ "IRS &amp; IVA &lt;2026&gt;"
  end

  test "shows the summary standfirst, capped on a word boundary" do
    user = user_fixture()
    subscription = subscription_fixture(user, %{query: nil, period: :semanal})
    act = act_fixture()

    long = String.duplicate("palavra ", 60)
    summary_fixture(act, %{headline: "Titular simples", plain_text: long})

    email = deliver(subscription, user, [with_summaries(act)])

    assert email.html_body =~ "Titular simples"
    assert email.html_body =~ "palavra palavra"
    assert email.html_body =~ "…"
  end

  test "a capped digest links the rest home in both parts" do
    user = user_fixture()
    subscription = subscription_fixture(user, %{query: nil, period: :semanal})
    acts = [with_summaries(act_fixture())]

    email = deliver(subscription, user, acts, 5)

    assert email.text_body =~ "E mais 4."
    assert email.html_body =~ "E mais 4."
    assert email.html_body =~ "Veja tudo na Arcada"
  end
end

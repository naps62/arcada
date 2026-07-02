defmodule OQueMudouWeb.RemoteIpProxies do
  @moduledoc """
  Trusted-proxy CIDR sets for the `RemoteIp` plug (issue #43), so a deploy can
  turn on real-client-IP recovery without hand-pasting the Cloudflare range list
  into an env var. Used as the default `:proxies` in `config/runtime.exs`.

  Two groups:

  * `cloudflare/0` — Cloudflare's published edge ranges
    (https://www.cloudflare.com/ips/). These rotate rarely; refresh them if
    Cloudflare updates the list. When the origin is firewalled to these ranges
    (the CF-lock in the arcada-public-golive plan), any request reaching the app
    genuinely came through Cloudflare.

  * `private/0` — RFC1918 + loopback + unique-local ranges. The Traefik container
    peer sits on the Docker/Swarm overlay network, whose address is always
    private, so trusting these as proxies lets `RemoteIp` walk back past Traefik.
    Private ranges can never be a real public client, so trusting them is safe.

  `default/0` is `cloudflare/0 ++ private/0` — the right proxy set for the
  Cloudflare → Traefik → Phoenix chain, walking `X-Forwarded-For` back to the
  real client.
  """

  # Cloudflare IPv4 + IPv6 edge ranges — https://www.cloudflare.com/ips/
  @cloudflare ~w(
    173.245.48.0/20
    103.21.244.0/22
    103.22.200.0/22
    103.31.4.0/22
    141.101.64.0/18
    108.162.192.0/18
    190.93.240.0/20
    188.114.96.0/20
    197.234.240.0/22
    198.41.128.0/17
    162.158.0.0/15
    104.16.0.0/13
    104.24.0.0/14
    172.64.0.0/13
    131.0.72.0/22
    2400:cb00::/32
    2606:4700::/32
    2803:f800::/32
    2405:b500::/32
    2405:8100::/32
    2a06:98c0::/29
    2c0f:f248::/32
  )

  # RFC1918 + loopback + IPv6 loopback/unique-local. Covers the Docker/Swarm
  # overlay network the Traefik peer lives on.
  @private ~w(
    10.0.0.0/8
    172.16.0.0/12
    192.168.0.0/16
    127.0.0.0/8
    ::1/128
    fc00::/7
  )

  @spec cloudflare() :: [String.t()]
  def cloudflare, do: @cloudflare

  @spec private() :: [String.t()]
  def private, do: @private

  @spec default() :: [String.t()]
  def default, do: @cloudflare ++ @private
end

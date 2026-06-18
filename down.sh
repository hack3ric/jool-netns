#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

INSTANCE=${1:-}
[ -n "$INSTANCE" ] || usage

load_env
resolve_common_settings
configure_jool_mode

cleanup_stale_netns_ref

if netns_is_usable; then
  if [ -n "$JOOL_CONFIG" ] && [ -r "$JOOL_CONFIG" ] && command -v "$JOOL_BIN" >/dev/null 2>&1; then
    ip netns exec "$NETNS_NAME" "$JOOL_BIN" -f "$JOOL_CONFIG" instance remove >/dev/null 2>&1 || true
  fi
fi

if [ -n "${HOST_ROUTE4:-}" ]; then
  ip route del "$HOST_ROUTE4" via "$(route_ipv4_gateway)" dev "$HOST_VETH" >/dev/null 2>&1 || true
fi

if [ -n "${HOST_ROUTE6:-}" ]; then
  ip -6 route del "$HOST_ROUTE6" via "$(route_ipv6_gateway)" dev "$HOST_VETH" >/dev/null 2>&1 || true
fi

if nat_rule_enabled && command -v nft >/dev/null 2>&1; then
  nft delete table ip "$NFT_TABLE" >/dev/null 2>&1 || true
fi

if ip link show dev "$HOST_VETH" >/dev/null 2>&1; then
  ip link delete dev "$HOST_VETH" >/dev/null 2>&1 || true
fi

if netns_is_usable; then
  ip netns delete "$NETNS_NAME" >/dev/null 2>&1 || true
fi

cleanup_stale_netns_ref

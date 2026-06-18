#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

create_nat_rule() {
  nft delete table ip "$NFT_TABLE" >/dev/null 2>&1 || true
  nft -f - <<EOF
add table ip $NFT_TABLE
add chain ip $NFT_TABLE postrouting { type nat hook postrouting priority srcnat; policy accept; }
add rule ip $NFT_TABLE postrouting iifname "$HOST_VETH" masquerade
EOF
}

create_host_routes() {
  if [ -n "${HOST_ROUTE4:-}" ]; then
    ip route replace "$HOST_ROUTE4" via "$(route_ipv4_gateway)" dev "$HOST_VETH"
  fi

  if [ -n "${HOST_ROUTE6:-}" ]; then
    ip -6 route replace "$HOST_ROUTE6" via "$(route_ipv6_gateway)" dev "$HOST_VETH"
  fi
}

cleanup_needed=1
cleanup_on_error() {
  if [ "$cleanup_needed" -eq 1 ]; then
    log "startup failed; cleaning up partial state"
    "$SCRIPT_DIR/down.sh" "$INSTANCE" || true
  fi
}
trap cleanup_on_error EXIT HUP INT TERM

INSTANCE=${1:-}
[ -n "$INSTANCE" ] || usage

load_env
resolve_common_settings
[ -n "$JOOL_MODE" ] || die "JOOL_MODE must be set"
[ -n "$JOOL_CONFIG" ] || die "JOOL_CONFIG must be set"
[ -r "$JOOL_CONFIG" ] || die "JOOL_CONFIG is not readable: $JOOL_CONFIG"
configure_jool_mode

validate_ifname "$HOST_VETH" HOST_VETH
validate_ifname "$NS_VETH" NS_VETH

require_cmd ip
require_cmd nft
require_cmd modprobe
require_cmd sysctl
require_cmd umount
require_cmd "$JOOL_BIN"

cleanup_stale_netns_ref

if netns_is_usable; then
  die "network namespace already exists: $NETNS_NAME"
fi

if ip link show dev "$HOST_VETH" >/dev/null 2>&1; then
  die "host veth already exists: $HOST_VETH"
fi

enable_host_forwarding

ip netns add "$NETNS_NAME"
ip link add "$HOST_VETH" type veth peer name "$NS_VETH" netns "$NETNS_NAME"

ip link set dev "$HOST_VETH" addrgenmode none
ip link set dev "$HOST_VETH" up
ip addr add dev "$HOST_VETH" "$HOST_IPV4"/32 peer "$NS_IPV4"/32
ip addr add dev "$HOST_VETH" "$HOST_IPV6" nodad

ip netns exec "$NETNS_NAME" sysctl -qw net.ipv4.conf.all.forwarding=1
ip netns exec "$NETNS_NAME" sysctl -qw net.ipv6.conf.all.forwarding=1
ip netns exec "$NETNS_NAME" ip link set dev lo up
ip netns exec "$NETNS_NAME" ip link set dev "$NS_VETH" addrgenmode none
ip netns exec "$NETNS_NAME" ip link set dev "$NS_VETH" up
ip netns exec "$NETNS_NAME" ip addr add dev "$NS_VETH" "$NS_IPV4"/32 peer "$HOST_IPV4"/32
ip netns exec "$NETNS_NAME" ip addr add dev "$NS_VETH" "$NS_IPV6" nodad
ip netns exec "$NETNS_NAME" ip route replace default via "$HOST_IPV4" dev "$NS_VETH"
ip netns exec "$NETNS_NAME" ip -6 route replace default via "${HOST_IPV6%/*}" dev "$NS_VETH"

modprobe "$JOOL_MODULE"
ip netns exec "$NETNS_NAME" "$JOOL_BIN" file handle "$JOOL_CONFIG"

if nat_rule_enabled; then
  create_nat_rule
fi
create_host_routes

cleanup_needed=0
trap - EXIT HUP INT TERM

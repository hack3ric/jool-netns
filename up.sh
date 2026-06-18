#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

log() {
  printf '%s\n' "$*" >&2
}

die() {
  log "error: $*"
  exit 1
}

usage() {
  die "usage: $0 <instance>"
}

load_env() {
  if [ -n "${JOOL_ENV_FILE:-}" ]; then
    ENV_FILE=$JOOL_ENV_FILE
  else
    ENV_DIR=${JOOL_ENV_DIR:-/etc/jool-netns}
    ENV_FILE=$ENV_DIR/$INSTANCE.env
  fi

  if [ -r "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE"
  elif [ -z "${JOOL_MODE:-}" ] || [ -z "${JOOL_CONFIG:-}" ]; then
    die "env file not found: $ENV_FILE"
  fi
}

instance_hash() {
  printf '%s' "$INSTANCE" | cksum | awk '{print $1}'
}

validate_ifname() {
  name=$1
  label=$2

  case $name in
  "" | *[!A-Za-z0-9_.:-]*)
    die "$label contains unsupported characters: $name"
    ;;
  esac

  if [ "${#name}" -gt 15 ]; then
    die "$label must be 15 characters or fewer: $name"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

netns_ref_path() {
  printf '/var/run/netns/%s' "$NETNS_NAME"
}

netns_is_usable() {
  ip netns exec "$NETNS_NAME" true >/dev/null 2>&1
}

cleanup_stale_netns_ref() {
  ref_path=$(netns_ref_path)

  if [ -e "$ref_path" ] && ! netns_is_usable; then
    umount -l "$ref_path" >/dev/null 2>&1 || true
    rm -f "$ref_path"
  fi
}

route_ipv4_gateway() {
  printf '%s' "$NS_IPV4"
}

route_ipv6_gateway() {
  printf '%s' "${NS_IPV6%/*}"
}

create_nat_rule() {
  nft delete table ip "$NFT_TABLE" >/dev/null 2>&1 || true
  nft -f - <<EOF
add table ip $NFT_TABLE
add chain ip $NFT_TABLE postrouting { type nat hook postrouting priority srcnat; policy accept; }
add rule ip $NFT_TABLE postrouting iifname "$HOST_VETH" masquerade
EOF
}

nat_rule_enabled() {
  case ${HOST_MASQUERADE:-0} in
  1 | yes | YES | true | TRUE | on | ON)
    return 0
    ;;
  0 | no | NO | false | FALSE | off | OFF)
    return 1
    ;;
  *)
    die "HOST_MASQUERADE must be a boolean"
    ;;
  esac
}

create_host_routes() {
  if [ -n "${HOST_ROUTE4:-}" ]; then
    ip route replace "$HOST_ROUTE4" via "$(route_ipv4_gateway)" dev "$HOST_VETH"
  fi

  if [ -n "${HOST_ROUTE6:-}" ]; then
    ip -6 route replace "$HOST_ROUTE6" via "$(route_ipv6_gateway)" dev "$HOST_VETH"
  fi
}

enable_host_forwarding() {
  case ${HOST_IPV4_FORWARD:-1} in
  1 | yes | YES | true | TRUE | on | ON)
    sysctl -qw net.ipv4.ip_forward=1
    ;;
  esac

  case ${HOST_IPV6_FORWARD:-1} in
  1 | yes | YES | true | TRUE | on | ON)
    sysctl -qw net.ipv6.conf.all.forwarding=1
    ;;
  esac
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

INSTANCE_HASH=$(instance_hash)
NETNS_NAME=${NETNS_NAME:-jool-$INSTANCE}
HOST_VETH=${HOST_VETH:-jool$INSTANCE_HASH}
NS_VETH=${NS_VETH:-veth0}
HOST_IPV4=${HOST_IPV4:-169.254.64.1}
NS_IPV4=${NS_IPV4:-169.254.64.2}
HOST_IPV6=${HOST_IPV6:-fe80::64:1/64}
NS_IPV6=${NS_IPV6:-fe80::64:2/64}
NFT_TABLE=${JOOL_NFT_TABLE:-jool_netns_$INSTANCE_HASH}

JOOL_MODE=${JOOL_MODE:-}
JOOL_CONFIG=${JOOL_CONFIG:-}
[ -n "$JOOL_MODE" ] || die "JOOL_MODE must be set"
[ -n "$JOOL_CONFIG" ] || die "JOOL_CONFIG must be set"
[ -r "$JOOL_CONFIG" ] || die "JOOL_CONFIG is not readable: $JOOL_CONFIG"

case $JOOL_MODE in
nat64)
  JOOL_BIN=jool
  JOOL_MODULE=jool
  ;;
siit)
  JOOL_BIN=jool_siit
  JOOL_MODULE=jool_siit
  ;;
*)
  die "JOOL_MODE must be 'nat64' or 'siit'"
  ;;
esac

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

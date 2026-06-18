#!/bin/sh
set -eu

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

INSTANCE=${1:-}
[ -n "$INSTANCE" ] || usage

load_env

INSTANCE_HASH=$(instance_hash)
NETNS_NAME=${NETNS_NAME:-jool-$INSTANCE}
HOST_VETH=${HOST_VETH:-jool$INSTANCE_HASH}
NS_IPV4=${NS_IPV4:-169.254.64.2}
NS_IPV6=${NS_IPV6:-fe80::64:2/64}
JOOL_MODE=${JOOL_MODE:-}
JOOL_CONFIG=${JOOL_CONFIG:-}
NFT_TABLE=${JOOL_NFT_TABLE:-jool_netns_$INSTANCE_HASH}

case $JOOL_MODE in
nat64)
  JOOL_BIN=jool
  ;;
siit)
  JOOL_BIN=jool_siit
  ;;
*)
  die "JOOL_MODE must be 'nat64' or 'siit'"
  ;;
esac

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

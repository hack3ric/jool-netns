#!/bin/sh

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

resolve_common_settings() {
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
}

configure_jool_mode() {
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

bool_is_true() {
  case ${1:-} in
  1 | yes | YES | true | TRUE | on | ON)
    return 0
    ;;
  0 | no | NO | false | FALSE | off | OFF)
    return 1
    ;;
  *)
    return 2
    ;;
  esac
}

nat_rule_enabled() {
  bool_is_true "${HOST_MASQUERADE:-1}"
  result=$?

  case $result in
  0)
    return 0
    ;;
  1)
    return 1
    ;;
  *)
    die "HOST_MASQUERADE must be a boolean"
    ;;
  esac
}

enable_host_forwarding() {
  bool_is_true "${HOST_IPV4_FORWARD:-1}"
  result=$?
  case $result in
  0)
    sysctl -qw net.ipv4.ip_forward=1
    ;;
  1)
    ;;
  2)
    die "HOST_IPV4_FORWARD must be a boolean"
    ;;
  esac

  bool_is_true "${HOST_IPV6_FORWARD:-1}"
  result=$?
  case $result in
  0)
    sysctl -qw net.ipv6.conf.all.forwarding=1
    ;;
  1)
    ;;
  2)
    die "HOST_IPV6_FORWARD must be a boolean"
    ;;
  esac
}

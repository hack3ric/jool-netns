# jool-netns

`jool-netns` wraps a Jool instance in a dedicated network namespace and exposes it as a oneshot systemd template service.

The wrapper does three things:

- creates a namespace and veth pair for the instance
- loads a normal Jool JSON config with `jool file handle` or `jool_siit file handle`
- adds the host-side nftables masquerade rule for packets entering from the namespace veth

It does not create extra host routes.

## Files

- `up.sh`: bring one instance up
- `down.sh`: tear one instance down
- `common.sh`: shared helper library for both scripts
- `jool-netns@.service`: template unit for systemd
- `jool-netns.env.example`: sample per-instance settings

## Install

```sh
install -Dm0644 common.sh /usr/local/lib/jool-netns/common.sh
install -Dm0755 up.sh /usr/local/lib/jool-netns/up.sh
install -Dm0755 down.sh /usr/local/lib/jool-netns/down.sh
install -Dm0644 jool-netns@.service /etc/systemd/system/jool-netns@.service
install -Dm0644 jool-netns.env.example /etc/jool-netns/example.env
systemctl daemon-reload
```

Then edit `/etc/jool-netns/example.env` to point at the desired Jool JSON file.

## Configuration

Each systemd instance uses `/etc/jool-netns/%i.env`.

Required keys:

- `JOOL_MODE=nat64|siit`
- `JOOL_CONFIG=/path/to/jool.json`

Optional keys:

- `NETNS_NAME`
- `HOST_VETH`
- `NS_VETH`
- `HOST_IPV4`
- `NS_IPV4`
- `HOST_IPV6`
- `NS_IPV6`
- `HOST_ROUTE4`
- `HOST_ROUTE6`
- `HOST_MASQUERADE`
- `HOST_IPV4_FORWARD`
- `HOST_IPV6_FORWARD`
- `JOOL_NFT_TABLE`

`HOST_*` specifies if this wrapper creates some host rules for you. Default to off so you can configure them yourself.

If your JSON uses the `iptables` Jool framework instead of `netfilter`, this project still loads the instance correctly, but you must manage the separate `JOOL` or `JOOL_SIIT` iptables rules yourself.

## Usage

```sh
systemctl enable --now jool-netns@example.service
systemctl stop jool-netns@example.service
```

Without systemd, you can run the scripts directly:

```sh
JOOL_ENV_FILE=/etc/jool-netns/example.env ./up.sh example
JOOL_ENV_FILE=/etc/jool-netns/example.env ./down.sh example
```

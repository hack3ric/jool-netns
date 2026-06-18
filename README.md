# jool-netns

`jool-netns` wraps a Jool instance in a dedicated network namespace and exposes it as a oneshot systemd template service.

It creates a netns and veth pair for the instance, loads a normal Jool JSON config with `jool file handle` or `jool_siit file handle`, and set up necessary routing rules to allow you to route packets through the Jool-enabled netns like a new node.

## Install

```sh
make install
systemctl daemon-reload
```

Common overrides:

```sh
make install PREFIX=/usr
make install PREFIX=/opt/jool SYSCONFDIR=/etc DESTDIR=/tmp/jool-netns-stage
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

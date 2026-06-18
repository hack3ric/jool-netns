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
- `jool-netns@.service`: template unit for systemd
- `jool-netns.env.example`: sample per-instance settings

## Install

```sh
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
- `HOST_IPV4_FORWARD`
- `HOST_IPV6_FORWARD`
- `JOOL_NFT_TABLE`

The Jool JSON file must be a normal file accepted by the upstream tools, such as `/etc/jool/jool.conf` or `/etc/jool/jool_siit.conf`. The file itself is responsible for defining the Jool instance name and framework.

If you want the host itself to send traffic into the translator, set:

- `HOST_ROUTE6` to the NAT64 pool6 prefix, usually `64:ff9b::/96`
- `HOST_ROUTE4` to the pool4 prefix or address range used by the Jool config

`up.sh` installs those routes through the namespace-side peers, and `down.sh` removes them.

If your JSON uses the `iptables` Jool framework instead of `netfilter`, this project still loads the instance correctly, but you must manage the separate `JOOL` or `JOOL_SIIT` iptables rules yourself. The nftables rule created by `up.sh` is only the host-side masquerade rule from the original TODO.

## Address Reuse Across Instances

The default link addresses can be reused across instances:

- `169.254.64.1 <-> 169.254.64.2`
- `fe80::64:1/64 <-> fe80::64:2/64`

That works because every instance gets its own namespace and its own veth pair. What must stay unique per instance is the namespace name and the host-side veth name.

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

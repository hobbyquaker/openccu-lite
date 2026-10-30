<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/openccu-lite-dark@2x.png">
    <img src="docs/images/openccu-lite-light@2x.png" alt="openccu-lite" width="428">
  </picture>
</h1>

[![upstream versions](https://img.shields.io/endpoint?url=https://hobbyquaker.github.io/openccu-lite/badge.json)](https://hobbyquaker.github.io/openccu-lite/en.html)

[:de: Deutsches README](README.md)

openccu-lite is a firmware for Homematic central units, a fork of the [OpenCCU project](https://github.com/OpenCCU/OpenCCU).
It is meant for everyone who runs their automation elsewhere, for example in Home Assistant, ioBroker or Node-RED, and
wants one thing above all from the central unit: that it connects the Homematic devices reliably.

That is why some things a CCU usually brings are missing: **openccu-lite has no ReGaHSS, no WebUI programs, no
Homematic scripts and no diagrams.** The old CCU WebUI has been replaced by a
[newly developed interface](docs/walkthrough/README.md) (a German walkthrough), and the new system service
[occulited](https://github.com/hobbyquaker/occulited) takes over the system administration. System internals such as
the init system, the logging and the radio module detection have been redesigned from the ground up.

## Focus

- **Stable.** Fewer parts means less that can fail, and a high test coverage guards against regressions.
- **Secure.** Addons and system services run under their own users with restricted rights, ports are closed by
  default, authentication with passkeys, OAuth and tokens, certificates via ACME, encrypted backups. Programs and addons
  reach the interface processes through lite-rpc, with API tokens whose scopes set what they may do: read, operate,
  configure or administer.
- **Private.** No telemetry. In the [local key mode](docs/lokaler-schluesselmodus.md) a central unit can run without an
  internet connection and without depending on eQ-3's key server; other outgoing connections (update checks) happen
  only with the user's consent. Details: [Privacy](docs/privacy.md).
- **Free radio configuration.** Which radio module serves which interface can be chosen freely. That allows special
  setups, for example separate radio modules for BidCos-RF and HmIP-RF, or an HmIP-only mode without BidCos. The
  walkthrough shows [examples](docs/walkthrough/README.md#beispiele-für-funk-konfigurationen) (German).
- **Minimal.** openccu-lite ships only what a central unit really needs. Everything else comes as an addon, and only
  what is actually used.

## Addons: only what is needed

The firmware itself stays small on purpose. Whatever is needed beyond that can be installed as an addon from the
built-in addon catalogue with one click.

### Pairing and managing devices: a free choice

What the devices are paired and configured with, and what manages the direct links, is a free choice. The following
programs **can** be installed as addons on openccu-lite, and are then integrated into its web interface, **but they do
not have to be**: they run just as well on another computer. That way the central unit stays as lean a radio gateway as
possible.

- [Homematic Manager](https://github.com/hobbyquaker/homematic-manager) (managing devices and direct links; also as an
  application for Windows, macOS and Linux)
- [OpenCCU-Loom](https://github.com/SukramJ/openccu-loom) (managing devices and direct links, a user interface,
  charts, MQTT, Home Assistant, Matter and more; also as a Docker container or a Home Assistant add-on)

### More addons

- [ccu-addon-battery](https://github.com/hobbyquaker/ccu-addon-battery) (detecting battery changes, battery statistics)
- [ccu-addon-longpressdim](https://github.com/hobbyquaker/ccu-addon-longpressdim) (dimming with a long key press across
  interface boundaries)
- [ccu-addon-mosquitto](https://github.com/homematic-community/ccu-addon-mosquitto) (MQTT broker)
- [ccu-addon-mui](https://github.com/firsttris/ccu-addon-mui) (managing devices and direct links, a nice user interface
  with charts)
- [hm2mqtt.js](https://github.com/hobbyquaker/hm2mqtt.js) (MQTT connection, Home Assistant auto discovery, follows the
  mqtt-smarthome spec 2.0)
- [RedMatic](https://github.com/rdmtc/RedMatic) (automation with Node-RED, MQTT, Home Assistant, HomeKit, Matter and
  more)

### openccu-lite only

These addons use openccu-lite's interfaces and do not run on an (Open)CCU.

- [lite-addon-forwarder](https://github.com/hobbyquaker/lite-addon-forwarder) (forwarding events and system data to
  InfluxDB, Prometheus, Elasticsearch/OpenSearch, SQL databases, syslog, Loki and webhooks)
- [lite-addon-nut](https://github.com/hobbyquaker/lite-addon-nut) (a NUT client: shuts the system down in time when the
  UPS reports a power failure)
- [lite-addon-snmp](https://github.com/hobbyquaker/lite-addon-snmp) (an SNMP agent with data from the Homematic devices
  and interfaces, traps)
- [lite-addon-tailscale](https://github.com/hobbyquaker/lite-addon-tailscale) (remote access to the system over a
  Tailscale network, also with your own Headscale)
- [lite-addon-wireguard](https://github.com/hobbyquaker/lite-addon-wireguard) (remote access to the system over a
  WireGuard VPN)

More addons are in the catalogue. How addons work on openccu-lite, and how an existing addon can be adapted, is
described in [Addons](docs/addons.md).

## Installation

The releases are at [github.com/hobbyquaker/openccu-lite/releases](https://github.com/hobbyquaker/openccu-lite/releases).

- **Raspberry Pi 3/4:** unpack the release's `.zip` and write the `.img` inside it to the SD card.
- **Virtual machine:** import the `.ova` (Proxmox, VMware, VirtualBox and so on).
- **Proxmox by script:** as root on the Proxmox VE host, a script creates the VM in one step (`--help` lists the
  options):
  `bash -c "$(wget -qLO - https://raw.githubusercontent.com/hobbyquaker/openccu-lite/main/scripts/install-proxmox.sh)"`

## Switching from (Open)CCU to openccu-lite

In the OpenCCU WebUI under *Settings → Control panel → CCU maintenance → Perform software update*, upload
`openccu-lite-<product>-<version>.zip`; from an original CCU3 firmware, the `-ccu3.tgz`. Pairings, keys, addons, names,
rooms and functions are taken over; WebUI programs and system variables are dropped without replacement. Take a backup
first, it is the way back! Everything else: [Switching from and to OpenCCU](docs/switching.md).

## Updates

### How to update

On the web interface's *Updates* page: *Check now*, *Download and stage*, *Reboot and install*. Before the install a
backup is written to the configured backup targets and the checksum is verified. Over SSH the same works with
`occulited update check` and `occulited update install`
([commands and options](https://github.com/hobbyquaker/occulited/blob/master/docs/config.md)).

Which versions are offered is configurable: **stable** (finished releases only, the default), **beta** (beta and
release candidate versions as well) or **dev** (everything, development builds too).

### What is planned

- **Every new HMIPServer from eQ-3 brings a new release** of openccu-lite, so that new HmIP devices and eQ-3's fixes
  arrive quickly.
- **The interface processes rfd, hs485d and multimacd** come from an
  [own fork of OpenCCU-Base](https://github.com/hobbyquaker/OpenCCU-Base). It is meant to stay as close to OpenCCU as
  possible; a [comparison](https://hobbyquaker.github.io/OpenCCU-Base/) shows which of OpenCCU's changes are already in.
- **From Buildroot 2027.02 on, openccu-lite is based on Buildroot's LTS versions.** They get security updates for
  longer; in between the system stays on a maintained base, and their point releases can be taken over with little
  effort.
- Whether the components are current (Buildroot, kernel, firmware, Java, HMIPServer, OpenCCU-Base) is shown by an
  [overview](https://hobbyquaker.github.io/openccu-lite/en.html) renewed every day.

## Documentation

**Getting started**
- [Walkthrough of the web interface](docs/walkthrough/README.md): every page with a picture (German)
- [Switching from and to OpenCCU](docs/switching.md)
- [Recommendations](docs/recommendations.de.md) (German)
- [What differs from OpenCCU](docs/aenderungen.md) (German)

**Operation**
- [Local key mode for HmIP](docs/lokaler-schluesselmodus.md): offline-capable, radio module swaps without eQ-3's key
  server (German)
- [Certificates](docs/tls-acme.md) (your own or automatically via ACME)
- [occulite-backup](https://github.com/hobbyquaker/occulite-backup): download the backups of one or more systems from
  cron or a timer

**Security and privacy**
- [Security](docs/security.md) and [threat model](docs/threat-model.md)
- [Privacy](docs/privacy.md): what the system sends to the outside

**For addon developers and own programs**
- [Addons on openccu-lite](docs/addons.md)
- [Porting kit: from ReGa to openccu-lite](docs/porting-from-rega.md)
- [ccu-addon-kit](https://github.com/hobbyquaker/ccu-addon-kit): settings page, service control and Go building blocks
  for addons
- [occulite-client](https://github.com/hobbyquaker/occulite-client): the client for openccu-lite's APIs (npm)
- [occulited](https://github.com/hobbyquaker/occulited): the system service; its
  [documentation](https://github.com/hobbyquaker/occulited/tree/master/docs) describes the metadata, system and auth
  APIs, `occulited.json`, the addon manifest and the catalogue

## Bugs and help

Bugs and wishes, for the firmware and for occulited alike: this repository's
[issue tracker](https://github.com/hobbyquaker/openccu-lite/issues) ([SUPPORT.md](SUPPORT.md)); security problems as
described in [SECURITY.md](SECURITY.md). OpenCCU's tracker and forum section are for OpenCCU, please do not report
openccu-lite's problems there.

## License

Apache-2.0 for everything written here; the `occu` components keep eQ-3's terms.

## Disclaimer

openccu-lite is provided WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, including but not limited to the warranty of
fitness for its intended or a particular purpose and of non-infringement. IN NO EVENT shall the authors or copyright
holders be liable for any damage or other claim, whether arising from the performance of a contract, a tort or
otherwise in connection with the software or any other use of the software.

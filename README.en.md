# openccu-lite

[:de: Deutsches README](README.md)

> [!CAUTION]
> openccu-lite is under development. Much of it is still untested.
> **Please use it on test systems only.**
>
> **It is aimed at experienced Homematic users** who know what they are doing and can help themselves if
> need be: people who know a CCU from the inside (`rfd`, `hs485d`, the `hmipserver`, radio modules
> and key handling, the RPC protocol, the paramsets, ...).

openccu-lite is a fork of the [OpenCCU project](https://github.com/OpenCCU/OpenCCU) that removes some old software parts
which users who run their automation elsewhere (e.g. in Home Assistant, ioBroker, Node-RED, ...) do not need:
**openccu-lite has no ReGaHSS, no WebUI programs and no Homematic scripts.**
The old CCU WebUI has been replaced by a [newly developed interface](docs/walkthrough/README.md) (a German walkthrough), and the new daemon ["occulited"](https://github.com/hobbyquaker/occulited)
takes over the system administration tasks. System internals such as the init system, logging, radio module detection and the like
have been redesigned from the ground up, and many new security features have been implemented.

## Installation

The releases are at [github.com/hobbyquaker/openccu-lite/releases](https://github.com/hobbyquaker/openccu-lite/releases).

- **Switching from OpenCCU (Raspberry Pi or VM):** take a backup first, then upload
  `openccu-lite-<product>-<version>.zip` in the OpenCCU WebUI under Settings → Control panel → CCU maintenance → Perform software update.
  Pairings, keys and addons stay; the system takes over names, rooms and functions at its first start.
  Details in [switching.md](docs/switching.md).
- **Switching from a CCU3:** upload `openccu-lite-aarch64-rpi3-<version>-ccu3.tgz` in the CCU3's software update.
- **New install on a Raspberry Pi 3/4:** unpack the release `.zip` and write the `.img` inside it to the SD card.
- **New install as a VM:** import the `.ova` (Proxmox, VMware, VirtualBox and so on); the LXC container is described
  in [install-lxc.md](docs/install-lxc.md).
- **Proxmox VM by script:** as root on the Proxmox VE host, a script creates the VM in one step (`--help` lists
  the options):
  `bash -c "$(wget -qLO - https://raw.githubusercontent.com/hobbyquaker/openccu-lite/main/scripts/install-proxmox.sh)"`
- a new install can (as long as no devices are paired yet) import paired devices, keys, names and rooms from an
  (Open)CCU backup in one step. The backup's BidCos security key comes along as it is (its passphrase is asked as a
  check only, never as a gate; later key changes need it); an HmIP identity bound to another radio module is taken over
  by hmipserver onto this system's module, and the Interfaces page shows how that went
  ([switching.md](docs/switching.md)).
- **Pairing and configuring devices, managing direct links:** install
  [Homematic Manager](https://github.com/hobbyquaker/homematic-manager) from the addon catalogue.

## Updating

On the web interface's *Updates* page: *Check now*, *Download and stage*, *Reboot and install*. Or as root over SSH:
`occulited update check` says whether a newer release is out, `occulited update install` installs it - after a backup
to the configured backup targets, with its sha256 checked; `occulited update install <version>` installs a given
version, an older one too. The commands and their options (`--yes` for scripts, `--no-backup`, `--file`, …) are in
[occulited's docs/config.md](https://github.com/hobbyquaker/occulited/blob/master/docs/config.md).

## Documentation

A walkthrough of every page of the web UI, with screenshots (in German): [docs/walkthrough](docs/walkthrough/README.md).
In [`docs/`](docs/) of this repository: moving from and to OpenCCU
([switching.md](docs/switching.md)), what differs from OpenCCU ([aenderungen.md](docs/aenderungen.md), in German),
known issues and what the system does about them
([known-issues.md](docs/known-issues.md)), HmIP local key mode - offline-capable, radio module swaps without eQ-3's key
server ([lokaler-schluesselmodus.md](docs/lokaler-schluesselmodus.md), in German), the Proxmox container ([install-lxc.md](docs/install-lxc.md)),
addons ([addons.md](docs/addons.md)), security ([security.md](docs/security.md),
[threat-model.md](docs/threat-model.md)), privacy – what the system sends to outside sources
([privacy.md](docs/privacy.md)), certificates ([tls-acme.md](docs/tls-acme.md)) and the
porting kit for addon maintainers ([porting-from-rega.md](docs/porting-from-rega.md)). The system
service with the web UI is [occulited](https://github.com/hobbyquaker/occulited); its
[`docs/`](https://github.com/hobbyquaker/occulited/tree/master/docs) describe the metadata, system
and auth APIs, `occulited.json`, the addon manifest and the catalogue.
Recommendations: [recommendations.de.md](docs/recommendations.de.md) (in German).

## Bugs and help

Bugs and wishes, for the firmware and for occulited alike: this repository's
[issue tracker](https://github.com/hobbyquaker/openccu-lite/issues) ([SUPPORT.md](SUPPORT.md));
security problems as described in [SECURITY.md](SECURITY.md). OpenCCU's tracker and forum section
are for OpenCCU — please do not report openccu-lite's problems there.

## License

Apache-2.0 for everything written here; the `occu` components keep eQ-3's terms.

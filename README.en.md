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
The old CCU WebUI has been replaced by a newly developed interface, and the new daemon ["occulited"](https://github.com/hobbyquaker/occulited)
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
- a new install can (as long as no devices are paired yet) import paired devices, keys, names and rooms from an
  (Open)CCU backup.
- **Pairing and configuring devices, managing direct links:** install
  [Homematic Manager](https://github.com/hobbyquaker/homematic-manager) from the addon catalogue.

## Documentation

In [`docs/`](docs/) of this repository: moving from and to OpenCCU
([switching.md](docs/switching.md)), the Proxmox container ([install-lxc.md](docs/install-lxc.md)),
addons ([addons.md](docs/addons.md)), security ([security.md](docs/security.md),
[threat-model.md](docs/threat-model.md)), privacy – what the system sends to outside sources
([privacy.md](docs/privacy.md)), certificates ([tls-acme.md](docs/tls-acme.md)) and the
porting kit for addon maintainers ([porting-from-rega.md](docs/porting-from-rega.md)). The system
service with the web UI is [occulited](https://github.com/hobbyquaker/occulited); its
[`docs/`](https://github.com/hobbyquaker/occulited/tree/master/docs) describe the metadata, system
and auth APIs, `occulited.json`, the addon manifest and the catalogue.

## Bugs and help

Bugs and wishes, for the firmware and for occulited alike: this repository's
[issue tracker](https://github.com/hobbyquaker/openccu-lite/issues) ([SUPPORT.md](SUPPORT.md));
security problems as described in [SECURITY.md](SECURITY.md). OpenCCU's tracker and forum section
are for OpenCCU — please do not report openccu-lite's problems there.

## License

Apache-2.0 for everything written here; the `occu` components keep eQ-3's terms.

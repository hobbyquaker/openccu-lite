# openccu-lite

*English — the German version is [README.md](README.md).*

> openccu-lite is under development. Much of it is still untested.
> **Please use it on test systems only.**
>
> **It is aimed at experienced users** who know what they are doing: people who know a CCU from
> the inside (`rfd`, `hs485d`, the HmIP server, radio modules, the RPC protocol, the paramsets, ...).
> There is no ReGaHSS, no programme editor and no Homematic scripts in openccu-lite.

## Documentation

In [`docs/`](docs/) of this repository: moving from and to OpenCCU
([switching.md](docs/switching.md)), the Proxmox container ([install-lxc.md](docs/install-lxc.md)),
addons ([addons.md](docs/addons.md)), security ([security.md](docs/security.md),
[threat-model.md](docs/threat-model.md)), certificates ([tls-acme.md](docs/tls-acme.md)) and the
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

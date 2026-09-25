# openccu-lite

*This is the English version; the German [README.md](README.md) is the primary one.*

> **Alpha software — read this first.**
>
> openccu-lite is in an **alpha** stage. Much of it is untested, some of it is tested on exactly
> one system, and there are bugs — known ones in [BUGS.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/BUGS.md) and others nobody has met yet.
> **Use it on a lab system.** If you are brave enough to put it on the CCU that runs your home,
> arrange a painless way back before you start: a **second SD card** with your working firmware
> (swap cards to go back), or a **clone of the VM** on x86. A backup taken *before* the switch is
> the only way to return to OpenCCU with your data — see [docs/switching.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/switching.md).
>
> **It is for experienced users** who know what they are doing: people familiar with Homematic
> paramsets, with how a CCU works inside (`rfd`, `hs485d`, the HmIP server, the addon machinery,
> lighttpd, the userfs) and comfortable with a shell. There is no ReGaHSS, no programme editor
> and no hand-holding; what you get is a radio gateway with a name store and an administration
> UI, and every automation lives elsewhere.

A Homematic CCU firmware without ReGaHSS: the radio interfaces (`rfd`, `hs485d`, `hmipserver`),
the addon machinery and lighttpd exactly as OpenCCU builds them — and in place of the WebUI and
the ReGa logic engine a small Go service, **`occulited`**, that administers the system and keeps the
one thing every integration still needs from a CCU: device names and rooms.

The system is a radio gateway with a name store. Automation lives where users already run it
(Home Assistant, Smart Home Engine ("she"), Node-RED, ioBroker, …); device management is
[homematic-manager](https://github.com/hobbyquaker/homematic-manager), installed as an addon
with one click.

## Versions and images

openccu-lite has its own semantic version, starting at **1.0.0-alpha.0**; the top bar of the UI
shows it. The images carry the OpenCCU base they are built on in `/VERSION` for the recovery
system. Release artefacts are named `openccu-lite-<product>-<version>.<ext>`:

| Product | Hardware | Artefacts |
| --- | --- | --- |
| `x86_64-ova` | a VM (VMware, Proxmox, VirtualBox) | `….ova`, `….zip` (the update package), `….img` |
| `aarch64-rpi3` | CCU3, Charly, Raspberry Pi 3, CM3 | `….zip`, `…-ccu3.tgz` (the in-place update from a CCU3) |
| `aarch64-rpi4` | Raspberry Pi 4, CM4 | `….zip` |
| `aarch64-rpi5` | Raspberry Pi 5, CM5 (never booted yet, task 32) | `….zip` |
| `lxc-lite_amd64`, `lxc-lite_arm64` | an unprivileged Proxmox LXC container (task 34; radio through LAN gateways or a passed-through HmIP-RFUSB only) | `openccu-lite-lxc-amd64-….tar.xz`, `openccu-lite-lxc-arm64-….tar.xz` (the CT template) |

openccu-lite runs in the lab on an x86_64 VM, a Raspberry Pi 4 with an HmIP-RFUSB and a Charly
(Raspberry Pi 3 B with an RPI-RF-MOD); a release has to pass
[docs/hardware-checklist.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/hardware-checklist.md) first.

## Features at a glance

Beside names, rooms, addons, network and device firmware (see *occulited in one paragraph*):

- **Log page:** the journal with filters by unit, tag, severity and text, following live and
  downloadable as text or JSON. The source *All / System / Kernel* shows the kernel log with
  since-boot timestamps as `dmesg` does; a boot menu jumps to earlier boots as far as the journal
  holds them.
- **Boot timeline** on the Services page: every unit of the boot as a bar, the critical chain, the
  comparison with the previous boot, export as SVG and JSON. The last ten boots are kept on every
  system.
- **Where the journal lives**, selectable: in RAM only (the default on the SD-card products); in RAM
  with copies to the userfs every 6 hours and at every shutdown, so the card sees one batch per
  interval and a reboot loses nothing; or straight to the userfs (the default on the VM and in
  containers).
- **Status LED** (RPI-RF-MOD): occulited is its only writer, and `hss_led` is no longer in the image.
  Solid blue when everything is fine, as on the CCU3; yellow fast without a network, red for a
  radio or service that is down, cyan for a system update. Order, colours and patterns are
  configurable, with a night mode and *Locate*; Home Assistant or Node-RED set the LED through the API
  with a token that may do only that.
- **Backups to network shares:** the nightly backup is made once and copied to every enabled target
  — a USB directory, NFS, CIFS/SMB or SSH (an SFTP upload from occulited, with a key made on the system
  and a pinned host key). Every target shows its state, has a write test and is mounted again after a
  failure; old backups are deleted only after a verified delivery.
- **Status page warnings** come from occulited. An administrator silences a warning for 1, 7 or 90
  days, and the silence ends early once the warning clears and comes back.

## Security

A CCU hands device control to the LAN on 2001, 2010 and 2000 without a login, runs addons, their
CGIs and the radio daemons as root, and protects an addon page only as well as the addon checks
itself. openccu-lite turns each of these defaults around.

### What the network can reach

The radio daemons and occulited listen on the loopback only; lighttpd is what faces the LAN. The
firewall is one list of INPUT rules in the order they are checked, with the policy `DROP` for IPv4
and IPv6: incoming traffic no rule accepts is dropped. What a switched-on feature needs, the system
adds itself as a rule with its owner — and a comment saying why it is there — and takes out again
when the feature is switched off; every rule can be edited, moved or deleted. A change has to be
confirmed within 60 seconds, or the system puts the previous rules back by itself. A system that
arrives from OpenCCU takes its `firewall.conf` over into this list once, with the same access as
before.

| Service | Port | Bound to | From outside |
| --- | --- | --- | --- |
| lighttpd | 80, 443 | LAN | web UI and API with a login, addon pages behind the login gate; a rule from the local networks |
| occulited | 8183 | `127.0.0.1`, enforced | only through lighttpd |
| rfd (BidCos-RF) | 32001 | `127.0.0.1` | only through lighttpd with classic RPC |
| hmipserver (HmIP-RF) | 32010 | `127.0.0.1` | only through lighttpd with classic RPC |
| hs485d (BidCos-Wired) | 32000 | `127.0.0.1` | only through lighttpd with classic RPC |
| hmipserver (VirtualDevices) | 39292 | all addresses | closed by the firewall; through lighttpd with classic RPC |
| classic RPC through lighttpd | 2001, 2010, 9292, TLS 42001, 42010, 49292; 2000/42000 only with hs485d | LAN | off by default; on System → Remote access, plain and TLS apart, with or without a user name and password |
| hmipserver (HmIP access point updates) | 9293, 9294, UDP 43438 | all addresses | open while HmIP-RF runs |
| network discovery | multicast, SSDP 1900, eQ-3 discovery | – | open, as rules of their own that can be edited |
| multimacd | – | no socket, no network | – |
| sshd | 22 | LAN | only with SSH switched on, only from local networks |
| ReGaHSS 1999, 8181 | – | – | do not exist (8183 is occulited's since task 182) |
| addons | their ports | as the addon binds them | every declared port a switch of its own on the Addons page, closed by default |

One switch per port means an MQTT broker's TLS listener can be open while its plaintext port stays
closed.

### Who runs as whom

- **occulited** runs as its own unprivileged user `occulite`; the HTTP side, the attack surface, can
  do nothing an unprivileged user cannot. What needs root — writing `/etc/config`, the firmware's
  scripts, `systemctl`, addon accounts — goes over a unix socket (`root:occulite 0660`) to a helper
  with a closed list: programs by name, write paths by prefix, and typed single operations that
  check their input at the boundary (the root password only as a finished hash, the certificate only
  as a chain with its matching key, a file for `X-Sendfile` only as a passed descriptor). Commands
  are argument lists, never shell strings, and every refusal is in the journal.
- **Addons** run confined by default as their own user `addon-<id>`: `ProtectSystem=strict`,
  `NoNewPrivileges`, no capabilities, their own mount and PID namespace with a private `/tmp` and
  `/var/run`, writable only in their own directories. What an addon needs beyond that —
  capabilities, groups, paths, data directories, ports — its catalogue entry declares, and the
  Services page shows it. An addon that declares nothing is confined all the same and marked
  *undeclared*. Root is a deliberate opt-out labelled unsafe; addons installed before the switch
  stay root once, until the user confines them. An addon's CGIs run as its user, not as root under
  lighttpd.
- **File ownership:** after every update through the UI a confined addon gets its files back; what a
  direct `install_addon` leaves behind as root is reported on the Status page with *Fix ownership*.
  occulited takes over data directories outside the addon's tree (`/usr/local/<id>` or declared ones)
  with guard rails: never a shared directory, never another addon's, never through a symlink.
- **Root addons** lose `CAP_SYS_ADMIN`: `mount -o remount,rw /` fails and the system partition stays
  read-only. So that addons such as jp-hb-devices keep working unchanged, `/firmware/rftypes` is
  writable from boot (an overlay on the userfs). An addon that really has to mount declares
  `sys_admin`, and the Services page says so.
- **AppArmor:** profiles for occulited, its helper, lighttpd and homematic-manager; an addon may ship
  a profile of its own. No profiles are generated for third-party software — a wrong profile is worse
  than none.
- **The system's certificate** (chain and key) is `root:certs 0640`. Confined addons are in the `certs`
  group, so a broker or web server offers TLS with the system's certificate.
- **The radio daemons** have users of their own: `rfd`, `hmipserver`, `multimacd`, `hs485d`, plus
  `hmlangw`. udev gives the device nodes resource groups (`raw-uart`,
  `eq3loop`, `mmd-bidcos`, `mmd-hmip`), and every unit may open only its own (`DevicePolicy=closed`).
  No capabilities, `ProtectSystem=strict`; the root preparation runs before the start, including an
  ownership repair at every start, since a `.sbk` restore is always root-owned. multimacd gets its
  real-time priority through `LimitRTPRIO=99` instead of `CAP_SYS_NICE`. A bug in hmipserver's JVM
  thus reaches neither rfd's BidCos key nor multimacd's UART, and `rfd.conf` with the LAN gateway keys
  is `root:rfd 0640`, unreadable to addons. The same holds in the LXC containers, and there is no
  fallback to root. The radio module's firmware is flashed as multimacd's user in a transient unit
  that may open the module's node and nothing else. Not tested in the lab: HB-RF-USB/ETH, a BidCos
  LAN gateway, an HM-CFG-USB-2, BidCos-Wired and LAN-gateway mode.

### Login, sessions and addon pages

- **Local accounts** with argon2id, the roles `admin` and `user`, a lockout after failed attempts per
  name and per address, a forced password on first boot, a session list with *sign out everywhere*.
  There is no password reset by mail; `occulited passwd <user>` on the console is the way back in. A
  system runs without any login only in a deliberately chosen mode for a trusted network.
- **The session cookie** is `__Secure-occulite_session` (`Secure`, `HttpOnly`, `SameSite=Lax`) over
  HTTPS and `occulite_session` over HTTP, so a login over one scheme never locks the other out.
- **The login gate:** before any request under `/addons/` — static files, CGIs, backends behind a
  proxy, WebSockets — lighttpd checks that a live session is behind it; without one the login comes
  up. On a CCU a CGI whose author forgot the session check is open.
- **`X-Occulite-Session`:** the gate passes the session id it validated to the addon in this header.
  lighttpd removes a client-sent header of that name on every request and every socket, in any
  spelling (`X_Occulite_Session` included); if that fails, the gate answers `500`. So the header
  never comes from the client, and an addon has no cookie to parse. Who the user is and which role
  they have is answered by `GET /api/auth/v1/state`.
- **Addons take over the system's session** instead of asking for a login of their own: RedMatic's
  Node-RED editor and homematic-manager open without a second login.
- **No session id in URLs:** embedded addon views and new tabs no longer carry `?sid=`, which ends up
  in the history, in bookmarks and in `Referer`. Only an addon that explicitly declares it still gets
  it; the session check of classic settings pages is answered by the `tclrega.so` shim.
- **OpenID Connect** (Authentik, Keycloak, Authelia, Zitadel, Pocket ID, …): authorization code with
  PKCE, set up through discovery with an issuer, a client id and a secret. Every login through the
  provider needs an account of the same name on the system; the match is by user name only, and the role
  comes from the account. The login page shows *Sign in with …* under the password form; password
  login beside it can be switched off, and then `occulited auth password-login on` on the console is
  the way back. Two-factor authentication is the provider's business.

### API tokens

Programs authenticate with `Authorization: Bearer olt_…`. A token carries 128 random bits, is shown
exactly once, stored only as SHA-256 and revoked on its own; `occulited token` creates one on the
console. Tokens carry **scopes** instead of a blanket role: every route names the scope it needs,
and a token may do only what it was given. The shared token of the addons on the system reads only.
Two scopes are made for one job each:

| Scope | May | For |
| --- | --- | --- |
| `led` | read the status LED's state, set its own override, *Locate* — nothing else | Home Assistant, Node-RED |
| `backup` | create and download backups, synchronously or as an asynchronous job — nothing else | backup integrations, scripts on a NAS |

For the maintainers of backup integrations there is a reusable prompt, `docs/INTEGRATOR-PROMPT.md`.

### Classic RPC (System → Remote access)

Clients configured for a CCU3 or OpenCCU — Home Assistant, ioBroker, homematic-manager as a desktop
app, node-red-contrib-ccu on another machine, FHEM, openHAB — work against openccu-lite unchanged: on
the same ports, with the same login and with callbacks.

- **Two switches, off by default:** plain (2001 BidCos-RF, 2010 HmIP-RF, 9292 VirtualDevices, 2000
  BidCos-Wired where hs485d runs) and TLS (42001, 42010, 49292, 42000) with the system's certificate.
  lighttpd serves the ports; the interface processes stay on the loopback.
- **Login:** none, or a user name and password for classic RPC only — not the system's accounts, not
  API tokens. Basic auth as on a CCU with authentication switched on, checked by lighttpd. The
  password is typed (at least 12 characters) or generated (32 characters, shown once) and stored
  only as SHA-512-crypt.
- **Firewall:** every open port gets a *Classic RPC* rule from the local networks, as OpenCCU allowed
  them; widen or narrow it on the Firewall page.
- **From OpenCCU:** if its XMLRPC ports were open, classic RPC is switched on afterwards, with the
  same access. If OpenCCU asked for a login (`authEnabled`, with the ReGa accounts, which do not
  exist here), it stays off until a user name and password are set.
- **As on a CCU:** no rights per method, no trace, no lockout after failed attempts. The interface
  processes call the client back at the address it registers; it must be reachable from the system.
  BIN-RPC through lighttpd does not work, as with OpenCCU.
- **Planned: lite-rpc** — requests and events over the web port with API tokens, SSE/WebSocket
  instead of callbacks, with rights per token and a trace.

### Certificates and HTTPS

- **Three ways to a certificate** (System → Certificate):
  - **self-signed**, the default (ten years, host name and address in the SAN);
  - **ACME**, built in with no second process: Let's Encrypt, ZeroSSL (with external account
    binding) or a CA of your own such as step-ca, by HTTP-01 or DNS-01 (Cloudflare, Hetzner, netcup,
    DuckDNS or a script of your own); *Test* runs against the staging environment, the check runs
    twice a day, and the certificate is renewed below 30 days or half its lifetime;
  - **manual**: certificate, chain and key uploaded as PEM or DER, or a key and certificate request
    made on the system — then the key never leaves it.

  After every install lighttpd reloads and the addons of the `certs` group restart. The Status page
  warns 14 days before expiry and after a failed renewal.
- **HTTPS redirect and HSTS** (System → Certificate): the redirect from HTTP to HTTPS is a switch. HSTS
  can be switched on only with a certificate that is not self-signed, with a `max-age` of 7 days by
  default and 730 at most. A question first says what it costs: the recovery system and a system
  update's install phase speak HTTP only and are then reachable only by IP address, and a way back
  to OpenCCU or a reset with a self-signed certificate is locked out under the name until the entry
  expires. **Switching it off** therefore sends `Strict-Transport-Security: max-age=0` for as long as
  the previous `max-age`, 30 days at most, and the page names the names to open once in every
  browser. The same happens before a switch back to self-signed and when a way back to OpenCCU is
  staged.
- **Recovery by IP address:** the recovery system has no TLS. Every way into it — the power menu's
  reboot into the recovery, the notice while an update installs — links to `http://<IP>/`, since HSTS
  never applies to an IP address.
- **From the short name to the full one:** a switch, off by default, redirects `https://<host>/` with
  `302` to `https://<host>.<domain>/`, keeping path and query; together with the HTTPS redirect also
  `http://<host>/` in one hop. A browser then has one name for the system: one cookie, one HSTS entry,
  one saved password. Only `GET` and `HEAD` are redirected, never `/api`, the ACME path, the loopback,
  IP addresses or other names; `302`, not `301`, because a browser keeps a `301`. The redirect applies
  only while the certificate covers the full name, and rests after a rename or a domain change until
  a matching certificate is installed.

### Also

- **No ReGaHSS:** no HM-Script interpreter, no port 8181 or 8183, nothing that runs scripts from the
  LAN.
- **One log:** the system and the addons write to the journal and to no log file; the build fails
  when a shipped configuration names a `.log` file. The only exceptions are the recovery system and a
  system update's install phase, which have no journal; their log is carried into the journal at the
  next boot. lighttpd's access log is off by default. **Remote syslog** sends every journal entry —
  syslog, the units' output, the kernel — as RFC 5424 over UDP to the configured `LOGHOST`.
- **Encrypted backups:** a `.sbk` holds the whole userfs — the BidCos key, the HmIP key material, the
  password hashes, the DNS providers' tokens, the TLS key. Once a recovery code is set up, every
  backup to a share, to USB and as a download is encrypted with age (`.sbk.age` around the unchanged
  `.sbk`) for two keys: the system's own, which is in no backup and opens its own backups without
  asking, and the **recovery code** — short, grouped, with a checksum, generated in the browser and
  never stored on the system —, which opens them on any other system. An unencrypted download asks for the
  password again and is logged. Older backups keep their key, and the page shows which one each
  needs. The recovery system restores plain `.sbk` files only; the emergency kit explains decrypting
  on a PC.
- **Bluetooth** is in the Raspberry Pi images only and off by default (`disable-bt`, the chip fully
  off); switching it on changes `config.txt` and needs a reboot.
- **Default security key:** while BidCos-RF runs with the publicly known default key, the Status page
  warns and leads straight to the key field on the Interfaces page.

## Boot time

The systemd conversion had turned OpenCCU's SysV order into one strictly serial chain: every step
waited for every earlier one, including ones it has nothing to do with. multimacd waited for
hs485d, the radio module detection for a blocking NTP sync, occulited for the radio module,
hmipserver for rfd, and every addon for hmipserver. openccu-lite boots along a dependency graph in
which every unit waits only for what it needs; a CI test fails when a serial link comes back.

| Seconds after the reboot | x86_64 VM | Raspberry Pi 4 | Charly (Raspberry Pi 3 B, CCU3 class) |
| --- | --- | --- | --- |
| Web UI answers | 48.8 → **36.5** | 81.1 → **48.9** | 60.8 → **45.8** |
| hmipserver ready | 67.4 → **55.8** | 108.2 → **95.1** | 111.1 → **97.3** |
| All addons running | 98.7 → **86.9** | 142.2 → **128.1** | 148.1 → **133.3** |

Measured with three plain reboots (`systemctl reboot`) per system, median, counted from the reboot
command, so shutdown and firmware are included; a client polled `/api/system/v1/health` every
0.25 s, and the unit times come from systemd.

- **chrony no longer blocks.** A `ntpdate -b` used to hold the boot for about 10 s (9.8 / 10.5 /
  10.9 s), and without internet at boot chronyd never started at all. Now chronyd starts at once and
  corrects a large first offset itself: 0.1–0.2 s. Whatever needs a correct clock waits for a clock
  gate that opens as soon as the RTC has set a plausible time, chrony has synchronised, or 60 s have
  passed (then with a notice on the Status page). That is the radio daemons, since hmipserver, rfd
  and multimacd hand the system time on to devices. On systems with an RTC it costs nothing; the Pi 4,
  which has none, waited 6 s for NTP while the radio module detection ran anyway.
- **The radio stack starts in parallel.** multimacd no longer waits for hs485d, rfd and hmipserver
  start side by side after multimacd, and the LAN gateways' firmware update and key come before rfd
  and hs485d instead of after the addon initialisation. multimacd is ready 9.5–10.8 s earlier.
- **lighttpd starts right after the network**, beside occulited instead of after it: active 19–24 s
  after the kernel start instead of 32–53 s. While occulited does not answer — at boot, after a
  restart or a crash —, lighttpd serves a static waiting page with the host name and version, light
  and dark, German and English. It asks again every 2 s and reloads the address that was requested
  once occulited is there; API clients get `503` with `Retry-After` and JSON.
- **A countdown bar** appears when the system is rebooted from the web UI. It starts full and empties
  from left to right until the moment the web UI answers again. At the points the browser can see —
  the system stops answering, lighttpd answers, occulited answers — it re-estimates without ever jumping
  back, and lighttpd's waiting page continues the same bar. The expected times first come from the
  measurements per product; after that every system uses the median of its last three reboots per
  phase. A second, slimmer bar then counts down until the radio interfaces are ready, and the
  Status, Interfaces and Services pages show an interface that is still coming up as *starting* with
  the elapsed time instead of as down.
- **Addons start by need.** An addon that talks to the interfaces starts only once hmipserver and rfd
  are ready — hmipserver's unit is active only once its RPC answers —, and no RPC error shows up in
  the addons' logs during boot. An addon that declares `runtime.needs: []` in the catalogue, such as
  Mosquitto, starts right after the network: on the Pi 4 the broker ran 25 s before hmipserver and
  about 40 s earlier than before. An addon without a declaration keeps the safe order. An addon whose catalogue entry declares
  `runtime.start: "early"` copes with interfaces that are not ready yet and starts before them; the Addons page
  switches that off, for all addons or per addon, from the next boot on. No unit has a fixed delay.
- **Shutdown deliberately ends later.** lighttpd now stops after the radio stack, so the system answers
  2.6–3.0 s longer; in exchange, the notice that the system can be unplugged appears only once hmipserver
  has really stopped.
- **What still dominates:** on the Pi 4 the radio module detection (about 21 s), and its firmware
  takes the longest before the kernel; on the Pi 3 class hmipserver's Java start (42 s, against 24 s
  on the Pi 4 and 14 s on the VM). The boot timeline on the Services page shows this for every system
  itself.

## What is where

openccu-lite is three repositories:

| | |
| --- | --- |
| **this repository** | The buildroot tree (a fork of OpenCCU): the products `x86_64-ova`, `aarch64-rpi3`, `aarch64-rpi4`, `aarch64-rpi5`, `lxc-lite_amd64`, `lxc-lite_arm64`, the lite overlay with the systemd units, the package that builds occulited in, the release workflow, `BUILD.md`. |
| [occulited](https://git.lan.raff.rocks/hobbyquaker/occulited) | The system service with its embedded web UI: `cmd/occulited`, `internal/`, `ui/`, `deploy/` (lighttpd wiring, the login gate, the `tclrega.so` shim), `fixtures/` (the conformance corpus of the metadata API). |
| [openccu-lite-addons](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-addons) | The addon catalogue (`index.json`) the system installs from. |

The documentation lives in the maintainer's working repository for now:
[docs/meta-format.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/meta-format.md) and [docs/meta-api.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/meta-api.md) (the metadata store, normative),
[docs/system-api.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/system-api.md) and [docs/config.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/config.md) (the system and auth APIs, `occulited.json`),
[docs/porting-from-rega.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/porting-from-rega.md) and [docs/PORTING-PROMPT.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/PORTING-PROMPT.md) (the porting kit for addon maintainers),
[docs/catalog-format.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/catalog-format.md) (the catalogue format),
[docs/addons.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/addons.md), [docs/security.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/security.md), [docs/switching.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/switching.md) (moving from and to OpenCCU),
[docs/hardware-checklist.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/hardware-checklist.md) (the release gate, D-26), [docs/study-without-rega.md](https://git.lan.raff.rocks/hobbyquaker/openccu-lite-agents/src/branch/master/docs/study-without-rega.md) (the lab evidence).
The roadmap, the decisions, the open bugs and the state of the work are there under `openccu-lite/`.

## occulited in one paragraph

Loopback-only HTTP service behind lighttpd. `/api/meta/v1`: objects keyed by
`<interface>.<address>`, enum trees (rooms, functions, floors), bulk and import/export, an SSE
change stream, one JSON file on disk. `/api/system/v1`: status, interfaces and their subscribers,
services and their units, addons (install/uninstall/update check, the catalogue with a progress
bar), device firmware fetched automatically for paired types, network with a confirm-or-revert
window, firewall in iptables' words, time, log levels and the journal, log. `/api/auth/v1`:
local users with argon2id, sessions shared with lighttpd's gate for addon pages, API tokens for
programs, OpenID Connect, or no login at all for a system alone on a trusted network. The web UI is
embedded; it is the system's shell and shows every addon's own web interface in its menu.

## Building occulited

In the [occulited](https://git.lan.raff.rocks/hobbyquaker/occulited) repository:

```sh
cd ui && npm ci && npm run build && cd ..   # embeds the UI
go build ./cmd/occulited                     # or scripts/build.sh for all three targets
go test ./...
```

Go 1.26 or newer, Node 24. `occulited --root <dir>` runs against a fake filesystem for development; system
commands are only logged in that mode.

## Licence

Apache-2.0 for everything authored here; the `occu` payloads keep eQ-3's terms.

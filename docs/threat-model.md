# Threat model

What openccu-lite and occulited protect, from whom, and where the lines run that an attacker has to cross. It is
written to be read before a change at a boundary, and to be checked against what the code does at every minor
release. The user's summary is [security.md](security.md).

**State:** reviewed against the code of 1.1.0-dev.6 (2026-10-30). It describes the system as it is, not as it should
be: what is missing is named as a check or a residual risk.

- [Scope](#scope)
- [Assets](#assets) — what an attacker is after
- [Actors](#actors) — who attacks, and what they start with
- [Trust boundaries](#trust-boundaries) — the lines and what crosses them
- [STRIDE per boundary](#stride-per-boundary)
- [Trust statements](#trust-statements) — what is deliberately trusted
- [Residual risks](#residual-risks) — known, accepted, and why
- [Audit log](#audit-log)
- [How this document is kept](#how-this-document-is-kept)

## Scope

**In scope:** the image (openccu-lite, the fork of OpenCCU) and everything it ships — occulited and its privilege
helper, lighttpd as the door, the eQ-3 interface processes (`rfd`, `hmipserver`, `multimacd`, `hs485d`, `hmlangw`),
the addon mechanism, the update and backup paths, and the system's own network services (sshd, chronyd).

**Out of scope, named so that nobody assumes otherwise:**

- **The radio protocols themselves.** BidCos-RF's AES and HmIP's pairing are eQ-3's design; this document takes
  them as they are and protects their keys, not their cryptography.
- **The physical system.** Whoever holds it can read the SD card, which carries the keys in clear ([Assets](#assets)),
  and can attach a serial console. Full-disk encryption is not part of the product.
- **The LAN's own security.** A CCU is a LAN device. This document assumes the LAN can be hostile
  ([Actors](#actors)) but does not try to defend the other devices on it.
- **The devices' firmware** and what a paired device does once it is paired.

## Assets

What an attacker wants, most valuable first. Each asset says where it lives, who may read it today, and what is
lost when it leaks or changes.

### 1. The radio keys

| | |
| --- | --- |
| **What** | The BidCos-RF system security key, the HmIP network key, and the HmIP device keys of every device whose sticker was scanned |
| **Where** | `/etc/config/keys` (rfd, 0600); hmipserver's data directory (0700, files 0600), `crRFD/hmip_user.conf` (the network key in local key mode, 0640) and `crRFD/sgtin.map` (0640) on the userfs, in clear because hmipserver needs them that way; every backup carries them |
| **Who reads them today** | root and the daemon that owns each file; occulited through the helper's read list (`sgtin.map` for the key sheet, `hmip_user.conf` for local key mode, the LAN gateways' keys in `rfd.conf`/`hs485d.conf`, never answered); of the accounts, an administrator through the key sheet, which asks for the password every time |
| **Lost when they leak** | Control of the devices, and the ability to impersonate the central to them. A key cannot be revoked: changing the BidCos key re-keys every AES device, and a new HmIP network key means teaching every device in again |
| **Lost when they change** | The system talks to nothing until every device is re-keyed or re-paired |

### 2. Control of the devices

| | |
| --- | --- |
| **What** | Switching, dimming, opening, and reading what the sensors report — the reason the system exists. It is reached through the interface processes' XML-RPC, not only through a key |
| **Where** | The interface processes on the loopback (2001, 2010, 9292), lighttpd's classic RPC ports when they are switched on, lite-rpc and occulited's API |
| **Who reaches it today** | Anything on the loopback, which means every addon; a client on the LAN through lite-rpc with a token of an `rpc` tier, through the Control app's public mode when it is on, or through classic RPC, whose ports are closed by default and carry the CCU's own optional password |
| **Lost when it leaks** | An attacker opens the door, switches the heating, reads when nobody is home — the privacy and safety of the household |

### 3. The system as a foothold in the LAN

| | |
| --- | --- |
| **What** | A small always-on Linux with root, a shell, an outbound path to the internet and a place in the LAN's trusted zone |
| **Where** | The whole image |
| **Who has it today** | root, and anything that reaches root: the helper's callers, an addon run as root |
| **Lost when it leaks** | The LAN's other devices, the household's traffic, and a machine somebody else pays for and controls |

### 4. Credentials and sessions

| | |
| --- | --- |
| **What** | The accounts' argon2id password hashes and passkeys' public keys, the session store (hashes), the API tokens (stored as SHA-256), the OIDC client secret, the ACME account key and DNS provider credentials, the backup targets' credentials (SFTP key, CIFS password), root's SSH password and `authorized_keys`, the classic RPC password, the Wi-Fi PSKs, the TLS private key |
| **Where** | occulited's state directory (`occulite`, files 0600), `/etc/config/shadow` (root, 0640), `/usr/local/etc/ssh/authorized_keys` (root, 0600), `wpa_supplicant.conf` (root, 0600), `server.pem` (root:certs, 0640) — all but the session store and the backup identity are in every backup |
| **Who reads them today** | occulited for its own store; root for the rest; the helper writes the ones occulited may not read; the `certs` group (every confined addon) reads the TLS key |
| **Lost when they leak** | The administrator's session, and with it assets 1 to 3. A leaked token is scoped; a leaked password is not |

### 5. The backups

| | |
| --- | --- |
| **What** | `.sbk` files: the keys, the credentials, the metadata and the addons' configuration — every asset above in one file; `.sbk.age` when encryption is set up |
| **Where** | Downloaded by the browser, or written nightly to a target the administrator chooses (a USB stick, an SMB or NFS share, an SFTP server) |
| **Who reads them today** | Whoever can read that target, and whoever can download one (a session or token with the scope `backup`, a paired program's among them, approved with the administrator's confirmation and limited to its address); an encrypted copy only with the system's identity or the recovery key |
| **Lost when they leak** | Everything above, without touching the system — unless the copy is encrypted |

### 6. The metadata

| | |
| --- | --- |
| **What** | The device and channel names, the rooms and the functions — the household's floor plan in words |
| **Where** | `meta.json` in the state directory, and the metadata API |
| **Who reads it today** | Every account, the local token every program on the system can read, any token with `meta:read`, and the public principal while the Control app's public mode is on |
| **Lost when it leaks** | Privacy: what the home looks like, which rooms exist, when a device was last touched |

### 7. The system's integrity

| | |
| --- | --- |
| **What** | The image and what runs from it: the firmware update path, the addon packages, the catalogue, the device firmware bundles |
| **Where** | The release file staged for the recovery system, `/usr/local/addons`, the catalogue's JSON and its pre-resolved copy, `/firmware` |
| **Who writes it today** | An administrator, through checked SHA-256 sums; an addon within its own tree |
| **Lost when it is subverted** | Everything, permanently: an attacker who installs the next update owns the system after the reboot |

## Actors

Who might attack the system, what each one already has when they start, and what stands in their way today. The
order is how likely each one is to appear in a real installation, not how dangerous they are.

### A1 · Anything else on the LAN

**Starts with:** an address on the same network — another household device, a guest's phone, a smart TV, an IoT
gadget with its own vulnerability, or a laptop somebody carried in.

**Wants:** the assets in order; most attempts here are untargeted scans.

**Reaches today:** the ports the firewall opens — the web server (80, 443) from the local networks, SSH and the
classic RPC ports while they are switched on, the HmIP access points' ports and the discovery ports. On the web port,
without a credential: the login, the open routes (health, version, the SBOM, the ACME challenge) and the client
pairing request, which is rate-limited and needs an administrator's approval (for backups, which hold the radio
keys, also the administrator's password, passkey or fresh login, and the token works only from the address that
asked). Everything else is dropped by the
policy.

**In the way:** the firewall's policy; the login, with argon2id, a lockout per user and per address, and a first
boot that forces an account; the interface processes listening on the loopback only; classic RPC being off until
somebody switches it on.

**Weakest point:** classic RPC is the CCU's own protocol and has no authentication worth the name — its own
password is optional and travels in the clear on the plain ports. Switching it on is a deliberate act, and the
page says so; an attacker on the LAN who finds it on has control of the devices without a login.

**The Control app's public mode is the same boundary, chosen on purpose:** with it on, a request without a session
on the app's paths (lite-rpc, the metadata's reads, the service messages) becomes the public account — one that reads
and operates, never more — so anyone who reaches the web port operates the house: every switch, dimmer and lock the
app shows, but nothing of the administration, the metadata's writes, the accounts or the tokens. The page says it in
plain words, the Status page warns while it is on, and the firewall's rule for the web port decides who reaches it.

### A2 · An addon on the system

**Starts with:** code running on the system, the loopback, and the addon's own files. Whether it runs as its own user
or as root is the confinement mode (confined is the default, root the opt-out).

**Wants:** root, the keys, and the metadata — or simply to stay and be useful for its author's purpose.

**Reaches today:** the loopback, which means the interface processes' XML-RPC and therefore the devices; its own
tree; the local token, which reads names and rooms; its own token's scopes; the system's TLS key (the `certs`
group); and whatever ports the administrator opened for it.

**In the way:** the confinement (its own user, its own tree, the generated unit, the validator's limits on what a
manifest may declare), the helper's allowlist for everything that needs root, the firewall's per-addon rules, and the
catalogue's *untested* mark as a hint to the administrator before installing.

**Weakest point:** an addon run as root **is** root — nothing in the way at all. Confinement escapes have been real
bugs here (the boundary sections list them), and an addon reaches the devices over the loopback whatever its user is.

### A3 · A malicious or compromised update source

**Starts with:** the ability to serve a file the system will install — a catalogue entry, an addon release, a
device firmware bundle, or a system release. Either the source itself is hostile, or a legitimate one was taken
over, or the transport was.

**Wants:** the system's integrity, which is everything else afterwards.

**Reaches today:** what the administrator installs. A system update is checked against the release's published
SHA-256, an addon package against one where its release publishes it; the catalogue's entries point at the releases
the entry names, and the pre-resolved copy of the catalogue only answers what GitHub's API would.

**In the way:** HTTPS to the sources, the checked sums, and the administrator's decision to install.

**Weakest point:** the sum is published by the same party as the file — it proves the download arrived whole, not
that it is trustworthy. Nothing is signed here today.

### A4 · A user account on the system

**Starts with:** a valid login below *administer* (*read*, *operate* or *configure*), or a token whose scopes are
narrower than Full access.

**Wants:** more than the level gives: the keys, the addon settings, root.

**Reaches today:** what the level's scopes allow — the metadata, the status, the log, operating and configuring
devices.

**In the way:** the scope check on every route, the administrator-only routes (only an administrator creates
accounts and tokens), and the confirmation the sensitive routes ask for even inside a valid session (the device key
sheet, an SSH key, root's password, a passkey).

**Weakest point:** an account below *administer* is a person the administrator invited; the model assumes they are not
hostile, but the code must not depend on that. Every route's scope is the line, and a missing scope check is the bug
class to look for.

### A5 · A stolen session or token

**Starts with:** a session cookie taken from a browser, a token copied from a program's configuration, or the local
token, which every program on the system can read.

**Wants:** whatever the session or the token is allowed to do — with a session, everything its account may do.

**Reaches today:** the API, until the session ends or the token is revoked.

**In the way:** `HttpOnly`, `Secure` with the `__Secure-` prefix and `SameSite=Lax` on the cookie, which is scoped to
`/api`; the idle timeout and the absolute lifetime; the sessions list, where a session can be ended; tokens carrying
scopes, an expiry and an address range; the confirmations named under A4, which a stolen session alone does not pass.

**Weakest point:** a token is a bearer credential. Its scopes and its address range are the only thing that limits
it, and `?sid=` — on the API, and the CCU's legacy alias in addon URLs — puts a credential into a link.

### A6 · An attacker from the internet

**Starts with:** nothing on the LAN — until somebody forwards a port to the system, publishes it through a reverse
proxy, or the router has UPnP on.

**Wants:** all of it, from anywhere, at scan speed.

**Reaches today:** whatever was forwarded. The system does not ask for this and nothing in it opens a port to the
internet by itself; the firewall's automatic rules for the web server, SSH and classic RPC are for the local networks.

**In the way:** the same as A1, plus HTTPS with a real certificate where ACME is used, and HSTS where it is on.

**Weakest point:** the classic RPC ports (A1) are the worst thing to forward, and a forwarded plain port 80 or 2001
hands over the credentials with the first request. The Control app's public mode (A1) forwarded to the internet puts
the house's switches on it without a login; the Remote access page says never to combine the two.

### A7 · Within radio range

**Starts with:** a radio and a place near the house.

**Wants:** to control devices, to listen, or to jam.

**Reaches today:** what the radio protocols allow — outside this document's scope ([Scope](#scope)); the keys are
what this system contributes to that.

**In the way:** the AES key on the BidCos side, the HmIP pairing, and the keys never leaving the system in clear
(except in an unencrypted backup and on the key sheet, both deliberate and both behind a login).

**Weakest point:** a system that never had its BidCos security key set uses the default key, which everyone knows.
The Status page warns about it while a BidCos device is paired, and the Keys page sets it.

### A8 · Physical access

**Starts with:** the system in hand.

**Reaches:** the SD card and the serial console, and with them every key in clear.

**In the way:** nothing — this is out of scope ([Scope](#scope)) and is stated here so that no other control is
assumed to survive it.

## Trust boundaries

Where something less trusted hands data or a request to something more trusted. Each line says what crosses it,
what checks the crossing, and what has gone wrong there before — the bugs are listed because this is where they
keep appearing.

```
        LAN / internet
              │  B1: TLS, the firewall, the login
              │  B1b: an addon's web ingress (PROXY socket)
        ┌─────▼─────┐
        │ lighttpd  │◀── B5a: an addon's static files and its CGI
        └─────┬─────┘
              │  B2: the loopback, the session gate, the session header
        ┌─────▼─────┐        B6: XML-RPC on the loopback   ┌──────────────────┐
        │ occulited │◀──────────────────────────────────▶ │ rfd, hmipserver, │
        └─────┬─────┘                                      │ multimacd, hs485d│
              │  B3: the unix socket, the group, the       └──────────────────┘
              │      operation allowlist                            │ B6b: the key files
        ┌─────▼─────┐                                               ▼
        │  helper   │  B4: what root does on behalf of a request   the radio
        └─────┬─────┘
              │
            root ─── B5b: an addon's own user, tree and units
              │
              └────── B7: the catalogue, the releases, eQ-3's firmware server, ACME, NTP
                      B8: the staged update the recovery system installs at the next boot
```

### B1 · The LAN ↔ lighttpd

**Crosses:** every request from a browser or a client: the shell, the API, lite-rpc, addon pages, classic RPC, the
ACME challenge, the client pairing request.

**Checked by:** the firewall (policy DROP, one rule per feature that wants a port); TLS where it is switched on, with
HSTS and the HTTP redirect as options; lighttpd's own parsing and limits (60 s read idle, 360 s write idle, a request
size limit, small caps in front of the routes that take no upload); the login, the lockout and the session cookie's
flags; the response headers. With the Control app's public mode on, the login is not asked for on the app's paths:
the public principal answers there, held to its level, and to nothing else.

**Has gone wrong here:** listeners bound to every interface instead of the loopback; lighttpd's slow-client limits
left at upstream's 20 minutes with no request size limit; a reverse-proxied body without `Content-Length` buffered
whole in RAM.

**B1b, an addon's web ingress:** an addon whose manifest declares `runtime.web_ingress` (lite-addon-wireguard ends a
peer's tunnel inside its own process) forwards the peer's requests to lighttpd through
`/run/lighttpd-addons/<id>/proxy.sock`, a Unix socket that speaks the HAProxy PROXY protocol. Had it connected to
`127.0.0.1:80`, every tunnel request would have come from the loopback, which the system trusts (the classic RPC
login, the HTTPS redirect and lite-rpc's token ranges exempt or allow it). Through the socket, `mod_extforward` makes
the peer's address the connection's address before the request is read, so everything B1 and B2 key on the client's
address — the lockout, a token's ranges, the gate, the journal — sees the peer; a tunnel address counts as a local
network, as a LAN address does.

**Checked by:**

- the socket's directory, `www-data:addon-<id> 0750`: lighttpd binds the socket there (0666) and only the addon's
  confinement group reaches it. occulited makes the directory (the helper's `ingressdir` operation) when it renders
  the block and before every start of the addon's unit, and the fork's `lite-lighttpd-addon-socket` from
  `lighttpd-prepare.service` does it again as a safety net, so the order of boot does not matter; while the group is
  missing the directory is `www-data`'s alone;
- the block's range check (403 for any claimed address outside the ranges the manifest declared — the loopback, a
  LAN address, a PROXY `LOCAL` header's socket path) and occulited's own (`403 ingress-range`, journaled, when the
  block's `X-Occulite-Ingress: <id>` comes with an address outside that addon's ranges);
- the manifest validator, which refuses ranges that hold the loopback, link-local or multicast addresses, or are wider
  than /8 (IPv4) or /32 (IPv6);
- the block itself, rendered by occulited from the stored manifest into
  `/etc/config/lighttpd/occulite-ingress-<id>.conf` at every install, uninstall, start and reload of lighttpd, so it
  exists exactly while the addon is installed. lighttpd is restarted, not reloaded, when a socket comes or goes: a
  graceful reload hands a dropped socket on and never binds it again (measured);
- on the socket: no TLS of lighttpd's (a tunnel encrypts; an addon that terminates TLS itself sets the PROXY v2 SSL
  TLV and lighttpd treats the request as `https`), no HTTPS redirect, no HSTS, `extforward.headers` emptied so a
  client-sent `X-Forwarded-For` is not taken, a client-sent `X-Occulite-Ingress` removed, and otherwise `webui.conf`
  as on the LAN sockets — the session gate, the security headers, the body limits. A connection without the PROXY
  header is closed unanswered; a PROXY header on a LAN port is a 400.

The tunnel itself is the addon's (B5): its peers are the keys the administrator made or imported.

### B2 · lighttpd ↔ occulited

**Crosses:** the proxied request, and with it the credential the gate validated (`X-Occulite-Session`: a session
id, its legacy alias, or an API token sent as `Authorization: Bearer` with the scope `addon:<id>`, with
`X-Occulite-Auth` saying which and `X-Occulite-Token` naming a token), the client's address (`X-Forwarded-For`:
lighttpd's element, the last one — a client-sent header is removed before lighttpd adds its own; through an addon's web
ingress, B1b, that element is the address the addon claimed, and `X-Occulite-Ingress` names the addon) and the
protocol (`X-Forwarded-Proto`).

**Checked by:** occulited listening on `127.0.0.1:8183` only; the gate script, which validates the session — or the
token against the token mirror (`/run/occulite/gate-tokens`, hashes only: the segments it opens, its expiry, its
ranges) — before an addon page is served and **removes a client-sent session or identity header** before it sets its
own; the global magnet script, which removes those headers and a client-sent `X-Forwarded-*`/`Forwarded` everywhere
the gate does not run; occulited trusting the forwarded headers only from the loopback. A token's other scopes give
nothing at the gate, and a token accepted there opens no API route beyond what its scopes say.

**Has gone wrong here:** the gate itself; a client-sent `X-Forwarded-For`, whose first element occulited took as the
client's address — which let a client dodge the lockout by address and a token's address range, and decided the
loopback-only route on a forged address (fixed: the last element, from the loopback only, and the header removed in
front). The rule to keep: anything a client may send and lighttpd may also set has to be removed before it is set.

### B3 · occulited ↔ the privilege helper

**Crosses:** one operation per request over `/run/occulite/helper.sock` (root:occulite, 0660) — a command from the
program list, a file write under an allowed prefix, a read of an exact path, or one of the named operations.

**Checked by:** the socket's group; `priv.Policy` (`internal/priv/proto.go`), which is an allowlist of programs with
their argument shapes, write prefixes, exact read paths and exact paths per named operation; and each named
operation's own check **at the boundary**, not only in the caller (the key is parsed again, the certificate is parsed
again, the pid must be an `sshd-session`). A request that carries a field its operation does not use is refused and
logged.

**The helper's operations, for reference:**

| operation | what it admits |
| --- | --- |
| `run` | the programs on the list (`systemctl`, `systemd-run`, `kill`, `ip`, `udhcpc`, `crypttool`, `install_addon`, `restoreBackup.sh`, `createBackup.sh`, the init and addon rc.d scripts, …), each with the argument shapes occulited builds: a verb table for `systemctl` (never `link`, `edit`, `set-environment`; `enable`/`disable`/`mask` only `--runtime`), two transient units for `systemd-run`, a pid the helper inspects for `kill`, one action word for the scripts, an archive under the backup or staging directory for `restoreBackup.sh`; a confined addon's `info`, `init` and `uninstall` run as the addon's user. With `--root` other than `/` nothing runs |
| `write`, `rename`, `chmod`, `chown`, `remove` | paths under the write prefixes (`/etc/config/`, `/usr/local/etc/config/`, `/usr/local/tmp/`, `/run/occulite/`, the update markers, …); renames only out of the daemon's staging directory, so big files never travel through the socket. **Outside every generic operation:** the files of the named operations; what root runs or obeys — an addon's rc.d entry, the addon web trees and what their links lead to, the policy drop-ins `addon-policy/<id>.conf`, `.needs`, `.start`; the addons' own directories (`/usr/local/addons/` is no prefix); a root addon's config directory under `addons/<id>` |
| `read` | exact files (`ReadPaths`): the regadom, `netconfig`, `rfd.conf`/`hs485d.conf` (the gateway keys never reach an answer), `crRFD/hmip_user.conf`, `crRFD/sgtin.map` (a key only through the confirmed key sheet), `classic-rpc.htpasswd`, `wpa_supplicant.conf`; hmipserver's `*.ap`, `*.apkx`, `*.bbkx`, `*.dev` for local key mode's snapshot. `/etc/config/shadow` is not on it |
| `rootpassword` | one crypt hash into the password field of the `root:` line of `shadow` (no `:`, no newline); the file never crosses the boundary |
| `writecert`, `readcert`, `removecert` | `server.pem` and its two markers: a certificate chain plus the one key of its leaf, or refused; the read answers the certificate blocks and the marker, never the key |
| `addonuser` | appends `addon-<id>` to `/etc/passwd` and `/etc/group` in place (uid from 30000, home derived from the name, shell `/bin/false`, no `shadow` line) |
| `addon-policy-file`, `addon-enable`, `addon-remove`, `addon-home-remove`, `addon-fragment` | renders the unit drop-in and `.needs`/`.start` itself from a checked decision (the addon's own uid from 30000, no root-equivalent group or capability for a confined addon, no value that adds a line); enables, disables and removes an addon's rc.d entry and web link; removes an emptied addon directory; installs the validated copy of an addon's lighttpd fragment |
| `owntree` | gives one addon's standard and data directories to the uid the passwd file has for `addon-<id>`, only when the drop-in the helper rendered confines the addon to that uid; the walk (`internal/ownwalk`) works by descriptors, follows no link, crosses no mount, never gives away a device node |
| `ingressdir` | `/run/lighttpd-addons/<id>/`, `www-data:addon-<id> 0750` |
| `authkeys-read`, `authkeys-write`, `ssh-end`, `ssh-keyonly` | root's `authorized_keys` (public keys only; occulited's section replaced, each key checked again: a modern type, no options, one line); SIGTERM to one `sshd-session` of a connection; the two lines that refuse password logins |
| `openfd` | opens the file an addon's CGI names in `X-Sendfile` under `/usr/local/tmp/` with `O_NOFOLLOW`, checks it through `/proc/self/fd`, passes a regular file back as a descriptor (`SCM_RIGHTS`) |
| `smartctl` | exactly `smartctl -j -H -A -i <device>` for a whole SATA/USB/NVMe disk, 60 s |
| `listlogs` | the paths, sizes and times of log files in a directory under `/usr/local/addons/` or `/var/log/`, never their content |
| further named operations | each on its own fixed paths or devices: the firewall's load, confirm and revert (`firewall-load`, `firewall-confirm`, `firewall-revert`), a network share's mount (`netmount`, `netunmount`), a USB stick's format and eject, the radio module's flash (`flashcopro`), the bootloader's staging, the status LED, the CCU's leftovers' removal |

**Has gone wrong here**, each fixed:

- the shell allowlist was a prefix test;
- write paths ran outside the helper;
- the program list checked names and passed the arguments through — `systemd-run /bin/sh -c …` was root;
- the symlink operation checked the link and not its target, and a write followed any link;
- the files of the named operations (`shadow`, `server.pem` and its markers) lay under the `/etc/config/` write
  prefix, so the generic write, rename, chmod, chown and remove reached them whole;
- the same prefixes, and `/usr/local/addons/`, reached files root later runs or obeys: rc.d, the addon web trees' CGIs,
  and the policy files the generator installs as the unit's drop-in (`User=`, `ExecStartPre=+`);
- a root addon's own directory (`bin/`, `node_modules`) and its config directory were under write prefixes;
- the ownership walk gave `/usr/local/addons/<id>` to `addon-<id>` whenever that account existed, confined or not;
- a confined addon's rc.d script — a link into its own tree — ran as root for `info` (at every addon listing),
  `init` and `uninstall`;
- a manifest could put a confined addon into the `occulite` group, the socket's group.

**The rule:** the unprivileged side assembles, the helper decides. Anything the helper accepts because "occulited
would not send that" is a bug waiting to be found.

### B4 · The helper ↔ root

**Crosses:** what the helper actually does — writing a file, running a program, signalling a process.

**Checked by:** the operation's own narrowness. A named operation exists so that a general one does not have to:
`/etc/config/shadow` is never readable by occulited because the helper rewrites one field of one line;
`authorized_keys` is written as a whole section rather than by a general file write; an addon's systemd drop-in is
rendered by the helper from the decision the daemon sends, never written as the daemon's text; an addon's emptied
directory is removed by an operation that removes nothing with content in it. Every path is resolved by the helper
itself; a symlink is followed only when it is the image's (root's, in a directory only root writes, not on removable
media), the resolved path is checked against the same lists, and the helper then acts through directory descriptors
with `O_NOFOLLOW` at every component, so a link swapped in after the check is an error, not a detour.

**Has gone wrong here:** X-Sendfile files opened by occulited itself, outside the boundary; the ownership repair as a
`chown -R` that followed a link swapped in mid-walk; the addon account written with busybox `adduser`, which failed on
the read-only `/etc`.

**Watch:** every new general capability (a new program on the list, a new write prefix) widens this line for
everything, not only for the feature that asked for it.

### B5 · The system ↔ addons

**B5a, an addon's HTTP side:** its static files and its CGI under `/addons/<id>/`, and its lighttpd fragment. lighttpd
runs as `www-data`; the fragment is a root-owned copy occulited validated against an allowlist (no `include_shell`, no
socket, a proxy target on this system only — the copy, never a link into the addon's directory); the files are served
by occulited as `occulite` through `os.Root`, which follows no link out of the addon's tree; a `.cgi` runs through
occulited, as the addon's own user where it has one. The gate (B2) requires a live session or an `addon:<id>` token
first.

**Has gone wrong here:** lighttpd ran as root, read a confined addon's fragment through a link, and served its www with
root's rights.

**B5c, an addon's web ingress** (B1b): an addon that declares `runtime.web_ingress` may tell lighttpd who a request is
from — inside the ranges it declared and nowhere else. The socket's directory is the gate (its confinement group
alone), the socket trusts the PROXY header and nothing else, lighttpd and occulited hold the claimed address to the
ranges, and what the addon claims inside them is its own doing: a compromised ingress addon could claim another of its
peers' addresses (R10). Every other confined addon reaches lighttpd only as the loopback.

**B5b, an addon's system side:** its own user and group, its own tree under `/usr/local/addons/<id>` (0751
directories, 0640 files, the www tree readable), the unit the generator writes from the rc.d script, the stored policy
and the manifest's `runtime` block, the ports it declares, its own token, and the local token.

**Checked by:** the confinement; the manifest validator (no root-equivalent capability or group for a confined addon,
`CAP_NET_ADMIN` included; the `usbstorage` group only when declared); root addons without `CAP_SYS_ADMIN` unless they
declare it; the helper for anything privileged; the firewall for its ports; the catalogue's marks (*untested*,
*undeclared*) as information for the administrator.

**Has gone wrong here:** X-Sendfile served outside the boundary; an addon's own unit file gave it root (a unit in the
addon's tree was linked by the generator; a `+` command ran as root — the generator now reads nothing from the tree);
every addon's tree was world-readable; the confined addon's rc.d script ran as root (B3); a manifest could declare
root-equivalent capabilities and groups.

**The residual line:** an addon reaches the interface processes over the loopback whatever its user is — B6 does not
distinguish callers. An addon run as root is root by definition.

### B6 · occulited (and the addons) ↔ the eQ-3 interface processes

**Crosses (B6):** XML-RPC and BIN-RPC on the loopback — `init`, `listDevices`, `putParamset`, `setValue`, the
subscriptions, and the events the processes send back to whoever registered.

**Crosses (B6b):** the key files and the configuration occulited writes for them, and the coprocessor's firmware
during a flash.

**Checked by:** the loopback, and nothing else. There is no authentication on these ports. The processes are eQ-3's
binaries; each runs as its own user (`rfd`, `hmipserver`, `multimacd`, `hs485d`, `hmlangw`) with an empty capability
set, `NoNewPrivileges`, `ProtectSystem=strict` with its own files writable, and restricted address families.

**The rule:** anything on the loopback is as good as the interface processes' owner. That is why an addon's
confinement does not stop it from switching a device, and why classic RPC is a switch and not a default. lite-rpc,
which carries the API's tokens and scopes, is the authenticated way to these processes from the LAN.

### B7 · The system ↔ the outside sources it calls

**Crosses:** the addon catalogue and its pre-resolved copy, the addon releases it points at, the openccu-lite release
feed, eQ-3's device firmware server and HmIP key server, the ACME directory of the chosen CA and the DNS provider's
API, the OIDC provider, NTP, and the remote syslog host where one is set.

**Checked by:** HTTPS with the system's trust stores and TLS 1.2 at least; the published SHA-256 of a release, and of
an addon package where one is published; the ACME account key and the challenge; the administrator's decision to
install anything at all. Nothing here is signed by a key this system holds.

**Watch:** these are the only outbound paths, and each one is a place where a hostile answer becomes local data
(A3). The parsers on this side — the JSON of the catalogue and the feed, the firmware bundle's `info` — are the ones
a fuzz test should see first.

### B8 · The running system ↔ the recovery system

**Crosses:** a staged release file and the marker that arms the install; the recovery system writes the boot and
root partitions at the next boot and keeps `/usr/local`.

**Checked by:** the file's kind (from its content) and checksum when it is staged, the space it needs at staging and
at install, the administrator's confirmation, and the recovery system's own checks of kind, board and space.

**Watch:** this is the one path where a file written today becomes the whole system tomorrow. Whoever can stage a
file and arm the marker owns the system after the reboot, without ever being root while the system runs.

## STRIDE per boundary

Six questions per line: spoofing, tampering, repudiation, information disclosure, denial of service, elevation of
privilege. **What stands in the way** is what the code does today; **to check** is what a review and its tooling have
to confirm. The [audit log](#audit-log) says which rows were checked and what came of them.

### B1 · The LAN ↔ lighttpd

| | Here that would be | In the way today | To check |
| --- | --- | --- | --- |
| **S**poofing | Answering as the system (ARP or DNS in the LAN), or using a stolen cookie (A5) | TLS with a real certificate where ACME runs; the cookie's flags; the lockout | Whether a self-signed system — the default — gives the browser anything to pin at all; what HSTS does after a way back to OpenCCU |
| **T**ampering | Changing a request in flight on the plain port; CSRF from another site | HTTPS and the redirect as options; `SameSite=Lax`; the `Origin`/`Sec-Fetch-Site` check and the `X-Occulite-Request` header on every state-changing call with the cookie alone | Whether any GET changes state |
| **R**epudiation | "It was not me who switched the heating" | The journal: logins, refusals and lockouts at Info/Warn with name, method and address; every system change with `user` and `remote` | That a new state-changing route logs its caller |
| **I**nformation disclosure | Reading the API without a login; an error page that says too much | The scope check per route; the login; `no-referrer`; the open routes are one list (`open()` in `internal/httpapi/auth.go`) | That list, whenever a route is added to it |
| **D**enial of service | Filling the login, the upload or the log stream | The lockout per user and per address; lighttpd's limits; a size limit on every body; the pairing request's rate limit | The follow stream's per-session cost |
| **E**levation | Reaching an administrator's route below *administer*, or with no session at all | The scope check, deny by default; the confirmations | Every route's scope, mechanically (`TestRouteTable` walks the mux) |

### B2 · lighttpd ↔ occulited

| | Here that would be | In the way today | To check |
| --- | --- | --- | --- |
| **S**poofing | A client sending `X-Occulite-Session`, `X-Occulite-Auth`, `X-Occulite-Token` or `X-Occulite-Ingress` itself, or faking `X-Forwarded-For` to dodge the lockout or a token's address range | The gate and the global magnet remove a client-sent copy of each before anything sets its own, and a client-sent `X-Forwarded-*`/`Forwarded`; occulited takes only the last element of `X-Forwarded-For`, and only from the loopback; only lighttpd reaches 8183; through the ingress, the claimed address is held to the manifest's ranges | That both removals are still in place after any lighttpd config change — this is the bug class |
| **T**ampering | Changing the proxied body or the path | The loopback; lighttpd is the only writer; no rewriting of `/api/` or `/addons/`; `url-path-2f-decode` off | — |
| **R**epudiation | — | The request log names lighttpd's address for the client | — |
| **I**nformation disclosure | An answer meant for one session served to another | No cache module; `Cache-Control: private, no-cache` where an answer sets none of its own; only content-hashed assets are `immutable` | Any route that answers the same bytes to everyone |
| **D**enial of service | A slow client holding a proxy connection | lighttpd's limits; occulited's read-header timeout (10 s) and idle timeout (120 s) | The long-lived answers (the change stream, the log follow): how many a session may hold |
| **E**levation | Reaching the API without passing the gate | The API's own session check — the gate is for the addon pages, not a substitute | That no route trusts the gate alone |

### B3 · occulited ↔ the privilege helper

| | Here that would be | In the way today | To check |
| --- | --- | --- | --- |
| **S**poofing | Another process on the system calling the helper | The socket is root:occulite 0660 — the group is the line; a manifest cannot put an addon into it | Which users are in `occulite` |
| **T**ampering | A request that carries more than its operation should | Every operation refuses the fields it does not use; one argument shape per program | A new operation's field list |
| **R**epudiation | — | The helper logs what it refuses, once per request, and the daemon logs what it asked for | — |
| **I**nformation disclosure | Reading a file through the helper that the daemon may not read | `ReadPaths` is a list of exact files; `/etc/config/shadow` is deliberately not on it; the answers carry only what the page shows | Each new read path, against what the page actually needs |
| **D**enial of service | A request that never ends, or a flood | Each connection in its own goroutine with the caller's deadline; per-operation timeouts | — |
| **E**levation | A path or a program that is wider than intended | The policy's exact paths and prefixes; the argument shapes; the checks at the boundary | Every prefix, read as an attacker would: what is under it that an addon can write, or root later runs? Every new command line needs its shape, or the helper refuses it |

### B4 · The helper ↔ root

| | Here that would be | In the way today | To check |
| --- | --- | --- | --- |
| **S**poofing | — | The helper is root; there is nothing above it to impersonate | — |
| **T**ampering | Writing through a symlink an addon controls; a partial write that leaves a broken file | The writes stage and rename; the ownership walk follows no link; only the image's links are followed, the resolved path is checked, `O_NOFOLLOW` at every component | A new trusted-link case (an image link the daemon writes through) needs its resolved path on the list |
| **R**epudiation | — | The journal | — |
| **I**nformation disclosure | A file read as root and handed out whole | The named operations return only what is needed (the certificate's blocks, not the key) | Each new operation's answer, field by field |
| **D**enial of service | An operation that blocks the helper for everyone | Concurrent connections; per-operation timeouts | Which operations can run long |
| **E**levation | The whole line: anything wrong here is root | The narrowness of each operation; a named operation's files, what root runs or obeys, and the addons' own directories are outside the generic operations | New operations, every time: what does this let the unprivileged side do that it could not do before? |

### B5 · The system ↔ addons

| | Here that would be | In the way today | To check |
| --- | --- | --- | --- |
| **S**poofing | An addon page passing itself off as the shell (a login form in a frame); an addon using another addon's token; an addon claiming a client address through its web ingress | `X-Frame-Options: SAMEORIGIN` keeps a foreign site out, but an addon **is** same-origin; each addon has its own user and its own token (0600); an ingress socket's directory opens to that addon's group alone, the claimed address is held to the manifest's ranges | The known residual risk: a same-origin addon frame can read the parent page (R1). That the socket's directory keeps its group and mode after every lighttpd and addon start |
| **T**ampering | An addon writing into another addon's tree, into occulited's state, or into a unit file that gives it root | The confined user owns only its own tree; units come from the generator and the helper, never from the addon; the shared directories are `root:root` | Every path an addon can write that another component later reads or executes |
| **R**epudiation | An addon acting through the local token, indistinguishable from the system | The addon's own token carries its name; occulited logs the token's name | Whether an addon's calls are traceable to the addon in the log |
| **I**nformation disclosure | Reading the keys, the metadata or another addon's configuration from the file system or over the loopback | The trees are closed to other users; the local token reads names and rooms only; the keys are root's and the daemons' | A walk of `/usr/local` and `/etc/config` as an addon user after a change to the confinement |
| **D**enial of service | An addon filling the disk, the journal or the CPU | The storage hint and the journal's limits; nothing enforces a quota (R5) | Whether an addon can fill the userfs and stop the system from writing its own state |
| **E**levation | An escape from the confinement to root | The generated unit, the validator, the helper's allowlist, the addon user | What an addon run as root means: it is root, by definition, and the Addons page is the only warning |

### B6 · occulited (and the addons) ↔ the eQ-3 interface processes

| | Here that would be | In the way today | To check |
| --- | --- | --- | --- |
| **S**poofing | Anything on the loopback calling `putParamset` as if it were the system; a client registering a callback in somebody else's name | Nothing — the ports have no authentication. Only the loopback limits who calls | Whether a subscriber's id is checked at all |
| **T**ampering | Changing a device's parameters or its pairing through the loopback | Nothing on this line | What occulited itself would notice |
| **R**epudiation | A change nobody can attribute | occulited logs what it sends; an addon's own calls are not in occulited's log | Whether the interface processes' own logs name the caller |
| **I**nformation disclosure | Reading every device, its values and its pairing over the loopback | Nothing on this line | — (in practice, everything) |
| **D**enial of service | An addon flooding the processes, or registering so many callbacks that events stop | Nothing; occulited's reachability probe and the stall check find a hung callback | What happens to the system when a subscriber's callback hangs |
| **E**levation | Reaching root through a process with a memory bug | Each process runs as its own user with no capabilities and a read-only system | What each daemon's user can write: its own files and keys, not the system |

### B7 · The system ↔ the outside sources it calls

| | Here that would be | In the way today | To check |
| --- | --- | --- | --- |
| **S**poofing | A hostile server answering as the catalogue, the release feed, eQ-3's servers or the ACME CA | HTTPS against the system's trust stores, `MinVersion` 1.2, no plain-HTTP fallback; the ACME account key | Whether the trust stores are kept current |
| **T**ampering | A changed release, addon package or firmware bundle | The published SHA-256 for releases and, where published, addon packages | Device firmware bundles have no published sum |
| **R**epudiation | — | The run log keeps an ACME or a firmware run | — |
| **I**nformation disclosure | What the system tells the outside: which version, which devices, which addons | [privacy.md](privacy.md), field by field, pinned by occulited's `outbound_test.go` tests | A new outbound call needs its row there and its pin |
| **D**enial of service | A source that never answers, or answers endlessly | Timeouts on each call; size limits on every answer (the catalogue 1 MiB, its release lists 4 MiB, a package 400 MiB, the feed 8 MiB, a firmware bundle 64 MiB, OIDC 1 MiB) | — |
| **E**levation | A hostile answer becoming code | Nothing is executed from these sources without the administrator installing it | The parsers: the catalogue's JSON, the feed, the firmware bundle's `info`, the addon package's `update_script` — fuzz tests are still missing |

### B8 · The running system ↔ the recovery system

| | Here that would be | In the way today | To check |
| --- | --- | --- | --- |
| **S**poofing | A file that claims to be a release for this platform | The kind is read from the content and the board from the name, shown before the install; the recovery checks both again | — |
| **T**ampering | Changing the staged file between staging and the reboot | It lies on the userfs, writable by root only | Whether the sum is checked again at install time or only at staging |
| **R**epudiation | — | The install is logged, and the recovery system keeps its own log | — |
| **I**nformation disclosure | — | — | — |
| **D**enial of service | A staged file that fills the userfs; a system that stays in the recovery | The space the recovery will unpack is checked at staging and again at install; a nightly backup on the userfs keeps room for an update; the Status page watches for a system that does not come back, and a boot that does not complete falls back to the previous system | — |
| **E**levation | The whole line: a staged file becomes the next system | The administrator's confirmation, the sum, the recovery system's checks | Signing. Today a sum published by the same party as the file is the only tie; this is the single most valuable place for a signature |

## Trust statements

What this system deliberately trusts. Each of these is a decision, not an oversight: if one of them is wrong for
an installation, the controls below it do not help.

### T1 · The administrator is root on the system

An administrator can write a unit file (own timers, unit overrides), install an addon, set root's password, add an
SSH key and install a system update. Every one of those is root, directly or at the next boot. **The system does
not try to protect itself from its own administrator.**

What follows from it:

- Splitting *administer* into smaller powers would be theatre as long as these routes exist.
- What a review does check is that every such route needs the administrator's scope and a token cannot reach it with
  a lesser one.
- The levels below *administer* are a different matter: they are not trusted with any of this, and that line is
  enforced per route.

### T2 · An addon is trusted as far as its confinement says

- **Confined** (the default): its own user, its own tree, its own unit. It is trusted with its own data, the
  loopback — and therefore the devices (B6) —, the local token's read of names and rooms, its own token's scopes and
  the system's TLS key (`certs`). It is not trusted with root, with another addon's tree, or with the radio keys.
- **Root:** there is no boundary left; choosing it is a decision to hand the system over. The Addons page says so.
- **In the browser** the addon is same-origin with the shell. The decision is defence in depth, not a separate origin:
  the API cookie is kept away from `/addons/`, API writes need a header credential, `Origin` and `Sec-Fetch-Site` are
  checked, and the shell gets a CSP. **The residual risk stays** and is stated below (R1).

### T3 · The eQ-3 interface processes are trusted, as opaque binaries

`rfd`, `hmipserver`, `multimacd`, `hs485d` and `hmlangw` are eQ-3's binaries. Their loopback ports have no
authentication, and their source is not ours to audit. The system trusts them with the radio and with the keys
because there is no alternative that still talks to Homematic devices. Running each as its own user without
capabilities narrows what a compromise of one of them reaches; it does not make them trustworthy.

### T4 · The LAN is not trusted, the loopback is

Every LAN device is a potential attacker (A1). The loopback is treated as trusted, which is what makes B6 work at
all — and it is why an addon's confinement stops at the devices. A request through an addon's web ingress (B1b) is
not the loopback's: it carries the tunnel peer's address, and a peer is a LAN device (A1) that has a key.

### T5 · The sources are trusted to the extent they are checked

A release and an addon package are checked against a published sum: that is integrity, not authenticity. The
intended answer is to sign releases with an offline key, the public key in the image, and to refuse an unsigned
update or catalogue install. **Until that is built, the trust statement is: the system trusts whoever controls the
release hosting.**

### T6 · The administrator's browser is trusted

Sessions live in a cookie; a compromised browser or a malicious extension has the administrator's rights. Nothing
here defends against that, and the confirmations (the password again for the key sheet, an SSH key, root's password,
a passkey) are the one place where a stolen session alone is not enough.

What is defended is the browser against *other sites*: the cookie is `SameSite=Lax`, a state-changing request on it
must come from this origin (`Sec-Fetch-Site`, else `Origin`/`Referer`) **and** carry the custom header
`X-Occulite-Request`, which no form post or link from elsewhere can send; the API's cookie is scoped to `/api` and a
separate gate cookie to `/addons/`; and the shell runs under a Content-Security-Policy that allows no inline or
foreign script, so an injection into the shell, should one appear, has less to work with. The addon pages under
`/addons/` are outside that policy ([security.md → The browser](security.md#the-browser)).

## Residual risks

Known, accepted for now, and written down so that nobody has to rediscover them. Each names what would remove it.

| # | Risk | Why it is accepted | What would remove it |
| --- | --- | --- | --- |
| R1 | **A same-origin addon frame can read the parent page** and act with the user's rights | Separate origins would break the addon interface every CCU addon relies on; defence in depth was chosen instead: the `Origin`/`Sec-Fetch-Site` check, the API cookie kept away from `/addons/` (a gate cookie of its own), the header credential on state-changing calls, the shell's CSP. Against a *malicious* addon page on the origin they add nothing — it can read the parent, send the header and call the API with the browser's cookie or with the session id the gate hands its server as `X-Occulite-Session`. What they take away: an addon that forwards or logs its requests' cookies no longer holds the API's; a form post or link from another site is stopped twice; a script injected into the shell has no inline execution | Addons on an origin of their own, which is a break with the CCU convention |
| R2 | **An addon reaches the devices over the loopback**, whatever its confinement | The interface processes have no authentication and are eQ-3's (T3) | A proxy in front of the interface processes that knows callers — a large change, and it would break addons that talk to 2001 directly |
| R3 | **A release is only as trustworthy as its host** | Signing is not built yet | Signed releases, the public key in the image |
| R4 | **The eQ-3 processes are unaudited binaries** with the radio and the keys | Their source is not ours; each runs as its own user with no capabilities, so a compromise reaches its own files, its keys and the devices, not root | Nothing within compatibility; a mandatory access control profile would narrow it further |
| R5 | **No quota for an addon**: it can fill the userfs or the journal | The storage hint warns, but nothing enforces | Per-addon limits in the unit (systemd's `MemoryMax`, a quota on the tree) |
| R6 | **The keys are in clear on the storage and in every unencrypted backup** | hmipserver needs them that way; a backup has to restore them | Nothing short of a change in hmipserver; encrypted backups cover the backup alone |
| R7 | **Physical access ends everything** (A8) | Out of scope; full-disk encryption is not part of the product | Encrypted storage with a key that is not on the same card |
| R8 | **Classic RPC has no real authentication** | It is the CCU's protocol, and compatibility is the point of it | Nothing, within compatibility: it stays a switch that is off by default, with the warnings on its page; lite-rpc is the authenticated alternative |
| R9 | **`?sid=` puts a credential in a URL**: the API still accepts a session id or a token there, and the CCU's legacy alias goes into the URLs of addons that need it | The CCU addon convention needs the alias; the API's acceptance is to be narrowed to where a header cannot be sent | The API's `?sid=` narrowed; the alias only for addons that still need it |
| R10 | **An ingress addon vouches for its peers' addresses** (B1b, B5c): whatever runs as `addon-<id>` can claim any address inside the ranges its manifest declared — another of its own peers, say — though never the loopback or a LAN address | The addon is the end of the tunnel, so nothing else knows the peer's address; the socket's directory keeps every other addon out, and the addon runs confined | The tunnel in the kernel with the address on an interface, where the kernel vouches for the source |
| R11 | **No second factor of the system's own**: a passkey is an alternative login, and the password alone still opens a session | A decision for a household system; an identity provider brings its own second factor | A second factor (TOTP, or passkeys required) as an option |

## Audit log

The "to check" rows that were checked, and what became of them. One entry per slice of a review.

**2026-10-30 — the documents against the code of 1.1.0-dev.6.** security.md, this document, the ASVS checklist and the
EN 303 645 baseline re-read against the fork's `lite` and occulited's `master`. Changed since the last slices: the
interface daemons run under their own users with no capabilities (R4, T3, B6 reworded); a confined addon's rc.d
script runs as its user (B3, B5); the known confinement escape paths of the earlier versions are closed; passkeys are
a login of their own and no longer a second factor (R11 added); accounts have four levels instead of two roles; client
pairing, the `addon:<id>` scope, the addon's own token and the install token; the pre-resolved catalogue and the
update channels (A3, B7); local key mode reads `hmip_user.conf` through the helper (asset 1). Found open: lighttpd's
`server.http-parseopts` still leave URL control characters and invalid UTF-8 to occulited (ASVS V3.7).

**2026-10-30 — B1b/B5c, the addons' web ingress** (lite-addon-wireguard is the first): per addon that declares
`runtime.web_ingress`, a PROXY-protocol Unix socket of lighttpd's in a directory only the addon's confinement group
reaches, its block rendered by occulited from the stored manifest, the claimed address held to the declared ranges by
lighttpd (403) and by occulited (`403 ingress-range`). Measured in the fork's lighttpd container test (1.4.85) and on
a lab system (1.4.84): the claimed address is what occulited receives, a client-sent `X-Forwarded-For` or
`X-Occulite-Ingress` through the door is not, an address outside the ranges (the loopback, the LAN) is a 403 before
any backend, the PROXY v2 SSL TLV makes the request https, the gate and the header removal run on it, HSTS and the
HTTPS redirect do not, a user outside the group is refused, a PROXY header on a LAN port is a 400. R10 added.

**2026-09-28 — B1/B5, the browser measures**: the session cookie scoped to `/api` with a gate cookie for `/addons/`,
`X-Occulite-Request` on state-changing calls with the cookie alone, the shell's Content-Security-Policy and
Permissions-Policy from occulited's own handler. Checked with occulited's Go and Playwright suites (every page under the
policy, no violation; the stub refuses every browser write without the header), the gate's Lua test and the fork's
lighttpd container test (the API's cookie name is no credential at the gate, HSTS untouched). R1 and T6 reworded.

**2026-09-26 — B1 and B2, the authentication, session and access-control slice** (the checklist is
[security-asvs.md](security-asvs.md), the product baseline [security-en303645.md](security-en303645.md)):

| row | outcome |
| --- | --- |
| B1 *Spoofing* — the lockout, the cookie's flags | the flags hold; the lockout by address could be dodged with a client-sent `X-Forwarded-For` — fixed the same day (occulited and the fork's global magnet script) |
| B1 *Tampering* — `SameSite=Lax` alone | not alone: the `Origin`/`Sec-Fetch-Site` check covers every state-changing call on the cookie; the header credential and the CSP followed on 2026-09-28 |
| B1 *Repudiation* — which changes are logged with who and from where | password logins, refusals and lockouts were at debug — fixed: logins at Info, refusals and the start of a lockout at Warn, with name, method, address and reason, flood-limited; the older system routes logged the action without the caller — fixed: every change names `user` and `remote` at Info, and an attempt refused with 403 is `api: change refused` |
| B1 *Information disclosure* — the list of open routes | `open()` in `internal/httpapi/auth.go` is the one list; each answers nothing a session would guard |
| B1 *Denial of service* — unauthenticated work | the login's argon2 runs one at a time; eight authenticated JSON routes read bodies without a cap and there was no idle timeout — fixed: every JSON body has a limit (413), a guard test keeps it so, idle keep-alive connections close after 120 s |
| B1 *Elevation* — every route's scope, mechanically | `TestRouteTable` walks the mux; the default is deny; no finding |
| B2 *Spoofing* — a faked `X-Forwarded-For` | lighttpd appended the real address to a client-sent header and occulited took the first element — fixed: the last element, only from the loopback; the global magnet and the gate remove the client's header (`lite-lighttpd-redirect-test.sh` checks it on a real lighttpd) |
| — (V6.3) | the login skipped argon2 for an unknown account, a timing oracle for names — fixed: a dummy hash is verified instead, both refusals take the same time |
| B3 *Elevation* — every program and prefix, read as an attacker would | the helper shaped the arguments of `sh` only; `systemd-run`, `systemctl`, `kill`, `ip`, `install_addon`, `restoreBackup.sh` ran with any arguments — fixed: one argument shape per program, `TestProgramsHaveShapes`, `TestProgramShapes` |
| B4 *Tampering* — every write, for symlink and TOCTOU handling | the `symlink` operation checked the link, not its target, and the write resolved links before writing — fixed: the target checked, only the image's links followed, the resolved path checked again, `O_NOFOLLOW` at every component below the check; `TestSymlinkBoundary`, `TestLocalNoFollow` |

**2026-09-26 (evening) — the input, file, lighttpd, cryptography and addon slices** (measured read-only on a lab
system as three addon users; the checklist rows are in [security-asvs.md](security-asvs.md) V1, V2, V4, V5,
V11–V15):

| row | outcome |
| --- | --- |
| B1 *Denial of service* — lighttpd's own limits, the upload's size cap | upstream's idle limits and no request-size limit; the reverse proxy buffered a body without `Content-Length` whole, into RAM; the system-update upload had no cap; the regadom import staged into RAM — all fixed |
| B1 *Information disclosure* — error texts with a path or version | `apiError` codes; the X-Sendfile path never in an answer; lighttpd's `Server` header empty — no finding |
| B2 *Tampering* — the path rewriting rules | none: `/api/`, `/addons/` and the rest are proxied as they are; the gate reads `uri.path` after lighttpd's normalisation and `url-path-2f-decode` stays off — no finding |
| B2 *Information disclosure* — a route cached by lighttpd | no cache module — no finding |
| B2 *Elevation* — no route trusts the gate alone | the API's middleware checks the session on every `/api/*` call — no finding |
| B3 *Spoofing* — who is in the `occulite` group | nobody; but a manifest could put a confined addon there — fixed: the validator refuses it |
| B3 *Tampering*, *Information disclosure*, *Denial of service* | one argument shape per program; the read list exact; each connection with the caller's deadline and per-operation timeouts — no finding |
| B4 *Information disclosure*, *Denial of service* | the certificate operation returns the blocks and the marker, never the key; the log listing names and sizes; concurrent connections — no finding |
| B5 *Tampering* — every path an addon can write that another component reads | none of the shared directories is writable by an addon user — no finding |
| B5 *Information disclosure* — what an addon user can read, measured | every addon's tree was world-readable — fixed: 0751 directories, 0640 files, the www tree left readable; hmipserver's data files were `0664` — fixed: 0700/0600, `UMask=0077`, tightened at every start; `server.pem` readable through `certs` and `local-token` `0644` — by design |
| B5 *Elevation* — what a confined addon may declare | root-equivalent capabilities and groups were applied as declared — fixed: refused by the validator |
| B7 *Spoofing*, *Denial of service*, *Elevation* | every outbound `tls.Config` with the stores and TLS 1.2; size limits on every answer; Go's JSON with its nesting limit — no finding; fuzz tests still missing |
| B8 *Spoofing*, *Tampering* | the kind from the content, the board shown, the sum at staging, the recovery's own checks — no finding beyond R3 |

## How this document is kept

- **Reviewed at every minor release**, and whenever a boundary changes: a new helper operation, a new open route, a
  new outside source, a change to the confinement.
- **Work at a boundary names this document** — the boundary it touches, and the "to check" rows of that boundary.
- **The review's records** are [security-asvs.md](security-asvs.md) (the code against OWASP ASVS 5.0 L2) and
  [security-en303645.md](security-en303645.md) (the product against ETSI EN 303 645); the [audit log](#audit-log)
  above says which rows were checked when.
- **The "to check" column is the review's backlog.** Each row becomes a finding with a CVSS 3.1 rating, or is struck
  out with the reason it is not a finding.
- **The bugs are kept in the boundary sections** so the pattern stays visible: nearly every security bug in this
  project so far sat on a line in [Trust boundaries](#trust-boundaries), and most were found by reading, not by a tool.
- **A change to a trust statement is a decision**, made first and then written here — not the other way round.

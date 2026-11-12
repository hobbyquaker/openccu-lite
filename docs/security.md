# Security

How openccu-lite protects the system, what it leaves to you, and what is known to be missing. The companions:
[threat-model.md](threat-model.md) — the assets, the attackers, the trust boundaries and the accepted risks, with the
mechanisms at each boundary in detail; [security-asvs.md](security-asvs.md) — the code against OWASP ASVS 5.0
Level 2, row by row; [security-en303645.md](security-en303645.md) — the product against ETSI EN 303 645. Reporting a
vulnerability: [SECURITY.md](../SECURITY.md). The API's routes, scopes and files are in occulited's
[system-api.md](https://github.com/hobbyquaker/occulited/blob/master/docs/system-api.md) and
[config.md](https://github.com/hobbyquaker/occulited/blob/master/docs/config.md).

- [Overview](#overview)
- [What listens where](#what-listens-where)
- [Accounts and sign-in](#accounts-and-sign-in)
- [API tokens and scopes](#api-tokens-and-scopes)
- [The browser](#the-browser)
- [Network and firewall](#network-and-firewall)
- [TLS and certificates](#tls-and-certificates)
- [Addons and confinement](#addons-and-confinement)
- [The system service and its privilege helper](#the-system-service-and-its-privilege-helper)
- [The interface daemons](#the-interface-daemons)
- [Radio keys](#radio-keys)
- [Updates and integrity](#updates-and-integrity)
- [Backups](#backups)
- [Build hardening](#build-hardening)
- [Known gaps](#known-gaps)

## Overview

**What protects the system:**

- **One door.** lighttpd is the only program the system runs that listens on the LAN (80, 443). occulited and the
  interface daemons listen on the loopback. SSH and the CCU's classic RPC ports exist only while you switch them on.
- **A firewall that drops by default.** A port no rule accepts is closed, whatever listens on it. Each feature that
  needs a port adds its own rule and removes it again.
- **A login on everything.** Accounts with argon2id password hashes, a lockout after repeated failures, optional
  passkeys and an optional identity provider (OpenID Connect). The addon pages are behind the same login.
- **Scoped API tokens.** A program gets a token with the scopes it needs, optionally an expiry and the addresses it
  may come from. Every API route names its scope; a route without one is reached by nobody.
- **Least privilege inside.** occulited runs as its own unprivileged user; what needs root goes through a small root
  helper that runs a fixed list of operations. The interface daemons run under their own users with no capabilities,
  and addons run under their own users by default.

**The defaults on a fresh system:**

| | default |
| --- | --- |
| First boot | asks for an administrator account; no account and no password ship with the image |
| Web server | HTTP, and HTTPS with a self-signed certificate; the HTTPS redirect and HSTS are off |
| Firewall | policy DROP (IPv4 and IPv6); the web server from the local networks only |
| SSH | off |
| Classic RPC (2001, 2010, 9292, 2000) | off; switched on without a login after a switch from OpenCCU whose firewall opened the XMLRPC ports, or after an import of an OpenCCU backup with that option ticked ([switching.md](switching.md#what-changes-on-the-first-start)) |
| The Control app's public mode | off |
| Client pairing | on, for programs on the local networks; every request needs an administrator's approval |
| Addons | installed confined (their own user) |
| Daily update checks and the catalogue fetch | off until you choose them on the welcome page |
| Sessions | 30 minutes idle, 12 hours at most |
| Backups | not encrypted until you set up encryption |

**What you do yourself:**

- **Set an individual BidCos security key** if you use BidCos-RF devices (System → Keys); the default key is public.
  The Status page warns while it is unset and a BidCos device is paired.
- **Before the system is reachable from outside the LAN**, switch HTTPS on with a certificate the browser trusts
  ([TLS and certificates](#tls-and-certificates)), then the redirect and HSTS. Never forward the classic RPC ports,
  and never combine the Control app's public mode with a port forward.
- **Encrypt your backups and keep the recovery key** apart from the system. An unencrypted backup holds every radio
  key and credential of the system.
- **Install updates.** The checks are off until you switch them on; the Updates page shows what is available.
- **Decide which addons to trust.** An addon you run as root is root on the system, and a confined addon still reaches
  every device over the loopback.
- **Prefer SSH keys** to root's password, and keep SSH off when you do not need it.

**What is known to be missing** (see [Known gaps](#known-gaps)): releases are checked against a published SHA-256 but
not signed; HTTP is the default; the radio keys are stored in clear; addon pages share the shell's origin; the
interface daemons' RPC ports on the loopback have no authentication.

## What listens where

| | bound to | reached by |
| --- | --- | --- |
| lighttpd | the LAN, 80/443 | browsers, programs with a token |
| `occulited` | `127.0.0.1:8183` only; it refuses any other listen address | lighttpd (proxy), programs on the system |
| `rfd`, `hs485d`, `hmipserver` | the loopback: `Listen IP = 127.0.0.1` in `rfd.conf`, `Legacy.BindAddress=127.0.0.1` in `crRFD.conf` (the fork's config templates) | occulited, addons on the system |
| sshd | the LAN, 22, only while SSH is switched on; the firewall opens it for the local networks only | the administrator |
| lighttpd, classic RPC | the LAN, 2001/2010/9292/2000 (plain) and 42001/42010/49292/42000 (TLS), only while switched on | CCU clients off the system |
| lighttpd, an addon's web ingress | the Unix socket `/run/lighttpd-addons/<id>/proxy.sock` (PROXY protocol), one per addon whose manifest declares `runtime.web_ingress` | that addon alone |

The ReGa ports 1999 and 8181 do not exist. An integration that ran off the system and spoke to the interface
daemons' ports runs on the system instead, uses lite-rpc over the web port with a token, or needs classic RPC.

**What the web port answers without a login:** the login itself, the client pairing request, `/api/system/v1/health`
(the release and occulited's commit), the SBOM, the ACME challenge and the metadata API's feature detection
`/api/meta/v1/version`. That last one says what a program needs before it is paired: the API versions and
capabilities, the HmIP key-server mode and the number of stored device keys (never a key or an SGTIN), and the
**names** of the interfaces lite-rpc offers (`HmIP-RF`, `BidCos-RF`, …), so that a program looking for the system on
the network - ioBroker's discovery, for one - proposes exactly the connections it has. Nothing more of the radio is
open: no module type, serial, address, firmware or URL; the details stay behind `rpc:read`. The interface names were
behind the credential up to 1.2.0: they say which kind of radio the system has, a coarse fact that every CCU shows to a
scan of its classic RPC ports.

**Classic RPC** (System → Remote access, off by default, except after a switch from OpenCCU whose firewall opened the
XMLRPC ports, or an import of an OpenCCU backup with that option ticked: then it is on, plain and TLS, without a
login, and the Status page warns; see [switching.md](switching.md#what-changes-on-the-first-start)) makes lighttpd
serve the CCU's ports again and proxy them to the interface daemons, which stay on the loopback
(`lite-classic-rpc-conf` writes only the switched-on sockets).
These are the CCU's risks and the page states them: without the login, whoever the firewall lets in controls every
device; with the login on the plain ports, the password travels in clear. The login is a user name and password of
its own (SHA-512-crypt in a root-0600 htpasswd file, checked by lighttpd's `mod_authn_file`), not the system's
accounts or tokens; the loopback is exempt. As on a CCU there are no per-method rights and no lockout — lite-rpc is
the authenticated alternative. Each open port gets its own firewall rule from `local networks`; a port converted
or imported from OpenCCU keeps the sources OpenCCU allowed instead.

**An addon's web ingress.** A VPN or tunnel addon that ends the tunnel in its own process (lite-addon-wireguard)
would otherwise forward its peers' requests from the loopback, which the system trusts more than the LAN. Instead it
gets a socket of its own: it sends the peer's address in a PROXY header, and lighttpd and occulited both hold that
address to the ranges the manifest declared — never the loopback, never a LAN address (`403 ingress-range`). The
socket's directory is reachable for that addon's group alone. The mechanism and its checks are in the threat model,
[B1b](threat-model.md#b1--the-lan--lighttpd).

## Accounts and sign-in

- **Accounts** are in occulited's `users.json`. Each has a **level**: *read*, *operate*, *configure* or *administer*.
  Read sees the metadata, the status and the log; operate also switches devices; configure also edits names, rooms
  and functions and configures devices; administer is everything, the system and the accounts included. Only
  administrators create accounts and tokens.
- **Passwords**: at least 8 characters, hashed with argon2id (t=3, 32 MiB). After **8 failures** the name and the
  client address are **locked for 15 minutes**. A wrong name and a wrong password take the same time and give the
  same answer. Changing your password needs the current one; a reset ends the account's other sessions.
- **Passkeys** (Account → *Passkeys*): a passkey on a phone, a laptop or a FIDO2 key with a PIN or biometrics is a
  **login of its own** — it signs in without name and password. It is **not a second factor**: the password alone
  still opens a session. A passkey is bound to the system's full name (`<host>.<domain>`) over a trusted certificate;
  renaming the host or the domain orphans every passkey, and the Network page warns before one. A sign count that goes
  backwards (a cloned key) is refused. Adding and removing a passkey asks for the password again. An administrator
  removes another account's passkeys on System → Users. Locked out entirely, root on the console runs `occulited admin
  reset-auth <user>`: the account's passkeys removed, a one-time password set, its sessions ended.
- **The identity provider** (OpenID Connect, with state, nonce and PKCE): a provider login is the local account of the
  same user name; nothing is created from a provider identity, and an unknown name is refused and logged. Password
  login beside the provider is a switch; switched off, the provider is the only way in through the browser. **The way
  back** is the console: `occulited auth password-login on` and `occulited passwd <user>`, as root.
- **Sessions**: a 130-bit random id, **30 minutes idle and 12 hours from the login** by default (System → Users →
  Authentication → Sessions; 5 minutes to 30 days idle, 1 hour to 90 days at most; in force at once). The session
  cookie is `HttpOnly`, `SameSite=Lax`, `Secure` with the `__Secure-` prefix over HTTPS, and scoped to `/api`; a
  separate gate cookie with `Path=/addons/` opens the addon pages and is no credential on the API. occulited keeps
  sessions **only as the SHA-256 of their id** — in memory, in its session store and in the gate's mirror on tmpfs —
  so no id is written anywhere. Sessions survive a restart and a reboot; the store is in no backup. A logout,
  *sign out everywhere*, a password change, a changed level or a removed account end the sessions concerned, also when
  the change is made on the console.
- **Confirmation inside a session**: the device key sheet, adding an SSH key, setting root's password and adding or
  removing a passkey ask for the password again (or a fresh login at the provider). The ticket is single use, 60
  seconds, bound to the session and the path.
- **Authentication off** (`auth.mode: off`, System → Users → Authentication): every caller is one anonymous
  administrator. It is meant for a system alone on a trusted network; the shell shows it in the warning colour. It
  takes effect at the next start of occulited, so a mistaken switch is undone by editing `occulited.json`.

Not provided: a second factor of the system's own (the identity provider's applies), TOTP, and a check against
breached passwords ([security-asvs.md](security-asvs.md) V6.2 says why).

## API tokens and scopes

- **Tokens** (`olt_…`, 128 bits) are shown once and stored as SHA-256. Each carries **scopes** — `meta:read`,
  `meta:write`, `system:read`, `logs:read`, `system:write`, `addons:write`, `power`, `backup`, `led`, `radio:keys`,
  `auth:admin`, the RPC tiers `rpc:read` … `rpc:admin`, or Full access (`*`) — and optionally an expiry and the
  address ranges it may come from. The route table and what each scope opens are in
  [system-api.md → Scopes](https://github.com/hobbyquaker/occulited/blob/master/docs/system-api.md#scopes). A token
  is sent as `Authorization: Bearer` or as the password of HTTP basic authentication (for XML-RPC libraries) — **never
  in the URL**: since 1.3.0 the API reads no credential from `?sid=`, neither a token nor a session id, and answers
  such a request `401` with a message that names the header. `?sid=` lives on under `/addons/` alone, where the gate
  takes the session id and the CCU's legacy alias for the addon pages that need it.
- **The local token** `/usr/local/etc/occulite/local-token` is world-readable on purpose: every program on the system
  may read names and rooms with it. It holds **`meta:read` alone**.
- **An addon's own token** comes from its manifest's `runtime.api_scopes`: minted at every start into
  `/run/occulite/addon-tokens/<id>.api` (0600, the addon's user), never written to `users.json`, gone with the addon.
  It never carries `*`, `auth:admin`, `power`, `backup`, `radio:keys` or a scope for another addon's pages; a
  declaration naming one is logged and left out. So an addon cannot reboot or halt the system or download a backup
  through the API.
- **The install token** `/run/occulite/install-token` (root, 0600) opens one route, from the system itself, so that an
  install started on the command line ends up in the addon's unit and policy. It grants root nothing it does not have.
- **An addon's pages with a token**: a token with the scope `addon:<id>` opens that addon's pages at lighttpd's gate
  (`Authorization: Bearer` on every request) and opens no API route; the addon receives the token's name. No token
  becomes a session there.
- **Client pairing**: a program on the local network asks for access by area (devices, names, system, backup) and level;
  an administrator compares a six-digit code and approves the request on the Status page, and the program receives its
  token. The code is bound to the certificate the program saw. Pairing **never grants** `*`, `auth:admin`,
  `radio:keys` or `power`. **Backups** hold the radio keys, so a request for `backup` says so loudly on the card, is
  approved only with the administrator's own confirmation (password, passkey or a fresh login at the identity
  provider, enforced by the API, per request, 60 seconds), and its token works only from the address that asked (an
  IPv4 address, or the IPv6 /64, in which a client's temporary addresses change). A request expires after five minutes, and requests are rate-limited per address;
  the switch is in the API tokens panel.

## The browser

- **Response headers** from lighttpd on every answer: `X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options:
  nosniff`, `Referrer-Policy: no-referrer`, an empty `Server`, and `Cache-Control: private, no-cache` where an answer
  sets none of its own (the API's secrets carry `no-store`). HSTS where you switch it on.
- **The shell's Content-Security-Policy**, set by occulited on the shell's own pages (`internal/ui/csp.txt`): scripts
  only from the system, never inline or evaluated; inline styles allowed; `frame-ancestors 'self'`; `object-src
  'none'`; the camera for the shell itself (the QR scanner), no microphone or location. occulited's UI tests open every
  page under this policy. The addon pages under `/addons/` keep the CCU's conventions (inline scripts) and get no CSP.
- **Cross-site requests**: a state-changing API call whose only credential is the cookie must come from this origin
  (`Sec-Fetch-Site`, else `Origin`/`Referer`) **and** carry the header `X-Occulite-Request`, which no form or link from
  another site can send (`403 request-header` otherwise). The API sets no CORS headers.
- **Addons share the shell's origin** (`/addons/<id>/`), because every CCU addon expects it. The cookie scoping, the
  header and the CSP limit what a careless addon leaks; a malicious addon page can still act with the user's rights
  (threat model R1).

## Network and firewall

- **The firewall** is one list of INPUT rules with policy DROP in both families. Features own their rules (the web
  server, SSH, classic RPC, the HmIP access points, the network discovery, an addon's opened port) and add or remove
  them with the feature; the web server, SSH and classic RPC are from `local networks` only (classic RPC converted
  or imported from OpenCCU keeps OpenCCU's sources). Every rule is editable. A
  change from the page reverts after 60 seconds unless confirmed, so a rule that locks you out undoes itself. The
  rules load before the network comes up and apply to Ethernet and Wi-Fi alike. A system that comes from OpenCCU
  converts its `firewall.conf` once. The Firewall page lists every listening socket with the rule that covers it, or
  the policy.
- **Addon ports**: an addon declares its ports in its manifest; the Addons page lists each with a switch that is off
  by default, and a switched-on port becomes the addon's own rule. An MQTT broker's TLS port can be opened and its
  plain port left closed.
- **SSH** is off by default (`sshd.service` exits while it is off). With it on, the firewall opens 22 for the local
  networks; root's `authorized_keys` and password are set on the SSH page, and an option refuses password logins
  (keys only).
- **The Control app's public mode** (System → Remote access, off by default): a request without a session on the
  app's paths becomes the public account, which may read and operate devices but reaches nothing of the
  administration, the metadata's writes, the accounts or the tokens. Anyone who reaches the web port operates the
  house. The Status page warns while it is on.
- **Wi-Fi**: `/etc/config/wpa_supplicant.conf` (root, 0600) keeps a WPA2 network as its PBKDF2 hash, not the
  passphrase; a WPA3 network keeps its SAE password in clear because SAE needs it, and the dialog says so. No key is
  answered or logged. The boot partition's setup file `openccu-lite-wifi.txt` holds the password in clear until the
  first boot takes it and deletes it. A change made over the Wi-Fi itself reverts after 90 seconds unless confirmed.
- **Outbound calls**: every connection the system opens by itself — where to, when, which fields, how to switch it
  off — is in [privacy.md](privacy.md). All of them use HTTPS with certificate checks (TLS 1.2 or newer), except NTP
  and the opt-in syslog forward. No telemetry.

## TLS and certificates

- **The certificate** `/etc/config/server.pem` (certificate and key) is self-signed at first. It can come from an ACME
  CA — Let's Encrypt, ZeroSSL, or a LAN CA such as step-ca — issued and renewed by occulited, with HTTP-01 or DNS-01
  (Cloudflare, Hetzner DNS, netcup, DuckDNS, OVHcloud, or a script of your own that runs as the `occulite` user), or
  you bring your own (System → Certificate). [tls-acme.md](tls-acme.md) is the guide. HTTP-01 from a public CA needs
  port 80 reachable from the internet, which the default firewall does not allow; DNS-01 is the way for a system
  behind NAT. The DNS provider's credentials are kept in occulited's state directory and redacted from its logs.
- **lighttpd's TLS**: TLS 1.2 at least, TLS 1.3 offered, AES-GCM and ChaCha20 suites only (`sslsettings.conf`).
- **Who reads the key**: `server.pem` is `root:certs 0640`. Every confined addon is in the group `certs`, so a broker
  can serve TLS with the system's certificate — which means the group can impersonate the system on TLS. occulited is
  not in the group: it installs a certificate through two operations of the helper that accept a certificate chain
  plus the one key that belongs to its leaf and nothing else, and it never reads the key back. The ACME account key
  and the key of a certificate occulited ordered are in its own state directory (0600). After a new certificate the
  confined addons of the `certs` group are restarted.
- **HSTS** refuses to switch on with a self-signed certificate. **The host name redirect** (off by default) sends
  `https://<host>/` to `https://<host>.<domain>/` with a `302`, only while the certificate covers the full name.
- **One open route outside `/api`**: `/.well-known/acme-challenge/<token>` answers only the tokens of an order in
  flight.

## Addons and confinement

- **Confined by default.** A newly installed addon runs as `addon-<id>` with its own group, its own tree under
  `/usr/local/addons/<id>` (directories 0751, files 0640; its `www` stays readable for the web server), and a systemd
  unit the system generates from the addon's start script and its manifest. Root is the deliberate opt-out per addon;
  addons installed before an update to a confining release keep root, once per system. An addon whose manifest has no
  `runtime` block is marked *undeclared*, and the catalogue marks entries *untested* where nobody has checked them.
- **Its start script runs as its user too**: `info`, `init` and `uninstall` of a confined addon run under its user, not
  as root. The system removes as root what the script cannot (its emptied directories, its web link).
- **What a manifest may declare** for a confined addon: groups, capabilities, writable paths, data directories, ports,
  API scopes, a web ingress. The validator refuses root-equivalent capabilities (`CAP_SYS_ADMIN`, `CAP_DAC_OVERRIDE`,
  `CAP_SETUID`, `CAP_NET_ADMIN` and the like) and groups (the helper's group `occulite` among them), values that would
  add a line to the unit, and ingress ranges that hold the loopback or are wider than /8 (IPv4) or /32 (IPv6). The
  `usbstorage` group (FAT/exFAT/NTFS sticks, which may hold backups) is given only to an addon that declares it.
- **No unit of its own.** An addon cannot ship a systemd unit; the generator reads nothing from the addon's tree and
  logs a shipped unit file as ignored. Its lighttpd fragment is a root-owned copy occulited validated (no
  `include_shell`, no socket, a proxy target on this system only).
- **Root addons** run without `CAP_SYS_ADMIN` unless their manifest asks for it, so they cannot remount the system
  partition; the system offers writable extension directories instead.
- **What a confined addon still reaches**: the loopback, and with it the interface daemons' RPC and every device; the
  local token's names and rooms; its own token's scopes; the ports opened for it; the system's TLS key (`certs`). It
  does not reach the radio keys, occulited's state, another addon's tree or root.
- **No quota**: an addon can fill the userfs or the journal (threat model R5).
- **`requires.lite`** in a manifest is checked for its form only; an install on an older release is not refused yet.

The addon author's view of all this is in [addons.md](addons.md).

## The system service and its privilege helper

occulited runs as the user `occulite` in a sandboxed unit (`CapabilityBoundingSet=` empty, `NoNewPrivileges`,
`ProtectSystem=strict` with only its state and session directories writable, `PrivateTmp`, `ProtectHome`, a system
call filter, `UMask=0077`). What needs root — writing `/etc/config`, the firmware's scripts, `systemctl`, an addon's
account and policy, staging an update — goes over the socket `/run/occulite/helper.sock` (root:occulite 0660) to
`occulited helper`, which does **only what its allowlist names**:

- programs by name, each with the **argument shapes** occulited builds (a `systemctl` verb table, two kinds of
  transient unit, a pid the helper checks itself for `kill`, one action word for the init scripts);
- file writes under a short list of prefixes — **never** into files root later runs or obeys (an addon's rc.d entry,
  the addon web trees, the addon policy drop-ins, the addons' own directories), and never into the files of a named
  operation;
- named operations on exact paths for the sensitive cases: root's password (one hash into one line of `shadow`, which
  occulited never reads), root's `authorized_keys`, ending an SSH session, the certificate, an addon's account and
  policy files, the ownership of an addon's tree, a disk's SMART read (exactly `smartctl -j -H -A -i <disk>`), the
  log files' names and sizes in an addon's directory (never their content), an X-Sendfile file handed back as a
  descriptor.

The helper resolves every path itself, follows only the image's own symlinks, and acts through directory descriptors
with `O_NOFOLLOW`; a refusal is logged. The operations, their checks and the bugs found at this boundary are in the
threat model, [B3](threat-model.md#b3--occulited--the-privilege-helper) and
[B4](threat-model.md#b4--the-helper--root).

What it means: an administrator reaches every operation the helper offers — administering a CCU needs that, and the
administrator is root on the system by design (threat model T1). A bug in the HTTP side reaches only what the
allowlist names.

## The interface daemons

`rfd`, `hmipserver`, `multimacd`, `hs485d` and `hmlangw` are eQ-3's binaries and not ours to audit. Each runs as its
own user with **no capabilities** (`CapabilityBoundingSet=` empty), `NoNewPrivileges`, `ProtectSystem=strict` with
write access to its own files only, and restricted address families; they listen on the loopback. Their RPC ports
have **no authentication**: anything on the system, every addon included, can switch devices through them. That is
the CCU's design and the reason classic RPC is off by default; lite-rpc on the web port is the authenticated way in
from outside.

## Radio keys

- **The BidCos-RF security key** is in `/etc/config/keys` (rfd's, 0600). Set it on System → Keys; the default key is
  public.
- **The HmIP keys** — the network key and the device keys (`/etc/config/crRFD/sgtin.map`, 0640) — are stored in clear,
  because hmipserver needs them that way; hmipserver's data directory is 0700 with 0600 files. Every route that
  touches device keys needs the scope `radio:keys`, which only Full access includes and an addon's token never gets.
  **The key sheet** is the one answer with every key in clear: a session confirms it every time, each export is
  logged with who and from where, and the page keeps the keys in memory only. The QR scanner decodes in the browser;
  only the decoded text reaches the API.
- **Local key mode** keeps the HmIP network key on the system, so a radio module exchange or a pairing needs no call to
  eQ-3's key server ([lokaler-schluesselmodus.md](lokaler-schluesselmodus.md)).
- Whoever holds the SD card holds every key; full-disk encryption is not part of the product.

## Updates and integrity

- **System updates**: the release check reads openccu-lite's release list (from GitHub, or from the catalogue's
  pre-resolved copy) for the update channel you chose (stable, beta or dev). A download is checked against the
  release's **published SHA-256** before it is staged; a sum that cannot be read fails the download, and a release
  without a sum file is staged with a warning that it is not verified. The file's kind
  is read from its content, the space it needs is checked at staging and again at install, and the recovery system
  checks kind, board and space once more before it writes the system partitions. The Status page watches the system
  come back, and a boot that does not complete falls back to the previous system.
- **Not signed.** The sum comes from the same place as the file, so it proves the download is whole, not who made it
  (threat model R3).
- **Addons** from the catalogue are checked against a `.sha256` where the release publishes one; installing an addon
  runs its package's install script as root, as on every CCU — installing is trusting the package.
- **Device firmware** comes from eQ-3's server over HTTPS; there is no published sum to check it against.
- An SBOM (CycloneDX) is published with every release and served at `/api/system/v1/sbom`.

## Backups

- **An unencrypted backup** (`.sbk`) holds everything: the radio keys, `users.json` with the password and token hashes,
  the identity provider's client secret, the ACME account key and DNS credentials, the TLS key, the backup targets'
  credentials. Live sessions and the backup encryption identity are never in a backup.
- **Encrypted backups** (`.sbk.age`, Backup page): the `.sbk` inside one age v1 stream (X25519, ChaCha20-Poly1305 in
  chunks, truncation detected) for two recipients — the system's own identity and your **recovery key**. A copy on a
  lost stick, a share or in a download folder is ciphertext without either key beside it, and damage or tampering is
  detected before anything reaches `restoreBackup.sh`. It does not protect against a compromised running system, the
  system's own storage being stolen, or losing the recovery key together with the system. Downloading unencrypted
  while encryption is set up asks for the password and is logged; an API token with `backup`, also one from client
  pairing, can ask for the unencrypted file with `?encrypted=false` and is not asked, so such a token is as sensitive
  as the backup itself. age proves integrity, not authorship: a restore also
  checks the BidCos key's signature.
- **Targets**: a USB stick, an SMB or NFS share (mounted `nosuid,nodev,noexec`), or an SFTP server whose host key you
  compare and pin.
- The recovery system's restore takes plain `.sbk` only; decrypt with `age -d` on a PC first.

## Build hardening

Every C program the image builds is a position-independent executable with the strong stack protector,
`_FORTIFY_SOURCE` and RELRO; lighttpd, busybox and chronyd (beside sshd and systemd) link with **full RELRO**
(`buildroot-external/lite-hardening.mk`). `scripts/lite-hardening-guard.sh` reads the image's ELF headers at the end of
every build and stops it on a regression. occulited is a static Go binary without cgo and therefore not a PIE; Go's
memory safety stands in for that. eQ-3's prebuilt daemons are PIE with partial RELRO as delivered. systemd is built
with seccomp, so the units' `SystemCallFilter=`, `RestrictAddressFamilies=`, `RestrictNamespaces=` and
`RestrictSUIDSGID=` are enforced.

## Known gaps

What is missing or accepted today; the threat model's [residual risks](threat-model.md#residual-risks) say why each is
accepted and what would remove it.

- **Releases are not signed** — only checked against a published SHA-256 (R3).
- **HTTP is the default**; HTTPS, the redirect and HSTS are switches.
- **The radio keys are in clear** on the storage and in every unencrypted backup (R6). Physical access ends everything
  (R7).
- **Addon pages share the shell's origin** (R1); a malicious addon page acts with the user's rights.
- **The interface daemons' loopback ports have no authentication** (R2): every addon reaches the devices.
- **Classic RPC has no real authentication** when you switch it on (R8).
- **The CCU's legacy alias in addon URLs** is on for the addons that need it (R9): a short-lived alias of the session,
  under `/addons/` alone, which the API refuses everywhere. The API itself takes no credential from a URL since 1.3.0.
- **No second factor** of the system's own: passkeys are an alternative login.
- **No quota** for an addon (R5), and **no AppArmor** profiles.
- **lighttpd does not refuse invalid UTF-8 in a URL**; control characters it does.
- **Switching an addon off is a setting, not a boundary against root.** Nothing on the system starts it until it is switched on, across reboots and updates, but root can still run its script by hand, outside any unit.
- **No fuzz tests, no SAST and no automated dependency scan** in CI yet.

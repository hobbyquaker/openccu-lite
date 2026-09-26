# Threat model

Phase 1. What openccu-lite and occulited protect, from whom, and where the lines run that an attacker
has to cross. It is written to be read before a change at a boundary, and to be checked against what the code does
at every minor release.

**State: first version complete** (2026-09-20, image `1.0.0-dev.19`). It describes the system
as it is, not as it should be: what is missing is named as a check or a residual risk, and each of those becomes a
finding of the review.

- [Scope](#scope)
- [Assets](#assets) — what an attacker is after
- [Actors](#actors) — who attacks, and what they start with
- [Trust boundaries](#trust-boundaries) — the lines and what crosses them
- [STRIDE per boundary](#stride-per-boundary)
- [Trust statements](#trust-statements) — what is deliberately trusted
- [Residual risks](#residual-risks) — known, accepted, and why
- [How this document is kept](#how-this-document-is-kept)

## Scope

**In scope:** the image (openccu-lite, the fork of OpenCCU) and everything it ships — occulited and its privilege
helper, lighttpd as the door, the eQ-3 interface processes (`rfd`, `hmipserver`, `multimacd`, `hs485d`), the addon
mechanism, the update and backup paths, and the system's own network services (sshd, chronyd).

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
| **What** | The BidCos-RF system security key ("Zentralenschlüssel"), the HmIP network key, and the HmIP device keys (DLKs) of every device whose sticker was scanned |
| **Where** | `/etc/config/keys` (rfd, 0600), hmipserver's key files and `crRFD/sgtin.map` on the userfs, both in clear because hmipserver needs them that way; every backup carries them |
| **Who reads them today** | root; occulited only through the helper, and only to write them; of the accounts, an administrator through the Keys page (the device key sheet asks for the password every time) |
| **Lost when they leak** | Control of the devices, and the ability to impersonate the central to them. A key cannot be revoked: changing the BidCos key re-keys every AES device, and a new HmIP network key means teaching every device in again |
| **Lost when they change** | The system talks to nothing until every device is re-keyed or re-paired |

### 2. Control of the devices

| | |
| --- | --- |
| **What** | Switching, dimming, opening, and reading what the sensors report — the reason the system exists. It is reached through the interface processes' XML-RPC, not only through a key |
| **Where** | The interface processes on the loopback (2001, 2010, 9292), lighttpd's classic RPC ports when they are switched on, and occulited's API |
| **Who reaches it today** | Anything on the loopback, which means every addon; a client on the LAN only through classic RPC, whose ports are closed by default and carry the CCU's own optional password |
| **Lost when it leaks** | An attacker opens the door, switches the heating, reads when nobody is home — the privacy and safety of the household |

### 3. The system as a foothold in the LAN

| | |
| --- | --- |
| **What** | A small always-on Linux with root, a shell, an outbound path to the internet and a place in the LAN's trusted zone |
| **Where** | The whole image |
| **Who has it today** | root, and anything that reaches root: the helper's callers, an unconfined addon, an interface process with a memory bug |
| **Lost when it leaks** | The LAN's other devices, the household's traffic, and a machine somebody else pays for and controls |

### 4. Credentials and sessions

| | |
| --- | --- |
| **What** | The accounts' argon2id password hashes, the session store, the API tokens (stored as SHA-256), the OIDC client secret, root's SSH password and root's `authorized_keys`, the classic RPC password, the Wi-Fi PSKs, an ACME account key and the TLS private key |
| **Where** | occulited's state directory (0700 occulite), `/etc/config/shadow` (root, 0640), `/usr/local/etc/ssh/authorized_keys` (root, 0600), `wpa_supplicant.conf` (root, 0600), `server.pem` (root:certs, 0640) — the state directory and most of the files are in every backup |
| **Who reads them today** | occulited for its own store; root for the rest; the helper writes the ones occulited may not read |
| **Lost when they leak** | The administrator's session, and with it assets 1 to 3. A leaked token is scoped; a leaked password is not |

### 5. The backups

| | |
| --- | --- |
| **What** | `.sbk` files: the keys, the credentials, the metadata and the addons' configuration — every asset above in one file |
| **Where** | Downloaded by the browser, or written nightly to a directory the administrator chooses (a USB stick or a share) |
| **Who reads them today** | Whoever can read that directory, and whoever can download one (a session with `system:write`, or a `backup`-scoped token) |
| **Lost when they leak** | Everything above, without touching the system |

### 6. The metadata

| | |
| --- | --- |
| **What** | The device and channel names, the rooms and the functions — the household's floor plan in words |
| **Where** | `meta.json` in the state directory, and the metadata API |
| **Who reads it today** | Every account, the local token an addon holds, and any token with `meta:read` |
| **Lost when it leaks** | Privacy: what the home looks like, which rooms exist, when a device was last touched |

### 7. The system's integrity

| | |
| --- | --- |
| **What** | The image and what runs from it: the firmware update path, the addon packages, the catalogue, the device firmware bundles |
| **Where** | The release zip staged for the recovery system, `/usr/local/addons`, the catalogue's JSON, `/firmware` |
| **Who writes it today** | An administrator, through checked SHA-256 sums; an addon within its own tree |
| **Lost when it is subverted** | Everything, permanently: an attacker who installs the next update owns the system after the reboot |

## Actors

Who might attack the system, what each one already has when they start, and what stands in their way today. The
order is how likely each one is to appear in a real installation, not how dangerous they are.

### A1 · Anything else on the LAN

**Starts with:** an address on the same network — another household device, a guest's phone, a smart TV, an IoT
gadget with its own vulnerability, or a laptop somebody carried in.

**Wants:** the assets in order; most attempts here are untargeted scans.

**Reaches today:** the ports the firewall opens to the local networks — the web server (80, 443), SSH while it is
switched on, the classic RPC ports while they are switched on, the HmIP access points' ports and the discovery
ports. Everything else is dropped by the `RESTRICTIVE` default.

**In the way:** the firewall's policy; the login, with argon2id, a lockout per user and per address, and a first
boot that forces an account; the interface processes listening on the loopback only; classic RPC being off
until somebody switches it on.

**Weakest point:** classic RPC is the CCU's own protocol and has no authentication worth the name — its own
password is optional and travels in the clear on the plain ports. Switching it on is a deliberate act, and the
page says so; an attacker on the LAN who finds it on has control of the devices without a login.

**The Control app's public mode is the same boundary, chosen on purpose:** with it on, a request
without a session on the App's paths becomes the public account — one that operates, never an administrator — so
anyone who reaches the web port operates the house: every switch, dimmer and lock the App shows, but nothing of
the administration, the metadata's writes, the users or the tokens. It is not held to the local networks (a
deliberate choice); the page says it in plain words, the Status page warns while it is on, and the firewall's
rule for the web port is what decides who reaches it.

### A2 · An addon on the system

**Starts with:** code running on the system, the loopback, and the addon's own files. Whether it runs as its own user
or as root is the confinement mode (a confined addon is the default, an unconfined one is root).

**Wants:** root, the keys, and the metadata — or simply to stay and be useful for its author's purpose.

**Reaches today:** the loopback, which means the interface processes' XML-RPC and therefore the devices; its own
tree; the local token, which reads names and rooms; and whatever ports the administrator opened for it.

**In the way:** the confinement (its own user, its own tree, systemd's settings), the helper's allowlist for
everything that needs root, the firewall's per-addon rules, and the catalogue's *verified* mark as a hint to the
administrator before installing.

**Weakest point:** an unconfined addon **is** root — nothing in the way at all. Confinement escapes have been real
bugs here (and known paths are still open, see security.md), and an addon reaches the devices over the loopback whatever
its user is.

### A3 · A malicious or compromised update source

**Starts with:** the ability to serve a file the system will install — a catalogue entry, an addon release, a
device firmware bundle, or a system release. Either the source itself is hostile, or a legitimate one was taken
over, or the transport was.

**Wants:** the system's integrity, which is everything else afterwards.

**Reaches today:** what the administrator installs. An addon package and a system update are checked against a
published SHA-256; the catalogue's entries point at the releases the entry names.

**In the way:** HTTPS to the sources, the checked sums, and the administrator's decision to install.

**Weakest point:** the sum is published by the same party as the file — it proves the download arrived whole, not
that it is trustworthy. Nothing is signed here today.

### A4 · A user account on the system

**Starts with:** a valid login with the `user` role, or a token whose scopes are narrower than the administrator's.

**Wants:** more than the role gives: the keys, the addon settings, root.

**Reaches today:** what the scopes allow — the metadata, the status, the log.

**In the way:** the scope check on every route, the administrator-only routes (only an administrator creates
tokens), and the confirmation the sensitive routes ask for even inside a valid session (the device key sheet, and
an SSH key and root's password).

**Weakest point:** a `user` account is a person the administrator invited; the model assumes they are not hostile,
but the code must not depend on that. Every route's scope is the line, and a missing scope check is the bug class
to look for.

### A5 · A stolen session or token

**Starts with:** a session cookie taken from a browser, a token copied from an addon's configuration, or the
local token read off the state directory by an addon that should not have it.

**Wants:** whatever the session or the token is allowed to do — with a session, everything its account may do.

**Reaches today:** the API, until the session ends or the token is revoked.

**In the way:** `HttpOnly`, `Secure` with the `__Secure-` prefix and `SameSite=Lax` on the cookie; the sessions
list on the Users page, where a session can be ended; tokens carrying scopes, an expiry and an address range;
the confirmations named under A4, which a stolen session alone does not pass.

**Weakest point:** a token is a bearer credential. Its scopes and its address range are the only thing that limits
it, and the addon session in the URL (the legacy CCU convention, an option) puts a session id into a link.

### A6 · An attacker from the internet

**Starts with:** nothing on the LAN — until somebody forwards a port to the system, publishes it through a
reverse proxy, or the router has UPnP on.

**Wants:** all of it, from anywhere, at scan speed.

**Reaches today:** whatever was forwarded. The system does not ask for this and nothing in it opens a port to the
internet by itself; the firewall's automatic rules are for the local networks.

**In the way:** the same as A1, plus HTTPS with a real certificate where ACME is used, and HSTS where it is on.

**Weakest point:** the classic RPC ports (A1) are the worst thing to forward, and a forwarded plain port 80 or
2001 hands over the credentials with the first request. The documentation has to say this where somebody will
read it. The Control app's public mode (A1) forwarded to the internet puts the house's switches on it without a
login; the Remote access page says never to combine the two.

### A7 · Within radio range

**Starts with:** a radio and a place near the house.

**Wants:** to control devices, to listen, or to jam.

**Reaches today:** what the radio protocols allow — outside this document's scope ([Scope](#scope)); the keys are
what this system contributes to that.

**In the way:** the AES key on the BidCos side, the HmIP pairing, and the keys never leaving the system in clear
(except in a backup and on the key sheet, both deliberate and both behind a password).

**Weakest point:** a system that never had its BidCos security key set uses the default key, which everyone knows.
The Status page warns about it and the Keys page sets it.

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

**Crosses:** every request from a browser or a client: the shell, the API, addon pages, classic RPC, the ACME
challenge.

**Checked by:** the firewall (`RESTRICTIVE` by default, one rule per feature that wants a port); TLS where it is
switched on, with HSTS and the HTTP redirect as options; lighttpd's own parsing; the login, the lockout and the
session cookie's flags; the response headers (`X-Frame-Options: SAMEORIGIN`, `nosniff`, `no-referrer`). With the
Control app's public mode on the login is not asked for on the App's paths: the public principal answers
there, held to its level and to the origin rule of lite-rpc, and to nothing else.

**Has gone wrong here:** listeners bound to every interface instead of the loopback.

### B2 · lighttpd ↔ occulited

**Crosses:** the proxied request, and with it the session the gate validated (`X-Occulite-Session`), the client's
address (`X-Forwarded-For`: lighttpd's element, the last one — a client-sent header is removed before lighttpd adds
its own, B-230) and the protocol (`X-Forwarded-Proto`).

**Checked by:** occulited listening on `127.0.0.1:2121` only; the gate script, which validates the session
before an addon page is served and **removes a client-sent session header** before it sets its own; occulited
trusting the forwarded headers only because nothing else can reach the port.

**Has gone wrong here:** the gate itself. The rule to keep: anything a client may send and lighttpd may
also set has to be removed before it is set.

### B3 · occulited ↔ the privilege helper

**Crosses:** one operation per request over `/run/occulite/helper.sock` (root:occulite, 0660) — a command from
the program list, a file write under an allowed prefix, or one of the named operations (the root password, the
certificate, the LED frames, the log listing, and root's `authorized_keys` and ending an SSH
session).

**Checked by:** the socket's group; `priv.Policy`, which is an allowlist of programs, path prefixes and exact
paths; and each named operation's own check **at the boundary**, not only in the caller (the key is parsed again,
the certificate is parsed again, the pid must be an `sshd-session`).

**Has gone wrong here:** the shell allowlist was a prefix test; write paths ran outside the helper; the ownership repair walked addon-controlled paths as root.

**The rule:** the unprivileged side assembles, the helper decides. Anything the helper accepts because "occulited
would not send that" is a bug waiting to be found.

### B4 · The helper ↔ root

**Crosses:** what the helper actually does — writing a file, running a program, signalling a process.

**Checked by:** the operation's own narrowness. A named operation exists so that a general one does not have to:
`/etc/config/shadow` is never readable by occulited because the helper rewrites one field of one line;
`authorized_keys` is written as a whole section rather than by a general file write.

**Watch:** every new general capability (a new program on the list, a new write prefix) widens this line for
everything, not only for the feature that asked for it.

### B5 · The system ↔ addons

**B5a, an addon's HTTP side:** its static files and its CGI under `/addons/<id>/`, and its lighttpd drop-in.
lighttpd runs as `www-data`, its drop-in is a root-owned copy occulited validated against an
allowlist (no `include_shell`, no socket, a proxy target on this system only — the copy, never a link into the
addon's directory), and the files are served by occulited as `occulite` through `os.Root`, which follows no link
out of the addon's tree; a `.cgi` runs through occulited, as the addon's own user where it has one, with
the CGI environment lighttpd used to provide. The gate (B2) requires a live session first.

**Has gone wrong here:** lighttpd ran as root and read a confined addon's drop-in through a link, and served its
www with root's rights.

**B5b, an addon's system side:** its own user and group, its own tree under `/usr/local/addons/<id>`, its unit
file, the ports it declares, and the local token it may read.

**Checked by:** the confinement, the helper for anything privileged, the firewall for its ports, and the
catalogue's marks (*verified*, *community*, *untested*) as information for the administrator.

**Has gone wrong here:** X-Sendfile served outside the boundary; an addon's own unit file gave it
root; known confinement escape paths that are still open (security.md).

**The residual line:** an addon reaches the interface processes over the loopback whatever its user is — B6 does
not distinguish callers. An unconfined addon is root by definition.

### B6 · occulited (and the addons) ↔ the eQ-3 interface processes

**Crosses (B6):** XML-RPC and BIN-RPC on the loopback — `init`, `listDevices`, `putParamset`, `setValue`, the
subscriptions, and the events the processes send back to whoever registered.

**Crosses (B6b):** the key files and the configuration occulited writes for them, and the coprocessor's firmware
during a flash.

**Checked by:** the loopback, and nothing else. There is no authentication on these ports, and the processes are
eQ-3's binaries running as root today (confining them is still to come).

**The rule:** anything on the loopback is as good as the interface processes' owner. That is why an addon's
confinement does not stop it from switching a device, and why classic RPC is a switch and not a default.

### B7 · The system ↔ the outside sources it calls

**Crosses:** the addon catalogue, the addon releases it points at, the openccu-lite release feed, eQ-3's device
firmware server, the ACME directory of the chosen CA, NTP, and the remote syslog host where one is set.

**Checked by:** HTTPS; the published SHA-256 of a release or an addon package; the ACME account key and the
challenge; the administrator's decision to install anything at all. Nothing here is signed by a key this system
holds.

**Watch:** these are the only outbound paths, and each one is a place where a hostile answer becomes local data
(A3). The parsers on this side — JSON of the catalogue and the feed, the firmware bundle's `info` — are the ones
a fuzz test should see first.

### B8 · The running system ↔ the recovery system

**Crosses:** a staged release file and the marker that arms the install; the recovery system writes the boot and
root partitions at the next boot and keeps `/usr/local`.

**Checked by:** the file's kind and checksum when it is staged, the administrator's confirmation, and the
recovery system's own checks.

**Watch:** this is the one path where a file written today becomes the whole system tomorrow. Whoever can stage a
file and arm the marker owns the system after the reboot, without ever being root while the system runs.

## STRIDE per boundary

Six questions per line: spoofing, tampering, repudiation, information disclosure, denial of service, elevation of
privilege. **What stands in the way** is what the code does today; **to check** is what the audit's manual review
and its tooling have to confirm, and is the list that becomes findings.

### B1 · The LAN ↔ lighttpd

| | Here that would be | In the way today | To check |
| --- | --- | --- | --- |
| **S**poofing | Answering as the system (ARP or DNS in the LAN), or using a stolen cookie (A5) | TLS with a real certificate where ACME runs; the cookie's flags; the lockout | Whether a self-signed system — the default — gives the browser anything to pin at all; what HSTS does after a way back to OpenCCU |
| **T**ampering | Changing a request in flight on the plain port; CSRF from another site | HTTPS and the redirect as options; `SameSite=Lax`; the API needs JSON and a session | Every state-changing route for `SameSite=Lax` being enough (a top-level POST from a hostile page is not blocked by Lax); whether any GET changes state |
| **R**epudiation | "It was not me who switched the heating" | The journal, with occulited's own lines at their real priority; the log page | Which state changes are logged with who and from where — the SSH and key routes are, the older ones are not all |
| **I**nformation disclosure | Reading the API without a login; an error page that says too much | The scope check per route; the login; `no-referrer`; the open routes are exactly the health, the SBOM, the ACME challenge and the login itself | The list of open routes, deliberately, in one place; error texts that carry a path or a version |
| **D**enial of service | Filling the login, the upload or the log stream | The lockout per user and per address; lighttpd's own limits; the upload's size cap | The follow stream's per-session cost; whether an unauthenticated request can start real work (the ACME challenge, the health check) |
| **E**levation | Reaching an administrator's route as a user, or with no session at all | The scope check; the confirmations (the password again for the key sheet and the SSH settings) | Every route's scope, mechanically: a test that walks the mux and asserts a scope for each |

### B2 · lighttpd ↔ occulited

| | Here that would be | In the way today | To check |
| --- | --- | --- | --- |
| **S**poofing | A client sending `X-Occulite-Session` itself, or faking `X-Forwarded-For` to dodge the lockout | The gate removes a client-sent header before setting its own; the global magnet removes it everywhere the gate does not run; both remove a client-sent `X-Forwarded-For`, `-Proto`, `-Host` and `Forwarded` too, and occulited takes only the last element of `X-Forwarded-For` (lighttpd's), and only from the loopback (B-230); only lighttpd reaches 2121 | That both removals are still in place after any lighttpd config change — this is the bug class; that nothing but the loopback can reach 2121 |
| **T**ampering | Changing the proxied body or the path | The loopback; lighttpd is the only writer | The path rewriting rules: what `/addons/<id>/…` can become before occulited sees it |
| **R**epudiation | — | The request log names the address the gate forwarded | Whether the log's address is the forwarded one and not lighttpd's |
| **I**nformation disclosure | An answer meant for one session served to another | No shared cache; `Cache-Control: private, no-cache`; the session decides the answer | Any route that answers the same bytes to everyone and is cached by lighttpd |
| **D**enial of service | A slow client holding a proxy connection | lighttpd's limits; occulited's read-header timeout | The long-lived answers (the change stream, the log follow): how many a session may hold |
| **E**levation | Reaching the API without passing the gate | The API's own session check — the gate is for the addon pages, not a substitute | That no route trusts the gate alone |

### B3 · occulited ↔ the privilege helper

| | Here that would be | In the way today | To check |
| --- | --- | --- | --- |
| **S**poofing | Another process on the system calling the helper | The socket is root:occulite 0660 — the group is the line | Which users are in `occulite`; that no addon is |
| **T**ampering | A request that carries more than its operation should (a path beside a pid, data beside the keys) | Each named operation refuses the fields it does not use — the SSH operations, the log listing, the LED frames do this explicitly | The same refusal on the older operations; a table of operation → the fields it accepts |
| **R**epudiation | — | The helper logs what it refuses, and the daemon logs what it asked for | Whether every refusal is logged once and not per line (a journalctl refusal was once a silent failure on the daemon's side) |
| **I**nformation disclosure | Reading a file through the helper that the daemon may not read | `ReadPaths` is an allowlist; `/etc/config/shadow` is deliberately not on it; the answers carry only what the page shows (the log listing returns names and sizes, never content) | Each read path, against what the page actually needs |
| **D**enial of service | A request that never ends, or a flood | One connection per call with a deadline; the helper is single-purpose | The timeouts on the long operations (a flash, a firewall load) |
| **E**levation | A path or a program that is wider than intended | The policy's exact paths and prefixes; the program list; the checks at the boundary | Every prefix in the policy, read as an attacker would: what is under it that an addon can write? |

### B4 · The helper ↔ root

| | Here that would be | In the way today | To check |
| --- | --- | --- | --- |
| **S**poofing | — | The helper is root; there is nothing above it to impersonate | — |
| **T**ampering | Writing through a symlink an addon controls; a partial write that leaves a broken file | The writes stage and rename; the ownership walk does not follow links (the fix) | Every write the helper does, for symlink and TOCTOU handling; that a rename cannot land outside the intended directory |
| **R**epudiation | — | The journal | — |
| **I**nformation disclosure | A file read as root and handed out whole | The named operations return only what is needed (the certificate's blocks, not the key) | Each operation's answer, field by field |
| **D**enial of service | An operation that blocks the helper for everyone | Timeouts; the helper answers one connection at a time | Which operations can run long, and whether one caller can starve the others |
| **E**levation | The whole line: anything wrong here is root | The narrowness of each operation | New operations, every time: what does this let the unprivileged side do that it could not do before? |

### B5 · The system ↔ addons

| | Here that would be | In the way today | To check |
| --- | --- | --- | --- |
| **S**poofing | An addon page passing itself off as the shell (a login form in a frame); an addon using another addon's token | `X-Frame-Options: SAMEORIGIN` keeps a foreign site out, but an addon **is** same-origin; each confined addon has its own user and its own token | The known residual risk: a same-origin addon frame can read the parent page. Whether the shell may be framed by an addon at all, and what an addon page can reach through `window.parent` |
| **T**ampering | An addon writing into another addon's tree, into occulited's state, or into a unit file that gives it root | The confined user owns only its own tree; unit files come from the helper, not from the addon (the fix); the ownership walk does not follow links | Every path an addon can write that another component later reads or executes — the catalogue's cache, the shared directories under `/usr/local`, anything the helper touches by prefix |
| **R**epudiation | An addon acting through the local token, indistinguishable from the system | The token is the addon's own; occulited logs the token's name | Whether an addon's calls are traceable to the addon in the log, or only to "a token" |
| **I**nformation disclosure | Reading the keys, the metadata or another addon's configuration from the file system or over the loopback | The confinement's file permissions; the local token reads names and rooms only; the keys are root's | What an addon user can read today, measured on the system, not assumed: a walk of `/usr/local` and `/etc/config` as an addon user belongs in the audit |
| **D**enial of service | An addon filling the disk, the journal or the CPU | The storage hint and the journal's limits; nothing enforces a quota | Whether an addon can fill the userfs and stop the system from writing its own state — no limit exists today |
| **E**levation | An escape from the confinement to root | The unit's settings, the helper's allowlist, the addon user | Known escape paths are still open (security.md); the audit's manual review starts here. Also: what an **unconfined** addon means (it is root, by definition, and the catalogue's mark is the only warning) |

### B6 · occulited (and the addons) ↔ the eQ-3 interface processes

| | Here that would be | In the way today | To check |
| --- | --- | --- | --- |
| **S**poofing | Anything on the loopback calling `putParamset` as if it were the system; a client registering a callback in somebody else's name | Nothing — the ports have no authentication. Only the loopback limits who calls | Whether classic RPC's optional password is the only thing between the LAN and this, when it is switched on; whether a subscriber's id is checked at all (the Registered clients page shows duplicates, which says it is not) |
| **T**ampering | Changing a device's parameters or its pairing through the loopback | Nothing on this line | What occulited itself would notice — a changed paramset appears in no log today |
| **R**epudiation | A change nobody can attribute | occulited logs what it sends; an addon's own calls are not in occulited's log at all | Whether the interface processes' own logs name the caller (they carry the subscriber id at init time) |
| **I**nformation disclosure | Reading every device, its values and its pairing over the loopback | Nothing on this line | What an addon learns this way that its token would not give it — in practice, everything |
| **D**enial of service | An addon flooding the processes, or registering so many callbacks that events stop | Nothing; the processes are single-threaded on this path | What happens to the system when a subscriber's callback hangs — the reachability probe exists because unreachable callbacks are common |
| **E**levation | Reaching root through a process that runs as root | The processes are eQ-3's binaries, running as root today | The confinement is the answer; until then, this is the softest root path on the system after an unconfined addon |

### B7 · The system ↔ the outside sources it calls

| | Here that would be | In the way today | To check |
| --- | --- | --- | --- |
| **S**poofing | A hostile server answering as the catalogue, the release feed, eQ-3's firmware server or the ACME CA | HTTPS with the system's trust store; the ACME account key | Whether the trust store is the one the image ships and is updated; whether a failed name check anywhere falls back to plain HTTP |
| **T**ampering | A changed release, addon package or firmware bundle | The published SHA-256 for releases and addon packages | That every download path checks the sum before it is used — the device firmware bundles do not have a published sum, so what is the check there? |
| **R**epudiation | — | The run log keeps an ACME or a firmware run | — |
| **I**nformation disclosure | What the system tells the outside: which version, which devices, which addons | The release check sends the version and the platform; the firmware check sends the paired device types; the syslog forward sends the journal | The exact fields of each outbound call, written down — a privacy statement belongs in the documentation |
| **D**enial of service | A source that never answers, or answers endlessly | Timeouts on each call; the checks are daily, not per request | Response size limits: what happens when the catalogue answers 2 GB of JSON |
| **E**levation | A hostile answer becoming code | Nothing is executed from these sources without the administrator installing it | The parsers: the catalogue's JSON, the feed, the firmware bundle's `info`, the addon package's `update_script` — this is the first place for fuzz tests |

### B8 · The running system ↔ the recovery system

| | Here that would be | In the way today | To check |
| --- | --- | --- | --- |
| **S**poofing | A file that claims to be a release for this platform | The kind and the board are read from the file and shown before the install | Whether a file's own claim is believed anywhere it should not be |
| **T**ampering | Changing the staged file between staging and the reboot | It lies on the userfs, writable by root only | Who can write the staging directory; whether the sum is checked again at install time or only at staging |
| **R**epudiation | — | The install is logged, and the recovery system keeps its own log | — |
| **I**nformation disclosure | — | — | — |
| **D**enial of service | A staged file that fills the userfs; a system that stays in the recovery | The size is checked before staging; the Status page's notice watches for a system that does not come back | What the recovery system does with a file that fails its own check — it must not leave the system unbootable |
| **E**levation | The whole line: a staged file becomes the next system | The administrator's confirmation, the sum, the recovery system's checks | Signing. Today a sum published by the same party as the file is the only tie; this is the single most valuable place for a signature, and the audit should say so plainly |

## Trust statements

What this system deliberately trusts. Each of these is a decision, not an oversight: if one of them is wrong for
an installation, the controls below it do not help.

### T1 · The administrator is root on the system

An administrator can write a unit file (own timers, unit overrides), install an addon, set root's password, add an
SSH key and install a system update. Every one of those is root, directly or at the next boot. **The system does
not try to protect itself from its own administrator** (F-8).

What follows from it:

- Splitting "administrator" into smaller powers would be theatre as long as these routes exist.
- What the audit does check is that every such route needs the administrator role and a token cannot reach it with
  a lesser scope.
- The `user` role is a different matter: it is not trusted with any of this, and that line is enforced per route.

### T2 · An addon is trusted as far as its confinement says

- **Confined** (the default): its own user, its own tree, its own unit. It is trusted with its own data, the
  loopback — and therefore the devices (B6) — and the local token's read of names and rooms. It is not trusted
  with root, with another addon's tree, or with the keys.
- **Unconfined:** it is root. There is no boundary left; installing one is a decision to hand the system over. The
  catalogue marks it and the Addons page says so.
- **In the browser** the addon is same-origin with the shell (F-1). The decision is defence in depth, not a
  separate origin: the API cookie is kept away from `/addons/`, API writes need a header credential, `Origin` and
  `Sec-Fetch-Site` are checked, and the shell gets a CSP. **The residual risk stays** and is stated below.

### T3 · The eQ-3 interface processes are trusted, as black systems

`rfd`, `hmipserver`, `multimacd` and `hs485d` are eQ-3's binaries. They run as root today, their loopback ports
have no authentication, and their source is not ours to audit. The system trusts them with the radio and with the
keys because there is no alternative that still talks to Homematic devices. Narrows what a compromise of
one of them reaches; it does not make them trustworthy.

### T4 · The LAN is not trusted, the loopback is

Every LAN device is a potential attacker (A1). The loopback is treated as trusted, which is what makes B6 work at
all — and it is why an addon's confinement stops at the devices.

### T5 · The sources are trusted to the extent they are checked

A release and an addon package are checked against a published sum: that is integrity, not authenticity (F-7).
The decision is to sign releases with minisign, an offline key the project's maintainer holds, the public key in the
image, and to refuse an unsigned update or catalogue install. **Until that is built, the trust statement is: the
system trusts whoever controls the release hosting.**

### T6 · The administrator's browser is trusted

Sessions live in a cookie; a compromised browser or a malicious extension has the administrator's rights. Nothing
here defends against that, and the confirmations (the password again for the key sheet, an
SSH key, root's password) are the one place where a stolen session alone is not enough.

## Residual risks

Known, accepted for now, and written down so that nobody has to rediscover them. Each names what would remove it.

| # | Risk | Why it is accepted | What would remove it |
| --- | --- | --- | --- |
| R1 | **A same-origin addon frame can read the parent page** and act with the administrator's rights (F-1) | Separate origins would break the addon ABI every CCU addon relies on; defence in depth was chosen instead | Addons on an origin of their own, which is a break with the CCU convention |
| R2 | **An addon reaches the devices over the loopback**, whatever its confinement | The interface processes have no authentication and are eQ-3's (T3) | A proxy in front of the interface processes that knows callers — a large change, and it would break addons that talk to 2001 directly |
| R3 | **A release is only as trustworthy as its host** (F-7) | Signing is decided but not built | The phase 7: minisign, the public key in the image |
| R4 | **The eQ-3 processes run as root** | They are black systems; confining them is still to come and needs care with the radio | |
| R5 | **No quota for an addon**: it can fill the userfs or the journal | The storage hint warns, but nothing enforces | Per-addon limits in the unit (systemd's `MemoryMax`, a quota on the tree) |
| R6 | **The keys are in clear on the storage and in every backup** | hmipserver needs them that way; a backup has to restore them | Nothing short of a change in hmipserver; a backup password would help the backup alone |
| R7 | **Physical access ends everything** (A8) | Out of scope; full-disk encryption is not part of the product | Encrypted storage with a key that is not on the same card |
| R8 | **Classic RPC has no real authentication** | It is the CCU's protocol, and compatibility is the point of it | Nothing, within compatibility: it stays a switch that is off by default, with the warnings on its page |
| R9 | **`?sid=` puts a session id in a URL** | The CCU addon convention needs it | The narrow legacy alias, on by default only for undeclared addons |

## Audit log

The "to check" rows that were checked, and what became of them. One entry per slice of the audit.

**2026-09-26 — B1 and B2, the authentication, session and access-control slice** (occulited `00fda6e`, image
`1.0.0-dev.25`; the checklist is [security-asvs.md](security-asvs.md), the product baseline
[security-en303645.md](security-en303645.md)):

| row | outcome |
| --- | --- |
| B1 *Spoofing* — the lockout, the cookie's flags | the flags hold (V7.5); the lockout by address is dodged with a client-sent `X-Forwarded-For` → **B-230** (confirmed on a lab system) — **fixed** 2026-09-26: occulited `5b63d52`, the fork's global magnet script |
| B1 *Tampering* — `SameSite=Lax` alone | not alone any more: the `Origin`/`Sec-Fetch-Site` check of task 213 covers every state-changing call on the cookie; the header credential and the CSP of D-78 remain → **task 259** |
| B1 *Repudiation* — which changes are logged with who and from where | password logins, refusals and lockouts are at debug → **B-231**; the older system routes log the action without the caller (stays open in B-231's wake) |
| B1 *Information disclosure* — the list of open routes | `open()` in `internal/httpapi/auth.go` is the one list: health, version, the auth flow, the ACME challenge, the pairing request, `addonctl` (own token), `homematic.cgi` (loopback only — the loopback was decided on the forged address, **B-230**, fixed 2026-09-26), the SBOM. Each answers nothing a session would guard, except that one |
| B1 *Denial of service* — unauthenticated work | the login's argon2 runs one at a time; eight authenticated JSON routes read bodies without a cap, no idle timeout → **B-232** |
| B1 *Elevation* — every route's scope, mechanically | `TestRouteTable` walks the mux; the default is deny; pass |
| B2 *Spoofing* — a faked `X-Forwarded-For` | lighttpd appends the real address to a client-sent header and occulited takes the first element → **B-230** — **fixed** 2026-09-26: occulited takes the last element, and only from the loopback; the fork's global magnet and the gate remove the client's header (`lite-lighttpd-redirect-test.sh` checks it on a real lighttpd) |
| B2 *Repudiation* — the log's address | the forwarded one, and therefore the client's choice → **B-230** — **fixed** 2026-09-26: lighttpd's element |
| — (V6.3) | the login skips argon2 for an unknown account: a timing oracle for names → **B-233** |
| B3 *Elevation* — every program and prefix, read as an attacker would | `programAllowed` shapes the arguments of `sh` only; `systemd-run`, `systemctl`, `kill`, `ip`, `install_addon`, `restoreBackup.sh` … run with any arguments — a compromised daemon is root → **B-234** |
| B4 *Tampering* — every write, for symlink and TOCTOU handling | the `symlink` operation checks the link, not its target, and `WriteFile` resolves links before writing → a root write to any file from an allowed prefix → **B-235**; the writes into addon-controlled trees are listed there |

## How this document is kept

- **Reviewed at every minor release** (the standing process), and whenever a boundary changes: a new helper
  operation, a new open route, a new outside source, a change to the confinement.
- **An agent's prompt for boundary work names this document** — the boundary it touches, and the "to check" rows
  of that boundary.
- **The audit's records** are [security-asvs.md](security-asvs.md) (the code against OWASP ASVS 5.0 L2) and
  [security-en303645.md](security-en303645.md) (the product against ETSI EN 303 645); the [audit log](#audit-log)
  above says which rows were checked when.
- **The "to check" column is the audit's backlog.** Each row becomes a finding (a bug or a task) with a CVSS 3.1
  rating, or is struck out with the reason it is not a finding.
- **The bugs are kept in the boundary sections** so the pattern stays visible: nearly every security bug in this
  project so far sat on a line in [Trust boundaries](#trust-boundaries), and most were found by reading, not by a
  tool.
- **Changes to a trust statement are decisions,** recorded in `decisions.md` and then here — not the other way
  round.


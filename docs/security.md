# Security: what openccu-lite does today, and what it still owes

**The audit's records** (task 120): [threat-model.md](threat-model.md) — assets, actors, boundaries and the residual
risks; [security-asvs.md](security-asvs.md) — the code against OWASP ASVS 5.0 Level 2, row by row;
[security-en303645.md](security-en303645.md) — the product against ETSI EN 303 645.

The honest baseline: separate users now, AppArmor later.
Written 2026-09-06 for the busybox-init step; the move to systemd changed the last section.

## What listens where

| | bound to | reached by |
| --- | --- | --- |
| lighttpd | the LAN, 80/443 | browsers, addon clients |
| `occulited` | `127.0.0.1:2121` only — refuses any other `listen` | lighttpd (proxy), programs on the system |
| `rfd`, `hs485d`, `hmipserver` | the loopback: `Listen IP = 127.0.0.1` in `rfd.conf`, `Legacy.BindAddress=127.0.0.1` in `crRFD.conf` — both verified on a running system; the fork ships them in its config templates | `occulited`, addons on the system |
| sshd | the LAN, 22, only while the SSH switch is on; the firewall opens the port for local networks only | the administrator |

The CCU's XML-RPC proxies on 2001/2000/2010/9292 exist only when the user switches them on (task
143, below); the ReGa ports 1999/8181/8183 do not exist at all. Without the switch, an integration
that ran *off* the system and talked to those must run *on* the system or use the metadata API.

**Classic RPC, the way out** (System → Remote access, off by default). Two
switches, plain (2001, 2010, 9292; 2000 where hs485d runs) and TLS (42001, 42010, 49292; 42000),
make lighttpd serve the CCU's ports again and proxy them to the interface processes, which stay on
the loopback — `S50lighttpd` writes only the switched-on sockets (`lite-classic-rpc-conf`), never
upstream's ReGa ones. The risks are the CCU's and the page says them: without a login, whoever the
firewall lets in controls every device; with the login on the plain ports, the password travels
in clear text. The login is a user name and password of its own — not the system's accounts (argon2id
would block single-threaded lighttpd for up to 931 ms per check on a Pi 3), not API
tokens — stored as SHA-512-crypt in a root-0600 htpasswd file and checked by lighttpd's
`mod_authn_file` (about 2 ms uncached on the Charly), realm `theRealm`, the loopback exempt. As on
a CCU there are no per-method rights, no trace and no lockout; lite-rpc is where those
come. Each open port has an owned firewall rule from `local networks`. Measured 2026-09-18: the
stock OpenCCU and lite answer the same 401 and realm; BIN-RPC through lighttpd's proxy gets no
answer on either; a client off the system with the pair gets `listDevices`/`newDevices` callbacks
from hmipserver and rfd; lighttpd's graceful reload keeps answering one request with the old
configuration right after a change (milliseconds), and keeps a listening socket the new
configuration dropped — so a switch change restarts lighttpd instead.

**Verified from another machine on the LAN** (2026-09-07, against a test system): 22, 80 and 443
answer; 2000, 2001, 2010, 2121, 8181, 9292, 32001, 32010 and 39292 all refuse. Holds for
everything openccu-lite runs — with classic RPC off; switched on, lighttpd answers on its ports.

**The bare host name redirected to its full name** (System → Certificate, off by default).
With the switch on, lighttpd answers `GET` and `HEAD` for `https://<host>/` — and for
`http://<host>/` together with the HTTP → HTTPS redirect, in one hop — with `302` to
`https://<host>.<domain>/`, path and query kept, so a browser keeps one name: one session cookie,
one HSTS entry (the redirect carries the header too), one saved password. Left alone: any other
method, so a script's `POST` is not turned into a redirect it might not repeat with its body;
`/api`; `/.well-known/acme-challenge/`; the loopback; IP literals and every other name. `302`, not
`301`, because a browser keeps a `301` after the switch is off. The name is used only while the
live certificate covers it — occulited refuses to switch the redirect on otherwise, and
`S50lighttpd` checks again at every reload — so the redirect never leads into a certificate
warning: after a rename or a new domain it waits for a certificate for the new name. The match is
lighttpd's `$HTTP["host"]`, case-insensitive, with or without a port; checked with curl against
lighttpd in a container (`scripts/lite-lighttpd-redirect-test.sh` in the fork).

**The firewall is one list of INPUT rules** (libfirewall is out of the image).
The policy is `DROP` in both families — the `RESTRICTIVE`, now stated as what iptables does — and
a port no rule accepts is closed, whatever binds it. What a feature needs is an owned rule the system
adds and removes with the feature (the web server, SSH, classic RPC, the HmIP access points, the
network discovery, an addon's opened port), each with a comment saying why; every rule is editable.
A change from the page loads with a 60 s confirm window the privilege helper keeps, so a rule that
cuts the page off reverts by itself. At boot the rules load before the network. A system that arrives
from OpenCCU converts its `firewall.conf` once, keeping what OpenCCU's patched libfirewall did:
*full* services and user ports come from `local networks` (its local-only chain), MOST_OPEN becomes
policy ACCEPT only where the default was never applied (the marker), and open XMLRPC switches
classic RPC on unless `authEnabled` asked for a ReGa login.

**The cost is explicit rather than discovered**, the same standard the XML-RPC
change: an update closes addon ports that answered before it. Measured on a test system while it was
still `MOST_OPEN`: the Mosquitto addon — installed from the catalogue in one click, marked
*verified*, the first-class pairing — listens on 1883, 1884 and 8883 with `allow_anonymous true`
in its shipped configuration, and a subscriber on the LAN with no credentials received every device
value the hm2mqtt bridge publishes, `hm/set/#` being a topic the same bridge acts on. Under the `DROP` policy that subscriber is refused, and the way to allow it deliberately is a rule —
or the addon's own switch: a catalogue entry declares its ports (`runtime.ports`,
described in `runtime.port_info`), the Addons page lists each one with a switch that is off by
default, and a switched-on port becomes the addon's owned rule.
The point of one switch per port is exactly this case: the TLS listener can be opened and the
plaintext one left closed. An uninstall closes them again.

None of that was an openccu-lite regression: a CCU3 in `MOST_OPEN` with the same two addons behaves
identically, and the addons are doing what an MQTT broker and a bridge are for. It is written down
because the sentence above it — "nothing listens beyond the loopback except lighttpd" — is true of
*this project's* processes and not of the system as a user will run it. The remaining half is making
it visible: the Firewall page's view of ports that are listening and that no rule covers
which under `RESTRICTIVE` is what turns "my addon stopped answering" into a page
that names the port.

## Who is who

- **Accounts** in `users.json` (argon2id, 32 MiB, parameters in the hash), roles `admin` and
  `user`. `user` reads everything and changes only its own password; every mutation is `admin`.
  Failed logins lock the name and the remote address for a while. An account may have no password: it then signs in through the identity provider only, and `POST /login` fails for it
  like a wrong password — the login page tells no names apart.
- **Sessions**: a 10-character id (uniformly random alphanumerics, 59.5 bits), 30 days from the
  login, 24 h idle timeout; cookie (`HttpOnly`, `Secure` behind TLS, `SameSite=Lax`), bearer
  header, or `?sid=` — the CCU convention addon pages rely on. **Sessions survive a restart of
  occulited and a reboot**, and **no session id is written anywhere**: occulited
  keeps each session under the SHA-256 of its id — in memory, in the session store and in the
  gate's mirror — and hashes the id a request carries to find it.
  - *The session store* `/usr/local/etc/occulite/sessions/sessions.json` (config.md) holds per
    session the hash, the user, role and login method (`password` or `oidc`), the login time, both
    expiries, a last-seen time at most ten minutes old, the client address and user agent (the
    session list shows them). `0600` in a `0700` directory of the `occulite` user. Its directory
    carries `.nobackup`, so **no backup contains it** (the firmware's backup tars `/usr/local`
    with `--exclude-tag=.nobackup`); a restored backup brings no session back.
  - *Written* at a login, a logout, *sign out everywhere*, ending a session from the list, a
    password change, a user deleted or given another role, an expiry (a request or the five-minute
    sweep), a clean shutdown, and a last-seen time at most every ten minutes per session — never on
    every request. Atomically (a temporary file renamed). A write that ends a session and fails
    removes or empties the store rather than leave that session to come back at the next start.
  - *Changes outside occulited*: a reboot no longer ends sessions, so nothing relies on it. A
    password set with `occulited passwd <user>` on the console ends that account's sessions —
    the command removes them from the store, and a running occulited drops them before the
    account's next request (it looks at `users.json` on every session check). An account removed
    from `users.json` by hand or by a restored file loses its sessions the same way, a changed
    role is taken over, and a missing `users.json` ends every session.
  - *At start* occulited drops what no longer fits — an expired session, a user that is gone, a
    login method the running mode does not offer (a provider session without the provider, every
    session with authentication off) — takes each role from `users.json`, rebuilds the gate's
    mirror from the rest and then serves. A restored session keeps its original expiry. An
    unreadable or corrupt store restores nothing (everyone logs in again) with a warning in the
    journal; the start never fails on it.
  - *What the hash does not protect*: the id has 59.5 bits, so whoever reads the store (root, or
    the `occulite` user) could find an id by brute force, with a large GPU effort, within its 30
    days; that reader can read `users.json` and the system's TLS key as well. API tokens (128 bits)
    and the local token are unaffected. The recovery system does not read the store.
- **API tokens** (`olt_…`): sha256 in `users.json`, **scopes** each (the list and
  the route table in [system-api.md → Scopes](https://github.com/hobbyquaker/occulited/blob/master/docs/system-api.md#scopes)), shown once; an
  expiry and allowed address ranges are optional. Every API route names its scope, the
  middleware refuses with a `403` that names the missing one, and a route without a scope in the
  table is reached by nobody — the default is deny. Full access (`*`) is a wildcard over every
  scope, later ones included. Accounts keep `admin` and `user` (Full access; the three read scopes
  plus one's own account). A `users.json` from before the scopes migrates its tokens by their role
  (`admin` → `*`, `user` → the read scopes, `led` → `led`) — nothing is widened but `admin`,
  which was everything already. Only administrators create tokens.
  - **The local token** `<state>/local-token` is **world-readable, `0644`, on purpose**: it is
    the system's token for the programs running on it, root or confined alike, and it holds
    **`meta:read` alone** — names and rooms; the journal and the system pages are out of its
    reach. The state directory is `0711` for the same reason: reachable, not listable. A token
    from before the scopes keeps its secret and loses every other scope at the first start.
  - **An addon's own token** comes from its catalogue entry's `runtime.api_scopes`: minted at
    every start, after an install and after a policy change, `/run/occulite/addon-tokens/<id>.api`
    (`0600`, the addon's user) beside its control token, in memory only, never in `users.json`,
    gone with the addon. Never `*`, `auth:admin`, `power` or `backup`: a declaration naming one
    is logged and the scope left out. An addon without a declaration has the local token alone.
  - The daemon's own update check of an addon rides on a `system:read` token it mints for
    itself at start, not on the local token.
  - **The scope `led`** (the role, which no account can have): the status LED's state, its
    own override and locate (`GET /api/system/v1/led/state`, `POST`/`DELETE /led/override[/{id}]`,
    `POST`/`DELETE /led/locate`) and nothing else — every other route, addon pages included,
    answers 403.
- **The identity provider** (OIDC): a provider login is the account of exactly the
  provider's user name (`username_claim`, compared as a string), with or without a password, with
  the role it has here — nothing is created from a provider identity, an unknown name is
  refused and logged with the remote address, and the provider is trusted with the name. Password
  login beside the provider is a switch (`auth.oidc.password_login`, [config.md](https://github.com/hobbyquaker/occulited/blob/master/docs/config.md)): off,
  the provider is the only way into the web interface, `POST /login` and `POST /password` answer
  `403 password_login_disabled`, and it can only be turned off from a session that came through the
  provider. **The break-glass is the console**: `occulited auth password-login on` and `occulited
  passwd <user>`, as root over SSH or on the system — a provider that is down never locks the console
  out, only the browser. The first-boot setup always takes a password.
- **Addon pages** (`/addons/…`): lighttpd's `mod_magnet` gate checks for a live session before the
  request reaches the CGI — one SHA-256 (`lighty.c.md`) and one `open()` against the session
  mirror on tmpfs, `/run/occulite/sessions`, whose files are named by the hash of the session id, so the mirror holds no usable id either. Addons keep their own `tclrega` check; the
  shim hashes the id it is asked about the same way and answers exactly that call and nothing else.

**The `certs` group (2026-09-09).** `/etc/config/server.pem` — the system's TLS certificate
*and* key, one PEM, what lighttpd serves and what S50lighttpd regenerates when it expires — is
`root:certs 0640`; `lite-cert-perms` sets that after every lighttpd start and reload. Every
confined addon runs with `SupplementaryGroups=certs`, so a broker (mosquitto's `8883`)
or a web server behind its own user offers TLS with the system's certificate instead of dying on
a permission error. The group is a trust boundary: whoever is in it can impersonate the
system on TLS. Root addons read the file anyway; nothing else is in the group.

**The certificate itself.** The live file can come from an ACME CA now — Let's
Encrypt, ZeroSSL, or a LAN CA such as step-ca — issued and renewed by occulited with lego as a
library ([tls-acme.md](tls-acme.md)) — or one the user brings himself (mode
*manual*: uploaded or pasted, PEM or DER, or signed by his CA for a key and request the system made;
that key lives under `<state>/tls/` as the `occulite` user and no route ever returns it). Three
things about it belong on this page. The helper got **two enumerated operations** for that one
file, `writecert` and `readcert`, with an allowlist of exactly three paths (`CertPaths`:
`/etc/config/server.pem` and the two markers the operation writes beside it — root 0644, one line
each: **`/etc/config/server.pem.managed`** with the mode, `acme` or `manual`, and the leaf's issuer, and the `/etc/config/server.pem.acme` with the issuer alone, kept until the
fork's `S50lighttpd` reads the new name; the issuer is derived from the PEM, never taken from the
caller, and the mode is checked at the boundary — anything but `acme` or `manual` is refused — and
which `S50lighttpd`'s `check_certificate` honours: a certificate occulited installed is
occulited's, renewed by it in mode `acme` and left to the user in mode `manual`, and is never
regenerated by the init script, which mattered on the first live run, where a step-ca's 24-hour
certificate failed the script's one-day check on the very reload that installed it; the switch
back removes the markers first so the script regenerates); `/etc/config/` is a prefix on the
generic write list, so a generic write *could* have replaced the system's trust anchor, and the point
of the separate operation is the check at the boundary: the data must be a certificate chain plus
the one private key that belongs to its leaf, nothing else, or it is refused and logged. The read
side returns the certificate blocks and the marker's line (`<mode> <issuer>`; an old `.acme` marker alone reads as mode `acme`), never the key — the `occulite` user is not in the `certs`
group, and the daemon shows what the system serves without holding the key S50lighttpd made (the key
of an ACME certificate it holds anyway, in its own state directory). After an install lighttpd is
reloaded and **every confined addon of the certs group is restarted** (a broker reads the file
only at a start; a short interruption every sixty days beats an addon serving an expired
certificate; the restarted ids are in the attempt's record on the Certificate page). And there is
**one open route outside `/api`**: `/.well-known/acme-challenge/<token>`, which lighttpd hands to
occulited on port 80 (the fork's HTTPS redirect leaves the path alone); it answers only the tokens
of an order in flight, `404` otherwise, and nothing about the system. HTTP-01 from Let's Encrypt
means port 80 must reach the system from the internet — the web server's rule allows the local
networks only, so that needs a rule for port 80 whose source lets the CA in, which is why the page
recommends DNS-01 for a system behind NAT; a LAN CA's HTTP-01 works as the firewall stands.

## What the service does with root (through a helper)

`occulited` runs as its own user `occulite`. What needs root — writing `/etc/config`,
running the firmware's scripts (`install_addon`, `createBackup.sh`, `restoreBackup.sh`,
`setfirewall.tcl`, `udhcpc`, the init and rc.d scripts, `crypttool`), `systemctl`, staging a
firmware update, creating an addon user — goes over a unix socket to `occulited helper`, a root
process that offers exactly those operations and refuses everything else (`internal/priv`:
the programs by name or directory, the writable paths by prefix, renames only out of the daemon's
staging directory, and a handful of enumerated operations on exact paths — the root password,
the live certificate, the addon account, a disk's SMART read, the log listing of a directory under `/usr/local/addons/` or `/var/log/` (the paths, sizes and times of its log files, never their content, a symlink out of those trees refused); a refusal is logged). Big files (an addon archive, an update image) are written
by the daemon into its own directory and moved into place by one rename, never copied through the
socket. In the other direction the helper **passes a descriptor** rather than bytes: the file an
addon's CGI names in an `X-Sendfile` answer is opened as root and the descriptor is handed back
over the socket (`SCM_RIGHTS`), so occulited streams it without ever holding the privilege to open
that path — see "What moved across the boundary" below. Every command is an argument slice —
never a shell string — and every input that reaches one is validated first. **A program on the
list is a program with a shape** (B-234): the helper admits, per program, only the command lines
occulited builds — `systemctl` a table of verbs and unit names without a slash (never `link`,
`edit`, `set-environment`, and `enable`/`disable`/`mask` only `--runtime`), `systemd-run` its two
transient units (the addon install scope around `install_addon` or an rc.d script, the DHCPv6
client), `kill` a pid the helper looks at itself (a DHCP client, or an addon's process outside the
system's own units), `restoreBackup.sh` an archive under the backup or staging directory, `crypttool`
its four fixed forms, the init and rc.d scripts one action word — and a name on the list without a
shape fails the tests. **No write follows a link an addon or occulited planted** (B-235): the
helper resolves every path itself and follows a symlink only when it is the image's — root's, in
a directory only root writes, not on removable media — checks the resolved path against the same
lists, refuses a link's target outside them, and then acts through directory descriptors with
`O_NOFOLLOW` at every component, so a link swapped in after the check is an error, not a detour.
With `--root` pointing anywhere but `/` no command runs at all.

The socket `/run/occulite/helper.sock` is root:occulite 0660; the systemd unit adds
`NoNewPrivileges`, `ProtectSystem=strict` (the daemon can write only its state directory and
the session mirror) and `PrivateTmp`; on the busybox products `S48occulited` starts the helper and
drops to `occulite` when the image has that user, and runs as root on an older image. As root
(development, an old image) the same operations happen in process — the boundary is the same
code either way.

What that still means: a session with role `admin` reaches every operation the helper offers,
which is what administering a CCU needs. The difference to before is what a bug in the HTTP
side can do: nothing the helper's lists do not name.

## What the night of 2026-09-06/07 found in all of this

Four of the night's findings belong here, because they are the difference between what this page
claimed and what the beta.1 image did:

- **The firewall was never applied on the systemd products**. `/usr/bin/tclsh` was a symlink
  to itself, so `/bin/setfirewall.tcl` — which `eQ3StartNetwork` runs at every boot without
  checking its exit code — died with `ELOOP`. The test system came up with an empty `iptables` ruleset,
  every policy `ACCEPT`, while the Firewall page showed the configuration it believed was applied.
  Fixed in the fork's `post-build-systemd.sh`. **"What listens where" above is only true with the
  firewall up**; on an image without this fix, everything the daemons bind is reachable from the
  LAN.
- **The LAN gateways' encryption keys were in the API answer**. Every line of an
  `[Interface N]` section went into a `Raw` map that is serialised into `GET /radio` and
  `GET /radio/lan-gateways` — including `Encryption Key`. It had not bitten only because the
  unprivileged daemon could not read `rfd.conf` at all, which the same night fixed. The key
  now lives in an unexported field that only the write path reads.
- **A saved gateway list would have relaxed that file to 0644**, handing the keys to every
  addon user and to lighttpd. It is written `0600`, as the firmware writes it.
- **Three write paths were outside the boundary** — the backup upload, the cleanup of the
  streamed backup, and the device-firmware deploy — so those features did not work at all rather
  than working with too much privilege. They use the staging-plus-rename pattern now.

The one deliberate widening: the helper's read allowlist gained `netconfig`, `rfd.conf` and
`hs485d.conf`. The gateway keys are in the last two, so they do pass through the
unprivileged process — it needs them to preserve a key the caller did not resend — but they never
reach a response. `/etc/config/shadow` stays off the list, and it stays off it now that
`POST /ssh/password` works: the file is written by an operation of the helper's own, not read by
the daemon (below).

- **root's SSH keys and sessions** cross the boundary through three operations of the helper's own, and
  through nothing more general:
  - **`authkeys-read`** answers root's `authorized_keys` (public keys only). The helper names
    `/usr/local/etc/ssh/authorized_keys`, where `/root/.ssh` links to, because its `ProtectHome=yes` hides `/root`.
  - **`authkeys-write`** replaces occulited's section of that file with the keys it is given. Each key is checked
    again at the boundary (a modern type, no options prefix, one line). Every line outside the section stays as it
    was, and the file is written via a new file and a rename, 0600 root.
  - **`ssh-end`** sends SIGTERM to one pid, and only when that process is an `sshd-session` of a connection: not the
    listener, not anything else.
  - **Adding a key and setting root's password ask for the user's own password every time.** They use the same
    confirmed ticket as the device key sheet, bound to the session and the path, and a provider login confirms at
    the provider. A key the page refuses is refused before the password is asked. A pasted public key may wait in
    the tab's `sessionStorage` during a provider round trip; a password never does.

## What moved across the boundary

- **`X-Sendfile` was served outside it**. `writeCGIResponse` opened the file an addon's CGI
  names with a plain `os.Open`, as `occulite`. Today's helper umask leaves a root CGI's archive
  `0644`, so RedMatic's backup worked and nothing showed; a **confined** addon writing its
  archive `0600` as `addon-<id>` would have got a 404. It is a descriptor now: a new enumerated
  operation opens the file as root and passes the descriptor back over the socket (`SCM_RIGHTS`),
  and occulited streams from that — the bytes never travel through the socket and the path never
  becomes openable by the unprivileged side.
  Its allowlist is a **new** list, `SendfileDirs` (`/usr/local/tmp/`), deliberately not `ReadPaths`,
  which stays exact and stays a list of files the daemon may read *into itself*. Three rules keep a
  directory addons write into from becoming a grant on whatever they put there: the open is
  `O_NOFOLLOW`, so the last component cannot be a symlink into `/etc`; only a regular file is passed
  back (`O_NONBLOCK` too, so a fifo left there cannot block the helper); and the descriptor is
  checked *after* opening, through `/proc/self/fd`, which catches a symlinked *directory* in the
  middle of the path that no test of the requested string could ever see. Each of those refusals is
  a test in `internal/priv`.
- **The root password could not be set at all**. `SetRootPassword` read
  `/etc/config/shadow` (0640 root:root) to replace root's hash, and the daemon is unprivileged, so
  `POST /ssh/password` failed — the one thing on the SSH page that never worked. The two answers
  were putting shadow on `ReadPaths`, which carries every hash on the system through the unprivileged
  process, or one more enumerated operation. The choice was the operation: occulited runs
  `mkpasswd` (which needs no privilege, and takes the password on stdin), hands the helper **one
  hash**, and the helper replaces the password field of the `root:` line as root. Nothing else in
  the file changes — the ageing fields, the other accounts, the mode and the owner are written back
  as they were — and the file crosses the boundary in neither direction. `ShadowPaths` is an exact
  list of one path, and the hash is checked at the boundary as well as inside the operation: it has
  to look like a crypt hash, and so can carry neither a `:`, which would add fields to the line,
  nor a newline, which would add lines to the file.
- **The addon account is written by the helper itself, not by busybox**. Before that confining an addon ran `addgroup` and `adduser` through the
  helper's program list. Both write a temporary file beside `/etc/group` and rename it — and on
  the image `/etc` is read-only; only the two files themselves are bind mounts of
  `/run/openccu-lite/{passwd,group}` (`occu-etc-writable`), so the first Pi 4 boot answered
  *addgroup: can't create '/etc/group+': Read-only file system* and the addon fell back to root.
  The container and the OVA never showed it because their rootfs is writable. The answer is one
  more enumerated operation, `addonuser`: the passwd file and the group file (`AccountFiles`, an
  exact list of the two, in that order), an account name of the `addon-<id>` shape and a uid at or
  above `AddonUIDBase` (30000). The helper appends `addon-<id>:x:<uid>:` to `/etc/group` and
  `addon-<id>:x:<uid>:<uid>::/usr/local/addons/<id>:/bin/false` to `/etc/passwd` with `O_APPEND`
  on the existing inode — never a temporary file plus rename, which would fail there and could not
  land on a mount point anyway. Idempotent: the same name and number already present is fine; the
  name with another number, or the number with another name, is an error and nothing is written.
  The name is checked at the boundary and in the operation both (no `:`, no newline: the same
  argument as the hash above), the home directory is derived from the name rather than taken from
  the caller, and the shell is always `/bin/false`. `/etc/shadow` is left alone — `x` with no
  shadow line is an account nobody can log in to (busybox `adduser -D` wrote a locked `!` line
  there, and nothing needed it). `adduser` and `addgroup` are off the program list: one path on
  every product, the in-place append, which the writable roots take just as well. The certs group and the runtime block's groups are not memberships in `/etc/group` — the unit's
  `SupplementaryGroups=` names them — so the group file gets the one line.
- **A disk's SMART data is read by the helper itself**. The Status page's storage
  health panel shows SMART for USB, SATA and NVMe disks, and `smartctl` needs root to open the
  device. On the program list it would take any option — `-s`, `-t` and `-X` change a drive's
  state — so it is one more enumerated operation, `smartctl`, in the pattern of `flashcopro`: the
  request carries the device and nothing else; the device must match
  `^/dev/(sd[a-z]{1,2}|nvme[0-9]{1,2}n[0-9]{1,2})$` — a whole SCSI/SATA/USB disk or an NVMe
  namespace; no partition, no SD card or eMMC (they have no SMART), no virtio disk (its health is
  the host's), no NVMe controller node, no path with a component to follow — and must be a block
  device (checked with `lstat` in the operation); and the helper runs exactly
  `/usr/bin/smartctl -j -H -A -i <device>` with a 60-second limit. Where that program is not
  installed (the VM and the container products) the operation answers
  `not-available:`, the client's `ErrNotAvailable` — neither a refusal nor a failure — after the
  shape check and before it looks at the device node. A request that also carries
  arguments, a program, stdin, an environment, a directory, data or a second path is refused and
  logged rather than ignored, and `smartctl` is not on the program list. Each refusal is a test in
  `internal/priv`. The daemon asks at most once an hour per disk, never for a virtual one, and not at all on a system
  whose host monitors the disks.
  Everything else the panel reads needs no privilege: the sysfs attributes and the ext4 counters
  are world-readable, and the kernel log comes from the journal through the unit's
  `systemd-journal` group.
- **An addon's files are given to its user by a walk that follows no link**. Root changes owners inside directories the confined addon's user controls,
  and that user can plant links or swap a directory for one while the walk is inside. Until then
  the repair was `chown -R` through the program list (busybox, which opens a directory by its
  path again after its `lstat`) and the helper's recursive chown was `filepath.WalkDir`: a swap in
  that window made root give away whatever the link led to. And `chown` on the program list took
  any arguments. Now `internal/ownwalk` does the walk by descriptors only - `openat` with
  `O_PATH|O_NOFOLLOW` relative to the directory's descriptor, `statx` and `fchownat` with
  `AT_EMPTY_PATH` on the entry's own descriptor, a directory read through `.` below it - follows no
  link, enters nothing on another device or mount, never gives away a device node, a file with
  several links only with `fs.protected_hardlinks` on, and resolves each top directory from `/`
  through directories only root can change. The helper's `owntree` operation admits one addon's
  three standard directories and data directories below `/usr/local` outside the shared trees, and
  only the uid the passwd file gives `addon-<id>`; `chown` is off the program list. The fork's
  addon units run the same walk as root before every start (`occulited -addon-own <id>` with the
  same boundary).
- **An addon cannot bring its own systemd unit** (fork `occu-addons`). Let an
  addon ship `/usr/local/addons/<id>/etc/systemd/<id>.service`, and the generator linked it as
  `addon-<id>.service`. That directory belongs to the confined addon's user, so the running addon
  could write the file itself. systemd read it at the next boot or `daemon-reload`, and a
  `User=root` or a `+`/`!` prefix (`ExecStartPre=+/bin/sh -c …`) ran as root; the policy's `User=`
  drop-in does not stop a `+` command. A validated root-owned copy made at install, or own units
  for root addons only, were the alternatives; the option was dropped. The
  generator now reads nothing from an addon's directory. It writes the generated unit from the rc.d
  script, the stored policy and the catalogue's `runtime` block, and names an ignored unit file in
  the journal (*"addon &lt;id&gt; ships its own unit file; ignored since openccu-lite 1.0.0-alpha.0,
  the generated unit is used"*). No catalogue entry and none of our addons shipped such a file.
- **Still open, the same kind of path** (found 2026-09-13): a
  confined addon's rc.d script lives in its own directory and still runs as root outside its unit
  (`info` for every addon listing through the helper, `init` at boot, `uninstall`); lighttpd
  runs as root and includes an addon's drop-in that links into the addon's directory; the
  userfs `ld.so.conf.d` include.

## Encrypted backups

A `.sbk` is signed with the BidCos security key, not encrypted: it holds the radio keys, `users.json`,
the tokens, `acme/settings.json` and `tls/key.pem` in plain, and copies end up on sticks, unauthenticated
NFS exports and download folders. With encryption set up, `GET /backup` hands out `.sbk.age` — the
`.sbk` inside one age v1 stream (ChaCha20-Poly1305 in 64 KiB chunks, a header MAC, truncation detected)
for two X25519 recipients (config.md has the files):

- **What it protects against:** a lost stick, a readable share, a leaked download — the copy is
  ciphertext and neither key is beside it. Damage and tampering are detected chunk by chunk; a partial
  decryption is never handed to `restoreBackup.sh`.
- **What it does not:** a compromised running system (root reads `/usr/local` in plain, and an
  administrator can download unencrypted after confirming the password — journaled); the system's own
  storage stolen (the identity is on it; that is disk encryption, not this); the recovery key lost
  together with the system (those backups are gone for everyone; the kit, the tick and *Test my recovery
  key* make it less likely); deletion; metadata (names, sizes, dates); "harvest now, decrypt later"
  against X25519 (age's hybrid post-quantum recipients are a later switch for all recipients at once).
- **A planted backup:** age proves integrity to the key holder, not authorship — whoever knows a
  recipient can encrypt a file to it. Hence the API shows fingerprints only and never a recipient
  string, the system keeps the hashes of the backups it handed out (`created_here` at the check), and a
  user BidCos security key's signature still has to match at the restore. No signature scheme of its own.
- **The recovery system** (`restore_backup.cgi`) stays plain `.sbk` only: decrypt on a PC with
  `age -d` first (the kit says how). An encrypted upload there stops at its untar and leaves the file in
  `/usr/local/tmp` until the next boot — upstream's, not reported.

## Outbound calls

Every connection the system opens by itself - where to, when, which fields, and how to switch it off - is in
[privacy.md](privacy.md), and the requests occulited builds are pinned by tests (`internal/*/outbound_test.go`). In
short: the system release check (GitHub), the device firmware check and download (eQ-3), the addon catalogue and the
addons' update checks (GitHub, each addon's URL) - each on *Check now* and, with *Check daily*, once a day, **off on a
fresh system** and asked once on the welcome page (D-90); time (NTP)
always; eQ-3's HmIP key server at a radio module exchange and at pairing a device whose key is not on the system,
unless in local key mode; ACME and OpenID Connect only when configured. No telemetry; no request carries a serial
number, the host name or the list of devices, except the device types a firmware download names and the SGTINs the
key server needs.

## Not done

- **Addon confinement** is in on the systemd products and **on by default** (`docs/config.md`
  → `addons.default_mode`, `docs/addons.md` → Confinement): a newly installed addon runs as
  `addon-<id>`, root is the deliberate opt-out, and an addon that declared no `runtime` block is
  marked *undeclared* in the UI. Addons already installed when a system updates keep root, pinned once
  per system. The busybox products run addons as root as they always did. Confinement depends on
  `occu-etc-writable.service`, which has not yet been exercised on a real system.
- **Wi-Fi**:
  - **What is stored where:** `/etc/config/wpa_supplicant.conf` (root 0600, userfs, in the backup) holds the networks.
    - A WPA2 network's key is hashed as `wpa_passphrase` does (PBKDF2 over the SSID); the passphrase itself is not
      kept.
    - A WPA3 or WPA2/WPA3 network also keeps its `sae_password` in clear, because SAE needs it; the connect dialog says
      so.
    - occulited reads the file through the helper's read list, so that a change keeps the other networks' keys; no
      key is answered or logged.
  - **The supplicant** (`occu-wpa@<if>.service`, root) runs with `CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
    CAP_CHOWN CAP_DAC_OVERRIDE`: `CAP_CHOWN` gives its control directory `/run/wpa_supplicant` to the group
    `occulite`, so the web UI scans and connects through the socket, without the helper. `CAP_DAC_OVERRIDE` lets its
    replies reach occulited's own socket in `/run/occulite/wpa` (owned by `occulite`); without it every request timed
    out on a test Pi 4 (dev.17). It also runs with `ProtectSystem=strict`,
    `RestrictAddressFamilies=AF_UNIX AF_NETLINK AF_PACKET AF_INET AF_INET6`, `NoNewPrivileges` and the rest.
  - **The boot partition's setup file** (`openccu-lite-wifi.txt`) carries the password in clear until the first boot
    takes it. Then it is deleted (`/boot` remounted rw for the moment) and saved as a WPA2 network, hash only. A file
    that cannot be used stays, and why is shown on the Network page.
  - **A change made over the Wi-Fi itself** is reverted after 90 s unless confirmed, as the Ethernet settings are.
  - **The firewall:** `lite-input` is not tied to an interface, so its rules apply to `wlan*` as to `eth*`.
- **HmIP device keys**:
  - **What is stored where:** `/etc/config/crRFD/sgtin.map` (`SGTIN=KEY`, `0640`, written by the helper, hmipserver's
    after its start; on the userfs and in every backup) holds each device key in clear, since hmipserver needs it that
    way. `hmip_user.conf` names it (`SGTIN.LocalKey.MappingFile`). occulited reads it through the helper's read list.
  - **Who reaches them:** every route needs the scope `radio:keys`. Only Full access includes it (`system:write` does
    not), so of the accounts only an administrator has it, and an addon's token never gets it.
  - **Only the key sheet answers keys.** A session confirms the sheet every time, even a fresh valid one:
    - with the password, where a wrong one counts towards the lockout like a failed login;
    - or, for an account without one (or with password login off), with a fresh login at the identity provider:
      `prompt=login`, `max_age=0`, the same account, `auth_time` after the start.
    - The confirmed ticket is single use, 60 s, bound to that session and path, and never works as a download ticket.
    - It comes back from the provider in the URL fragment, which reaches no server and no log; the page drops it from
      the address at once.
    - A token with the scope is not asked: holding it is the grant.
  - Each export is logged with who, from where and how many keys. The sheet keeps the keys in the page's memory only,
    never in the browser's storage, and drops them when it closes.
  - **The scanner** decodes in the browser: a photo, or the live camera where the page is a secure context. Nothing
    of the picture leaves the page; only the decoded text goes to the API.
- **The seccomp-backed sandbox lines are enforced since `1.0.0-dev.15`**: systemd is built with
  libseccomp (`systemctl --version` says `+SECCOMP`).
  - Before that image, `RestrictSUIDSGID=`, `RestrictNamespaces=`, `LockPersonality=`, `RestrictRealtime=`,
    `MemoryDenyWriteExecute=` and `SystemCallArchitectures=` were accepted and not enforced.
    `RestrictAddressFamilies=` and `SystemCallFilter=` were refused as unknown and dropped from unit files.
  - Measured on the Pi 4 with transient units: `RestrictAddressFamilies=AF_UNIX` and `SystemCallFilter=~@network-io`
    block a TCP connect, `RestrictSUIDSGID=yes` refuses `chmod u+s`, and `RestrictNamespaces=yes` refuses
    `unshare -m`.
  - **What it covers:** the interface daemons' units, `occu-syslog-forward` and systemd's own units, and
    the confined addons' `RestrictSUIDSGID=yes` from occulited's drop-in.
  - rfd and hs485d keep `AF_NETLINK`: their LAN gateway library lists the interfaces with `getifaddrs()`.
- **AppArmor** profiles per component: deferred (2026-09-06).
- **TLS for lighttpd** is upstream's self-signed certificate by default; the ACME
  option above replaces it. The metadata API over TLS is lighttpd's job either way.
- **`hs485d`'s bind address**: the same `Listen IP` key as `rfd` by the binary's strings, but no wired
  hardware at hand to prove it; verify on the first system with an HM-Wired adapter.

## Authentication off

`auth.mode: off` in `occulited.json` — set on System → Users, section Authentication  — removes the login entirely:
every caller on the API, the addon pages and through lighttpd's gate is the one anonymous
administrator session occulited keeps alive (`/api/auth/v1/state` answers it with `auth_off:
true` and sets its cookie, so the gate's session file exists). It is meant for a system that is
alone on a trusted network and nothing else; the shell shows the user icon in the warning
colour and says so on the Account and Users pages. The mode is written to the file and takes
effect at the next start of occulited, which the Authentication section offers, so a mistaken switch is
undone by editing the file and restarting.

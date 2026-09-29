# Addons on openccu-lite

An addon here is an **unchanged CCU addon**: the `.tar.gz` with an executable `update_script` at
its top level, an `rc.d` script that answers `info`/`start`/`stop`/`restart`/`uninstall`, and
optionally a settings page under `/usr/local/etc/config/addons/www/<id>/`. openccu-lite installs it
with the firmware's own `/bin/install_addon`, exactly as OpenCCU's `cp_software.cgi` does, and
`/usr/local` survives a switch in either direction, so an addon installed on a stock CCU3 or
on OpenCCU simply comes along.

> **`/bin/install_addon` on the command line** (`/usr/local/tmp/new_addon.tar.gz`, as on a CCU) and
> from an addon's own updater hands the archive to the system's install, the same one as an upload
> on the Addons page: the addon's manifest, its policy and its unit apply, and the addon is started
> in its unit as its own user — not by its update script as the caller, root and unconfined. The
> output of that install is printed, and the exit code is the installer's. When the system's
> service does not answer, the script installs on its own as before.

> **Where the declarations live:** an addon describes itself in its own manifest, `openccu-lite.json`
> at the root of its archive ([manifest-format.md](https://github.com/hobbyquaker/occulited/blob/master/docs/manifest-format.md)): its `ui` facts and its `runtime`
> block. The system reads it at every install and update; the catalogue only says where an addon's
> manifest is.

What is different from a CCU3 is what is *not* there: no ReGaHSS, no ReGa DOM, no system variables,
no programs. `tclrega.so` is a shim that answers the session check and nothing else. Anything
an addon does through the radio interfaces (XML-RPC/BIN-RPC on the loopback), through MQTT, or
through openccu-lite's own metadata API keeps working.

- The **catalogue** — which addons are known to work, and how their entries are written — is
  [catalog-format.md](https://github.com/hobbyquaker/occulited/blob/master/docs/catalog-format.md).
- **Porting** an addon away from ReGa is [PORTING-PROMPT.md](PORTING-PROMPT.md) and
  [porting-from-rega.md](porting-from-rega.md).
- The **API** behind the Addons page is in [system-api.md](https://github.com/hobbyquaker/occulited/blob/master/docs/system-api.md).

## Enabled and disabled

"Disabled" means one thing: **the `rc.d` script is not executable**. Busybox `run-parts` and the
systemd generator of the systemd products both skip a non-executable script, so nothing starts it,
and re-enabling is one `chmod`. Nothing of the addon is moved, renamed or deleted; its
configuration under `/usr/local` is untouched. The Addons page's *Enable* / *Disable* buttons flip
that bit (through the privilege helper — the script is root's) and then start or stop the addon.

Two checks disable an addon by themselves, both on the first boot after a switch from OpenCCU, and
both reversible by the user:

## After a backup restore

A backup is what a CCU backup is: all of `/usr/local`, except the contents of every directory that
holds a `.nobackup` file (the directory and the file are kept). Most addons put that file into their
program directories — Mosquitto into `bin`, `lib`, `www`; Homematic Manager into `app`, `bin`, `www`;
RedMatic into `bin`, `lib`, `www` and more, unless its settings ask for a full backup — so a restore
brings such an addon back with its settings and data but without its program, exactly as on a CCU.

Such an addon is **not started** after the restore: every addon unit's `ExecCondition=` runs
`lite-addon-payload <id>`, which finds the addon-rc wrapper's script missing (or linked to nothing),
or every tagged program directory holding nothing but its tag (`tmp`, `cache` and what is under
`var` are caches and do not count). The unit is then *skipped*, never *failed*, with one journal
line. The Addons page and Status name the addon — "installed before the restore; reinstall it" —
with a *Reinstall* button where the catalogue has it; the settings stay. Nothing is reinstalled
automatically. An addon that wants its program in every backup leaves its directories untagged.

## Addons that need the ReGa

A built-in list (CUxD, the XML-API, the Programmdrucker, the E-Mail and Sonos addons, HM-Script
runners) plus a scan of the addon's own code for ReGa idioms — `dom.GetObject`, `rega.exe`, port
8181 and their relatives. A hit means the addon is disabled and shown as **"deaktiviert,
inkompatibel" / "disabled, incompatible"** with the reason, and the Status page lists it.

An addon that has been ported keeps its ReGa path beside the openccu-lite one — the porting kit
requires it — so the scan alone would punish exactly the addons that did the work. A manifest
exempts an addon (it runs without the ReGa unless it declares `requires.rega`), and so do an adapter
manifest the catalogue in the image carries for it and, for an addon without a manifest, a file named
`openccu-lite.ok` in its directory.

Enabling such an addon anyway is the user's call and the UI asks first.

## Architecture and addon binaries

`/usr/local` survives a switch, and so do the binaries in it. An addon installed on a machine this
one is not — a stock CCU3's 32-bit userland, an x86 system's package on an ARM one — carries
executables and shared objects this kernel cannot load, and it would fail at start with a message
no user can act on.

So the addon scan reads the **ELF header** of every file in the addon's directory and its `www`
directory (`node_modules` included — a Node addon's native modules are exactly where this bites),
and compares machine, word size and, for a program, its `PT_INTERP` loader with what this system can
execute:

| Product | Runs natively | Runs in addition |
| --- | --- | --- |
| `x86_64` (ova) | x86-64 | 32-bit x86, through `/lib32/ld-linux.so.2` |
| `aarch64` (rpi3, rpi4) | 64-bit ARM | 32-bit ARM, through `/lib32/ld-linux-armhf.so.3` |

The second column is upstream's `multilib32` package, and it is why a stock CCU3's addons survive
the move to OpenCCU at all. A **32-bit ARM** binary therefore runs on the ARM products and
not on the x86 one; a 64-bit ARM binary runs on neither x86 product.

The verdict is deliberately conservative, so that a package shipping prebuilt binaries for several
architectures beside each other is not punished for the ones it does not use:

- if the addon has ELF **programs** (files with a loader) and none of them runs here, it is
  incompatible — the thing that would be started cannot start;
- otherwise, if it has only **shared objects** (`.so`, Node `.node` modules, static binaries) and
  none of those runs here, it is incompatible — nothing of it can be loaded;
- an addon with no ELF file at all (pure Tcl, shell or JavaScript), or with at least one runnable
  program, passes.

A program whose loader is missing is incompatible even when the machine matches — the same shape as
a dangling 32-bit interpreter link.

The walk stops at 60 000 files, and when it does, **no verdict is drawn**: "nothing runnable was
found" would then only mean "not yet", and a false "needs update" that disables a working addon is
the expensive mistake here. The verdict is also forgotten whenever an addon is installed or
removed, because that replaces exactly what the scan looked at.

An incompatible addon is disabled on the first boot after the switch and shown as **"deaktiviert,
braucht ein Update" / "disabled, needs update"**, with the offending file and its architecture in
the tooltip; the Status page lists it too. The `openccu-lite.ok` marker does **not** exempt from
this check: it says "runs without the ReGa", which is a statement about code, not about machine
code.

**The repair is a release built for this system** — the catalogue's *Install* or *Update* button when
the addon has one, otherwise the addon's own download page. A flagged addon the catalogue knows
carries a *Reinstall from the catalogue* button on its row, which opens its card with the
architecture already resolved. Reinstalling replaces the binaries and the addon passes the check on
the next scan. Enabling it without that is possible and the UI asks first; it will not work.

In the API (`GET /api/system/v1/addons`) this is `binary_incompatible` and `binary_reason`, and on
the first boot the list is `first_boot_import.disabled_binary_addons`.

## Settings page or frontend

Two different things, and only one of them is a menu entry.

| | what it is | where it is declared | where the shell shows it |
| --- | --- | --- | --- |
| **Settings page** | what OpenCCU reaches through *Systemsteuerung → Zusatzsoftware*: the addon's own configuration, usually with a start/stop control for its daemon. Most addons have one. | `Config-Url:` in the addon's rc.d `info` output (and `CONFIG_URL` in `hm_addons.cfg`) | the **Addons page**, as the *Settings* button on the addon's row |
| **Web frontend** | a full interface of its own, independent of the CCU's | a **lighttpd fragment the addon ships** as `etc/lighttpd.conf` in its tree, mapping a path to the addon's own server; occulited validates it and writes the copy lighttpd reads, `/usr/local/etc/config/lighttpd/<id>.conf` | the **addon dropdown** in the header, with the addon's icon |

Measured on a test system: `mosquitto` has `Config-Url: /addons/mosquitto/settings.cgi` and no
lighttpd drop-in, so it is on the Addons page only. `redmatic` has the same kind of `Config-Url`
*and* `/usr/local/etc/config/lighttpd/redmatic.conf`, which proxies `/addons/red/` to its Node-RED
on `127.0.0.1:1880` — so it is in the dropdown, and the dropdown links to `/addons/red/`, not to
`settings.cgi`.

occulited reads those drop-ins itself (`GET /nav`). The parse is deliberately narrow: it takes the
key of a `proxy.server` mapping, falls back to the literal prefix of the enclosing `$HTTP["url"]`
regex when that key is the catch-all `""`, and accepts the result only when it is a plain path
under `/addons/`. Anything it cannot read confidently means *no frontend*, because a wrong link in
the menu is worse than a missing one — RedMatic's second block, which proxies `/description.xml`
and `/api/*/lights` to its Philips-Hue emulation, falls out by that rule. Only a proxy counts:
`/addons/<id>/` is served off the filesystem anyway (by occulited, behind lighttpd's gate), so an addon whose frontend is static
needs no drop-in and cannot be told apart from its settings page there.

An addon that proxies in some other way can still declare its frontend explicitly with a `nav.d`
drop-in named after it (`/usr/local/etc/config/nav.d/<id>.json`); that is taken as the deliberate
statement it is and lands in the dropdown with the rest. A `nav.d` drop-in that is not an addon
stays a tab of its own.

**A proxied frontend never gets `?sid=`** (2026-09-15). The legacy `?sid=` alias exists
for the addons' tclsh CGIs, which ask the `tclrega.so` shim; a server behind
lighttpd's proxy learns the session from the gate's `X-Occulite-Session` header and
can do nothing with the alias — occulited's API refuses it. Homematic Manager's server
checks a `?sid=` it is handed against the API before anything else, so with the alias it sent the
frame to the system's page; without `?sid=` its header path signs the user in. So `GET /nav` never
marks a frontend proxied to the addon's own server `legacy_session`, whatever the switches say; a
page named by the addon's own `nav.d` drop-in that is not proxied (a CGI) keeps the alias,
and so does every settings page.

**Where the `Config-Url` is not the settings page**: Homematic Manager's `Config-Url` is the
CCU's *Systemsteuerung* button into its app — `settings.cgi` checks the session and hands the
browser over to the frontend with its token cookie — and its settings are `settings.cgi?cmd=config`.
On openccu-lite the frontend has its own menu entry, and the `Config-Url` is what the shell frames
behind ⚙ and the *Settings* button, so the addon's manifest names the settings page in
`ui.settings_url` ([manifest-format.md](https://github.com/hobbyquaker/occulited/blob/master/docs/manifest-format.md)); `GET /addons` answers it as
`config_url`. An addon on openccu-lite is better off writing the settings page itself as its
`Config-Url` (its `update_script` knows the firmware from `/VERSION`); the manifest key covers the
versions that do not.

## Settings pages and CGI

An addon's settings page is served under `/addons/<id>/…` by occulited behind lighttpd's gate: the
session gate accepts the CCU's `?sid=@…@`, occulited runs the CGI through the privilege helper as
root (or as the addon's own user when it is confined), and the addon's `check_session`
accepts the session through the `tclrega.so` shim. **What `?sid=@…@` carries is the session's legacy
alias, not the session**: ten characters the system makes for a session when the shell
opens such an addon, accepted by the gate and the shim for `/addons/` alone and never by
occulited's API; the session id itself is 26 characters of base32 and never stands in a URL. The
shell passes the alias only to addons whose installed version's manifest does not declare
`ui.session_header` (and to every addon without a manifest), on by default and switchable off — for all and per addon on the Addons
page (its section Addon sessions and the ⋯ menu of an addon's row), with a Status warning naming them. **The `X-Occulite-Session` header is the way**:
every request the gate passes carries the credential it validated (`HTTP_X_OCCULITE_SESSION` in a
CGI) — the session id, or the alias on a request accepted by the alias alone; only the former
works against the API (`GET /api/auth/v1/state` with `Authorization: Bearer <id>`). lighttpd
removes a client-sent header from every request, so it is never client-controlled (the
contract is in [PORTING-PROMPT.md](PORTING-PROMPT.md)). An addon that reads the header declares it,
and gets no `?sid=` any more. `X-Sendfile` is honoured for files under
`/usr/local/tmp`, with `Range` and the conditional headers passed through to the caller. The named
file is opened by the privilege helper, which passes the descriptor back over its socket
(`SCM_RIGHTS`), so an archive a confined addon wrote `0600` as its own user is delivered without
the unprivileged daemon ever being able to open that path itself.

## Confinement

Gives each addon its own user and a policy. **Confined is the default** (since
2026-09-07): an addon installed from now on runs as `addon-<id>` with
`ProtectSystem=strict`, no capabilities and write access to its own directories plus whatever its
manifest's `runtime` block declares. Root is the opt-out — deliberate, labelled *unsafe*,
and taken either by the manifest (`runtime.root: true`, for an addon that genuinely needs
it) or by the user on the Services page, where the confirmation says what it means: an addon
running as root can change anything on the system, the firmware and openccu-lite itself included.
`addons.default_mode` in `occulited.json` flips the whole system back to `root` for someone who wants
the old behaviour.

**Your tree is yours alone.** When an addon runs confined, the ownership step that runs before its
unit starts (`lite-addon-own`) also closes its directories to other users: `/usr/local/addons/<id>`,
`/usr/local/etc/config/addons/<id>` and any data directory it took over become traversable but not
listable by others (`0751`), and the files in them become the addon's own (`0640`, with the group the
addon's own user — so unreadable to any other addon or local account). One addon can no longer read
another's configuration, sessions or credentials. Your own web tree (`www`) stays world-readable,
because the system serves it to the browser; keep secrets out of `www`, and write a credential file
`0600` yourself rather than relying on the step (it only ever tightens, never loosens). This differs
from a classic CCU, where every addon is `root` and reads everything, so an addon that reached into
another addon's files will need its own copy or a shared, deliberately readable location.

**Undeclared addons.** An addon whose manifest carries no `runtime` block — or that has no
manifest at all, neither in its package nor as an adapter manifest in the catalogue — has declared
nothing about how it can run. It is confined like any other, and both the Addons page and the Services page mark it
**undeclared**, so that a user who sees it misbehave has the reason on the page rather than only
in the log. The repair is either a `runtime` block in the addon's manifest (the good one) or the
unsafe switch to root (the one that always works).

**Addons that were already installed** when a system updates into this default keep what they run as:
occulited pins each of them to `root` once per system, marked `migrated`, and says so in the log. A
firmware update that silently took write access away from a working addon would break a setup at a
reboot nobody connects to the cause, and unlike a closed firewall port the symptom is a
restart loop or a half-working addon rather than a page that names it. They are shown as root and
undeclared, and the Services page confines them one at a time, when the user chooses to.

**What confinement needs from the image.** Creating `addon-<id>` writes `/etc/passwd` and
`/etc/group`, which are on the read-only rootfs; `occu-etc-writable.service` copies both into `/run` at boot and bind-mounts them back, before the addon units and
before occulited. Without that unit confinement cannot work: `PUT /addons/<id>/policy` answers 422,
and a fresh install falls back to a root policy marked `fallback` so the addon still runs. The
user and its group are written by the privilege helper's own operation, two lines appended in
place to the bind-mounted files: busybox `adduser`/`addgroup`, which
did it until then, write a temporary file beside `/etc/group` and rename it, and `/etc` itself is
read-only — the first Pi 4 boot showed that, after the container and the OVA had hidden it behind
their writable rootfs. What the account looks like is in [security.md](security.md). The unit and
the mount were observed working on that boot; the in-place write is verified in tests and waits
for the next Pi run.


## An addon's own start/stop buttons

Many addons' settings pages start, stop or restart their daemon by calling their own rc.d
script — `/usr/local/etc/config/rc.d/<id> restart`. On the busybox CCU that was the whole
story. On openccu-lite the addon runs in `addon-<id>.service`, and a daemon started from a CGI
would live in lighttpd's cgroup, invisible to the unit (the problem, addon edition).

So the rc.d script is fronted: `occu-addons.service` (at boot) and occulited (after an install)
run `/usr/libexec/occu/lite-addon-rc adopt`, which moves the addon's script to
`rc.d/<id>.script` and puts `/usr/libexec/occu/addon-rc-wrapper` in its place as `rc.d/<id>`.
The unit runs `<id>.script`. The wrapper passes everything through to it — `info`, `uninstall`,
whatever the addon defines — except **`start`, `stop` and `restart` from outside the unit**
(systemd sets `INVOCATION_ID` inside), which become `systemctl <action> addon-<id>.service` as
root, or, as the addon's own user, a `POST /api/system/v1/addonctl` with the addon's control
token (`/run/occulite/addon-tokens/<id>`, readable by that user alone) — which may do exactly
that and nothing else. Beside it, an addon whose manifest declares `runtime.api_scopes`
finds its own API token in `/run/occulite/addon-tokens/<id>.api` (`0600`, its user;
minted at every start, after an install and after a policy change, gone with the addon), with
exactly the declared scopes less what an addon never gets (`*`, `auth:admin`, `power`,
`backup`). Every other addon reads names and rooms with the system's local token
(`/usr/local/etc/occulite/local-token`, `meta:read` alone) — see security.md. An addon update that copies a fresh script over the wrapper is adopted
again at the next boot or install; the stale `.script` is replaced. `lite-addon-rc release <id>`
puts the script back by hand.

Addon authors need not change anything.

## No unit files of its own

**Every addon runs in the generated unit.** It is built from the addon's rc.d script, its stored
policy (root or its own user, with the grants) and the manifest's `runtime` block. An addon
cannot bring its own unit any more.

- **What is ignored:** a unit file in the addon's directory
  (`/usr/local/addons/<id>/etc/systemd/<id>.service`) and drop-ins beside it (`<id>.service.d/`).
  The generator reads neither file.
- **What the system says:** one journal line per such addon at every unit generation (boot, and the
  reload after an install), *"addon &lt;id&gt; ships its own unit file; ignored since openccu-lite
  1.0.0-alpha.0, the generated unit is used"* (identifier `occu-addons`).
- **Why:** a confined addon owns its directory, so it could write that file itself. Until then the
  generator used it as the addon's unit at the next boot, and an `ExecStartPre=+…` or `User=root`
  line in it ran as root.
- **What an addon needs beyond the generated unit** is declared in its manifest
  ([manifest-format.md](https://github.com/hobbyquaker/occulited/blob/master/docs/manifest-format.md), `runtime`): capabilities, groups, extra paths, data
  directories, ports and the interfaces it waits for. Something the `runtime` block cannot say yet
  is a manifest format change, never a unit file.
- **Addons affected:** none known. No manifest in the catalogue and none of the addons maintained here
  (RedMatic, homematic-manager, hm2mqtt.js, Mosquitto) ships such a file, and none was on the
  test Pi 4 on 2026-09-13.

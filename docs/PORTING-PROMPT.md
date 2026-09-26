# Porting prompt — names, rooms and functions from openccu-lite instead of ReGa

*Copy everything below the line into your coding agent, in the repository of the addon or
integration you maintain. Fill in the two placeholders. Metadata API version 1; this prompt is
versioned with it — if `GET /api/meta/v1/version` answers a higher `version`, fetch the prompt
from the matching openccu-lite release.*

*An addon declares what it needs in its own manifest, `openccu-lite.json` at the root of its package
([manifest-format.md](https://github.com/hobbyquaker/occulited/blob/master/docs/manifest-format.md)); the catalogue only
says where it is.*

---

You are porting **<PROJECT>** (repository: this one) so that it works on **openccu-lite**, a
Homematic CCU firmware without ReGaHSS, while continuing to work unchanged on a CCU3 /
RaspberryMatic / OpenCCU. Read `<PATH TO docs/porting-from-rega.md>` first; it is the mapping and
it lists what has no replacement. The normative API reference is `docs/meta-api.md` next to it.

## First: which kind of addon is this?

Most addons use the ReGa for exactly one thing, the session check of their settings page. If
that is all — no device names, rooms, functions, system variables or programs anywhere in the
code — **skip "What to build" entirely**: the tclrega shim answers the session check, and the
work is the systemd section below (pid file location, a writable directory, the journal instead
of `/var/log/messages`). Grep the addon for `dom.GetObject`, `rega_script`, `:8181/`,
`homematic.cgi` and `hmscript` to know which kind it is.

## Bringing a system up for your tests (no hardware)

`occulited` from the openccu-lite repository runs anywhere: `go build ./cmd/occulited`, then
`occulited --root <empty dir with a VERSION file: VERSION=3.89.8.20260719 PRODUCT=ova
PLATFORM=ova VARIANT=lite> --state-dir <dir> --session-dir <dir> --listen 127.0.0.1:2121 --log stderr`.
`POST /api/auth/v1/setup {"username","password"}` creates the administrator and answers a `sid`
that works as `Authorization: Bearer <sid>`; `PUT /api/meta/v1/import` with a document from
`fixtures/store/` fills the store (the API normalises documents: default `enums`/`meta` appear
in the snapshot, `_reason` keys do not). `<state>/local-token` is the local token.

## What openccu-lite offers

- `GET http://<box>/api/meta/v1/version` → `{"api":"meta","version":1,...}`. No auth. This is
  the feature detection: **anything but a JSON body with `"api":"meta"` is a CCU** (404, HTML, or a
  proxy's 200 with something else).
- `GET /api/meta/v1/snapshot` → `{format, revision, objects: {"<interface>.<address>": {name,
  enums: ["room/eg/wohnzimmer", ...], meta: {...}, orphaned}}, enums: {"room": {name, tree:
  [{id, name, icon?, children?: [...]}, ...]}, "function": ..., ...}}` — `room` and `function`
  are the defaults; a user may add enums of their own, so treat enum ids as data.
- `GET /api/meta/v1/events/sse` → Server-Sent Events, one JSON event per message: `{revision,
  kind: "object.updated"|"object.deleted"|"node.created"|"node.updated"|"node.deleted"|
  "node.moved"|"enum.created"|"enum.updated"|"enum.deleted"|"import", ...}`. `?since=<revision>`
  replays; a `{"kind":"resync"}` answer means: fetch the snapshot again.
- Authentication for everything but `/version`: `Authorization: Bearer <credential>`, where the
  credential is either the user's session id (26 characters of base32, which a page under
  `/addons/` gets in the `X-Occulite-Session` header, below — **not** the ten-character
  `?sid=@xxxxxxxxxx@`, which is a legacy alias only addon pages accept, never the API) or
  an API token `olt_<32 hex>`. **On the system, read the token from
  `/usr/local/etc/occulite/local-token`** (one line; the scope `meta:read` = names and rooms,
  read-only, and nothing else of the system; that is `<state>/local-token` in `meta-api.md`, the
  default state directory). Off the system, the user pastes a token created on the system's Security
  page into your configuration — with the scopes it needs, `meta:read` for a reader, `meta:write`
  for a writer; a `403` names the missing scope in its `scope` field.
- Refs, not ids: `BidCos-RF.JEQ0230153:1` is a channel, `HmIP-RF.0001D3C99C7D4B` a device. There
  are no numeric ReGa ids anywhere.
- Rooms and functions are trees of paths. A channel in `room/eg/wohnzimmer` is also in `room/eg`.

## The systemd products (openccu-lite runs addons in generated units)

On the systemd products every rc.d script runs inside a generated unit `addon-<name>.service`
(`Type=oneshot`, `RemainAfterExit=yes`, `ExecStart=<script> start`, `KillMode=control-group`):
the cgroup tracks whatever the script started, so `start` must return after backgrounding the
daemon and `stop` must stop it. When the addon is *confined* (its own user `addon-<name>`,
`ProtectSystem=strict`), three things differ from a CCU and are worth one `if` each:

- **`/var/log/messages` does not exist** (journald). Read the daemon's log with
  `journalctl -t <tag>` when the file is absent.
- **`/var/run/<name>.pid` is root's.** The unit gives the addon `/run/addon-<name>/`, owned by its
  user (`RuntimeDirectory=`); keep the pid file there when not running as root, or inside the
  addon's own directory.
- **Writable paths are** the addon's directory, `/usr/local/etc/config/addons/<name>/` (created
  for you), `/usr/local/etc/config/rc.d`, `/run`, `/var/log`, `/tmp`, plus whatever the
  manifest's `runtime.paths` grants. Everything else is read-only; a daemon that writes
  elsewhere fails visibly in the journal, and the user can switch the addon back to root on the
  Services page.

**Do not ship a systemd unit file.** Every addon runs in the generated unit, root or confined. A
unit in your addon's directory (`etc/systemd/<name>.service`, or drop-ins beside it) is ignored,
with a journal line saying so: the confined addon's user owns that directory, so a unit
there would let the addon give itself root. Declare what the daemon needs in the manifest's
`runtime` block instead: capabilities, groups, extra writable paths, data directories, ports and
the interfaces it waits for at start (`needs`). If something is missing there, ask for a manifest
field.

Session-less endpoints (a status poll from the page's JavaScript) keep working behind the
lighttpd gate because the browser sends the session cookie the gate accepts (`occulite_session`
over HTTP, `__Secure-occulite_session` over HTTPS), next to the `?sid=@…@` convention. An addon
that reads the cookie itself must accept both names. **`?sid=@…@` carries the session's legacy
alias** (ten characters), not the session: the system hands it to addons that do not declare the
header (`ui.session_header` in the manifest), on by default and switchable off
by the user, with a warning; the gate takes it from `?sid=` only, never from a cookie, and the
API never takes it.

**The session header `X-Occulite-Session`** is the better way for an addon to learn
the user's session. The cookie's names can change, and have.
- **What it holds:** the bare credential the gate accepted, without the `@` wrapping: the
  session id (26 characters of `A-Z2-7`) from either cookie or from `?sid=`, or — on a request
  the gate accepted by the ten-character legacy alias in `?sid=` alone, with no live cookie —
  that alias, which only the tclrega shim answers and the API refuses. An addon that validates
  the header against the API declares `ui.session_header`, is opened without `?sid=`, and so
  always sees the id.
- **Where it arrives:** on every request the gate passes under `/addons/` to your addon: static
  files, XHRs, the proxied backend of your lighttpd fragment (`etc/lighttpd.conf`), WebSocket upgrades over HTTP/1.1 and
  over HTTP/2 (extended CONNECT), and your CGIs (as `HTTP_X_OCCULITE_SESSION`).
- **Guarantee:** lighttpd removes any header of that name a client sent, on every request and every
  socket, before anything else. That covers any case, and any spelling a CGI would read as the same
  variable (`X_Occulite_Session`, `x.occulite.session`). So the header is present only behind a
  session the gate found live, and never client-controlled.
- **Absent everywhere else:** paths your fragment proxies outside `/addons/`, a socket of your own,
  `/api/` and the shell never carry it.
- **What it does not tell you:** who the user is, and whether the session outlives the request. The
  gate checks only that the session exists. For the user and the role ask
  `GET /api/auth/v1/state` with `Authorization: Bearer <id>` (`authenticated`, `user`, `role`),
  and cache the answer briefly, if at all.
- **Always validate that way.** A CCU has no gate and passes a client's header straight through,
  and so does an openccu-lite image older than the header. Your backend's loopback port is also
  open to every process on the system. Use the header only on openccu-lite (`/VERSION` has
  `VARIANT=lite`), and treat a missing header like a missing cookie.
- **Node-RED:** `adminAuth.tokenHeader: 'x-occulite-session'` with a `tokens(id)` that asks `/state`
  as above; comms authenticates a WebSocket by that header.
- **The cookie and `?sid=@…@` stay** as they are, for the pages that pass the session along.
- **Declare it, and `?sid=` stops**. Once a release of your addon reads the header
  everywhere the shell opens it (the frontend your fragment proxies, and the settings page with
  every CGI it calls), say so in that release's manifest `openccu-lite.json`:
  `"ui": {"session_header": true}` ([manifest-format.md](https://github.com/hobbyquaker/occulited/blob/master/docs/manifest-format.md)). The manifest is per
  version, so this is a boolean. The system then opens that installed version without `?sid=@…@`:
  embedded, in a new tab and in the settings frame. Older releases whose manifest does not say so
  and addons without a manifest keep getting `?sid=`, and a CCU always sends it, so keep accepting
  it. Declaring `ui` alone does not mark your addon's confinement as declared; that is the `runtime`
  block.

**Ship the marker file `openccu-lite.ok`** in your addon's directory (`/usr/local/addons/<name>/`)
once the port is done. The system scans installed addons for ReGa idioms after an update from
OpenCCU and disables what it finds; a ported addon keeps its ReGa path (invariant 1), so the
marker — or a manifest that does not declare `requires.rega` — is what tells the system "this one
runs here".

## Architecture: ship a package per architecture, and name it so

openccu-lite runs on **x86_64** (the VM/appliance product) and on **aarch64** (two board images,
rpi3-class and rpi4-class); both also execute 32-bit binaries of their own family through
upstream's `multilib32` (`/lib32`), which is why a stock CCU3's 32-bit ARM addons keep running
after the move. What does **not** run is a binary from the other family: an armv7 or aarch64 build
on the x86_64 product, an x86 build on an ARM one.

Because `/usr/local` survives a switch, an addon installed on the old system comes along with its
binaries. The system therefore reads the ELF header of every file in an installed addon
(`node_modules` included) and, if none of its programs can run here, **disables it** and shows
**"disabled, needs update"** with the offending file named. The marker file above does not exempt
from this — it is a statement about code, not about machine code. Details in
[addons.md](addons.md#architecture-and-addon-binaries).

For a packager this means:

- **Build and publish one asset per architecture**, and put the architecture in the asset name as
  `uname -m` reports it: `x86_64`, `aarch64`, `armv7l`. The catalogue matches assets by exactly
  that string (`catalog-format.md`), and `uname -m` on both ARM images is `aarch64`.
- **`armv7l` is for eQ-3's own CCU3 firmware, not for this one.** That firmware is 32-bit ARM and
  is what most old addon packages were built against; OpenCCU and openccu-lite build the same
  hardware 64-bit, so `uname -m` there is `aarch64` and an `armv7l` asset is never the one
  selected. Publish it if you still support stock CCU3s; do not publish it *instead of* `aarch64`.
- **Do not ship a fat package** with binaries for every architecture unless the launcher really
  picks the right one at runtime: it passes the check (one runnable program is enough), but the
  user pays for it in download size and you carry the dispatch.
- **A pure-Tcl, shell or JavaScript addon needs nothing** — no ELF file, no check, one package.
- **Native Node modules count.** A `.node` prebuild for the wrong architecture is the usual way an
  addon that "installed fine" fails to start. Build them for each published architecture, or
  ship the prebuilds for all of them side by side.
- **The version in the package must be the version of the release that carries it.** An asset or
  a `versions` file that calls itself something the tag does not (`3.6.0-beta` inside release
  `v3.6.0`) makes the Addons page offer an update that reinstalls the same build, forever — no
  version comparison can repair a package that disagrees with its own tag.

**CGIs**: your tclsh CGIs run through occulited, not lighttpd, on the systemd products;
`SERVER_SOFTWARE=occulited` in the environment is the feature test from Tcl. `X-Sendfile:` for a
file under `/usr/local/tmp` works as on the CCU; anything else behaves like mod_cgi.

**Authentication of your own users**: an addon that let CCU users log in through the ReGa
(user lookup in the DOM, the password service on UDP 1998) uses `POST /api/auth/v1/login
{username, password}` on openccu-lite (`docs/system-api.md`), detected the same way. There is no
user-readable "does this user exist" probe; a session your addon issued is your proof.

## Invariants — do not break these

1. **The existing ReGa path stays.** You add a provider; you delete nothing. On a CCU the
   behaviour before and after your change is identical, byte for byte where output is concerned.
2. **Detection is at runtime**, by `GET /api/meta/v1/version`, once at start and again on
   reconnect. No new mandatory configuration. A user who moves between a CCU and openccu-lite
   with the same configuration must not have to edit anything.
3. **The data shape your users see does not change.** Whatever your addon publishes, emits, or
   renders (MQTT payloads, node outputs, JSON responses, UI tables) keeps its fields. Rooms and
   functions that used to be arrays of names stay arrays of names; build them from the tree.
4. **No user's configuration may break.** Options that only make sense with ReGa (variable
   polling, program topics) stay accepted and are documented as CCU-only; on openccu-lite they
   log one line at start ("system variables are not available on this system") and are otherwise
   silent.
5. **Missing credential = degrade, not fail.** `401` → run without names (addresses only), log
   once, retry on the next reconnect.
6. **Keep the session check of your settings page as it is**. openccu-lite ships a `tclrega.so`
   shim that answers exactly one script, matched by a regular expression:
   `Write(system.GetSessionVarStr('<sid>'));` — `<sid>` ten alphanumerics with or without the
   `@` wrapping, either quote style, optional whitespace and semicolon. Anything else
   `rega_script` is asked returns an error, so do not add other calls.
7. **Do not import a new HTTP or SSE library** if the runtime has one (`net/http` in Go,
   `http::geturl` in Tcl, `fetch` in browsers; in Node prefer `node:http`/`node:https` — `fetch`
   cannot honour a per-request "ignore invalid certificate" option without a new dependency, and
   Node has no global `EventSource`). Keep the dependency footprint as it is.
8. **Port**: probe `http://<box>/` on 80 (443 when your project already speaks TLS to the system);
   offer an optional port override for a locally run `occulited` (it listens on 2121 by default).
9. **Rooms and functions, flattened**: a channel in `room/eg/wohnzimmer` is reported with its
   ancestors included, most specific first — `["Wohnzimmer", "EG"]` — so a single-valued field
   (`msg.room`) is the leaf and a filter on the parent still matches. Every port uses this order;
   do not invent another. (hm2mqtt.js 3.6.0 shipped leaf-only before this rule was written;
   its next release aligns.)
10. **`orphaned`**: keep the name, ignore the flag unless your project has a UI to mark the
    object as gone.
11. **The SSE stream** opens with a `: connected` comment line; treat that as "established". The
    heartbeat comes every 30 s. `?since=<revision>` is exclusive: `since=0` replays everything
    including the initial `import`; a revision the system does not have answers `{"kind":"resync"}`.
    Reconnect means: the stream dropped or the version probe failed three times — not the RPC
    links of your project, which stay as they are.
12. **Detection distinguishes two silences**: a `404`/HTML answer is a CCU — stop probing; a
    refused or timed-out connection is a system that may still be booting — keep probing (once a
    minute is plenty) and switch providers in place when it answers.
13. **Writes on the system**: the local token has the scope `meta:read` alone and is shared by
    every addon; an addon that wants to write (its `meta.<id>` namespace, a rename) needs the
    user's session (the `X-Occulite-Session` header) or a token with `meta:write` — one the user
    created for it on the system's System → Remote access page, or the addon's own from its manifest's
    `runtime.api_scopes` (`/run/occulite/addon-tokens/<id>.api`, minted by the system at every
    start). Say so in your README.
14. **Persist the snapshot in the same state directory as your ReGa cache, in its own file** —
    the same file would destroy the other provider's cache when a configuration moves between
    systems.
15. **Node paths in URLs are relative to the enum** (`/enums/room/nodes/eg/bad`) while a path in
    a document includes the enum id (`room/eg/bad`); `room/room/eg/bad` answers `unknown-path`.
    `GET /objects/{ref}` answers `{ref, object, revision}`, not the bare object.
16. **Addon-side behaviour before a credential exists** (which login to offer, which mode to
    start in) may read `/VERSION`: `VARIANT=lite` is the supported signal. The metadata detection
    itself stays the version probe.
17. **An addon that writes headlessly** (a migration, assigning rooms by itself) needs a token
    with `meta:write`: its own from `runtime.api_scopes` in its manifest (the system writes it
    to `/run/occulite/addon-tokens/<id>.api`, readable by the addon's user), or one the user
    created on the system's System → Remote access page and pasted into its configuration; the local token is not
    enough. Full access is never an addon's.
18. The SSE stream carries no `id:`/`retry:`; resumption is `?since=` only — a browser
    `EventSource` cannot resume, use it for live updates and re-snapshot on reconnect.

## What to build

1. A provider module beside the existing ReGa one, with the **same public surface** the rest of
   the code already calls (names by address, rooms/functions by address, a "names changed"
   event, whatever `<PROJECT>` uses). It loads the snapshot, then follows the event stream;
   on `import` or `resync` it reloads the snapshot. Persist the last snapshot where the ReGa
   provider persists its cache, so a restart without the system does not lose names.
2. Detection and selection in the startup path. Order: explicit configuration (if the project
   has a provider option) → `/api/meta/v1/version` answers → ReGa.
3. A configuration option for the token (name it like the project's other credentials), read
   from the local token file by default when the file exists (and from
   `/run/occulite/addon-tokens/<id>.api` when the addon declares `runtime.api_scopes`).
4. Tests:
   - unit tests of the provider against the conformance corpus in openccu-lite's `fixtures/`
     (copy `store/*.json` into your test fixtures verbatim — exclude them from your formatter;
     they are the documents the API serves; `cases/*.json` are for writers, a reader skips them);
   - a fake `/api/meta/v1` server (a few lines with the runtime's HTTP server) for the
     detection, the 401 path, and an event → "names changed" round trip;
   - the existing ReGa tests untouched and green.
5. Documentation: a section "openccu-lite" in the README — what works, what does not (system
   variables, programs, HM-Script), where the token comes from. Copy the "What has no
   replacement" list from `porting-from-rega.md` rather than paraphrasing it.
6. A CHANGELOG entry. Semver: this is a minor version — a new capability, nothing removed.

## How to verify

- Against openccu-lite: `curl -sH "Authorization: Bearer $(cat /usr/local/etc/occulite/local-token)"
  http://127.0.0.1/api/meta/v1/snapshot | head -c 400` on the system shows the objects; your addon
  must show the same names. Rename a channel in the system's UI (or `PATCH /objects/{ref}` with a
  token that has `meta:write`) and confirm your addon picks it up within a second without a restart.
- Against a CCU: run your existing integration test / smoke test; nothing may differ.
- Both: start with an unreachable system and confirm the addon comes up and degrades.

Work in small commits: provider → detection → configuration → tests → docs. Report what you
could not verify rather than assuming it works.

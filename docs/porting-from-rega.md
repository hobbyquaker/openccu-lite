# Porting an addon or integration from ReGa to openccu-lite

For maintainers of addons and integrations that read **names, rooms and functions** (and
possibly system variables and programs) from ReGaHSS. openccu-lite has no ReGaHSS: nothing
listens on 8181/8183, `rega.exe`/`tclrega.exe` do not exist, HM-Script is never interpreted. What
it has instead is `occulited`'s **metadata API** — a small JSON store of names and enums served on
the system — and a `tclrega.so` shim for the one call every addon settings page makes (the session
check).

This document is the mapping. The copy-paste prompt for a coding agent is
[PORTING-PROMPT.md](PORTING-PROMPT.md); the normative API is [meta-api.md](https://github.com/hobbyquaker/occulited/blob/master/docs/meta-api.md), the
file format [meta-format.md](https://github.com/hobbyquaker/occulited/blob/master/docs/meta-format.md), and the test data [`occulited/fixtures/`](https://github.com/hobbyquaker/occulited/tree/master/fixtures/).

## The one rule

**Keep your ReGa code path. Add a provider. Detect at runtime.**

```
GET http://<system>/api/meta/v1/version
```

answers `{"api":"meta","version":1,...}` on openccu-lite (no authentication needed for this one
call) and 404 / HTML on a CCU or RaspberryMatic. That is the whole detection. Do not look at
`/VERSION`, hostnames or ports. A user moving a backup from openccu-lite to a CCU and back (which is
a supported operation) must not have to touch your configuration.

## Authentication

Every other endpoint needs a credential — the same one addon pages already know:

| you have | send |
| --- | --- |
| the user's session (a settings page opened by the shell) | the session header `X-Occulite-Session` the gate hands the page (manifest `ui.session_header`), sent on as `Authorization: Bearer <session id>`. The `?sid=@xxxxxxxxxx@` a page opens with is the **legacy alias**: addon pages and their CGIs accept it, **the API never does** — neither as `?sid=` nor as a Bearer value. |
| nothing — you are a daemon on the system | the **local token**: read `/usr/local/etc/occulite/local-token` (one line, `olt_…`, root-readable) and send it as `Authorization: Bearer olt_…`. It holds **`meta:read` only**: names, rooms and functions, nothing of the system API and no writes. For more, the addon declares its own token's scopes in its manifest (`runtime.api_scopes`). |
| nothing — you run elsewhere (Home Assistant, a PC) | an **API token** the administrator creates on the system's *Users* page (`olt_…`, with the scopes it needs), stored in your configuration like a password |

A token may carry an expiry and allowed address ranges, and can be rotated (`POST /api/auth/v1/tokens/self/rotate`);
the administrator can revoke it at any time. A `401` means the token is gone or expired: fall back
to "no names" and log it, do not crash.

## Mapping `homematic-rega` to the metadata API

`homematic-rega` (the JS client that RedMatic, hm2mqtt.js and others use) as the reference; other
clients ask ReGa for the same things.

| ReGa call | openccu-lite | notes |
| --- | --- | --- |
| `getChannels()` → `[{id, address, name}]` | `GET /api/meta/v1/objects` → `{"objects": {"<ref>": {"name", "enums", "meta", "orphaned"}}}` | The **ref** is `<interface>.<address>` — `BidCos-RF.JEQ0230153:1`, `HmIP-RF.0001D3C99C7D4B:3`, `HmIP-RF.0001D3C99C7D4B` for the device. There is no numeric ReGa id; if your code keys on `id`, key on the ref. Devices and channels are both objects. |
| `getRooms()` → `[{id, name, channels: [ids]}]` | `GET /api/meta/v1/enums/room/tree` and the `enums` list of each object | Rooms are a **tree** (`room/eg/wohnzimmer`), not a flat list; a channel lists the paths it belongs to. To build the old shape: walk the tree for the names, then invert `objects[*].enums`. `GET /objects?enum=room/eg` gives the members of a subtree in one call. |
| `getFunctions()` | same with `function` | Same shape. `room` and `function` are the two defaults of a fresh store; users may add more (older stores still carry a `floor` enum). Treat enum ids as data, not as a fixed pair. |
| names of the interface itself, of programs/variables | none | Interfaces have no ReGa name; use the interface id. |
| `setName(id, name)` | `PATCH /api/meta/v1/objects/{ref}` with `{"name": "..."}` (admin) | A `user`-role token gets `403`. |
| add a channel to a room | `PATCH /objects/{ref}` with `{"enums": [...]}` (the full list) or `POST /objects:bulk` | Paths must exist (`422 unknown-path`). |
| change detection (polling `getChannels` on an interval) | `GET /api/meta/v1/events/sse` (Server-Sent Events; there is no WebSocket variant) | Events: `object.updated`, `object.deleted`, `node.*`, `enum.*`, `import` (re-snapshot). Every event carries `revision`; reconnect with `?since=<revision>` to replay. No polling needed. |
| `getValues()` (datapoint values via ReGa) | none — use the interface (XML-RPC/BIN-RPC `getValue`, or your event subscription) | On a CCU this was a convenience; the values were always the interface's. |
| `getVariables()`, `setVariable()` | **none** | System variables are a ReGa concept. See "What has no replacement". |
| `getPrograms()`, `startProgram()`, `setProgram()` | **none** | Same. |
| `exec(script)` / `script(file)` | **none** | There is no HM-Script interpreter. |
| `Rega.webUrl` (a link into the CCU WebUI) | `http://<box>/` is `occulited`'s admin UI; device pages are homematic-manager's (`/addons/hmm/`) when installed | |

### The object, once more

```json
"BidCos-RF.JEQ0230153:1": {
  "name": "Wohnzimmer Thermostat",
  "enums": ["room/eg/wohnzimmer", "function/heizung"],
  "meta": { "hm2mqtt": { "topic": "wohnzimmer/thermostat" } },
  "orphaned": false
}
```

`meta` is a per-consumer namespace: **your addon may keep its own settings per object there**
(`{"meta": {"<your-id>": {...}}}` via `PATCH`; `null` removes your namespace; other namespaces are
untouched). `orphaned` is set by the system when the device disappeared from its interface — keep
showing the name, mark it as gone.

### Rooms as a flat list, if you must

```js
const flat = (enumId, tree, prefix = enumId) =>
  tree.flatMap((n) => [{path: `${prefix}/${n.id}`, name: n.name}, ...flat(enumId, n.children ?? [], `${prefix}/${n.id}`)]);
```

Then `members(path) = Object.entries(objects).filter(([, o]) => o.enums.some((p) => p === path || p.startsWith(path + '/')))`.
A channel in `room/eg/wohnzimmer` is also "in" `room/eg` — that is what the tree buys.

## User authentication

Addons that let CCU users log in (RedMatic's `adminAuth`) used the ReGa's user objects and the
password service on UDP 1998. openccu-lite: `POST /api/auth/v1/login {username, password}`
answers a session (`docs/system-api.md`); detection is the same version probe.

## What has no replacement

Be blunt in your README about this; it saves everyone a round trip.

- **System variables** and **programs**: there is no ReGa DOM. Users who need them run
  automation in Node-RED (RedMatic), Home Assistant, or whatever the addon is bridging to. Your
  addon should expose the feature as "not available on this system" — not as an error every 30 s.
- **`exec()`** of HM-Script, `dom.GetObject`, `system.GetSessionVarStr` from your own code: gone.
  The *Tcl* form `rega_script` used by addon settings pages for the **session check** keeps working
  (`tclrega.so` shim, [occulited/deploy/tclrega](https://github.com/hobbyquaker/occulited/tree/master/deploy/tclrega/)): it answers exactly that call and
  errors on anything else. Do not build on the shim for more than the session check.
- **ReGa ids** (`dom.GetObject(1234)`): there are none. Refs are the identity.
- **Service messages / alarms** (variables 40 and 41): no ReGa variables; the system collects the service
  messages itself — `GET /api/system/v1/service-messages` and its stream `/service-messages/stream`
  (`system:read`).
- **The CCU WebUI's JSON-RPC API** (`/api/homematic.cgi`, `Session.login`, `Device.listAll`,
  `Interface.*`): not present. `Interface.*` calls map to XML-RPC on the interface; names come
  from the metadata API; the rest has no replacement.

## What stays exactly the same

- The addon ABI: `update_script`, rc.d `info`, `/addons/<name>/` served by lighttpd, tclsh CGIs,
  `hm_addons.cfg`, exit codes, reboot flag. An addon package built for the CCU installs unchanged.
- The interfaces: `rfd` (BidCos-RF, BIN-RPC 32001), `hs485d` (32000), `hmipserver` (XML-RPC
  32010), their `InterfacesList.xml` — **but on the loopback only**. An integration running
  *off* the system uses **lite-rpc**: the interfaces' XML-RPC (and JSON-RPC) over the web port with a
  token, and their events as a stream instead of a callback server (`/api/rpc/v1`, occulited's
  `docs/system-api.md`). The CCU's classic XML-RPC ports exist only when the administrator switches
  them on (Remote access; off by default). An addon *on* the system sees no difference.
- Session ids, `?sid=@…@`, the `Config-Url` menu entry, the login redirect — with one addition:
  lighttpd itself redirects unauthenticated `/addons/` requests to the login page, so a
  settings page that forgot its own check is no longer open to the LAN.

## The systemd products

`PORTING-PROMPT.md` → "The systemd products" is the addon-side view: generated units, the
journal instead of `/var/log/messages`, `/run/addon-<name>/` for the pid file when confined,
the writable paths. [systemd-scope.md](systemd-scope.md) is the design.

## Verifying a port

1. `fixtures/` in the openccu-lite repository holds a conformance corpus: `store/*.json` documents and `cases/*.json`
   operations with expected results. If your code parses the metadata document, run it over the
   corpus.
2. Against a system: `curl -H "Authorization: Bearer $(ssh root@box cat /usr/local/etc/occulite/local-token)" http://box/api/meta/v1/snapshot`
   must return the same objects your addon shows.
3. Against a CCU: your addon must behave as before. The port adds a path; it removes nothing.

## Worked example: hm2mqtt.js

`lib/rega.js` (`RegaSync`) owns `channelNames`, `channelRooms`, `channelFunctions`, `sysvars`,
`programs`, persisted to `rega.json`, with `syncNames()` and polling. The port:

- a `lib/meta.js` (`MetaSync`) with the same public surface for names/rooms/functions —
  `channelName(address)`, `rooms(address)`, `functions(address)`, `syncNames()`, the `names`
  event — filled from `/snapshot` and kept current from `/events/sse`; `sysvars`/`programs` stay
  empty and `hasVariable`/`hasProgram` return false;
- `index.js` probes `/api/meta/v1/version` when `--rega` is on and picks `MetaSync` if it answers;
  a `--meta-token` option for the off-box case, the local token file by default on the system;
- `--rega-poll-interval` and the variable/program topics are documented as CCU-only;
- the `hm` block of published messages keeps its shape (`rooms`, `functions` arrays of names) so no
  consumer downstream notices.

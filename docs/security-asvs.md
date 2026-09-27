# openccu-lite against OWASP ASVS 5.0, Level 2

The verification checklist for occulited, its UI and lighttpd's gate: one table per ASVS chapter, each row a section
of the standard with the requirement in our own words, the verdict, and where in the code or in the documents the
answer is. **The requirement texts are paraphrased;** the numbering follows the sections of OWASP ASVS 5.0.0 (V1–V17).
Level 2 is ASVS's level for applications with administrative functions and sensitive data, which a system that
controls a home is. The scope is the one of the audit: occulited, the UI, the fork's lite overlay and lighttpd's
configuration; the eQ-3 processes only as black boxes (their confinement and network exposure).

**Verdicts:** `pass` — verified in the code named; `partial` — the requirement is met in part, the gap is named;
`fail` — not met, with the item that tracks it; `n.a.` — does not apply to this system, with the reason;
`under review` — a finding whose fix has not landed; the row says no more until it has.

**As of:** occulited `2412769`, image `1.0.0-dev.28`, 2026-09-26. The manual review has now passed over every
chapter once: the first slice covered **V6, V7, V8** in full and **V3, V16** in part; the second covered **V1, V2, V4,
V5** (input handling, files and archives), **lighttpd's configuration and the Lua gate**, **V11–V13** (cryptography,
transport, configuration — with the TLS settings and the secret files' modes measured on a lab system), **V14** and
**V15**, and completed V3 and V16. What follows is the standing process: a fix flips its row, a new boundary adds one.
The threat model ([threat-model.md](threat-model.md)) says why the authentication chapters came first: nearly every
security bug of the project so far sat on the boundary between the LAN and the API.

The items named (`B-n`, `task n`) are the project's roadmap items; a finding gets a CVSS 3.1 rating there.

## V1 Encoding and Sanitization

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V1.2 injection | no shell strings built from input; every external command an argument vector | pass | every `exec.Command` in `internal/system`, `internal/priv`, `cmd/occulited` takes an argument slice; the one `sh -c` left (`CheckBackup`, `internal/system/backup.go`) carries a fixed command with a single-quoted path whose name the code chose (`restore-<safe name>.sbk`), and the helper's shape for `sh` admits that one line (B-234). journalctl filters (`JournalLog.args`) go as separate arguments |
| V1.2 | input that becomes part of a configuration file cannot add a line or a directive | pass | Wi-Fi: `quote()` hex-encodes an SSID or SAE password with a quote or a non-printable, the PSK is the 64-hex hash (`internal/wifi/supplicant.go`); shares: user and domain by regex, the password refused with `\n`, `\r`, `\x00` (`internal/shares/share.go`), the mount options fixed with `credentials=<the helper's path>`; the firewall's comment refuses `\n\r"`, the id space and quotes, addresses through `net.ParseCIDR`/`ParseIP` (`internal/firewall/model.go`); the addon drop-in takes `capabilities`, `groups`, `paths` through `capRe`, `groupRe`, `pathRe` (no space, `%`, newline — `internal/manifest/manifest.go`); hostnames `hostnameRe` (`internal/system/netwrite.go`) |
| V1.2 | the values an administrator may write into a unit are checked | pass, as a stated trust | own timers and unit overrides are the administrator's (T1): the name through `ValidLocalUnitName`, the content through `systemd-analyze verify` before it is applied (`internal/system/localtimer.go`), the calendar expression refused with a leading `-` or a control character |
| V1.3 sanitization for the browser | untrusted text is not rendered as HTML | pass | Svelte escapes every `{…}`; the one `{@html}` in the UI renders static icon paths |
| V1.5 deserialization | JSON and YAML bodies are decoded with limits, no code execution | pass | `encoding/json` (nesting capped at 10 000 by Go), 64 KiB / 1 MiB body caps (B-232); the metadata import's YAML is `gopkg.in/yaml.v3`, which refuses alias bombs (`allowedAliasRatio`), under the same 1 MiB cap (`internal/httpapi/meta.go` `importDoc`) |
| V1.5 | XML is parsed without external entities and without unbounded recursion | pass | the regadom import (`internal/regaimport/regadom.go`) and the XML-RPC proxy (`internal/literpc`, `DecodeCall`) use Go's `encoding/xml`: no DTD expansion, no external entities, "exceeded max depth" at 10 000 nested elements (measured: a 4.3 MB body of 100 000 nested `<array>`s costs 3 MiB of heap and is refused). JSON-RPC (`ServeJSON`) is `encoding/json` |

## V2 Validation and Business Logic

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V2.2 input validation | every field is validated positively (allowlist) against its type and range | pass | the metadata store: ids `[a-z0-9][a-z0-9-]*` ≤ 32, names without control characters ≤ 255 and valid UTF-8 (B-38), refs without whitespace (`internal/meta/validate.go`), copy–validate–swap on every mutation; account names `usernameRe`; token names; share and target ids `^[a-z][a-z0-9]{0,15}$`; addon ids `addonIDRe`; radio-firmware file names `radioFirmwareNameRe` and the module's own pattern; update file names normalised to `[A-Za-z0-9._-]`; backup upload names `uploadNameRe` or `upload.sbk`; the firewall model; the network settings (`NetworkSettings.Validate`: IPv4, netmask contiguity, the gateway in the subnet); the manifest's every field by regex |
| V2.2 | path parameters cannot leave their directory | pass | every `r.PathValue` that reaches a file goes through a validator or a listing: `RadioFirmware.Delete` (`filepath.Base` + regex), `Firmware.BundleFile` (the name must be in the bundle's own listing), own timers (`ValidLocalTimerName`), the trust store (store id from `StoreIDs`, the entry id a fingerprint the store looks up), `restore:<file>` (`filepath.Base(name) == name`, the `restore-` prefix, `.sbk`); the metadata paths resolve through the store |
| V2.2 | certificates and keys are parsed as what they are | pass | `internal/certpem` (PEM or DER, `x509.ParseCertificate`, the key matched to the leaf), `trust.ParseAny` for the stores; the manual upload 4 MiB through `ParseMultipartForm`, each part ≤ 1 MiB (B-237 fixed the DER trim) |
| V2.2 | SSH public keys are one line and parse | pass | `internal/sshkeys` `Parse`: refuses `\r`/`\n`, decodes the key type and blob |
| V2.3 business logic | dangerous state changes have their guards (one install at a time, one flash, a staged file checked twice) | pass | `installs.running()`, `ErrFlashRunning`, `checkUpdateSpace` at staging and again at `ArmSystemUpdate` (B-247), the restore's key check before the reboot |
| V2.3 | a value an addon declares about itself is applied only within limits the system sets | pass | a confined addon may not declare a root-equivalent capability or the privilege helper's group (**B-251** fixed): refused at manifest validation and never rendered into the unit; D-119's other guard rails (ports closed until opened, `data_dirs` fenced, `CAP_SYS_ADMIN` an opt-in for root addons) hold as documented |

## V3 Web Frontend Security

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V3.3 cookies | see V7.5 | pass | `Path=/` to narrow (**task 259**) |
| V3.4 headers | `X-Content-Type-Options`, `X-Frame-Options`/`frame-ancestors`, `Referrer-Policy`, HSTS over HTTPS | pass | lighttpd `conf.d/setenv.conf`: `X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `Cache-Control: private, no-cache`, `Server` emptied; `conf.d/hsts.conf` when HSTS is switched on (it refuses to switch on with a self-signed certificate). Measured on a lab system on `/`, `/api/system/v1/health` and the HTTP→HTTPS redirect. `X-XSS-Protection: 1; mode=block` is upstream's and deprecated — harmless, to drop with task 259's header change |
| V3.4 | a Content-Security-Policy on the application's own pages | fail | upstream's CSP line is commented out (`setenv.conf`); no `Permissions-Policy` — **task 259** (F-5) |
| V3.5 origin separation | third-party content is not same-origin with the application | fail, accepted | addons live under `/addons/<id>/` on the same origin — the CCU addon ABI needs it. D-78 chose defence in depth (task 213 done; task 259 the rest); the residual risk R1 is stated in the threat model |
| V3.5 | no permissive CORS | pass | the API sets no `Access-Control-Allow-*` header at all (grep of `internal/httpapi`); a cross-origin page cannot read an answer |
| V3.5 | no open redirect | pass | `/login?return=` is checked by `safeReturn` (`ui/src/lib/routes.ts`: same origin, a path that does not start with `//`, never `/login` itself); the gate's redirect carries the URL-encoded path only; lighttpd's HTTP→HTTPS redirect repeats the client's own `Host` (`${url.authority}`), which redirects nobody anywhere they did not ask for; the FQDN redirect's target is the validated host name from the marker |
| V3.6 external resources | scripts and styles come from the system, not from a CDN | pass | the shell is embedded in the binary (`internal/ui/dist`), no external URL in the built assets (the `{@html}` in the UI is one, for static icon paths) |
| V3.7 browser behaviour | the request line and headers are parsed strictly | partial | lighttpd's `server.http-parseopts` keeps upstream's `url-ctrls-reject`, `url-invalid-utf8-reject` at `disable`; on lite every request is proxied to occulited, whose `net/http` refuses a control character in the request line (400), so the gap is theoretical — `enable` costs nothing and belongs into the lighttpd change of the next fix |

## V4 API and Web Service

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V4.1 general | JSON only, a body limit on every route, idle connections closed | pass | every JSON body 64 KiB or 1 MiB (`decodeSmall`, `readJSON`), `413 too-large` beyond, `TestNoUnboundedBody` keeps it so; `IdleTimeout` 120 s, `ReadHeaderTimeout` 10 s — **B-232**, fixed 2026-09-26 (occulited `6d46161`) |
| V4.1 | the upload routes have a ceiling as well | pass | addon archive `MaxAddonSize`, radio firmware 4 MiB, backup 2 GiB, device-firmware bundle 64 MiB (a refusal, not a silent truncation), regadom 64 MiB / `.sbk` 2 GiB on the userfs (**B-255** fixed), certificate parts 1 MiB, XML-RPC and JSON-RPC 4 MiB, `logLevelsPut`/`journalConfigPut` 64 KiB. The system-update upload is capped at 2 GiB and its space check no longer trusts `Content-Length` (**B-256** fixed); a lighttpd `server.max-request-size` of 2.25 GiB backstops them all (**B-254**) |
| V4.1 | the reverse proxy in front does not undo the limits | partial | lighttpd's slow-client limits are tightened to its own defaults (60 s read idle, 360 s write idle, well above the 30 s stream ping) and a 2.25 GiB `server.max-request-size` replaces the former unlimited (**B-254** fixed); every request body streams to the backend — the exception that buffered a body without `Content-Length` whole into `/dev/shm` is gone, the overflow directory is the web server's own on the userfs, and the routes that take no upload are capped small in front of occulited (**B-239** fixed) |
| V4.2 RESTful | state changes only on `POST`/`PUT`/`PATCH`/`DELETE`; safe methods change nothing | pass | the route table (`internal/httpapi/scopes.go`); the cross-site check of task 213 applies to every non-safe method; `TestRouteTable` |
| V4.2 | the interface processes are not reachable from the LAN through the API without a session and scope | pass | `/api/rpc/v1/xmlrpc/{interface}` and `/json/{interface}` need `liteGate` (a session, the `rpc` scope), every call parsed and checked (`liteChecker`) before it is forwarded to the loopback port; classic RPC is a switch that is off (R8) |
| V4.4 | a server-side request forgery is not possible through a user-supplied URL | pass | the outbound calls go to fixed URLs (`internal/outboundpin`, `privacy.md`); the one user-chosen host is the OIDC issuer (an administrator's setting, through the trust store's transport), the syslog forward's host (`ParseLogHost`, UDP) and the NFS/SMB server of a share (`ValidHost`, a mount by the helper, `nosuid,nodev,noexec`) |

## V5 File Handling

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V5.1 documentation | where uploads land and who may read them is written down | pass | `internal/system/staging.go`: the staging directory `<state>/staging` on the userfs, 0700, the helper renames from there (B-20); this table |
| V5.2 upload | uploads have a size limit and land outside the web root, under a name the system chooses | pass (with V4.1's two exceptions) | `stageFile` under a name the code builds (`upload-<random>.tar.gz`, `restore-<safe>.sbk`, `radio-firmware-<checked>`, a normalised update name); `safeUploadName`, `updateNameRe`; nothing is served from the staging directory |
| V5.2 | a file's type is decided by its content, not by the client | pass | `detectUpdateKind` (zip with `EULA.*`, tar with `EULA.*`, the MBR, the ext4 superblock), `backupcrypt.Sniff` for `.sbk`/age, `manifest.FromArchive` peeks at the gzip magic, `accessPointZip` |
| V5.3 execution | an uploaded file is never executed by its path, and archive members never become units or scripts the system runs as root without the administrator's install | pass, as a stated trust | an addon archive's `update_script` runs as root through `install_addon` — that is installing an addon (T2: installing is trusting the package); the manifest is read in Go from the staged file before any code of the package runs (`SystemdAddons.Install`, never a helper `tar -xOf`, B-39); own units are the administrator's (T1) |
| V5.4 storage | archive extraction refuses climbing paths, links and oversized members | pass | device-firmware bundles: `filepath.Base(filepath.Clean(name))`, regular files only, 64 MiB total, `io.LimitReader(tr, h.Size)`, `0644` (`internal/firmware/deploy.go`); the radio import: `path.Clean`, `TypeReg`/`TypeDir` only, 4 MiB per member (`internal/system/radioimport.go`); the regadom from an `.sbk`: only `usr_local.tar.gz` → `homematic.regadom`, 256 MiB (`internal/regaimport`); the manifest: only `openccu-lite.json`, 256 KiB. The system update and the `.sbk` restore are not extracted by occulited at all: the recovery system and `restoreBackup.sh` do that, after the checks of B8 and `checkUpdateSpace` (B-247) |
| V5.4 | files are written with a mode that fits, in a directory with a mode that fits | partial | occulited's state 0600 in a `drwx--x--x` directory (`UMask=0077`), sessions 0600, the helper's writes through `O_NOFOLLOW` at every component (B-235). confined addon trees are closed to other users — the ownership step makes the directories 0751 and the files 0640 (group the addon's own), the www tree left world-readable (**B-252** fixed); hmipserver's key and device files are readable only by hmipserver — the directory 0700, the files 0600, the unit's `UMask=0077`, and what an older image or a restored backup left wider is tightened at every start (**B-253** fixed); the world-writable CCU leftover `/usr/local/etc/config/addons/mh` is removed at first boot and any 0777 directory under config is hardened (**B-257** fixed) |
| V5.5 download | `X-Sendfile` serves only what the allowlist names, through the privilege boundary | pass | `internal/system/cgi.go` `writeCGIResponse`: the path cleaned, `/usr/local/tmp/` prefix and no `..`, opened by the helper (`SendfileDirs`) and streamed by descriptor (B-35, B-36), the path never in the answer (B-21); lighttpd's own `mod_cgi` is not loaded on lite (`overlay/lite/etc/lighttpd/modules.conf`), so `cgi.x-sendfile` is not in play |
| V5.5 | served files carry `nosniff`, a fixed type and `Content-Disposition` where they are downloads | pass | `firmwareBundleFile` (`text/plain`, `nosniff`, `no-store`, a size cap `MaxViewSize`), the log download, the backup download, the SBOM — each sets its type; lighttpd adds `nosniff` to every response |

## V6 Authentication

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V6.1 documentation | the authentication controls are written down: the factors, the lockout, the recovery path | partial | [security.md](security.md) *Who is who* and *Authentication off*; the numbers (8 failures → 15 min, argon2id t=3 m=32 MiB, 8-character minimum, 24 h idle / 30 d absolute) were in the code only until this table |
| V6.2 password security | at least 8 characters, any character, no truncation, paste allowed | pass | `internal/auth/auth.go` `ErrWeakPassword` (8), no upper bound below the body limit, the UI's password fields are plain inputs |
| V6.2 | passwords checked against known breached passwords | fail | none; **task 262** (an offline list, no outside call) |
| V6.2 | a change needs the current password; an administrator may reset | pass | `internal/httpapi/auth.go` line ~889 (`current` required unless the caller is an administrator resetting another account) |
| V6.2 | no password hints, no secret questions | pass | none exist |
| V6.2 | passwords stored with a memory-hard hash | pass | argon2id, t=3, 32 MiB (`auth.go` lines 682–690; the memory is what a 1 GB system sharing with a JVM can spare), one verification at a time |
| V6.3 general | anti-automation: a lockout or rate limit against guessing | pass | per user and per address after 8 failures for 15 minutes (`lockedOut`, `LockAfter`, `LockFor`); the address key is lighttpd's element of `X-Forwarded-For` (`internal/clientaddr`; it was the client's choice until **B-230**, fixed 2026-09-26) |
| V6.3 | the refusal does not tell a wrong user name from a wrong password, in text or in time | pass | the text is generic; an unknown account, or one without a password, is verified against a dummy argon2id hash with the current parameters (`verifyOrBurn`), so every refusal costs one argon2 run — **B-233**, fixed 2026-09-26 (occulited `e9ff8d6`; on a lab Raspberry Pi 4 both refusals take the same 0.42 s) |
| V6.3 | no default accounts, no default credentials | pass | the first boot forces an administrator account (`Store.Setup`, once: `ErrSetupDone`); the image ships no account with a password |
| V6.3 | the "authentication off" mode | fail, accepted | everyone is the anonymous administrator (task 29; `AuthAPI.Off`, `EnsureAnonymous`). A documented trust choice for a system in a trusted LAN, stated in [security.md](security.md) *Authentication off* and the threat model's trust statements — not a requirement openccu-lite meets in that mode |
| V6.4 factor lifecycle | initial credentials set by the user, not shipped; a reset ends the account's other sessions | pass | `Store.Setup`; `SetPassword` → `dropSessionsOf(name, keepSession)` |
| V6.4 | API tokens can expire and be revoked | pass | `occulited token --expires`, `DELETE /api/auth/v1/tokens/<name>` (`auth:admin`), `POST …/tokens` with `expires` and `ips` |
| V6.5 multi-factor | a second factor is available for the accounts | fail | none of its own; only through OIDC (the provider's MFA). **Task 262** asks the maintainer whether delegation is the answer or a local WebAuthn/TOTP factor is needed |
| V6.6 out-of-band | out-of-band authenticators, if used, are bound to the request and expire | n.a. | none. Task 219's client pairing (a program asks, an administrator approves on Status, the poll secret is the credential) is an approval flow, not an authenticator; its tickets expire |
| V6.7 cryptographic | API tokens are random, long enough, stored hashed, compared safely | pass | `olt_` + 32 hex characters (128 bits from `crypto/rand`), SHA-256 at rest, looked up by hash (`internal/auth/auth.go` `TokenPrefix`, `validateTokenLocked`); an optional address list (`fromAllowed`, against lighttpd's address since B-230's fix) and an expiry |
| V6.8 identity provider | OIDC with state, nonce and PKCE; the ID token checked; no account created from the provider | pass | `internal/oidc/oidc.go`: `state, nonce, verifier := random(24), random(24), random(48)`, S256 challenge, `code_verifier` at the token endpoint (lines 175–235), the nonce compared (269); the code flow's ID token comes from the token endpoint over TLS with the client secret, which OIDC Core allows in place of a local signature check; a login for a name with no local account is refused and creates nothing (`httpapi/auth.go` 1168); the provider's certificate chain against the OIDC trust store (task 231) |

## V7 Session Management

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V7.1 documentation | the session model is written down: lifetime, storage, what ends a session | partial | this table and [security.md](security.md); the API's session routes in occulited's `docs/system-api.md` |
| V7.2 fundamentals | session ids from a CSPRNG with at least 64 bits of entropy, never derived from the account | pass | 130 bits, 26 characters of base32 (`newSID`, task 125); the CCU's ten-character `@…@` alias (about 59 bits) is a separate legacy id for the addon CGIs only, off unless an undeclared addon needs it, and never a credential on the API (D-77) |
| V7.2 | a fresh id at login (no fixation) | pass | `Store.Login` → `newSID()` for every login; the browser cannot bring its own |
| V7.2 | session ids are not carried in URLs | fail | `?sid=` is accepted on every API route, for a full session id and for a token (`sessionIDs`, `httpapi/auth.go` 273–295) — **task 260**; the legacy alias in addon URLs is the CCU convention, R9 in the threat model |
| V7.2 | session state stored safely on the server | pass | `<state>/sessions/sessions.json` 0600 in a 0700 directory of its own, ids kept as hashes (`live.hash`), a `.nobackup` marker so a backup carries no live session; the gate's mirror `/run/occulite/sessions/<sha256 of the id>` in a `drwx--x--x` directory (measured) |
| V7.3 timeout | an idle timeout and an absolute lifetime | partial | idle 24 h, absolute 30 d (`Options.IdleTimeout`, `MaxAge`, `auth.go` 301–337). ASVS's Level 2 numbers are shorter (re-authentication within 12 hours); the lengths are a usability choice for a phone shell — a question to the maintainer in **task 262** |
| V7.4 termination | logout ends the session on the server; "log out everywhere" exists; a password change ends the other sessions; removing an account ends its sessions | pass | `logout`, `logoutEverywhere` (`httpapi/auth.go` 857, 920); `SetPassword` and `DeleteUser` → `dropSessionsOf` (`auth.go` 929, 853) |
| V7.5 abuse | the cookie is `HttpOnly`, `Secure` over HTTPS, `SameSite`; a prefix where it applies | pass | `setCookie` (`httpapi/auth.go` 432): `HttpOnly`, `Secure` when the request came over HTTPS (`X-Forwarded-Proto`), `SameSite=Lax`, `MaxAge` 30 d; the HTTPS cookie is `__Secure-occulite_session`. `Path` is `/` — **task 259** scopes it to `/api` |
| V7.5 | state-changing requests are protected against cross-site requests | pass | task 213: `crossSite()` (`httpapi/crosssite.go`) on every non-safe API call whose only credential is the cookie (`Sec-Fetch-Site`, else `Origin`/`Referer`), and on the addon pages at the gate (`occulite-gate.lua` `cross_site()`); refused requests are logged. `SameSite=Lax` alone would let a top-level POST through |
| V7.5 | re-authentication for sensitive operations | pass | the confirmations of tasks 154 and 185 (`confirm`, `httpapi/auth.go` 670–767): the password, or the OIDC provider, before the SSH key routes, the radio key routes and the other guarded paths |
| V7.5 | stale or foreign session cookies are cleaned up | pass | `clearStale` deletes cookies that name no live session |
| V7.6 federated | a federated login can be re-confirmed at the provider | pass | `confirm … by oidc` (`httpapi/auth.go` 739–767) |

## V8 Authorization

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V8.1 documentation | the roles/scopes and what each route needs are written down | pass | the route table `internal/httpapi/scopes.go` (task 66) and the scope column of occulited's `docs/system-api.md`; the ladder of levels (D-116, task 78) in `internal/auth/scopes.go` |
| V8.2 design | deny by default; the check in one place, not per handler | pass | `Middleware` (`httpapi/auth.go` ~330): every `/api/*` route needs a session, then the scope of the table; a route the table does not know answers 403 ("nobody reaches it") and is logged at Error. `open()` lists the routes that need no session (health, version, the auth flow, the ACME challenge, the pairing request, `addonctl` with its own token, `homematic.cgi` for the loopback — lighttpd's address since B-230's fix — and the SBOM) |
| V8.2 | the authorization rules are tested mechanically | pass | `TestRouteTable` walks every registered route with a token of exactly its scope (200) and without (403 naming the scope), the open ones without a session, Full access everywhere; `TestNoRouteOutsideTheTable` fails on a registration that bypasses `route()`. What is not in the walk: the role/level dimension per route (a `user` against an administrator's route) — `TestLocalTokenAndRoles` covers the local token and the roles by sample |
| V8.2 | least privilege for machine credentials | pass | scopes per token (`meta:read` … `auth:admin`, `*`), an address list, an expiry; an addon's local token carries `meta:read` alone ([addons.md](addons.md)); each addon's own token in `/run/occulite/addon-tokens/<id>` is 0600 and the addon user's (measured) |
| V8.3 operation level | dangerous operations need an explicit confirmation or a higher scope | pass | `power` for reboot, restore and the paired-devices import (task 251; the handler checks the scope itself as well, because test rigs bypass the middleware), `radio:keys`, `auth:admin`; the confirmations of V7.5 |
| V8.3 | object-level authorization (a user reaches only their objects) | n.a. | single-tenant: the metadata and the system are one household's; a `user` level reads and operates, an administrator configures — there are no per-user objects beyond the account itself (`self`) |
| V8.4 other | the administrator is root on the system: own timers and unit overrides take arbitrary unit content | pass, as a stated trust | trust statement T1 in the threat model (F-8): those routes need the administrator's scope (`system:write`; verified by `TestRouteTable`), and a token needs it too. There is no "administrator who is not root" role, by design |
| V8.4 | "authentication off" grants everything to everyone | fail, accepted | as V6.3: a documented mode for a trusted LAN |

## V9 Self-contained Tokens

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V9.1–V9.2 | self-contained tokens (JWT and the like) are validated, their algorithm pinned, their lifetime bounded | n.a. | occulited issues none; sessions and API tokens are opaque references looked up by hash. The OIDC ID token is consumed once, from the token endpoint over TLS with the client secret (V6.8) |

## V10 OAuth and OIDC

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V10.1 general | the code flow with PKCE, `state` and `nonce`; the redirect URI exact | pass | V6.8; the redirect URI is the system's own `/api/auth/v1/oidc/callback` on the request's host, exact (`internal/oidc/oidc.go`) |
| V10.2 client | the client secret is stored as a secret and never answered | pass | `occulited.json` 0600 in the 0700 state directory (measured); the settings route answers a placeholder, never the secret |
| V10.4 provider metadata | the discovery document is fetched over TLS with the trust store, with a size limit, and its endpoints must be HTTPS | pass | `internal/oidc/oidc.go` 145: 1 MiB, the OIDC store's transport (task 231); the failure path of a moved CA root is B-248, fixed |
| V10.4 | the provider's chain can be inspected without being trusted | pass | the comparison view dials with `InsecureSkipVerify` to *show* the presented chain and trusts nothing from it (`oidc.go` 393, marked so) |

## V11 Cryptography

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V11.1 inventory | the algorithms in use are known and current | pass | argon2id (passwords), SHA-256 (token lookup, session mirror names, release sums), HMAC/PBKDF2-SHA1 only where Wi-Fi's PSK derivation defines it (`wifi.HashPSK`), age (encrypted backups, task 91), ECDSA P-256 or RSA for the TLS key (`acme.KeyRequest`), TLS 1.2/1.3 (V12). No MD5 or SHA-1 for anything security-relevant (the `lite-lighttpd-reload` fingerprint is a change detector, not a check) |
| V11.2 randomness | secrets come from a CSPRNG | pass | `crypto/rand` for sessions, tokens, OIDC `state`/`nonce`/verifier, staging names; nothing from `math/rand` on a security path |
| V11.3 secret management | keys and secrets live in files only the owner reads, never in code or logs | pass | measured on a lab system (dev.28): `acme/account.key`, `acme/key.pem` 0600 `occulite`; `backup-key/` 0700 with `.nobackup`; `users.json`, `occulited.json`, `trust-anchors.json`, `sessions/sessions.json` 0600; `/etc/config/keys` `rfd` 0600; `crypttool.cfg` root:ssdp 0640; `server.pem` root:certs 0640 (every confined addon is in `certs` by D-46 — stated in [security.md](security.md)). Nothing hard-coded; no secret is a log field (V16.2). hmipserver's key and device files are its own alone — 0700/0600, `UMask=0077` (**B-253** fixed) |
| V11.4 hashing | passwords hashed with a memory-hard function with a per-password salt | pass | V6.2 |
| V11.5 encryption | encrypted backups use an authenticated construction with a recovery key the user holds | pass | age (X25519, ChaCha20-Poly1305), the system's own identity plus the user's recovery key (task 91, `internal/backupcrypt`) |

## V12 Secure Communication

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V12.1 general | TLS 1.2 as the minimum, TLS 1.3 offered, no CBC/SHA-1/RSA key exchange | pass | `conf.d/sslsettings.conf`: `MinProtocol TLSv1.2`, `CipherString EECDH+AESGCM:AES256+EECDH:CHACHA20:!SHA1:!SHA256:!SHA384`. **Measured on a lab system:** TLS 1.0 and 1.1 refused, TLS 1.2 `ECDHE-ECDSA-AES256-GCM-SHA384`, TLS 1.3 `TLS_AES_256_GCM_SHA384`; `AES128-SHA`, `ECDHE-RSA-AES128-SHA`, static RSA refused |
| V12.1 | HTTPS is available with a real certificate; HTTP redirects | partial | ACME (Let's Encrypt, ZeroSSL, a private CA with EAB, `internal/acme`) and a manual certificate; the redirect and HSTS are switches (HSTS refused with a self-signed certificate). **HTTP is the default** on a fresh system — the LAN-device trade-off stated in [security.md](security.md); a user who forwards a port must switch HTTPS on first |
| V12.2 outbound | every outbound call verifies the server against a trust store and speaks TLS 1.2 at least | pass | `internal/trust/transport.go`, `internal/oidc/oidc.go` 92, `internal/acme/lego.go` 195: `RootCAs` from the four stores of task 231, `MinVersion` 1.2; no plain-HTTP fallback anywhere (`privacy.md` lists every destination); the ACME directories are HTTPS constants (`internal/acme/settings.go`) |
| V12.3 internal | the processes of the system talk over the loopback only | pass | occulited `127.0.0.1` (D-29), the interface processes `Listen IP = 127.0.0.1`, lite-rpc; lighttpd is the door (D-9); the ACME challenge path is proxied on every socket, answered by occulited for the current order only |
| V12.3 | the client's address a backend sees is the proxy's word, not the client's | pass | `occulite-session-header.lua` (global) and the gate strip a client-sent `X-Forwarded-*`/`Forwarded`, fail closed if one survives; occulited takes the last element from the loopback only — **B-230**, fixed 2026-09-26, with `lite-lighttpd-redirect-test.sh` on a real lighttpd |

## V13 Configuration

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V13.1 documentation | the components, their versions and the build are documented; an SBOM exists | pass | `scripts/lite-sbom.py` (CycloneDX) published with every release and served at `/api/system/v1/sbom`; the release notes name the base version |
| V13.2 backend communication | the reverse proxy passes only what the backend needs and removes what a client must not set | pass | V12.3; `proxy.forwarded = ("for", "proto")`; the gate sets `X-Occulite-Session` only behind a session it validated; a client-sent one is removed everywhere (`modules.conf` sets the script globally, the gate's block replaces it) |
| V13.2 | the reverse proxy's own limits fit a backend that reads as it goes | pass | see V4.1: the idle and request-size limits are set (**B-254** fixed), request bodies stream and nothing is buffered in RAM (**B-239** fixed) |
| V13.3 | the web server runs with the least privilege | pass | `lighttpd.service` (lite): `User=www-data`, `CapabilityBoundingSet=CAP_NET_BIND_SERVICE`, `ProtectSystem=strict`, `TemporaryFileSystem=/usr/local:ro` with the two read-only binds, `InaccessiblePaths` for the daemons' and the addons' configuration, `NoExecPaths=/`, `PrivateDevices`, `ProtectProc=invisible`, `SystemCallFilter=@system-service`, `MemoryDenyWriteExecute`; `lighttpd-prepare.service` (root, oneshot) reads root-owned input only (B-120). Loaded modules: access, auth (file), setenv, redirect, rewrite, proxy, magnet, openssl — `mod_cgi` is not loaded; `mod_authn_rega` is loaded without a use (a leftover to drop) |
| V13.3 | the system service and its helper are sandboxed | pass | `occulited.service`: `User=occulite`, `CapabilityBoundingSet=` (empty), `NoNewPrivileges`, `ProtectSystem=strict` with `ReadWritePaths` for the state and the two session directories, `PrivateTmp`, `ProtectHome`, `RestrictAddressFamilies`, `RestrictNamespaces`, `SystemCallFilter=@system-service`, `UMask=0077` (task 208: `systemd-analyze security` 2.1); the helper keeps the capabilities its operations need and drops the rest (`CapabilityBoundingSet=~…`, seccomp), 7.4 |
| V13.3 | the build's hardening flags | pass | PIE, the strong stack protector, FORTIFY and RELRO for every C program the image builds; RELRO **full** for lighttpd and its modules, busybox, chronyd, sshd, systemd and the tclrega shim (`buildroot-external/lite-hardening.mk`, **task 261**); `scripts/lite-hardening-guard.sh` reads the ELF headers of the image at every build and fails it on a regression (a non-PIE, a lost RELRO, an executable stack, a missing `__stack_chk_fail`). occulited is a static executable and not a PIE: Go without cgo cannot produce a static PIE (see `package/occulited/occulited.mk`), and a dynamic one is what D-15 rules out; eQ-3's prebuilt daemons are checked as delivered (PIE, partial RELRO). `systemd-analyze security` for every lite unit with thresholds → **task 264** |
| V13.4 | debug and unused features are off in the shipped configuration | pass | `server.tag = ""`, no directory listing (`dir-listing.activate` unset), no `debug.*` on, the access log off unless the Log page switches it on (`access_log.conf`), no ReGa endpoints (`.exe/.oxml/.hssml` denied), the classic RPC sockets written only when switched on (`lite-classic-rpc-conf`) |
| V13.4 | error pages of the proxy say nothing about the backend | pass | `occulite-starting.lua` answers a 502/503/504 with the starting page or `{"error":"starting"}`; occulited's own errors are `apiError` codes (V16.5) |

## V14 Data Protection

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V14.1 general | sensitive data is identified and its storage documented | pass | the threat model's assets 1–7 with *where* and *who reads it*; [privacy.md](privacy.md) for what leaves the system |
| V14.2 client side | no sensitive data cached by the browser; no secrets in URLs | partial | `Cache-Control: private, no-cache` on everything but images; the login form has `autocomplete` as a password manager expects; `?sid=` is the gap of V7.2 (**task 260**) |
| V14.3 server side | backups carry only what a restore needs; live sessions and the backup key stay out; encryption is available | partial | `.nobackup` on `sessions/`, `backup-key/`, `data/`, `boots/`, the radio firmware (measured); encrypted backups on request (task 91). **An unencrypted backup carries the radio keys (R6), the OIDC client secret (`occulited.json`), the ACME account key and the account hashes** — a backup is as sensitive as the system, and the Backup page says so; R6 is the accepted part |
| V14.3 | what is read from another component's storage is the minimum | pass | the helper's `ReadPaths` are seven exact files (`internal/priv/proto.go`): the regadom, `netconfig`, `rfd.conf`/`hs485d.conf` (the daemon strips the gateway keys from every answer and re-reads them so a write keeps them), `hmip_user.conf`, `sgtin.map` (a key only after the confirmation of task 154), `classic-rpc.htpasswd`, `wpa_supplicant.conf` (hashed PSKs; the page lists SSIDs); `/etc/config/shadow` is deliberately not on it |

## V15 Secure Coding and Architecture

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V15.1 documentation | the architecture and the trust boundaries are written down and reviewed | pass | [threat-model.md](threat-model.md) B1–B8, reviewed per minor release and per boundary change |
| V15.2 dependencies | dependencies are known, few, and scanned | partial | Go modules stdlib-first (a dependency needs a reason in the commit), `go.sum`, `npm audit` 0; `govulncheck` clean by hand — in CI with **task 124**; SAST (gosec, CodeQL, secret scanning, Scorecard, action pinning) → **task 264** |
| V15.3 defensive coding | memory safety, no `unsafe`, no cgo, argument vectors not shells | pass | Go with `CGO_ENABLED=0`; one `unsafe.Pointer` (`internal/eq3disc/socket_linux.go`, a `PKTINFO` struct copy from a control message, the size checked); V1.2 for the commands |
| V15.3 | integer and size handling on outside data | pass | every reader capped (`io.LimitReader`, `MaxBytesReader`), archive members by `h.Size` under a total, `checkUpdateSpace` against the recovery's rule |
| V15.4 concurrency | shared state is guarded; the privilege helper cannot be starved by one caller | pass | the store's copy–validate–swap; the helper serves each connection in its own goroutine with the caller's deadline (`Serve` → `go s.handle`, `conn.SetDeadline`), and every long operation has its own timeout (smartctl 60 s, firewall input 15 s, radio-module flash 120–240 s, `RuntimeMaxSec` on every transient unit); `-race` in the gate |
| V15.5 | every parser of outside data has a fuzz test | fail | none yet — **task 265** (the target table) |

## V16 Security Logging and Error Handling

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V16.2 general | structured logs with time, source and outcome; no credentials in the log | pass | `slog` to the journal with `SyslogIdentifier=occulited`; the auth lines carry user, method, remote and reason; passwords and token secrets are never fields (token creation logs the name); the gate logs a refused cross-site request with the path URL-encoded and control characters replaced |
| V16.3 security events | successful and failed authentication, lockouts and privilege changes are logged | pass | at the default level: `auth: login` (Info: user, role, method `password`/`oidc`/`ticket`, remote), `auth: login refused` (Warn: the name as given with non-printables replaced, the method — also a refused API token —, remote, a reason without secrets) and `auth: login locked after repeated failures` (Warn, once per lockout); the refusals inside a lockout and beyond 30 a minute are Debug, so a brute force cannot flood the journal (`internal/httpapi/authlog.go`) — **B-231**, fixed 2026-09-26 (occulited `ea5aafd`). Token creation, the confirmations, the cross-site refusals and the password-login switch were at Info/Warn before. The address in every such line is lighttpd's since **B-230**'s fix |
| V16.3 | administrative changes are attributable (who, from where) | pass | every `POST`/`PUT`/`PATCH`/`DELETE` of a scope that changes the system names `user` and `remote` at Info: the handler's own line (`reqLog`), or the middleware's `api: change` with the method, the route and the status (`internal/httpapi/auditlog.go`); an attempt refused with 403 (by the handler or the scope check) is `api: change refused` at Info, the other 4xx Debug (`562327f`); the RPC proxy (`setValue` and every interface call), the metadata and the LED's live state stay out of Info — **task 269**, 2026-09-26 (occulited `60dcc0e`) |
| V16.3 | the privilege helper logs what it refuses | pass | `refuse(…)` logs once per refused request with the operation and the path or program (`internal/priv/proto.go`), never per line |
| V16.4 protection | logs are readable only by those who may | pass | the journal is root's and `systemd-journal`'s (occulited reads through its supplementary group); the Log page needs `logs:read`; the syslog forward is opt-in; the lighttpd access log is off by default and, when on, goes to the journal through `systemd-cat` |
| V16.5 errors | errors answer a code, not a stack trace or a path | pass | `apiError{Error, Message}` everywhere; the store's error codes map to HTTP status; Go's panics are recovered by `net/http` and logged, not answered; the X-Sendfile path never appears in an answer (B-21) |

## V17 WebRTC

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V17 | — | n.a. | no WebRTC |

## How this document is kept

It is task 120's phase 3 record and is updated with each slice and with each fix: a `fail` or `under review` row
becomes a `pass` with the commit that fixed it in the last column. A new route, a new credential path, a new parser
or a new cookie changes a row here in the same change. The companion for the product baseline is
[security-en303645.md](security-en303645.md).

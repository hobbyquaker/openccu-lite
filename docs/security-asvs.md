# openccu-lite against OWASP ASVS 5.0, Level 2

The verification checklist for occulited, its UI and lighttpd's gate: one table per ASVS chapter, each row a section
of the standard with the requirement in our own words, its status, and where in the code or in the documents the
answer is. It describes what the code does; <ins>**it is not a certification or a statement of conformity.**</ins>
**The requirement texts are paraphrased;** the numbering follows the sections of OWASP ASVS 5.0.0 (V1–V17). Level 2 is
ASVS's level for applications with administrative functions and sensitive data, which a system that controls a home
is. The scope: occulited, the UI, the fork's lite overlay and lighttpd's configuration; the eQ-3 processes only from the outside
(their confinement and network exposure).

**Status:** ✅ met; ⚠️ partly met or accepted — the text says what is missing, or what is accepted and why; ❌ missing;
n/a does not apply, with the reason.

**As of:** 1.1.0-dev.6 (occulited `99133b04`), 2026-10-30. Every chapter has had one manual review (2026-09-26, with
the TLS settings and the secret files' modes measured on a lab system); this revision checks each row against today's
code. The threat model ([threat-model.md](threat-model.md)) says why the authentication chapters came first: nearly
every security bug of the project so far sat on the boundary between the LAN and the API.

## V1 Encoding and Sanitization

| section | the requirement, paraphrased | status | where, and why |
| --- | --- | --- | --- |
| V1.2 injection | no shell strings built from input; every external command an argument vector | ✅ | every `exec.Command` in `internal/system`, `internal/priv`, `cmd/occulited` takes an argument slice; the one `sh -c` left (`CheckBackup`, `internal/system/backup.go`) carries a fixed command with a single-quoted path whose name the code chose (`restore-<safe name>.sbk`), and the helper's shape for `sh` admits that one line. journalctl filters go as separate arguments |
| V1.2 | input that becomes part of a configuration file cannot add a line or a directive | ✅ | Wi-Fi: `quote()` hex-encodes an SSID or SAE password with a quote or a non-printable, the PSK is the 64-hex hash (`internal/wifi/supplicant.go`); shares: user and domain by regex, the password refused with `\n`, `\r`, `\x00` (`internal/shares/share.go`), the mount options fixed; the firewall's comment refuses `\n\r"`, addresses through `net.ParseCIDR`/`ParseIP` (`internal/firewall/model.go`); the addon drop-in is rendered by the helper from `capabilities`, `groups`, `paths` checked by `capRe`, `groupRe`, `pathRe` (`internal/manifest/manifest.go`); hostnames `hostnameRe` (`internal/system/netwrite.go`) |
| V1.2 | the values an administrator may write into a unit are checked | ✅ | own timers and unit overrides are the administrator's (T1): the name through `ValidLocalUnitName`, the content through `systemd-analyze verify` before it is applied (`internal/system/localtimer.go`), the calendar expression refused with a leading `-` or a control character |
| V1.3 sanitization for the browser | untrusted text is not rendered as HTML | ✅ | Svelte escapes every `{…}`; the one `{@html}` in the UI renders static icon paths |
| V1.5 deserialization | JSON and YAML bodies are decoded with limits, no code execution | ✅ | `encoding/json` (nesting capped by Go), 64 KiB / 1 MiB body caps (`decodeSmall`, `readJSON`); the metadata import's YAML is `gopkg.in/yaml.v3`, which refuses alias bombs, under the same 1 MiB cap (`internal/httpapi/meta.go`) |
| V1.5 | XML is parsed without external entities and without unbounded recursion | ✅ | the regadom import (`internal/regaimport`) and the XML-RPC proxy (`internal/literpc`) use Go's `encoding/xml`: no DTD expansion, no external entities, a nesting limit (measured: 100 000 nested `<array>`s refused with 3 MiB of heap). JSON-RPC is `encoding/json` |

## V2 Validation and Business Logic

| section | the requirement, paraphrased | status | where, and why |
| --- | --- | --- | --- |
| V2.2 input validation | every field is validated positively (allowlist) against its type and range | ✅ | the metadata store: ids `[a-z0-9][a-z0-9-]*` ≤ 32, names without control characters ≤ 255 and valid UTF-8, copy–validate–swap on every mutation (`internal/meta/validate.go`); account names `usernameRe`; share and target ids; addon ids `addonIDRe`; radio-firmware names `radioFirmwareNameRe`; update file names normalised to `[A-Za-z0-9._-]`; backup upload names `uploadNameRe`; the firewall model; the network settings (`NetworkSettings.Validate`); the manifest's every field (`internal/manifest`) |
| V2.2 | path parameters cannot leave their directory | ✅ | every `r.PathValue` that reaches a file goes through a validator or a listing: `RadioFirmware.Delete` (`filepath.Base` + regex), `Firmware.BundleFile` (the name must be in the bundle's own listing), own timers (`ValidLocalTimerName`), the trust store (a store id from `StoreIDs`, a fingerprint), `restore:<file>` (`filepath.Base(name) == name`, the `restore-` prefix, `.sbk`); the metadata paths resolve through the store |
| V2.2 | certificates and keys are parsed as what they are | ✅ | `internal/certpem` (PEM or DER, `x509.ParseCertificate`, the key matched to the leaf), `trust.ParseAny` for the stores; the manual upload 4 MiB, each part ≤ 1 MiB; the helper parses the certificate again at the boundary |
| V2.2 | SSH public keys are one line and parse | ✅ | `internal/sshkeys` `Parse`: refuses `\r`/`\n`, decodes the key type and blob; the helper checks again |
| V2.3 business logic | dangerous state changes have their guards (one install at a time, one flash, a staged file checked twice) | ✅ | the install queue, `ErrFlashRunning`, `checkUpdateSpace` at staging and again at `ArmSystemUpdate`, the restore's key check before the reboot |
| V2.3 | a value an addon declares about itself is applied only within limits the system sets | ✅ | a confined addon may not declare a root-equivalent capability (`CAP_SYS_ADMIN`, `CAP_DAC_OVERRIDE`, `CAP_SETUID`, `CAP_NET_ADMIN`, …) or group (`occulite` among them): refused at manifest validation and never rendered into the unit; ports stay closed until opened; data directories are fenced; `CAP_SYS_ADMIN` is an opt-in for root addons; an addon's token never gets `*`, `auth:admin`, `power`, `backup` or `radio:keys`; web ingress ranges without the loopback and no wider than /8 or /32 |

## V3 Web Frontend Security

| section | the requirement, paraphrased | status | where, and why |
| --- | --- | --- | --- |
| V3.3 cookies | see V7.5 | ✅ | the session cookie at `Path=/api`, the gate cookie at `Path=/addons/` |
| V3.4 headers | `X-Content-Type-Options`, `X-Frame-Options`/`frame-ancestors`, `Referrer-Policy`, HSTS over HTTPS | ✅ | lighttpd `conf.d/setenv.conf`: `X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `Cache-Control: private, no-cache` as a default an answer's own value overrides, `Server` emptied; `conf.d/hsts.conf` when HSTS is switched on (refused with a self-signed certificate). `X-XSS-Protection: 1; mode=block` is upstream's, inert in current browsers, and stays because the file is upstream's |
| V3.4 | a Content-Security-Policy on the application's own pages | ✅ | occulited sets `Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-src 'self'; frame-ancestors 'self'; form-action 'self'; base-uri 'self'; object-src 'none'` and `Permissions-Policy: camera=(self), microphone=(), geolocation=()` on every answer of the shell (`internal/ui/csp.txt`), never on `/api/` or `/addons/` — the addon pages keep the CCU's inline scripts. Scripts never inline; `'unsafe-inline'` for styles alone (Svelte's `style=""` attributes). `TestShellPolicy`, and `ui/test/e2e/csp.spec.ts` opens every page under the policy and fails on a violation |
| V3.5 origin separation | third-party content is not same-origin with the application | ⚠️ | **Accepted:** addons live under `/addons/<id>/` on the same origin — the CCU addon interface needs it. Defence in depth instead: the `Origin`/`Sec-Fetch-Site` check, the API cookie at `/api` with a gate cookie for `/addons/`, the header credential `X-Occulite-Request`, the shell's CSP; the residual risk is R1 in the threat model, with what the measures do and do not take away |
| V3.5 | no permissive CORS | ✅ | the API sets no `Access-Control-Allow-*` header at all |
| V3.5 | no open redirect | ✅ | `/login?return=` is checked by `safeReturn` (`ui/src/lib/routes.ts`: same origin, no `//`, never `/login` itself); the gate's redirect carries the URL-encoded path only; lighttpd's HTTP→HTTPS redirect repeats the client's own `Host`; the host name redirect's target is the validated name from the marker |
| V3.6 external resources | scripts and styles come from the system, not from a CDN | ✅ | the shell is embedded in the binary (`internal/ui/dist`), no external URL in the built assets |
| V3.7 browser behaviour | the request line and headers are parsed strictly | ⚠️ | lighttpd refuses a control character in a URL with 400 (`server.http-parseopts`, `url-ctrls-reject` enabled, on the system and in the recovery), before the addon pages, the ingress sockets, classic RPC or occulited read it. **Missing:** invalid UTF-8 is not refused: `url-invalid-utf8-reject` is enabled too and made no measured difference on lighttpd 1.4.85, raw or percent-encoded. `url-path-2f-decode` stays disabled: the session gate relies on it |

## V4 API and Web Service

| section | the requirement, paraphrased | status | where, and why |
| --- | --- | --- | --- |
| V4.1 general | JSON only, a body limit on every route, idle connections closed | ✅ | every JSON body 64 KiB or 1 MiB (`decodeSmall`, `readJSON`), `413 too-large` beyond, `TestNoUnboundedBody` keeps it so; `IdleTimeout` 120 s, `ReadHeaderTimeout` 10 s |
| V4.1 | the upload routes have a ceiling as well | ✅ | addon archive `MaxAddonSize`, radio firmware 4 MiB, backup 16 GiB and never more than the userfs's free space with 128 MB left (checked before the upload is read), device-firmware bundle 64 MiB, regadom 64 MiB / `.sbk` 16 GiB on the userfs, certificate parts 1 MiB, XML-RPC and JSON-RPC 4 MiB; the system-update upload 2 GiB with a space check that does not trust `Content-Length`; lighttpd's `server.max-request-size` backstops them all (2.25 GiB, 16 GiB + 64 MiB on the two backup routes) |
| V4.1 | the reverse proxy in front does not undo the limits | ✅ | lighttpd's slow-client limits (60 s read idle, 360 s write idle) and a request-size limit; every request body streams to the backend, nothing is buffered in RAM, and the routes that take no upload are capped small in front of occulited (`conf.d/webui.conf`) |
| V4.2 RESTful | state changes only on `POST`/`PUT`/`PATCH`/`DELETE`; safe methods change nothing | ✅ | the route table (`internal/httpapi/scopes.go`); the cross-site check applies to every non-safe method; `TestRouteTable` |
| V4.2 | the interface processes are not reachable from the LAN through the API without a session and scope | ✅ | lite-rpc (`/api/rpc/v1/xmlrpc/{interface}`, `/json/{interface}`, the event stream) needs a session or token with an `rpc` tier (`liteGate`), every call parsed and checked against the tier (`liteChecker`) before it is forwarded to the loopback port; the Control app's public mode opens these paths to the public principal at *operate* when switched on; classic RPC is a switch that is off (R8) |
| V4.4 | a server-side request forgery is not possible through a user-supplied URL | ✅ | the outbound calls go to fixed URLs (`internal/outboundpin`, [privacy.md](privacy.md)); the user-chosen hosts are an administrator's settings: the OIDC issuer (through the trust store's transport), the syslog forward's host (`ParseLogHost`, UDP), an NFS/SMB share or SFTP backup target (`ValidHost`; a share mounted by the helper, `nosuid,nodev,noexec`), a private ACME directory |

## V5 File Handling

| section | the requirement, paraphrased | status | where, and why |
| --- | --- | --- | --- |
| V5.1 documentation | where uploads land and who may read them is written down | ✅ | `internal/system/staging.go`: the staging directory `<state>/staging` on the userfs, 0700, the helper renames from there; this table |
| V5.2 upload | uploads have a size limit and land outside the web root, under a name the system chooses | ✅ | `stageFile` under a name the code builds (`upload-<random>.tar.gz`, `restore-<safe>.sbk`, `radio-firmware-<checked>`, a normalised update name); `safeUploadName`, `updateNameRe`; nothing is served from the staging directory |
| V5.2 | a file's type is decided by its content, not by the client | ✅ | `detectUpdateKind` (zip or tar with `EULA.*`, the MBR, the ext4 superblock), `backupcrypt.Sniff` for `.sbk`/age, `manifest.FromArchive` peeks at the gzip magic |
| V5.3 execution | an uploaded file is never executed by its path, and archive members never become units or scripts the system runs as root without the administrator's install | ✅ | an addon archive's `update_script` runs as root through `install_addon` — that is installing an addon (T2: installing is trusting the package); the manifest is read in Go from the staged file before any code of the package runs; an addon's units are generated, never taken from the package; own units are the administrator's (T1) |
| V5.4 storage | archive extraction refuses climbing paths, links and oversized members | ✅ | device-firmware bundles: `filepath.Base(filepath.Clean(name))`, regular files only, 64 MiB total (`internal/firmware/deploy.go`); the radio import: `path.Clean`, regular files and directories only, 4 MiB per member (`internal/system/radioimport.go`); the regadom from an `.sbk`: one member, 256 MiB (`internal/regaimport`); the manifest: one member, 256 KiB. The system update and the `.sbk` restore are extracted by the recovery system and `restoreBackup.sh`, after the checks of the threat model's B8 |
| V5.4 | files are written with a mode that fits, in a directory with a mode that fits | ✅ | occulited's state 0600 (`UMask=0077`), sessions 0600 in a 0700 directory; the helper writes through `O_NOFOLLOW` at every component; confined addon trees 0751 directories and 0640 files, the www tree readable; hmipserver's key and device files 0700/0600, tightened at every start; the CCU's world-writable leftover `addons/mh` removed at first boot when empty, its files losing the world-writable bit otherwise |
| V5.5 download | `X-Sendfile` serves only what the allowlist names, through the privilege boundary | ✅ | `writeCGIResponse` (`internal/system/cgi.go`): the path cleaned, `/usr/local/tmp/` and no `..`, opened by the helper's `openfd` (`SendfileDirs`, `O_NOFOLLOW`, a regular file, checked through `/proc/self/fd`) and streamed by descriptor; the path never in the answer; lighttpd's `mod_cgi` is not loaded |
| V5.5 | served files carry `nosniff`, a fixed type and `Content-Disposition` where they are downloads | ✅ | the firmware bundle view (`text/plain`, `nosniff`, `no-store`, `MaxViewSize`), the log download, the backup download, the SBOM — each sets its type; lighttpd adds `nosniff` to every response |

## V6 Authentication

| section | the requirement, paraphrased | status | where, and why |
| --- | --- | --- | --- |
| V6.1 documentation | the authentication controls are written down: the factors, the lockout, the recovery path | ✅ | [security.md → Accounts and sign-in](security.md#accounts-and-sign-in): the levels, the password rules, argon2id's parameters, the lockout (8 failures, 15 minutes), passkeys, the identity provider, the session lengths, the console's way back |
| V6.2 password security | at least 8 characters, any character, no truncation, paste allowed | ✅ | `internal/auth/auth.go` `ErrWeakPassword` (8), no upper bound below the body limit, the UI's password fields are plain inputs |
| V6.2 | passwords checked against known breached passwords | ⚠️ | **Accepted:** no check. A check against an online service would be an outbound call with a hash prefix on every password change ([privacy.md](privacy.md): the system makes none it does not have to), and a list in the binary is megabytes for little gain beside argon2id, an 8-character minimum and the lockout. Revisited when a compact offline filter is worth its weight |
| V6.2 | a change needs the current password; an administrator may reset | ✅ | `POST /api/auth/v1/password`: `current` required unless the caller is an administrator resetting another account |
| V6.2 | no password hints, no secret questions | ✅ | none exist |
| V6.2 | passwords stored with a memory-hard hash | ✅ | argon2id, t=3, 32 MiB (`internal/auth/auth.go`; the memory is what a 1 GB system sharing with a JVM can spare), one verification at a time |
| V6.3 general | anti-automation: a lockout or rate limit against guessing | ✅ | per user and per address after 8 failures for 15 minutes (`lockedOut`, `LockAfter`, `LockFor`); the address is lighttpd's element of `X-Forwarded-For` (`internal/clientaddr`), not a client-sent one; a failed passkey assertion counts like a wrong password; the pairing request is rate-limited per address |
| V6.3 | the refusal does not tell a wrong user name from a wrong password, in text or in time | ✅ | the text is generic; an unknown account, or one without a password, is verified against a dummy argon2id hash with the current parameters (`verifyOrBurn`), so every refusal costs one argon2 run (measured on a Raspberry Pi 4: both 0.42 s) |
| V6.3 | no default accounts, no default credentials | ✅ | the first boot forces an administrator account (`Store.Setup`, once: `ErrSetupDone`); the image ships no account with a password |
| V6.3 | the "authentication off" mode | ⚠️ | **Accepted:** with authentication off there is no authentication; everyone is the anonymous administrator (`AuthAPI.Off`, `EnsureAnonymous`). A documented trust choice for a system in a trusted LAN ([security.md](security.md#accounts-and-sign-in), threat model T1); the mode gives the requirement up by design |
| V6.4 factor lifecycle | initial credentials set by the user, not shipped; a reset ends the account's other sessions | ✅ | `Store.Setup`; `SetPassword` → `dropSessionsOf`; the console's `occulited admin reset-auth` removes the passkeys, sets a one-time password that must be changed, and ends the sessions |
| V6.4 | API tokens can expire and be revoked | ✅ | `occulited token --expires`, `DELETE /api/auth/v1/tokens/<name>` (`auth:admin`), `POST …/tokens` with `expires` and `ips` |
| V6.5 multi-factor | a second factor is available for the accounts | ❌ | **Not provided by the system.** Passkeys (WebAuthn, `internal/auth/webauthn.go`, `internal/httpapi/webauthn.go`, `github.com/go-webauthn/webauthn`) are a login of their own — a discoverable credential with user verification, which signs in without name and password — and not a second factor: the password alone still opens a session. An identity provider with its own MFA is the way to a second factor (V6.8). No TOTP. Threat model R11 |
| V6.6 out-of-band | out-of-band authenticators, if used, are bound to the request and expire | n/a | no out-of-band authenticator is used. Client pairing (a program asks, an administrator compares a code and approves on Status, the poll secret is the credential until then) is an approval flow; its requests expire after five minutes |
| V6.7 cryptographic | API tokens are random, long enough, stored hashed, compared safely | ✅ | `olt_` + 32 hex characters (128 bits from `crypto/rand`), SHA-256 at rest, looked up by hash (`TokenPrefix`, `validateTokenLocked`); an optional address list (`fromAllowed`, against lighttpd's address) and an expiry |
| V6.8 identity provider | OIDC with state, nonce and PKCE; the ID token checked; no account created from the provider | ✅ | `internal/oidc/oidc.go`: random `state`, `nonce` and verifier, S256 challenge, `code_verifier` at the token endpoint, the nonce compared; the code flow's ID token comes from the token endpoint over TLS with the client secret, which OIDC Core allows in place of a local signature check; a login for a name with no local account is refused and creates nothing; the provider's chain against the OIDC trust store |

## V7 Session Management

| section | the requirement, paraphrased | status | where, and why |
| --- | --- | --- | --- |
| V7.1 documentation | the session model is written down: lifetime, storage, what ends a session | ✅ | [security.md → Accounts and sign-in](security.md#accounts-and-sign-in) (*Sessions*), the API's session routes in occulited's `docs/system-api.md`, the session store in its `docs/config.md` |
| V7.2 fundamentals | session ids from a CSPRNG with at least 64 bits of entropy, never derived from the account | ✅ | 130 bits, 26 characters of base32 (`newSID`); the CCU's ten-character `@…@` alias (about 59 bits) is a separate legacy id for the addon CGIs only, never a credential on the API |
| V7.2 | a fresh id at login (no fixation) | ✅ | every login opens a new session with `newSID()`; the browser cannot bring its own |
| V7.2 | session ids are not carried in URLs | ✅ | the API reads no credential from the query string since 1.3.0 (`sessionIDs`, `internal/httpapi/auth.go`: cookies, `Authorization`, the basic-auth password; a request with only a `?sid=` is `401` with a message that names the header); the shell's downloads and the hand-over of a session to a new address go by one-time tickets. **Remaining by design:** the shell passes the session's ten-character legacy *alias* in the URLs of addons that live by the CCU convention, and the gate takes a session id from `?sid=` under `/addons/` for the shells from before task 125 (threat model R9) |
| V7.2 | session state stored safely on the server | ✅ | `<state>/sessions/sessions.json` 0600 in a 0700 directory of its own, ids kept as SHA-256 only, a `.nobackup` marker so no backup carries a live session; the gate's mirror `/run/occulite/sessions/<sha256 of the id>` |
| V7.3 timeout | an idle timeout and an absolute lifetime, by a documented risk decision | ✅ | **30 minutes idle, 12 hours absolute** by default (`DefaultIdleTimeout`, `DefaultMaxAge`) — the values ASVS 4.0.3 §3.3.2 named for Level 2, taken as the documented decision for a system that controls a home and may be reachable from the internet. Configurable on System → Users → Authentication → Sessions within 5 min–30 d and 1 h–90 d (`auth.session_idle`, `auth.session_max`), in force at once; the cookies' `Max-Age` follows the lifetime |
| V7.4 termination | logout ends the session on the server; "log out everywhere" exists; a password change ends the other sessions; removing an account ends its sessions | ✅ | `logout`, `logoutEverywhere`; `SetPassword`, a changed level and `DeleteUser` → `dropSessionsOf`; a change made on the console is taken over at the next request; the shell clears its stored session id at logout |
| V7.5 abuse | the cookie is `HttpOnly`, `Secure` over HTTPS, `SameSite`; a prefix where it applies | ✅ | `setCookie`: `HttpOnly`, `Secure` when the request came over HTTPS, `SameSite=Lax`, `Max-Age` the session's lifetime; over HTTPS `__Secure-occulite_session` at `Path=/api`, and the gate cookie `__Secure-occulite_gate` with the same id at `Path=/addons/`, which opens the addon pages and is no credential on the API (`gateCookieSIDs`); a logout deletes every cookie at every path it may sit at |
| V7.5 | state-changing requests are protected against cross-site requests | ✅ | `crossSite()` (`internal/httpapi/crosssite.go`) on every non-safe API call whose only credential is the cookie (`Sec-Fetch-Site`, else `Origin`/`Referer`), and at the gate (`occulite-gate.lua`); and such a call must carry `X-Occulite-Request` (`cookieAmbient`; `403 request-header`, `TestRequestHeader`) |
| V7.5 | re-authentication for sensitive operations | ✅ | the confirmed ticket (`confirm`): the password, or a fresh login at the provider (`prompt=login`, `max_age=0`), before the key sheet, the SSH key and root-password routes, a passkey's registration and removal, and an unencrypted backup download while encryption is set up; single use, 60 s, bound to the session and path |
| V7.5 | stale or foreign session cookies are cleaned up | ✅ | `clearStale` deletes cookies that name no live session |
| V7.6 federated | a federated login can be re-confirmed at the provider | ✅ | the confirmation by the provider (above) |

## V8 Authorization

| section | the requirement, paraphrased | status | where, and why |
| --- | --- | --- | --- |
| V8.1 documentation | the levels/scopes and what each route needs are written down | ✅ | the route table `internal/httpapi/scopes.go` and the scope column of occulited's `docs/system-api.md`; the scopes and the four levels (*read*, *operate*, *configure*, *administer*) in `internal/auth/scopes.go`; [security.md → API tokens and scopes](security.md#api-tokens-and-scopes) |
| V8.2 design | deny by default; the check in one place, not per handler | ✅ | `Middleware` (`internal/httpapi/auth.go`): every `/api/*` route needs a session, then the scope of the table; a route the table does not know answers 403 and is logged at Error. `open()` lists the routes that need no session: health, version, the auth flow and the passkey login, the ACME challenge, the pairing request (its poll secret), `addonctl`, the addon notices and views (each with the addon's control token), the local install (the install token), `homematic.cgi` for the loopback only, and the SBOM |
| V8.2 | the authorization rules are tested mechanically | ✅ | `TestRouteTable` walks every registered route with a token of exactly its scope (200) and without (403 naming the scope), the open ones without a session, Full access everywhere; `TestNoRouteOutsideTheTable` fails on a registration that bypasses `route()`; `TestLocalTokenAndRoles` covers the local token and the levels by sample |
| V8.2 | least privilege for machine credentials | ✅ | scopes per token, an address list, an expiry; the local token carries `meta:read` alone; each addon's own token in `/run/occulite/addon-tokens/<id>.api` is 0600 and the addon user's, without `*`, `auth:admin`, `power`, `backup`, `radio:keys`; pairing never grants `*`, `auth:admin`, `power` or `radio:keys`, and `backup` only with the administrator's confirmation and limited to the address that asked |
| V8.3 operation level | dangerous operations need an explicit confirmation or a separate scope | ✅ | `power` for reboot, halt, the system update, the restore, the paired-devices import and the radio module's firmware (the handlers check it themselves as well); `backup` for backups; `radio:keys` for the device keys, included only in Full access; `auth:admin`; the confirmations of V7.5 |
| V8.3 | object-level authorization (a user reaches only their objects) | n/a | the system is single-tenant: the metadata and the system are one household's; there are no per-user objects beyond the account itself (`self`) |
| V8.4 other | the administrator is root on the system: own timers and unit overrides take arbitrary unit content | ✅ | trust statement T1 in the threat model: those routes need `system:write`, which no level below *administer* has (`TestRouteTable`). There is no "administrator who is not root", by design |
| V8.4 | "authentication off" grants everything to everyone | ⚠️ | **Accepted**, as V6.3: a documented mode for a trusted LAN |
| V8.4 | the Control app's public mode | ⚠️ | **Accepted:** with it on, a request without a session on lite-rpc and the metadata's reads is the public principal at *read* or *operate* (`publicPath`, a list, not a prefix); the scope table holds it to its level. Off by default, warned about on Status |

## V9 Self-contained Tokens

| section | the requirement, paraphrased | status | where, and why |
| --- | --- | --- | --- |
| V9.1–V9.2 | self-contained tokens (JWT and the like) are validated, their algorithm pinned, their lifetime bounded | n/a | occulited issues none; sessions and API tokens are opaque references looked up by hash. The OIDC ID token is consumed once, from the token endpoint over TLS with the client secret (V6.8) |

## V10 OAuth and OIDC

| section | the requirement, paraphrased | status | where, and why |
| --- | --- | --- | --- |
| V10.1 general | the code flow with PKCE, `state` and `nonce`; the redirect URI exact | ✅ | V6.8; the redirect URI is the system's own `/api/auth/v1/oidc/callback` on the request's host, exact |
| V10.2 client | the client secret is stored as a secret and never answered | ✅ | `occulited.json` 0600 in the state directory; the settings route answers a placeholder, never the secret |
| V10.4 provider metadata | the discovery document is fetched over TLS with the trust store, with a size limit, and its endpoints must be HTTPS | ✅ | `internal/oidc/oidc.go`: 1 MiB, the OIDC store's transport |
| V10.4 | the provider's chain can be inspected without being trusted | ✅ | the comparison view dials with `InsecureSkipVerify` to *show* the presented chain and trusts nothing from it (marked so in `oidc.go`) |

## V11 Cryptography

| section | the requirement, paraphrased | status | where, and why |
| --- | --- | --- | --- |
| V11.1 inventory | the algorithms in use are known and current | ✅ | argon2id (passwords), SHA-256 (token lookup, session hashes, release sums, the pairing code), WebAuthn's signatures (ES256 and the others the library accepts), PBKDF2-SHA1 only where Wi-Fi's PSK derivation defines it, age (encrypted backups: X25519, ChaCha20-Poly1305), ECDSA P-256 or RSA for the TLS key, Ed25519 for the SFTP backup key, TLS 1.2/1.3 (V12). No MD5 or SHA-1 for anything security-relevant |
| V11.2 randomness | secrets come from a CSPRNG | ✅ | `crypto/rand` for sessions, tokens, OIDC `state`/`nonce`/verifier, WebAuthn challenges, pairing nonces, one-time passwords, staging names; nothing from `math/rand` on a security path |
| V11.3 secret management | keys and secrets live in files only the owner reads, never in code or logs | ✅ | measured on a lab system: `acme/account.key`, `acme/key.pem` 0600 `occulite`; the backup identity 0700 with `.nobackup`; `users.json`, `occulited.json`, `sessions/sessions.json`, the backup targets' secrets 0600; `/etc/config/keys` `rfd` 0600; `server.pem` root:certs 0640 (every confined addon is in `certs`, stated in [security.md](security.md#tls-and-certificates)); hmipserver's files 0700/0600. Nothing hard-coded; no secret is a log field, and the ACME log is redacted of the DNS credentials |
| V11.4 hashing | passwords hashed with a memory-hard function with a per-password salt | ✅ | V6.2 |
| V11.5 encryption | encrypted backups use an authenticated construction with a recovery key the user holds | ✅ | age (X25519, ChaCha20-Poly1305), the system's own identity plus the user's recovery key (`internal/backupcrypt`) |

## V12 Secure Communication

| section | the requirement, paraphrased | status | where, and why |
| --- | --- | --- | --- |
| V12.1 general | TLS 1.2 as the minimum, TLS 1.3 offered, no CBC/SHA-1/RSA key exchange | ✅ | `conf.d/sslsettings.conf`: `MinProtocol TLSv1.2`, `CipherString EECDH+AESGCM:AES256+EECDH:CHACHA20:!SHA1:!SHA256:!SHA384`. Measured on a lab system: TLS 1.0 and 1.1 refused, TLS 1.2 `ECDHE-ECDSA-AES256-GCM-SHA384`, TLS 1.3 `TLS_AES_256_GCM_SHA384`; `AES128-SHA`, `ECDHE-RSA-AES128-SHA`, static RSA refused |
| V12.1 | HTTPS is available with a real certificate; HTTP redirects | ⚠️ | **Not by default:** HTTP is the default on a fresh system, HTTPS (self-signed at first), the redirect and HSTS are switches (HSTS refused with a self-signed certificate). ACME (Let's Encrypt, ZeroSSL, a private CA with EAB; HTTP-01 or DNS-01, `internal/acme`) and a manual certificate are there; the LAN-device trade-off is stated in [security.md](security.md#tls-and-certificates) |
| V12.2 outbound | every outbound call verifies the server against a trust store and speaks TLS 1.2 at least | ✅ | `internal/trust/transport.go`, `internal/oidc`, `internal/acme`: `RootCAs` from the system's stores, `MinVersion` 1.2; no plain-HTTP fallback anywhere ([privacy.md](privacy.md) lists every destination); the ACME directories are HTTPS constants; an SFTP target's host key is pinned |
| V12.3 internal | the processes of the system talk over the loopback only | ✅ | occulited on `127.0.0.1:8183`, the interface processes `Listen IP = 127.0.0.1`; lighttpd is the door; an addon's web ingress is a Unix socket only that addon's group reaches |
| V12.3 | the client's address a backend sees is the proxy's word, not the client's | ✅ | `occulite-session-header.lua` (global) and the gate strip a client-sent `X-Forwarded-*`/`Forwarded` and fail closed if one survives; occulited takes the last element from the loopback only (`lite-lighttpd-redirect-test.sh` on a real lighttpd); on an ingress socket the PROXY header's address, held to the manifest's ranges by lighttpd and occulited |

## V13 Configuration

| section | the requirement, paraphrased | status | where, and why |
| --- | --- | --- | --- |
| V13.1 documentation | the components, their versions and the build are documented; an SBOM exists | ✅ | `scripts/lite-sbom.py` (CycloneDX), published with every release and served at `/api/system/v1/sbom`; the release notes name the base version |
| V13.2 backend communication | the reverse proxy passes only what the backend needs and removes what a client must not set | ✅ | V12.3; `proxy.forwarded = ("for", "proto")`; the gate sets `X-Occulite-Session` only behind a session or token it validated; a client-sent one is removed everywhere |
| V13.2 | the reverse proxy's own limits fit a backend that reads as it goes | ✅ | V4.1 |
| V13.3 | the web server runs with the least privilege | ✅ | `lighttpd.service` (lite): `User=www-data`, `CapabilityBoundingSet=CAP_NET_BIND_SERVICE`, `ProtectSystem=strict`, `InaccessiblePaths` for the daemons' and the addons' configuration, `NoExecPaths=/`, `PrivateDevices`, `ProtectProc=invisible`, `SystemCallFilter=@system-service`, `MemoryDenyWriteExecute`; `lighttpd-prepare.service` (root, oneshot) reads root-owned input only. Loaded modules: access, auth (file), setenv, redirect, rewrite, proxy, magnet, openssl, extforward (for the ingress sockets only) — no `mod_cgi`, no ReGa authentication |
| V13.3 | the system service, its helper and the interface daemons are sandboxed | ✅ | `occulited.service`: `User=occulite`, `CapabilityBoundingSet=` (empty), `NoNewPrivileges`, `ProtectSystem=strict` with `ReadWritePaths` for the state and the session mirrors, `PrivateTmp`, `ProtectHome`, `RestrictAddressFamilies`, `RestrictNamespaces`, `MemoryDenyWriteExecute`, `SystemCallFilter=@system-service`, `UMask=0077`; the helper drops the capabilities its operations do not need and filters system calls; `rfd`, `hmipserver`, `multimacd`, `hs485d`, `hmlangw` run as their own users with an empty capability set, `NoNewPrivileges`, `ProtectSystem=strict` |
| V13.3 | the build's hardening flags | ✅ | PIE, the strong stack protector, FORTIFY and RELRO for every C program the image builds; full RELRO for lighttpd and its modules, busybox, chronyd, sshd, systemd and the tclrega shim (`buildroot-external/lite-hardening.mk`); `scripts/lite-hardening-guard.sh` reads the ELF headers of the image at every build and fails it on a regression. occulited is a static executable and not a PIE: Go without cgo cannot produce a static PIE; eQ-3's prebuilt daemons are checked as delivered (PIE, partial RELRO) |
| V13.4 | debug and unused features are off in the shipped configuration | ✅ | `server.tag = ""`, no directory listing, no `debug.*` on, the access log off unless the Log page switches it on, no ReGa endpoints, the classic RPC sockets written only when switched on (`lite-classic-rpc-conf`) |
| V13.4 | error pages of the proxy say nothing about the backend | ✅ | `occulite-starting.lua` answers a 502/503/504 with the starting page or `{"error":"starting"}`; occulited's own errors are `apiError` codes (V16.5) |

## V14 Data Protection

| section | the requirement, paraphrased | status | where, and why |
| --- | --- | --- | --- |
| V14.1 general | sensitive data is identified and its storage documented | ✅ | the threat model's assets 1–7 with *where* and *who reads it*; [privacy.md](privacy.md) for what leaves the system |
| V14.2 client side | no sensitive data cached by the browser; no secrets in URLs | ✅ | no credential in a URL on the API since 1.3.0 (V7.2); the legacy alias in addon URLs remains by design (R9). In place: `Cache-Control: private, no-cache` on every answer that sets none of its own, `no-store` on the API's secrets, `immutable` only on content-hashed assets; the key sheet keeps keys in the page's memory only; the login form has the `autocomplete` a password manager expects |
| V14.3 server side | backups carry only what a restore needs; live sessions and the backup key stay out; encryption is available | ⚠️ | **Accepted:** an unencrypted backup carries the radio keys (R6), the OIDC client secret, the ACME account key and DNS credentials, the backup targets' credentials and the account hashes — a backup is as sensitive as the system, and the Status page warns about an unencrypted backup target. `.nobackup` on the session store, the backup identity and the caches; encrypted backups on request |
| V14.3 | what is read from another component's storage is the minimum | ✅ | the helper's `ReadPaths` are exact files (`internal/priv/proto.go`): the regadom, `netconfig`, `rfd.conf`/`hs485d.conf` (the gateway keys never reach an answer), `hmip_user.conf` (local key mode), `sgtin.map` (a key only through the confirmed key sheet), `classic-rpc.htpasswd`, `wpa_supplicant.conf` (the page lists SSIDs); hmipserver's `*.ap`, `*.apkx`, `*.bbkx`, `*.dev` for local key mode's snapshot; `/etc/config/shadow` is deliberately not on it |

## V15 Secure Coding and Architecture

| section | the requirement, paraphrased | status | where, and why |
| --- | --- | --- | --- |
| V15.1 documentation | the architecture and the trust boundaries are written down and reviewed | ✅ | [threat-model.md](threat-model.md) B1–B8, reviewed per minor release and per boundary change |
| V15.2 dependencies | dependencies are known, few, and scanned | ⚠️ | **Missing:** no vulnerability scan (`govulncheck`) and no SAST (gosec, CodeQL, secret scanning) in CI. In place: Go modules stdlib-first (a dependency needs a reason in its commit), `go.sum`, the SBOM; scans by hand |
| V15.3 defensive coding | memory safety, no `unsafe`, no cgo, argument vectors not shells | ✅ | Go with `CGO_ENABLED=0`; one `unsafe.Pointer` (`internal/eq3disc/socket_linux.go`, a `PKTINFO` struct copy from a control message, the size checked); V1.2 for the commands |
| V15.3 | integer and size handling on outside data | ✅ | every reader capped (`io.LimitReader`, `MaxBytesReader`), archive members by their size under a total, `checkUpdateSpace` against the recovery's rule |
| V15.4 concurrency | shared state is guarded; the privilege helper cannot be starved by one caller | ✅ | the store's copy–validate–swap; the helper serves each connection in its own goroutine with the caller's deadline, and every long operation has its own timeout (smartctl 60 s, the firewall's input 15 s, the radio-module flash 120–240 s, `RuntimeMaxSec` on every transient unit); `-race` in CI |
| V15.5 | every parser of outside data has a fuzz test | ❌ | **Missing:** no parser has a fuzz test yet (the catalogue, the release feed, the firmware bundle's `info`, the manifest, the XML-RPC decoder are the first candidates) |

## V16 Security Logging and Error Handling

| section | the requirement, paraphrased | status | where, and why |
| --- | --- | --- | --- |
| V16.2 general | structured logs with time, source and outcome; no credentials in the log | ✅ | `slog` to the journal with `SyslogIdentifier=occulited`; the auth lines carry user, method, remote and reason; passwords and token secrets are never fields (token creation logs the name); the gate logs a refused cross-site request with the path URL-encoded and control characters replaced |
| V16.3 security events | successful and failed authentication, lockouts and privilege changes are logged | ✅ | at the default level: `auth: login` (Info: user, role, method, remote), `auth: login refused` (Warn: the name as given with non-printables replaced, the method — also a refused API token —, remote, a reason without secrets) and `auth: login locked after repeated failures` (Warn, once per lockout); the refusals inside a lockout and beyond 30 a minute are Debug, so a brute force cannot flood the journal (`internal/httpapi/authlog.go`); token creation, the confirmations, the cross-site refusals, pairing requests and the pairing switch, the password-login switch and the public mode's switch at Info/Warn |
| V16.3 | administrative changes are attributable (who, from where) | ✅ | every `POST`/`PUT`/`PATCH`/`DELETE` of a scope that changes the system names `user` and `remote` at Info: the handler's own line (`reqLog`) or the middleware's `api: change` with the method, the route and the status (`internal/httpapi/auditlog.go`); an attempt refused with 403 is `api: change refused`; the RPC proxy, the metadata and the LED's live state stay out of Info |
| V16.3 | the privilege helper logs what it refuses | ✅ | `refuse(…)` logs once per refused request with the operation and the path or program (`internal/priv/proto.go`) |
| V16.4 protection | logs are readable only by those who may | ✅ | the journal is root's and `systemd-journal`'s (occulited reads through its supplementary group); the Log page needs `logs:read`; the syslog forward is opt-in; the lighttpd access log is off by default and, when on, goes to the journal |
| V16.5 errors | errors answer a code, not a stack trace or a path | ✅ | `apiError{Error, Message}` everywhere; the store's error codes map to HTTP status; Go's panics are recovered by `net/http` and logged, not answered; the X-Sendfile path never appears in an answer |

## V17 WebRTC

| section | the requirement, paraphrased | status | where, and why |
| --- | --- | --- | --- |
| V17 | — | n/a | no WebRTC |

## How this document is kept

A fix changes its row, with its status; a new route, a new credential path, a new parser or a new cookie changes a
row here in the same change. The whole table is read again at every minor release, with the threat model. The
companion for the product baseline is [security-en303645.md](security-en303645.md).

# openccu-lite against OWASP ASVS 5.0, Level 2

The verification checklist for occulited, its UI and lighttpd's gate: one table per ASVS chapter, each row a section
of the standard with the requirement in our own words, the verdict, and where in the code or in the documents the
answer is. **The requirement texts are paraphrased;** the numbering follows the sections of OWASP ASVS 5.0.0 (V1–V17).
Level 2 is ASVS's level for applications with administrative functions and sensitive data, which a system that
controls a home is. The scope is the one of the audit: occulited, the UI, the fork's lite overlay and lighttpd's
configuration; the eQ-3 processes only as black boxes (their confinement and network exposure).

**Verdicts:** `pass` — verified in the code named; `partial` — the requirement is met in part, the gap is named;
`fail` — not met, with the item that tracks it; `n.a.` — does not apply to this system, with the reason;
`open` — not reviewed yet.

**As of:** occulited `00fda6e`, image `1.0.0-dev.25`, 2026-09-26. The first slice of the manual review covered
**V6 (authentication), V7 (session management) and V8 (authorization)** in full and **V3 (web frontend) and V16
(logging)** in part; the other chapters are listed at the end with what is known and are the next slices. The threat
model ([threat-model.md](threat-model.md)) says why these first: nearly every security bug of the project so far sat on
the boundary between the LAN and the API.

The items named (`B-n`, `task n`) are the project's roadmap items; a finding gets a CVSS 3.1 rating there.

## V6 Authentication

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V6.1 documentation | the authentication controls are written down: the factors, the lockout, the recovery path | partial | [security.md](security.md) *Who is who* and *Authentication off*; the numbers (8 failures → 15 min, argon2id t=3 m=32 MiB, 8-character minimum, 24 h idle / 30 d absolute) were in the code only until this table |
| V6.2 password security | at least 8 characters, any character, no truncation, paste allowed | pass | `internal/auth/auth.go` `ErrWeakPassword` (8), no upper bound below the body limit, the UI's password fields are plain inputs |
| V6.2 | passwords checked against known breached passwords | fail | none; **task 262** (an offline list, no outside call) |
| V6.2 | a change needs the current password; an administrator may reset | pass | `internal/httpapi/auth.go` line ~889 (`current` required unless the caller is an administrator resetting another account) |
| V6.2 | no password hints, no secret questions | pass | none exist |
| V6.2 | passwords stored with a memory-hard hash | pass | argon2id, t=3, 32 MiB (`auth.go` lines 682–690; the memory is what a 1 GB system sharing with a JVM can spare), one verification at a time |
| V6.3 general | anti-automation: a lockout or rate limit against guessing | partial | per user and per address after 8 failures for 15 minutes (`lockedOut`, `LockAfter`, `LockFor`); the address key is the client's choice until **B-230** is fixed |
| V6.3 | the refusal does not tell a wrong user name from a wrong password, in text or in time | partial | the text is generic; the unknown-user path skips the argon2 verification and answers at once — **B-233** |
| V6.3 | no default accounts, no default credentials | pass | the first boot forces an administrator account (`Store.Setup`, once: `ErrSetupDone`); the image ships no account with a password |
| V6.3 | the "authentication off" mode | fail, accepted | everyone is the anonymous administrator (task 29; `AuthAPI.Off`, `EnsureAnonymous`). A documented trust choice for a system in a trusted LAN, stated in [security.md](security.md) *Authentication off* and the threat model's trust statements — not a requirement openccu-lite meets in that mode |
| V6.4 factor lifecycle | initial credentials set by the user, not shipped; a reset ends the account's other sessions | pass | `Store.Setup`; `SetPassword` → `dropSessionsOf(name, keepSession)` |
| V6.4 | API tokens can expire and be revoked | pass | `occulited token --expires`, `DELETE /api/auth/v1/tokens/<name>` (`auth:admin`), `POST …/tokens` with `expires` and `ips` |
| V6.5 multi-factor | a second factor is available for the accounts | fail | none of its own; only through OIDC (the provider's MFA). **Task 262** asks the maintainer whether delegation is the answer or a local WebAuthn/TOTP factor is needed |
| V6.6 out-of-band | out-of-band authenticators, if used, are bound to the request and expire | n.a. | none. Task 219's client pairing (a program asks, an administrator approves on Status, the poll secret is the credential) is an approval flow, not an authenticator; its tickets expire |
| V6.7 cryptographic | API tokens are random, long enough, stored hashed, compared safely | pass | `olt_` + 32 hex characters (128 bits from `crypto/rand`), SHA-256 at rest, looked up by hash (`internal/auth/auth.go` `TokenPrefix`, `validateTokenLocked`); an optional address list (`fromAllowed` — B-230) and an expiry |
| V6.8 identity provider | OIDC with state, nonce and PKCE; the ID token checked; no account created from the provider | pass | `internal/oidc/oidc.go`: `state, nonce, verifier := random(24), random(24), random(48)`, S256 challenge, `code_verifier` at the token endpoint (lines 175–235), the nonce compared (269); the code flow's ID token comes from the token endpoint over TLS with the client secret, which OIDC Core allows in place of a local signature check; a login for a name with no local account is refused and creates nothing (`httpapi/auth.go` 1168); the provider's certificate chain against the OIDC trust store (task 231) |

## V7 Session Management

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V7.1 documentation | the session model is written down: lifetime, storage, what ends a session | partial | this table and [security.md](security.md); the API's session routes in occulited's `docs/system-api.md` |
| V7.2 fundamentals | session ids from a CSPRNG with at least 64 bits of entropy, never derived from the account | pass | 130 bits, 26 characters of base32 (`newSID`, task 125); the CCU's ten-character `@…@` alias (about 59 bits) is a separate legacy id for the addon CGIs only, off unless an undeclared addon needs it, and never a credential on the API (D-77) |
| V7.2 | a fresh id at login (no fixation) | pass | `Store.Login` → `newSID()` for every login; the browser cannot bring its own |
| V7.2 | session ids are not carried in URLs | fail | `?sid=` is accepted on every API route, for a full session id and for a token (`sessionIDs`, `httpapi/auth.go` 273–295) — **task 260**; the legacy alias in addon URLs is the CCU convention, R9 in the threat model |
| V7.2 | session state stored safely on the server | pass | `<state>/sessions/sessions.json` 0600 in a 0700 directory of its own, ids kept as hashes (`live.hash`), a `.nobackup` marker so a backup carries no live session |
| V7.3 timeout | an idle timeout and an absolute lifetime | partial | idle 24 h, absolute 30 d (`Options.IdleTimeout`, `MaxAge`, `auth.go` 301–337). ASVS's Level 2 numbers are shorter (re-authentication within 12 hours); the lengths are a usability choice for a phone shell — a question to the maintainer in **task 262** |
| V7.4 termination | logout ends the session on the server; "log out everywhere" exists; a password change ends the other sessions; removing an account ends its sessions | pass | `logout`, `logoutEverywhere` (`httpapi/auth.go` 857, 920); `SetPassword` and `DeleteUser` → `dropSessionsOf` (`auth.go` 929, 853) |
| V7.5 abuse | the cookie is `HttpOnly`, `Secure` over HTTPS, `SameSite`; a prefix where it applies | pass | `setCookie` (`httpapi/auth.go` 432): `HttpOnly`, `Secure` when the request came over HTTPS (`X-Forwarded-Proto`), `SameSite=Lax`, `MaxAge` 30 d; the HTTPS cookie is `__Secure-occulite_session`. `Path` is `/` — **task 259** scopes it to `/api` |
| V7.5 | state-changing requests are protected against cross-site requests | pass | task 213: `crossSite()` (`httpapi/crosssite.go`) on every non-safe API call whose only credential is the cookie (`Sec-Fetch-Site`, else `Origin`/`Referer`), and on the addon pages at the gate; refused requests are logged. `SameSite=Lax` alone would let a top-level POST through |
| V7.5 | re-authentication for sensitive operations | pass | the confirmations of tasks 154 and 185 (`confirm`, `httpapi/auth.go` 670–767): the password, or the OIDC provider, before the SSH key routes, the radio key routes and the other guarded paths |
| V7.5 | stale or foreign session cookies are cleaned up | pass | `clearStale` deletes cookies that name no live session |
| V7.6 federated | a federated login can be re-confirmed at the provider | pass | `confirm … by oidc` (`httpapi/auth.go` 739–767) |

## V8 Authorization

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V8.1 documentation | the roles/scopes and what each route needs are written down | pass | the route table `internal/httpapi/scopes.go` (task 66) and the scope column of occulited's `docs/system-api.md`; the ladder of levels (D-116, task 78) in `internal/auth/scopes.go` |
| V8.2 design | deny by default; the check in one place, not per handler | pass | `Middleware` (`httpapi/auth.go` ~330): every `/api/*` route needs a session, then the scope of the table; a route the table does not know answers 403 ("nobody reaches it") and is logged at Error. `open()` lists the routes that need no session (health, version, the auth flow, the ACME challenge, the pairing request, `addonctl` with its own token, `homematic.cgi` for the loopback — B-230 — and the SBOM) |
| V8.2 | the authorization rules are tested mechanically | pass | `TestRouteTable` walks every registered route with a token of exactly its scope (200) and without (403 naming the scope), the open ones without a session, Full access everywhere; `TestNoRouteOutsideTheTable` fails on a registration that bypasses `route()`. What is not in the walk: the role/level dimension per route (a `user` against an administrator's route) — `TestLocalTokenAndRoles` covers the local token and the roles by sample |
| V8.2 | least privilege for machine credentials | pass | scopes per token (`meta:read` … `auth:admin`, `*`), an address list, an expiry; an addon's local token carries `meta:read` alone ([addons.md](addons.md)) |
| V8.3 operation level | dangerous operations need an explicit confirmation or a higher scope | pass | `power` for reboot, restore and the paired-devices import (task 251; the handler checks the scope itself as well, because test rigs bypass the middleware), `radio:keys`, `auth:admin`; the confirmations of V7.5 |
| V8.3 | object-level authorization (a user reaches only their objects) | n.a. | single-tenant: the metadata and the system are one household's; a `user` level reads and operates, an administrator configures — there are no per-user objects beyond the account itself (`self`) |
| V8.4 other | the administrator is root on the system: own timers and unit overrides take arbitrary unit content | pass, as a stated trust | trust statement T1 in the threat model (F-8): those routes need the administrator's scope (`system:write`; verified by `TestRouteTable`), and a token needs it too. There is no "administrator who is not root" role, by design |
| V8.4 | "authentication off" grants everything to everyone | fail, accepted | as V6.3: a documented mode for a trusted LAN |

## V3 Web Frontend Security (in part)

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V3.3 cookies | see V7.5 | pass | `Path=/` to narrow (**task 259**) |
| V3.4 headers | `X-Content-Type-Options`, `X-Frame-Options`/`frame-ancestors`, `Referrer-Policy`, HSTS over HTTPS | pass | lighttpd `conf.d/setenv.conf`: `X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `Cache-Control: private, no-cache`; `conf.d/hsts.conf` when HSTS is switched on |
| V3.4 | a Content-Security-Policy on the application's own pages | fail | upstream's CSP line is commented out (`setenv.conf` lines 10–11); no `Permissions-Policy` — **task 259** (F-5) |
| V3.5 origin separation | third-party content is not same-origin with the application | fail, accepted | addons live under `/addons/<id>/` on the same origin — the CCU addon ABI needs it. D-78 chose defence in depth (task 213 done; task 259 the rest); the residual risk R1 is stated in the threat model |
| V3.5 | no permissive CORS | pass | the API sets no `Access-Control-Allow-*` header at all (grep of `internal/httpapi`); a cross-origin page cannot read an answer |
| V3.6 external resources | scripts and styles come from the system, not from a CDN | pass | the shell is embedded in the binary (`internal/ui/dist`), no external URL in the built assets (the `{@html}` in the UI is one, for static icon paths) |

## V16 Security Logging and Error Handling (in part)

| section | the requirement, paraphrased | verdict | where, and why |
| --- | --- | --- | --- |
| V16.2 general | structured logs with time, source and outcome; no credentials in the log | pass | `slog` to the journal with `SyslogIdentifier=occulited`; the auth lines carry user, method, remote and reason; passwords and token secrets are never fields (token creation logs the name) |
| V16.3 security events | successful and failed authentication, lockouts and privilege changes are logged | fail | password logins and their refusals are `Debug`, the lockout logs nothing; only OIDC, token creation, the confirmations, the cross-site refusals and the password-login switch are at Info/Warn — **B-231**. The address in every such line is the client's choice until **B-230** |
| V16.3 | administrative changes are attributable (who, from where) | partial | the SSH and key routes and the confirmations name user and address; the older system routes log the action without the caller — the threat model's B1 *Repudiation* row stays open |
| V16.4 protection | logs are readable only by those who may | pass | the journal is root's and `systemd-journal`'s (occulited reads through its supplementary group); the Log page needs `logs:read`; the syslog forward is opt-in |
| V16.5 errors | errors answer a code, not a stack trace or a path | pass | `apiError{Error, Message}` everywhere; the store's error codes map to HTTP status; Go's panics are recovered by `net/http` and logged, not answered |

## The chapters not yet reviewed

| chapter | what is known already | next |
| --- | --- | --- |
| V1 encoding and sanitization | names are checked for control characters (B-38); the UI has one `{@html}`, for static icon paths | the metadata import and the tclrega shim |
| V2 validation and business logic | the store validates every mutation (copy–validate–swap) | hostnames, unit files (task 121/208), PEM (task 231) |
| V4 API and web service | JSON only, body limits on most routes | **B-232** (eight unlimited decoders, no idle timeout) |
| V5 file handling | the archive readers drop climbing members and links, cap member sizes (`internal/firmware/deploy.go`, `system/radioimport.go`, `regaimport`) | the update archive (`sysupdate`) and X-Sendfile (B-35/B-36) again; **task 265** fuzzes them |
| V9 self-contained tokens | none issued; the OIDC ID token is consumed, not issued | — |
| V10 OAuth/OIDC | see V6.8 | the provider metadata refresh and the trust store's failure path |
| V11 cryptography | argon2id, SHA-256 for tokens, `crypto/rand`, age for encrypted backups (task 91), TLS 1.2+ in lighttpd (`sslsettings.conf`) | the ACME account key's storage, the backup key derivation |
| V12 secure communication | HTTPS optional with ACME, HSTS optional, TLS 1.2 minimum; occulited and the interface processes on the loopback only (D-29) | the outbound calls' TLS (task 231's four stores cover the roots) |
| V13 configuration | `occulited.service` sandboxed (task 208), lighttpd's unit too; PIE and RELRO gaps — **task 261** | `systemd-analyze security` for every lite unit (task 264) |
| V14 data protection | the keys in clear on the storage and in backups (R6); backups encrypted on request (task 91) | **task 266** (what leaves the system) |
| V15 secure coding | Go, no cgo, stdlib first; the helper's allowlist | **task 264** (SAST), **task 265** (fuzzing) |
| V17 WebRTC | — | n.a. |

## How this document is kept

It is task 120's phase 3 record and is updated with each slice and with each fix: a `fail` becomes a `pass` with the
commit that fixed it in the last column. A new route, a new credential path or a new cookie changes a row here in the
same change. The companion for the product baseline is [security-en303645.md](security-en303645.md).

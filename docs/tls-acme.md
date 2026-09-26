# A certificate from an ACME CA: Let's Encrypt, or your own step-ca

The system serves HTTPS with a self-signed certificate that `S50lighttpd` generates (ten years, the
host name and the address in the SAN). It can also fetch one from an **ACME**
CA instead — **Let's Encrypt** (or ZeroSSL) for a system that has a public DNS name, a **LAN CA**
such as **step-ca** for everything else — and renew it itself: twice a day it checks, and below
30 days it renews. The certificate goes to lighttpd *and* to the confined addons (the `certs`
group), so a broker's `8883` or an addon's own web server offer the same certificate.

Everything is on **System → Certificate**. The page shows the certificate the system serves now
(issuer, names, expiry, days left), the mode switch, the settings, three buttons — **Test**,
**Issue now**, **Renew now** — and the last attempt's log lines. The Status page carries a card
with the mode and the expiry, and warns when fewer than 14 days remain or the last renewal
failed.

## Before you start: the name

An ACME certificate carries **DNS names**, never an address. The system needs a name that resolves
to it — for Let's Encrypt a public name (`ccu.example.org`), for a LAN CA whatever your DNS or
your `hosts` entries say (`openccu.lan`). The first name is the certificate's subject, every
further one a SAN. An address in the list is refused with a message that says so.

## The two challenges

The CA has to see that the name is yours. Two ways:

- **HTTP-01**: the CA fetches `http://<name>/.well-known/acme-challenge/<token>` on **port 80**.
  lighttpd hands that path to occulited, which answers only the tokens of an order in flight.
  For Let's Encrypt that means port 80 must reach the system **from the internet** — a port forward
  on the router, and under the firewall's `RESTRICTIVE` mode (the default) the source has to
  be allowed by the mode or the address list on System → Network → Firewall (Let's Encrypt
  validates from several addresses that are not published). For a LAN CA it means the CA can reach
  the system on the LAN, which the firewall allows as it stands. The HTTPS redirect (System →
  Security) leaves this one path alone.
- **DNS-01**: occulited puts a `_acme-challenge` TXT record into your zone through the
  provider's API, the CA reads it. Nothing has to reach the system — **this is the one for a system
  behind NAT**, and the only one for a wildcard. The providers built in: **Cloudflare,
  Hetzner DNS, netcup, DuckDNS** and **exec** (a script of your own, for every other provider —
  lego's exec contract, so a script written for lego works as it is). Each has its fields on the
  page; the secrets are stored on the system and never shown again — the page says "set" and an
  empty field on save keeps the stored value. deSEC, INWX and RFC 2136 (nsupdate) were in the
  first build and were dropped for their share of the binary (their API clients and a kerberos
  chain, +3.8 MB together); they come back on request — until then an exec script covers them.

## Let's Encrypt with DNS-01 (a home system behind NAT)

1. Give the system a public name in a zone one of the providers manages, e.g. `ccu.example.org` at
   Cloudflare. It does not have to resolve to a public address — the CA never connects to it with
   DNS-01; a private address or no A record at all is fine.
2. Make an API token at the provider — Cloudflare: *My Profile → API Tokens*, template *Edit zone
   DNS*, limited to that zone.
3. System → Certificate: mode **ACME**, directory **Let's Encrypt**, your e-mail (Let's Encrypt
   mails before an expiry it could not renew), the name(s), challenge **DNS-01**, provider
   **Cloudflare**, the token. **Save**.
4. **Test**: the whole flow against Let's Encrypt's *staging* directory — account, TXT record,
   propagation, order — without installing anything. The lines below the buttons show what
   happened; a wrong token or a name the zone does not hold fails here, cheaply and without
   touching Let's Encrypt's rate limits.
5. **Issue now**: the same against the production directory. The certificate is installed as
   `/etc/config/server.pem`, lighttpd reloaded, and every confined addon in the `certs` group
   restarted (they are named in the log lines). Open `https://ccu.example.org/` — a browser
   trusts it.

From then on the daemon renews it below 30 days, or once less than half of its lifetime is
left, whichever comes first. A failed renewal is a warning on the Status page and on this page
with the error; the old certificate stays in service until the next attempt, twelve hours later.

**DuckDNS** takes one TXT record per name — order one name at a time. **netcup** propagates
slowly; an issue can take a quarter of an hour. **exec** runs your script as the `occulite`
user: `program present <domain> <token> <keyAuth>` and `program cleanup …` (or, in mode `RAW`,
`present <domain> <fqdn> <txt-value>`), the same contract as lego's exec provider.

## Let's Encrypt with HTTP-01 (a system with a public address)

The same settings with challenge **HTTP-01**, and port 80 forwarded to the system from the
router. On System → Network → Firewall, `RESTRICTIVE` mode with the default address list lets
the LAN in and nothing else: Let's Encrypt has to be let in — the pragmatic setting is
`MOST_OPEN` for the minute of the issue, or the addresses your router presents. The exposure is
one path that answers tokens of an order in flight and `404` otherwise; the shell and the API
behind the same port still need a session. DNS-01 avoids the question altogether.

## step-ca on the LAN with HTTP-01

A [step-ca](https://smallstep.com/docs/step-ca/) with an ACME provisioner
(`step ca provisioner add acme --type ACME`) issues short-lived certificates to anything on the
LAN that can prove a name. On its side the system's name has to resolve for the CA — a DNS entry,
or `--add-host` on a containerised CA.

1. Copy the CA's root certificate: `step ca root` prints it, or read `certs/root_ca.crt` under
   the CA's home. It is a PEM, `-----BEGIN CERTIFICATE-----` to `-----END CERTIFICATE-----`.
2. System → Certificate: mode **ACME**, directory **custom**, the URL
   `https://<ca>:9000/acme/acme/directory` (the provisioner's name is the second `acme`), the
   root PEM pasted into **CA root** — occulited trusts it for that connection only, nothing on the
   system changes — the system's LAN name, challenge **HTTP-01**. Save, **Test** (a custom CA has no
   staging twin, so the test runs against the CA itself and only skips the install), **Issue
   now**.
3. Browsers trust the result once the CA's root is installed on them — that is step-ca's usual
   deal, one root for the whole LAN.

step-ca's default certificate lifetime is 24 hours. The system copes — below half the lifetime a
certificate is due, so a 24-hour one is renewed at every twelve-hourly check, and the page
warns at issue when a lifetime is under 48 hours — but the addons restart with every renewal,
and anything under twelve hours can lapse between two checks. Set the provisioner's
`--max-tls-cert-duration` to something like `2160h` (90 days) instead.

**The marker.** Next to the live file the helper writes `/etc/config/server.pem.acme` (one
line, the issuer). `S50lighttpd`'s own certificate check regenerates a self-signed certificate
whenever the file expires within a day — which a fresh 24-hour certificate does — and the marker
tells it to leave an ACME-managed file alone: occulited renews it. The page shows *managed* when
the marker is there; the switch back to self-signed removes it first, so the script regenerates
again.

## ZeroSSL and company CAs: external account binding

ZeroSSL's ACME directory wants an **EAB** key id and HMAC (from its dashboard, *Developer →
EAB credentials*), as do many company CAs. The two fields are on the page; the HMAC is a secret
like the DNS tokens. ZeroSSL has no staging directory, so **Test** runs against the real one.

## Your own certificate: mode manual

Not every certificate comes from an ACME CA — a company CA with a web form, a bought one, one
made on another machine. Mode **Manual** on the Certificate page takes it either way:

- **Upload or paste.** Three fields — certificate, chain, private key — each as a file (**PEM or
  DER**; a Windows CA's `.cer` and a router's export are DER, the system tells by the first byte)
  or pasted as PEM into a field tall enough for a whole certificate. The chain is optional and
  may be appended to the certificate instead, in any order; the key may be PKCS#8, PKCS#1 or
  SEC 1, **not encrypted** (there is no password field: the system would have to store it, and
  the file it writes is plain anyway — `openssl pkey -in key.pem -out key-plain.pem` first).
  Under each field a preview appears as soon as the text parses: subject, issuer, validity, the
  names; the key's algorithm and whether it belongs to the certificate. **Install** writes the
  file the same way an ACME certificate is written (the helper, `root:certs 0640`, lighttpd
  reloaded, the confined addons of the `certs` group restarted) and sets the mode to manual.
- **A key and request made on the system.** *Key and certificate request*: the algorithm (P-256
  by default; P-384, the CCU's own curve; RSA-2048 for a CA that wants RSA), the common name —
  the system's DNS name — other names, an organisation. The system generates the key and a CSR;
  download the `.csr` (or copy the text), have your CA sign it, and install the certificate it
  returns above **without a key** — the system holds the one the request was made for and checks
  that the certificate is really for it. **The key never leaves the system.** A new request replaces
  the pending one (the page asks). The same pair of buttons serves a renewal with the same key
  later: install the new certificate, the key is still there.

What is refused, with the reason: a key that is not the certificate's (both public-key
fingerprints named), an expired or not-yet-valid certificate (with its dates and the system's
clock), an encrypted key, material that does not parse. A **missing intermediate is a warning**,
not a refusal — you may know that every client has it. Nobody renews a manual certificate: the
Status page warns from 14 days out, and a new one is installed the same way. Back to self-signed
works as below; a switch to ACME keeps the pending key and request until a certificate is
installed.

## Back to self-signed

Mode **self-signed**, **Save** (from ACME or manual): `/etc/config/server.pem` and its markers are removed and lighttpd reloaded —
`S50lighttpd`'s certificate check regenerates a self-signed one on that reload (ten years, the
host name and address in the SAN) — and the addons of the `certs` group are restarted. The ACME
settings, the account and the last issued chain stay under the state directory
(`docs/config.md`), so switching back later is one press.

## What is where

- State: `/usr/local/etc/occulite/acme/` — settings with the secrets, the account key, the
  issued chain and key, the last attempt; `/usr/local/etc/occulite/tls/` — the manual mode's
  key, pending request and installed chain (config.md). In every backup.
- Live file: `/etc/config/server.pem`, chain then key, `root:certs 0640`, written by the
  privilege helper (security.md); the markers `/etc/config/server.pem.managed` (`<mode>
  <issuer>`) and, for now, `/etc/config/server.pem.acme` beside it.
- API: `GET/PUT /api/system/v1/certificate…` (system-api.md).
- The log: `journalctl -u occulited | grep certificate:` — one line per attempt, and the page's
  lines are the same run in detail.

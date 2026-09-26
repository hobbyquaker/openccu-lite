# Privacy: what the system sends to outside sources

openccu-lite has no telemetry, no vendor account and no cloud service of its own. This page lists every connection
the system opens by itself, field by field: where it goes, when it happens, what it sends, what it does not send, and
how to switch it off. It covers the system service `occulited`, the image (the radio stack, time, network) and the
recovery system. Traffic of an addon you install is that addon's own and is not covered here.

The requests to the internet that `occulited` builds are pinned by tests (`internal/*/outbound_test.go` in the
occulited repository). A change to what leaves the system fails those tests, and this page is changed with them.

## In short

| Connection | Destination | When | What identifies the system | Switch |
| --- | --- | --- | --- | --- |
| [System release check](#system-release-check) | GitHub (`api.github.com`) | on *Check now*; daily with *Check daily* (on by default) | nothing but the IP address | Updates page: *Check daily* |
| [Device firmware check](#device-firmware-check-and-download) | eQ-3 (`ccu3-update.homematic.com`) | on *Check now*; daily with *Check daily* (on by default) | the system's base firmware version; the device **types** that need an update | Updates page: *Check daily* |
| [Addon catalogue](#addon-catalogue) | GitHub (`raw.githubusercontent.com`, `api.github.com`) | on *Check now*; daily with *Check daily* (on by default); when the Addons page opens and the copy is older than 10 minutes; at an install | nothing but the IP address | Addons page: *Check daily* |
| [Addon update checks](#addon-update-checks) | each addon's own `Update:` URL | on the addon's check; daily with the Addons page's *Check daily* | the addon's installed version | Addons page: *Check daily* |
| [ACME certificates](#acme-certificates) | the chosen CA (e.g. Let's Encrypt), a DNS provider | only in ACME mode: at the order, then a renewal when due | the system's names, the contact mail if given | Certificate page (default: self-signed, no calls) |
| [Login with OpenID Connect](#login-with-openid-connect) | the configured provider | only when configured: at a login and at *Check* | the client id, the redirect URI | Users page (default: off) |
| [Status LED internet check](#status-led-internet-check) | the hosts of the above | only when the LED is set to show it: every 5 minutes | a TCP connection, nothing sent | Status LED page (default: off) |
| [Time (NTP)](#time-ntp) | your servers, the DHCP ones, and `0-3.de.pool.ntp.org` | always | the NTP protocol only | Network page (the pool servers stay, see there) |
| [HmIP key server](#hmip-key-server) | eQ-3 (`secgtw.homematic.com:8443`) | a radio module exchange; pairing a device whose key is not on the system | the radio module's and the device's serial numbers (SGTIN) | Keys page: *Local key mode* |

Everything else stays on your local network, unless you point it elsewhere yourself: see
[On the local network](#on-the-local-network).

## Common to every HTTPS request

- **User-Agent:** Go's default, `Go-http-client/1.1` (or `Go-http-client/2.0` over HTTP/2). Only ACME sends its own
  (see there). No request carries a cookie, a token of the system, a serial number, a MAC address, the host name or
  the list of your devices or addons, unless a section below says so.
- **What the server always sees:** your public IP address and the time of the request, as for any connection.
- **Certificates:** each request trusts the system's *Trust stores* (System → Trust stores); a proxy set in the
  service's environment (`HTTPS_PROXY`) is honoured.
- **Answers are cached:** the release list and GitHub's API are asked with the `ETag` of the last answer
  (`If-None-Match`), so an unchanged answer costs GitHub a `304`.

## Internet connections of the system service

### System release check

- **To:** `GET https://api.github.com/repos/hobbyquaker/openccu-lite/releases?per_page=20` (the feed can be changed
  in `occulited.json`, `system_update.feed`).
- **When:** *Check now* on the Updates page, always. With *Check daily* on (the default): 2–7 minutes after the
  start, then every 24–26 hours.
- **Sends:** the request line, `Accept: application/vnd.github+json`, `If-None-Match` with the last answer's ETag, the
  User-Agent. **Not sent:** the system's version, product or platform - the system picks the matching release from
  the list itself.
- **The download** of an update (the image and its `.sha256` file, from GitHub's release assets) happens only when you
  start it; a plain `GET` of the two files.
- **Off:** clear *Check daily*. *Check now* still works.

### Device firmware check and download

The firmware of paired Homematic and HmIP devices comes from eQ-3's update server, the same one a CCU3 uses.

- **To:** `GET https://ccu3-update.homematic.com/firmware/api/firmware/search/DEVICE?product=HM-CCU3&version=<VERSION>`
  - the list of current device firmware.
- **When:** *Check now* on the Updates page, always. With *Check daily* on (the default): 5 minutes after the start
  when the last run is older than a day, then daily; a failed run is tried again after an hour. No request is made
  while no device is paired.
- **Sends:** the product `HM-CCU3` and `<VERSION>`, the base (OpenCCU) firmware version of the system, as in
  `/VERSION`, e.g. `3.89.11.20260919`; the User-Agent.
- **The download, in the same run:** for every paired device type whose firmware on the server is newer than what
  the system already holds, `GET …/firmware/download?cmd=download&product=<DEVICE TYPE>&serial=0`. So eQ-3 learns
  which device types (e.g. `HmIP-BBL`) are paired and not up to date. The serial is always `0`: **no device serial
  number is sent.** Installing a downloaded firmware onto a device stays your action in your frontend.
- **Not sent:** device serial numbers, the system's serial or SGTIN, the host name, how many devices there are.
- **Off:** clear *Check daily* (also offered on the welcome page). Firmware files can be uploaded by hand instead.

### Addon catalogue

The catalogue is a list of addons with a manifest for each; it lives on GitHub.

- **The catalogue file:** `GET https://raw.githubusercontent.com/hobbyquaker/occulited/master/catalog/catalog.json`
  (the list of catalogue URLs is in `occulited.json`, `catalog.urls`). A copy of it ships in the image and is used
  when the network is not there.
- **When the catalogue file is fetched:**
  - *Check now* on the Addons page;
  - with *Check daily* on (the default): 3–8 minutes after the start, then daily;
  - **when the Addons page is opened and the copy in memory is older than ten minutes**, and at the start of the
    service when an installed addon carries no manifest of its own - also with *Check daily* off. This does not
    follow the rule "nothing goes out unless you ask or tick the box" yet; it is a known bug (B-240) and will change.
- **On *Check now*** in addition: each listed addon's manifest from its repository at its latest release
  (`GET https://raw.githubusercontent.com/<owner>/<repo>/<tag>/<path>`), its star count
  (`GET https://api.github.com/repos/<owner>/<repo>`) and its release list
  (`GET https://api.github.com/repos/<owner>/<repo>/releases?per_page=10`).
- **With *Check daily*:** the release lists of the addons already known, with their ETags.
- **At an install:** the package and its `.sha256` file from the addon's GitHub release.
- **Sends:** the URL, `Accept: application/vnd.github+json` to GitHub's API, `If-None-Match` where an ETag is known,
  the User-Agent. **Not sent:** which addons are installed, the system's version, serial or name. (The architecture
  is part of an asset's file name, e.g. `mosquitto-x86_64-2.1.2.tar.gz`, so a download shows it.)
- **Off:** clear *Check daily*; the catalogue as a whole can be switched off in `occulited.json`
  (`catalog.enabled: false`).

### Addon update checks

An addon names its own update check (the `Update:` line of its `rc.d` script, as on a CCU).

- **An absolute URL** (`https://…`): the system calls `GET <that URL>?cmd=check_version&version=<installed version>`
  directly. **Sends:** the addon's installed version and the User-Agent; no token, nothing about the system.
- **A path on the system** (`/addons/<id>/update-check.cgi` and the like): the system calls the addon's own script
  through its local web server. What that script then asks on the internet is the addon's own (usually its GitHub
  releases).
- **When:** the addon's check button; with the Addons page's *Check daily* on (the default): 2–5 minutes after the
  start, then daily.
- **Off:** clear *Check daily* on the Addons page.

### ACME certificates

The default certificate is self-signed and made on the system: no call at all. Only when you switch the Certificate
page to ACME:

- **To:** the CA you chose (Let's Encrypt, ZeroSSL, or a directory URL of your own) over the ACME protocol, and in
  DNS-01 mode your DNS provider's API with the token you entered.
- **When:** at the order, and when a renewal is due; the renewal check runs twice a day and talks to the CA only
  when the certificate has less than 30 days left.
- **Sends:** a new account key (made on the system), the contact mail if you entered one, the External Account
  Binding if your CA needs one, and the names the certificate is for (e.g. `<host>.<your domain>`). The User-Agent
  is `occulited/<version> xenolf-acme/<lego version> (release; linux; <architecture>)`.
- **Public:** every name in an issued certificate is published in the CAs' Certificate Transparency logs.
- **HTTP-01** means the CA connects **to** the system on port 80 from the internet; see [tls-acme.md](tls-acme.md).
- **Off:** set the Certificate page back to self-signed or to an uploaded certificate.

### Login with OpenID Connect

Off by default. When you configure a provider on the Users page:

- **Discovery:** `GET <issuer>/.well-known/openid-configuration` at a login and when you press *Check*; *Check* may
  also open a TLS connection to the issuer to show its certificate.
- **The login:** your browser goes to the provider with the client id, the scopes, a state, a nonce and a PKCE
  challenge, and the redirect URI (built from the address your browser used). The system then posts the code, the
  PKCE verifier, the redirect URI, the client id and, if set, the client secret to the token endpoint, and reads the
  user info with the access token.
- **The provider learns:** that someone logs in to this system, and the account they use there.
- **Off:** switch OpenID Connect off on the Users page.

### Status LED internet check

Off by default. When the status LED is set to show a missing internet connection, the system opens a TCP connection
every 5 minutes to the host of the catalogue URL and, in ACME mode, of the ACME directory, and closes it at once.
Nothing is sent over it. The Status LED page switches it off.

## Internet connections of the image

### Time (NTP)

The radio stack needs a correct clock, so time synchronisation (chrony) always runs, on every product but the LXC
container (which takes the host's clock).

- **To:** the servers set on the Network page (`/etc/config/ntpclient`), the ones your DHCP server hands out (unless
  switched off there), the default gateway when neither gives one - **and always also `0.de.pool.ntp.org` to
  `3.de.pool.ntp.org`**, with your own servers preferred. That the pool is asked even when you set your own servers
  is a known bug (B-242).
- **Sends:** NTP packets, which carry nothing but timestamps.
- **Off:** not switchable (the radio stack needs the time); the firewall can block UDP 123 to the internet if your own
  server is on the LAN.

### HmIP key server

HmIP devices share a network key, which normally is locked in the radio module; eQ-3's key server
(`secgtw.homematic.com`, port 8443) is what moves it. hmipserver, eQ-3's HmIP service, calls it in two cases:

- **A radio module exchange:** a new HmIP radio module on an existing HmIP network. hmipserver sends the old and the
  new module's serial numbers (SGTIN) and the network key in the encrypted form the modules produce; the key server
  answers the key wrapped for the new module. Never in plain text.
- **Pairing a device without its key:** a device whose key is not on the system (not scanned from its QR code, not
  under *HmIP device keys* on the Keys page). The device's SGTIN goes to the key server, and its answer lets hmipserver accept the device.
  With the device's key on the system, pairing asks nobody.
- **When:** only at those two moments; not at every start.
- **Off:** switch to *Local key mode* on the Keys page: the network key is then kept on the system, module
  exchanges and pairing work offline, and the key server is asked only when you allow it for the next pairing.
  Without local key mode, scanning each device's QR code before pairing avoids the call.

### DNS

Names are resolved by the DNS servers your DHCP server hands out, or the ones set on the Network page. No public
resolver is built in.

## On the local network

These go to devices on your LAN. Some go wherever you point them - a backup target or a syslog server on the internet
is then an internet connection you chose.

| Connection | What goes out | When | Switch |
| --- | --- | --- | --- |
| DHCP (IPv4) | the host name (default `openccu`), the vendor class `eQ3-CCU3` on Ethernet (a CCU3's; question B-243), the MAC address as any DHCP client | at boot and at each lease renewal | Network page: static address |
| DHCPv6 | the MAC-derived client id, as any DHCPv6 client | when IPv6 is set to DHCPv6 | Network page |
| SSDP (UPnP) | `NOTIFY` every 30 minutes and answers to `M-SEARCH`: `SERVER: Linux UPnP/1.0 openccu-lite/<version>`, the description URL, the board serial or SGTIN as the UUID and serial (the host name until one is known), the friendly name `openccu-lite - <host name>` | always | firewall |
| eQ-3 discovery (UDP 43439) | answers to a CCU finder's probe: the type, the serial or SGTIN, the version | always, only when asked | firewall |
| Syslog forward | every journal entry, RFC 5424 over UDP, unencrypted | only with a syslog server set on the Log page | Log page: clear the server |
| MQTT | the metadata store as retained messages (interface and address, names, rooms), plain TCP, the user name and password in clear | only when configured in `occulited.json` (`mqtt`, off by default) | `mqtt.enabled` |
| Backup targets | SFTP: the backup file (`<host name>-<version>-<date>.sbk`, encrypted with the recovery key unless you chose otherwise), the per-target SSH key, Go's SSH banner; SMB and NFS: the file over the kernel's client | at your backup and the nightly one, when a target is set | Backup page |
| Network shares | SMB and NFS mounts with the credentials you entered; a TCP probe of port 445 or 2049 every minute while a share is set | when a share is set | Storage page |
| HB-RF-ETH and LAN gateways | an mDNS query and `GET /sysinfo.json` to find and describe an HB-RF-ETH; the radio protocol to a configured gateway; a gateway's firmware and key from files on the system (nothing is downloaded) | on *Find* and when configured | LAN devices page |
| Finding eQ-3 LAN devices | a broadcast probe, and the network settings you enter (encrypted with the device password, which itself is not sent) | on *Find* | LAN devices page |
| An address in use check | one empty UDP datagram (port 9) to the address, to see whether anything answers on the LAN | when you enter a static address | - |
| Importing from a CCU | a script posted to the CCU you name (`/tclrega.exe`), reading its names and rooms | on your import | - |
| XML-RPC clients | the events the interfaces send to the address a client registered; a test connection to that address | while a client is registered | the client |

The interface processes (rfd, hmipserver, hs485d) talk only to the radio hardware, the LAN gateways you configured
and the loopback, apart from the key server above.

What reaches the system **from** the LAN (the web UI, the XML-RPC ports, SSH) is listed in
[security.md](security.md#what-listens-where).

## The recovery system

The recovery system (Raspberry Pi and OVA) runs only for an update from a file or a rescue. While it runs it:
- asks DHCP with the vendor class `eQ3-CCU3` and no host name;
- sets the clock with `ntpdate` against the default gateway, then `0-3.de.pool.ntp.org` - it does not read your NTP
  setting;
- announces itself over SSDP and answers eQ-3's discovery, with the board serial, as a CCU3's recovery system does;
- runs SSH and a web server on the LAN.

It downloads nothing: an update comes from the file you upload or a USB stick.

## The OVA

The virtual appliance ships the guest agents of the common hypervisors (QEMU, VMware, Xen). They report to the host
that runs the virtual machine - its addresses, the host name, the state - never to the internet.

## What never leaves the system

Unless you send it yourself (a backup, a syslog server, MQTT, an addon), none of this is sent anywhere:
- the names of devices, channels, rooms and functions, the metadata and the values of devices;
- the device keys, the HmIP network key (outside the encrypted exchange above), the BidCos security key;
- user names, password hashes, sessions and tokens, the system's private keys and certificates;
- the journal and the logs;
- serial numbers of devices and of the system (outside the key server, the LAN discovery and the DHCP request);
- MAC addresses beyond the LAN.

## Not in the image

openccu-lite removes OpenCCU's own calls: the internet check (`checkInternet`, and with it the `hasInternet` status),
the port forwarding check (`checkPortForwarding.sh`), the addon update script (`checkAddonUpdates.sh`), the firmware
update script (`checkFirmwareUpdate.sh`, OpenCCU's GitHub release check; the *System release check* above replaces
it), the WebUI's update check, and eQ-3's `ssdpd` and `eq3configd` (replaced by the answers above). No CA certificate
is fetched: the trusted roots come with the image and with what you add under *Trust stores*.

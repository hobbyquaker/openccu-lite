# Switching between OpenCCU (or a CCU3) and openccu-lite

*English — the German version is [switching.de.md](switching.de.md).*

Going **to** openccu-lite is a supported operation. Coming **back** is done by restoring the
backup you took before you left — not by flashing OpenCCU over lite and expecting your
configuration to be there.

**Take a backup before you migrate, and keep it.** That `.sbk` is the way back. Everything else on
this page is mechanics. **Since 2026-09-25 there is no other way back at all:** after its
first start openccu-lite removes the CCU's leftovers from the userfs - the ReGa database
(`homematic.regadom` and its `.bak`), the WebUI's `measurement` and `userprofiles`, ReGa's working
files and mediola's NEO Server - once the names have been imported from them. The radio identity,
the keys, the interface configuration and the addons stay.

The mechanics are the easy half: same partition layout, same image and update package format, and
`/usr/local` — pairings, radio keys, interface configuration, addons — survives either way. What
does not survive is ReGa's database. openccu-lite does not run ReGaHss, so from the moment
you switch, the `homematic.regadom` on the system stops being maintained: every name, room, function,
program and system variable you change afterwards exists in openccu-lite's metadata store and
nowhere else. Flashing OpenCCU back gives you OpenCCU with a ReGa database frozen at the day you
left, and no amount of copying pieces across changes that. **This page used to claim otherwise, and
offered an HM-Script export to paper over the gap. Both are gone (2026-09-08).**

## OpenCCU / CCU3 → openccu-lite

**The short version for an OpenCCU VM (`ova`) or an SD-card product**: on the OpenCCU WebUI go to
Settings → Control panel → CCU maintenance → Perform software update, upload `openccu-lite-<product>-<version>.zip`, confirm,
let it reboot. OpenCCU's own recovery system flashes the image and keeps `/usr/local`; the lite system
comes up with your pairings, keys and addons, reads the names, rooms and functions out of the ReGa
database on its first boot, and asks you for an administrator password. The `.zip` is accepted
because the lite image's `/VERSION` carries upstream's `PLATFORM` — the recovery compares
exactly that. **The way back**: flash OpenCCU through the *System update* section of the lite Status page with upstream's `OpenCCU-<version>-ova.zip`, then **restore the backup you took before migrating**. The flash alone gets you a working OpenCCU with your pairings, keys and addons — `/usr/local` survives — but its ReGa database is the one from the day you left. The backup is what makes the system the system it was.

1. **Back up** on the old system (Settings → Control panel → Security → Create backup, or `createBackup.sh`).
   Keep the `.sbk`.
2. **Flash / update** to openccu-lite. The updater accepts the package; the recovery system is
   upstream's.
3. **First boot**: if you updated in place, the system has its pairings and keys already —
   `/usr/local` was not touched — and you set the administrator password once. If you reflashed,
   **restore the `.sbk` first** (the Backup page is reachable after a throw-away administrator is
   created): the restore replaces `/usr/local` wholesale — pairings, keys, addons, and also
   `occulited`'s own state — so the administrator you created before the restore is gone and the
   system asks for one again on the next visit. That order is deliberate: nothing from the old system
   is lost, and nothing from before the restore lingers. The ReGa database inside the backup is
   accepted and simply ignored.
4. **Names, rooms and functions**: while the old CCU is still reachable, *Names → Import from a
   CCU* pulls them over its remote script port (8181). The old CCU's firewall must allow the new
   system (REGA: *full*, or the new address in the list). Rooms and functions become flat nodes;
   objects still carrying the CCU's default `<type> <address>` name are left out and counted.
   If the old CCU is gone, run the same import from any CCU that has the backup restored, or
   import a `meta.json` exported earlier.

   **Umlauts**: the ReGa database declares `iso-8859-1` and is not — it is mixed. eQ-3's own
   strings really are Latin-1 (a unit is the single byte for "°C"), while a name a user typed on a
   current firmware is UTF-8 in the same file. Both are read correctly; before 2026-09-07 every
   umlaut in a name came across as `Ã¼`. If you are looking at an import taken with an older image,
   that is what you are seeing, and a re-import on a current one fixes it. A system whose ReGa has the
   same room in both encodings — which happens on a CCU that has been through several firmware
   generations — ends up with one room here, not two.

   **The CCU's own rooms and functions**: the eleven rooms and ten functions a CCU creates by
   itself (Wohnzimmer … Terrasse, Licht … Energiemanagement) are stored in ReGa under a
   translation key — `roomBathroom`, or `${roomBathroom}` — and the WebUI swaps in the name from
   its language files on every page. Every import (from this system, from a backup, from a running
   CCU) now does the same, with the WebUI's German names: `roomBathroom` becomes *Badezimmer*,
   `funcHeating` *Heizung*. Only a name that is exactly one of these keys is translated; one you
   typed stays as it is, and an English system renames them by hand. A store imported before this
   (it lists `roomBathroom`, `funcCentral` … in the App's drawer) is corrected when `occulited`
   starts: those nodes are renamed in place, keep their ids (`room/roombathroom`) and so their
   members, and each rename is an ordinary revision on the change stream.
5. **What does not come across**: programs, system variables, alarms, favourites, diagrams —
   there is nothing here that could run or show them. Automation moves to Node-RED (RedMatic),
   Home Assistant, ioBroker or whatever you already use.
6. **Addons**: those in the [catalogue](https://github.com/hobbyquaker/occulited/blob/master/docs/catalog-format.md) are known to work. Addons that need
   the ReGa (CUxD, the XML-API, anything that reads system variables or keeps its settings in the
   ReGa DOM) are **disabled on this first boot** and listed on the Addons page as "disabled,
   incompatible", each with the reason; they are not uninstalled, and a switch brings one back
   for the brave. The catalogue does not list such addons at all.
7. **Addons with binaries for another architecture** are disabled on the same first boot and
   listed as **"disabled, needs update"** with the offending file named. `/usr/local`
   survives a switch, so an addon installed on the old system comes along exactly as it was — and an
   addon compiled for a machine this one is not cannot run here. See
   [Architecture and addon binaries](addons.md#architecture-and-addon-binaries): the repair is the
   catalogue's *Install* / *Update* button, which fetches the release built for this system.
8. **mediola's NEO Server**, which OpenCCU's own package unpacks onto the userfs
   (`/usr/local/addons/mediola`, `rc.d/97NeoServer`), comes across too and cannot work here: it
   posts to `/tclrega.exe` and `/api/homematic.cgi`, the ReGa and the WebUI's CGI stack.
   openccu-lite switches it off **once**, with the addon's own switch (`Disabled` in its
   directory, which its rc.d script honours) and the executable bit of its rc.d entry, and lists
   it with the other ReGa-dependent addons on the Status and Addons pages. After the first start
   it goes with the other leftovers (what the addon's own uninstall does, `neoDisabled`
   marker included).
10. **The leftovers** (there is no way back except the backup taken before the migration):
   once the first-boot name import has read the ReGa database (or settled: given up, or not needed
   because the store holds names), occulited removes exactly this list, once - `homematic.regadom`,
   `homematic.regadom.bak`, `measurement`, `userprofiles`, `etc/config/rega`, the NEO Server - and
   writes `<state>/ccu-leftovers-removed.json` and one journal line (`ccu leftovers removed …`, the
   paths and the bytes freed). An import that has still to run keeps them, with a warning, until a
   later start. A system with nothing left over records an empty run, so a CCU backup restored
   later is not swept. The Backup page's *Leftovers from OpenCCU* panel is gone.
9. **An addon's state outside its own directory** — homematic-manager's profile in
   `/usr/local/hmm`, root-owned from its OpenCCU days — is taken over when the addon is confined: chowned to the addon's user and made writable in its unit, at the confinement and again
   at every start, so an addon that was confined and then could not write its own state
   is repaired by the next update.

### Acceptance test on a VM (first run 2026-09-06)

What "everything keeps working" means, as a checklist. Run it on a Proxmox snapshot of the
OpenCCU VM so the way back is one click even if the software way back fails.

1. Before: note on the OpenCCU WebUI the device count, one device name, one room, the security
   key state (Settings → Control panel → Security), the LAN gateways, the addons, the IP/hostname.
   Take a `.sbk` backup and the Proxmox snapshot.
2. Upload `openccu-lite-x86_64-ova-<version>.zip` in Settings → Control panel → CCU maintenance → Perform software update, confirm,
   let it reboot. The recovery shows its progress on the console; the whole thing is ~3 minutes.
3. First visit of `http://<system>/`: the welcome page asks for an administrator password and shows
   the regadom import result — devices, channels, rooms and functions counted. `curl
   http://<system>/api/system/v1/status` → `first_boot_import` has the same numbers.
4. Check, in this order: **Radio** (module detected, `hm_mode` as before, security key "set" if it
   was, LAN gateways listed), **Names** (the device you noted has its name, the room exists with
   its channels), **Addons** (the same list, running), **Network** (address and hostname unchanged),
   **Log** (rfd/hmipserver lines, no error loop), **Services** (rfd, hmipserver up). The files you
   know from OpenCCU (`/var/log/messages`, `hmserver.log`, `lighttpd-*.log`) are the journal here:
   the Log page, its download, or `journalctl` (`-t hmipserver`, `-t lighttpd`).
5. A device round trip: press a paired device, watch its channel event in the Names page or via
   `/api/system/v1/radio/health` (the duty cycle updates) — the pairing survived if it does.
6. The way back: on the Status page upload `OpenCCU-<version>-ova.zip` (upstream's), *Reboot and
   install*. OpenCCU comes back **without** its ReGa database (openccu-lite removed `homematic.regadom`
   after its first start): restore the backup taken before the switch. A `meta.json` under
   `/usr/local/etc/occulite/` stays for the next switch.
   That is the second half of the acceptance test: **both directions, no reflash**.

Anything on this list that fails is a bug, not a documentation gap.

### What the run of 2026-09-07 found

The forward half was run on a test VM in the night of 2026-09-06/07, on an `ova-lite-systemd`
image built that night. It found twenty-seven bugs, three of which the
checklist above cannot phrase because nobody had got that far before:

- the system booted with **no firewall at all** — nothing written in Tcl ran;
- **the update could be installed once and never again**: the recovery system's own `/VERSION`
  kept the lite product name while the image's is rewritten to upstream's, so the recovery
  a lite image installs refuses every lite image — and refuses upstream's `ova.zip`, i.e. step 6
  of this list, the way back;
- the Network page and the LAN gateway list were empty on a system that had both, and a save would
  have written that emptiness back.

With those fixed, the list passes: the system installs a release zip from its own Status page and is
back in two and a half minutes with its addons, its metadata store and its configuration intact;
*Names → Import names from a ReGa database* reads the system's own ReGa database and reports what it found; the Radio,
Names, Addons, Network, Log and Services pages all answer with the system's real state; and the five
verified catalogue addons install, start in their own units and survive the firmware update.

### Step 6, the round trip, run on 2026-09-07 06:26–06:46

Both directions, on the same test VM, with upstream's own
`OpenCCU-3.89.8.20260719-ova.zip` (403 218 494 B, checksum verified against the release's
`.sha256`) and the night's `…-lite.0-beta.1-ova-lite-systemd.zip`:

| | how | took |
| --- | --- | --- |
| lite → OpenCCU | the lite Status page: `POST /system-update/upload` (accepted, `board: ova` against the running `platform: ova`), then *Reboot and install* | 3 min |
| OpenCCU → lite | OpenCCU's **own** WebUI path: its `cp_maintenance.cgi` validated the zip (it looks for `EULA.de`/`EULA.en` inside — the lite zip carries both), staged it and rebooted | 2.5 min |

What came back on the OpenCCU side: `ReGaHss` running and answering `rega_script`
(`dom.GetObject(1555).Name()` → `HM-CC-TC JEQ0230153`, thirteen room objects), `rfd`, lighttpd,
`sshd`, mosquitto and RedMatic's Node-RED, the four addons still in `/usr/local/addons` and their
`rc.d` links, `homematic.regadom` untouched at its pre-switch timestamp, and `meta.json` waiting
under `/usr/local/etc/occulite/` for the next switch. The recovery's own log for the way in is
worth reading once: *"[2/5] Checking update_script… no 'update_script', OK … flashing bootfs…OK,
updating bootloader (GRUB)… OK, flashing rootfs……OK, DONE"* — upstream's recovery flashing an
openccu-lite image without a word about the platform, which is what the lite image's `/VERSION`
keeping upstream's `PRODUCT` is for.

And back on the lite side afterwards: no failed units, the four `addon-*.service` units active,
55 firewall rules, no unclean-shutdown marker, the administrator login working and the metadata
store still at revision 1 with the channel renamed on the lite side and its room enum
(`BidCos-RF.JEQ0230153:1` → *Wohnzimmer Thermostat*, `room/wohnzimmer`). **Nothing had to be
reflashed, and nothing was restored from a backup.**

The round trip found one bug: the `occulite` user's id was auto-allocated out of buildroot's
system pool (100…999), which is the pool upstream fills with *its* system users, so on the OpenCCU
side the metadata store — `users.json`, `local-token` — belonged to upstream's `sshd`
privilege-separation user. The id is pinned to 8100 now; both init paths already repair the
store's ownership at boot, so an older system updates into the change without noticing it.

## openccu-lite → OpenCCU / CCU3

**The one that matters: restore the backup you took before you migrated.** Everything below
assumes you have it. If you do not, you can still get back to a running OpenCCU — you will not get
back to *your* OpenCCU.

0. **What openccu-lite removed**: `homematic.regadom` and the WebUI's data are gone after its first
   start. Names, rooms and functions changed on the lite side live in the metadata store
   and nowhere else. Programs and system variables were never on the lite
   side at all. So OpenCCU wakes up as it was when you left it — which is exactly why the
   pre-migration backup is the answer and not an afterthought.
1. **Flash / update** to OpenCCU: lite Status page → *System update* → upstream's
   `OpenCCU-<version>-<PRODUCT>.zip` → *Reboot and install*. `/usr/local` survives, so pairings,
   radio keys and addons are already there.
2. **Restore the pre-migration `.sbk`** through OpenCCU's own WebUI. This is the step that makes
   it your system again.
3. The metadata store's `meta.json` stays in `/usr/local/etc/occulite/` and is untouched by any of
   this, so switching to lite again later finds its names where it left them.

**With HSTS on** (System → Certificate): switch HSTS off, then **open the system once by its
name in every browser you use** before you install OpenCCU's zip — or open the system by its IP address
after the switch. Uploading a file that is not an openccu-lite release switches HSTS off by itself,
and the Status page then names the names to open. While HSTS is off, the system sends
`Strict-Transport-Security: max-age=0` for as long as the period was, at most 30 days, and a browser
that sees it forgets HSTS for that name. A browser that did not visit in that time still
remembers it: the recovery system that installs OpenCCU serves plain HTTP only, and OpenCCU serves a
self-signed certificate as soon as the one lite installed is within a day of expiring (upstream
renews nothing and replaces it). Such a browser refuses both under that name — the recovery page as
*connection refused*, OpenCCU's certificate with no way past — until the max-age has run out after
its last HTTPS visit (seven days by default). `max-age=0` has to reach the browser
before the switch: neither the recovery system nor OpenCCU can send it. `http://<IP address>/`
always works, since HSTS never applies to an address; the lite Status page's install notice links to
the recovery that way.

**There is no export to carry names back with.** There used to be an HM-Script export for exactly
that, and it was removed on 2026-09-08: it encouraged treating a half-migration as reversible when
the honest answer is a backup. Programs, system variables, and anything else that only ReGa
understands were never expressible that way either.

**Encrypted backups:** a `.sbk.age` from the lite Backup page is no `.sbk` for OpenCCU or a
CCU3. For the way back either use *Download unencrypted (for OpenCCU or a CCU3)* on the running lite
system — it asks for the password and is journaled — or decrypt the `.sbk.age` on a PC with
`age -d -i key.txt -o backup.sbk backup.sbk.age`, where `key.txt` holds the `AGE-SECRET-KEY-1…` line
from the emergency kit. The pre-migration `.sbk` of the way back was never encrypted.

## The reflash fallback

If one updater refuses the other's package (a version check, a changed partition table), flash
the image from scratch and restore the `.sbk`. Everything above still applies; only the flashing
step changes — and the backup is doing the same work either way.

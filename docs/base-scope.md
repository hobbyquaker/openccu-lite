# What "lite" is, in numbers

The eQ-3 CCU3 firmware is the reference for what belongs in the base system, and
*"lite" should be a number, not an adjective*. This file is that number, plus the written reason for
everything that was kept against the principle.

Everything here is measured, not estimated. The measurements are re-taken on every product added and
on every upstream rebase that moves them.

## The measurement

Both products built on the same host on the same day from the same upstream snapshot
(OpenCCU `3.89.8.20260906`, buildroot 2026.05.2), same architecture, same toolchain.
`oci_amd64` is upstream's OCI product unchanged; `oci-lite_amd64` is ours.
Neither product is in this repository any more (the lite one went on 2026-09-16, upstream's on
2026-09-26); the numbers stand as measured.

| | `oci_amd64` (upstream) | `oci-lite_amd64` | Δ |
| --- | ---: | ---: | ---: |
| rootfs tar | 817,326,080 B (779.5 MiB) | 414,535,680 B (395.3 MiB) | **−49.3 %** |
| Docker image tar | 282,525,696 B (269.4 MiB) | 178,910,720 B (170.6 MiB) | **−36.7 %** |
| release `.tgz` | 280,392,111 B (267.4 MiB) | 177,174,256 B (169.0 MiB) | **−36.8 %** |
| files in the rootfs | 21,943 | 4,305 | **−80.4 %** |
| `BR2_PACKAGE_*=y` | 323 | 278 | −45 |
| `/www` on the running system | tens of MB of WebUI | **5.5 KiB** | |

The file count is the number worth looking at twice: four fifths of the files in a CCU image are the
WebUI. The byte figures are dominated by things the WebUI does not account for — the JVM under
`/opt` is 136.8 MiB in both.

Build wall time is **not** a fair comparison and is recorded only for planning: upstream took
**225 min 42 s** on a cold ccache (of which Node.js alone was well over an hour), openccu-lite
**47 min 28 s** with that ccache warm and shared. Both on 8 cores, `nice -n 19`, `BR2_JLEVEL=8`.

## The running system

From `scripts/lite-boot-test.sh` against the image above, `docker run --privileged --read-only`
with `/usr/local` as a volume:

- **Boot to `startupFinished`: 10–28 s** (the spread is the SSL certificate generation on first
  boot). No init script hangs, none fails.
- **Processes**: `occulited`, `lighttpd` (+angel), `java` (hmipserver), `eq3configd`, `ssdpd`,
  `hss_led`, `udevd`, `crond`. **No `ReGaHss`, no `monit`, no `node`.** `rfd`, `multimacd` and
  `hs485d` report "no hardware found" / "disabled" and exit cleanly, which is correct without radio
  hardware.
- **RSS at idle**: `occulited` 6.5 MB, `lighttpd` 6.7 MB. (`ReGaHss` on a comparable OpenCCU holds
  the whole DOM; a CCU3 measurement is still to be taken.)
- **Listening sockets**: `lighttpd` on 80 and 443, `occulited` on `127.0.0.1:2121`, hmipserver on
  `:::39292`. Nothing on 8181, 1999, 2000, 2001, 2010 or any of their TLS twins — the XML-RPC
  proxies are gone.
- `/VERSION` carries upstream's `PRODUCT` and `PLATFORM` names (`oci_amd64`, `oci`) plus
  `VARIANT=lite`: update packages stay interchangeable in both directions.
- The addon ABI is intact: `/www/addons -> /etc/config/addons/www`, `package require HomeMatic`
  resolves, `/lib/tclrega.so` and `/lib/tclrpc.so` load, `.cgi` is bound to `/bin/tclsh`.

## What was removed, and why it was safe

All of it is `# … is not set` in `buildroot-external/configs/oci-lite_amd64.config`. No upstream
file is touched by any of it, which is what makes each line individually reversible.

**Removed without argument** — no stock CCU3 has any of it and nothing in the Homematic stack needs
it: `AVAHI`, `CIFS_UTILS`, `CLOUDMATIC`, `LOGROTATE`, `MONIT`, `MSMTP`, `NEOSERVER`, `NETSNMP`,
`NMAP`, `NODEJS`/`NODEJS_NPM`, `NUT`, `OPENVPN`, `RSYNC`, `SER2NET`, `SOCAT`, `STRACE`,
`TAILSCALE_BIN`, `TCPDUMP`, `WIREGUARD_TOOLS`, `XINETD`. Remote access to this system is SSH and the
LAN; a VPN or a mesh belongs on the router.

The init scripts of the removed daemons stay in the image and cost nothing: every one of them
begins with `test -x <daemon> || exit 0` (or the equivalent), so `S49xinetd`, `S50ser2net`,
`S59snmpd`, `S60openvpn` and `S51nut` print "disabled" and exit 0. The two places that did **not**
degrade quietly were found and fixed in `overlay/lite_oci`:

- `/etc/inittab` respawned `/usr/bin/monit` forever;
- `/etc/crontab.root` ran `updateDCVars.tcl`, `checkHmIPconsistency.tcl`, `checkPortForwarding.sh`,
  `checkAddonUpdates.sh`, `logrotate` and an `rsync`, none of which exist here.

**Removed and replaced by something we own**: `MONIT` (supervision moves into `occulited`),
`checkAddonUpdates.sh` (the Addons page checks on demand), `AVAHI` and `LOGROTATE` (busybox `syslogd`
already rotates `/var/log/messages`).

**Removed with the WebUI**: `ReGaHss`, `/www/webui`, `/www/config`, `/www/rega`, `/www/api`,
`/www/pda`, `/www/tools`, `/www/ise`, and the three ReGa clients the WebUI package installs into
`/bin` (`hm_autoconf`, `hm_startup`, `hm_deldev`). The firmware's own ReGa consumers —
`updateDCVars.tcl`, `triggerAlarm.tcl`, `checkHmIPconsistency.tcl`, `checkHmIPdevices.sh`,
`checkPortForwarding.sh` — are deleted by `board/oci-lite/post-build.sh` rather than stubbed: a
script that silently does nothing costs the next person an afternoon.

## What was kept, each for a reason

- **Everything radio, unconditionally**: `generic_raw_uart`, `bcm2835_raw_uart`,
  `eq3_char_loop`, `detect_radio_module`, `rpi-rf-mod`, `hmlangw`, `libLanDeviceUtils`,
  `libUnifiedLanComm`, and the `S47`/`S48`/`S58`/`S59` init scripts. Radio hardware support is not
  scope creep; it is the product.
- **`MULTILIB32`** — kept against the principle, deliberately. Real addons ship i386 and armv7
  helper binaries (RedMatic's `update_addon` helpers are the documented case) and dropping the
  32-bit loaders breaks them on exactly the architectures openccu-lite targets. Revisit when nothing
  in the first-class addon set needs it.
- **`TCL` / `TCLLIB` / `tcl_homematic` / `tclrpc`** — the addon ABI. `package require
  HomeMatic` and `.cgi` executed by `/bin/tclsh` are not negotiable.
- **`JAVA_AZUL`** — hmipserver. 136.8 MiB of the image, and the single largest thing left in it.
- **`IPTABLES`** and `libfirewall.tcl`, **`OPENSSH`**, **`LIBCURL`**, `E2FSPROGS`, `PARTED`,
  `USBMOUNT`, the filesystem tools, `RECOVERY_SYSTEM` and `S00watchdog` where the product has them.
- **`createBackup.sh` / `restoreBackup.sh` / `cronBackup.sh`** — small, `.nobackup`-aware,
  Apache-2.0, and the CCU3 has backup too, just implemented inside the WebUI we deleted.
- **`CHRONY`** over the CCU3's `ntpclient` on the products that build one; "not on the CCU3" is not
  an argument for shipping something worse. (The OCI product runs no time daemon at all — the
  container takes the host's clock.)

## The leftovers, measured (2026-09-06)

`ICU`, `FONTCONFIG`, `DEJAVU`, `LIBERATION` and `DAEMONIZE` come from upstream's shared
`Buildroot.config`. Measured on the booted lite image by reading the `NEEDED` strings of every
executable and library under `/bin`, `/sbin`, `/usr`, `/opt` and `/lib`:

| package | on disk | referenced by |
| --- | ---: | --- |
| `ICU` (`libicudata` 18.5 MiB, `libicuuc`, `libicui18n`, …) | ~22 MiB | only ICU's own tools (`icuexportdata`, `pkgdata`) and its own libraries — **nothing in the Homematic stack** |
| `FONTCONFIG` + `FREETYPE` | ~1.5 MiB | the `fc-*` tools and Java's `libawt_headless`/`libawt_xawt`/`libfontmanager` — the JVM's font stack, used by AWT only |
| `DEJAVU`, `LIBERATION` (`/usr/share/fonts`) | 9.8 MiB | fontconfig |
| `DAEMONIZE` | small | no init script, no `/bin/*.sh` |

AWT is what rendered the WebUI's diagrams (the "measurement" feature of HMServer); without the
WebUI nothing asks the JVM for a font, and a headless JVM starts without fontconfig. `DAEMONIZE`
is off in the lite products. The other four are **still in** (2026-09-06 13:00): the "is not set"
lines never reached a build, because `build-<product>/.config` is merged only when it is missing,
and once regenerated kconfig stops with "dejavu is in the dependency chain of java-azul" —
`package/java-azul/java-azul.mk` lists `fontconfig dejavu liberation` unconditionally in
`_DEPENDENCIES`. Removing them needs (1) an upstreamable change making those dependencies
conditional on their `BR2_PACKAGE_*` symbols, (2) a boot of hmipserver on a real HmIP system
(`rpi4-lite`) without them, since the HmIP branch of the JVM is the one place a font lookup could
still hide. Until both are done the lite images are ~33 MiB larger than they need to be.
`HMLANGW` is no longer in question: it stays.

## What the system writes, and how often (2026-09-07)

The SD card is what dies first on a CCU3, so the first step is an inventory: every
writer, with its rate, measured rather than argued about. This is that inventory. It was taken on
a test VM — `x86_64-ova`, four addons installed (mosquitto, hm2mqtt, RedMatic, jp-hb-devices),
seven paired devices — so the **layout** is exactly what an SD-card product has, and the **rates**
are what that system's software produces; a CCU3's radio traffic will add to them.

### Where writes can land at all

    /                ext4  ro,noatime,nodiratime          ← read-only, never written
    /boot            vfat  ro,relatime                    ← read-only
    /usr/local       ext4  rw,noatime,nodiratime,commit=30
    /var/log/journal ext4  the same partition, bind-mounted — on ova, or with PERSIST=1 in
                           /etc/config/journal; the card products keep the journal in RAM
    /var  /tmp  /run  /media  /dev/shm   tmpfs            ← RAM, never reaches the card
    swap             zram1, 2.0 GB compressed in RAM      ← no swap partition on the card

So **one** filesystem on the card is writable, and `noatime,nodiratime` is already set on it. `/var`
is a tmpfs, which is why an addon's log file costs nothing — unless the addon writes under
`/usr/local`. `commit=30` is upstream's; ext4's journal on that partition is 128 MB.

### The rate, measured at the block layer

`/sys/block/sda/stat` sampled every five minutes (`/usr/local/tmp/writewatch.sh` on the system writes
one CSV line per sample and is itself part of what is measured):

| window | sectors written | bytes/s | per day |
| --- | ---: | ---: | ---: |
| idle, nobody logged in, four addons installed but no bridge configured | 58 in 600 s | **~50** | **~4 MB** |
| idle, with hm2mqtt bridging 126 devices to the local Mosquitto | 167 in 900 s | **~95** | **~8 MB** |
| with an administrator on ssh and the web UI | 708 in 1800 s | ~200 | ~17 MB |
| a run of the acceptance checklist, a RedMatic restart | 1207 in 600 s | ~1000 | — |

The second row is the one to keep: **the bridge that makes the system useful doubles what it writes,
and it is still 8 MB a day.** The last row is what a *person* costs — a burst, not a rate.

At 4 MB a day an 8 GB card's rated endurance is not the thing that will fail. The number to keep
an eye on is the second one: logging in is what writes, because logging in is what journald
records.

### Who writes, attributed

`write_bytes` from `/proc/<pid>/io`, differenced over a 25-minute window (this counts what each
process handed to the storage layer, which the page cache and the 30-second commit then coalesce —
hence the larger figures than the block layer sees):

| process | bytes in 25 min | what it is |
| --- | ---: | --- |
| `systemd-journald` | 499,712 | the journal on the userfs. **The dominant writer, by an order of magnitude** |
| `jbd2/sda3-8` | 163,840 | ext4's own journal for those writes |
| `writewatch.sh` | 20,480 | the sampler itself, an artefact of this measurement |
| `sshd` | 8,192 | the sessions taking the measurement |
| `HMIPServer` (java) | 4,096 | one page in 25 min |
| `mosquitto` | 4,096 | one page in 25 min |

`occulited` does not appear at all: the metadata store is written copy-validate-swap **on change**,
and nothing changed in the window. `rfd`, `multimacd`, `eq3configd`, RedMatic's node-red and
hm2mqtt wrote nothing measurable either — their logs go to journald, which is the entry above.

### The journal, which is the whole answer

    Storage=auto  SystemMaxUse=32M  RuntimeMaxUse=16M  Compress=yes
    ForwardToSyslog=no  ForwardToConsole=no

Journald starts in `/run` and is flushed to `/var/log/journal` by `occu-persist.service` once the
userfs is bind-mounted there. Files are 4 MiB each and rotate; 18.9 MB of the 32 MB cap were in use
after a day of heavy testing, holding ten boots. There is no `RateLimitIntervalSec`/`RateLimitBurst`
in the fragment, so systemd's defaults apply.

The trade the task names is journal-on-the-card versus journal-in-RAM-with-a-copy-at-shutdown. The
argument for what is there today is in the same measurement: **the system has no clean shutdown on
power loss**, which is exactly when the log is worth having, and 4 MB a day is not what kills a
card. The argument against is that journald is nonetheless *the* writer, so anything that reduces
it — a rate limit, `SystemMaxFileSize` smaller than 4 MiB so rotation touches less, or moving the
journal to a USB stick where one is present — reduces the system's card wear by most of it.

### Still open, and needing hardware

- **The numbers above are from a VM.** A CCU3's `mmcblk0` has its own write amplification and its
  own `/sys/block/mmcblk0/stat`; the same sampler on the CCU3-class image is what turns these into
  the numbers that matter. `dumpe2fs -h` also reports *Lifetime writes* per filesystem, which is
  the cheapest long-term counter there is.
- **USB storage** (the task's second half): the cron-backup path already accepts `/media/usb*` and
  `/media` is a tmpfs with the stick mounted under it. Mount-by-label and the journal's optional
  home on the stick are unbuilt.
- **zram** is 2.0 GB and had 126 MB in use on a system with 1 GB of RAM — it is doing work, and it
  costs no card writes at all.

## Reachability

In the image as built: the lighttpd XML-RPC proxies are gone, so nothing answers on
1999/2000/2001/2010/8181/9292 or their TLS twins. What is still open to the LAN is hmipserver's own
`:::39292`, and `rfd`'s `0.0.0.0:32001` on a system that has radio hardware.

Both are closed from the second image on: `overlay/lite/etc/config_templates/rfd.conf` carries
`Listen IP = 127.0.0.1` (verified on a running system), and `S62HMServer` sources
`/etc/hmipserver.default` (an upstreamable hook; the lite overlay ships the file with
`HMIP_BIND_ADDRESS=127.0.0.1`) and appends `Legacy.BindAddress` to the generated `crRFD.conf` —
verified on a running system's HmIP server. What remains open: the BidCos-only `HMServer.jar` branch
(no HmIP module, `hmServerPort=39292`) has no bind property and relies on the firewall, and
`hs485d` has no template in the image at all.

Numbers are re-taken on every product and every rebase.

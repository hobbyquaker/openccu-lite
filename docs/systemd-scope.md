# systemd in openccu-lite: what is in, what is out, what it costs

The measurements and the unit inventory behind decision D-30 of the project roadmap: openccu-lite
uses systemd as init, with journald for logs, trimmed to what the image actually uses. It began as
`ova-lite-systemd` (task 20), a sibling of the busybox `ova-lite` — same kernel, same packages,
same D-23 reductions, different init — so that nothing tested on busybox init changed while it was
being built. D-39 ended that split: systemd is the product, the busybox variant is not carried
forward, and the x86_64 image is simply `x86_64-ova`. The two aarch64 board images followed with
the same delta on the Pi boards — `aarch64-rpi3` (the CCU3 class, from `rpi3.config`) and
`aarch64-rpi4` (from `rpi4.config`), two boards and one architecture, D-43. The three are listed
under [The products](#the-products).

Everything here is lite-only (`docs/upstream-delta.md`, item 12). The one place D-4's delta
discipline cannot help is the unit set itself: every OpenCCU init script the lite image keeps has a
unit that names it, and the weekly rebase diff of `overlay/base/etc/init.d/`, `overlay/RFD/etc/init.d/`
and `package/*/S*` is a review item against the table below.

## What is built

`configs/x86_64-ova.config` is upstream's `ova.config` plus the lite delta and `BR2_INIT_SYSTEMD=y`,
the `lite` overlay, `kernel/6.18/lite-systemd.config`, and every `BR2_PACKAGE_SYSTEMD_*`
sub-option written out as `is not set`; `configs/aarch64-rpi3.config` and
`configs/aarch64-rpi4.config` carry the identical systemd block on top of `rpi3.config` and
`rpi4.config`. What that leaves from the suite:

> **The journal is RAM-only by default since 2026-09-07 (task 23), and `occu-syslog-forward.service`
> was added (B-46).** The SD card is the CCU3's failure point and journald is the dominant writer by
> an order of magnitude, so `/var/log/journal` is no longer bind-mounted from the userfs except on
> the VM product, whose disk is not an SD card. `Storage=auto` is what makes that a one-line
> decision: journald is persistent exactly when that directory exists, so
> `/usr/libexec/occu/lite-journal-persist` decides by creating it or not. **Timer stamps still
> always go to the userfs** — a timer that forgets when it last ran runs again at every boot, which
> is correctness rather than wear. `/etc/config/journal` overrides it per box (`PERSIST`,
> `SYSTEM_MAX_USE`, `SYSTEM_MAX_FILE`, `RATE_LIMIT_BURST`) and lives on the userfs, so it survives a
> firmware update.
> `occu-syslog-forward.service` restores the remote syslog host: OpenCCU's `S07logging.script` used
> `LOGHOST` from `/etc/config/syslog` and lite ran no syslogd at all, so central logging quietly
> stopped for everything except hmipserver (B-46). journald now forwards to `/dev/log` and busybox
> syslogd sends it on — remote only, no `-L`, because journald is the local log and a local file
> would write to the card on every message. The unit uses `ExecCondition`, so a box with no
> `LOGHOST` leaves it inactive rather than failed.

> **`occu-etc-writable.service` was added on 2026-09-07 (B-28).** `/etc/passwd` and `/etc/group` are
> on the read-only rootfs — `package/openccu-base` links only `/etc/shadow` onto the userfs — so a confined
> addon's user could never be created and `PUT /addons/<id>/policy {"mode":"confined"}` answered
> *422 addgroup: /etc/group: Read-only file system*. The unit copies both files into `/run` and
> bind-mounts them back over themselves, before `occu-addons.service` and `occulited.service`.
> `/run` is tmpfs, so the base is rebuilt from the **new** rootfs at every boot and a firmware
> update that adds a system account is picked up rather than frozen — which is why this is not the
> symlink-onto-the-userfs that B-28 rejected as option 2. `ConditionPathIsReadWrite=!/etc` makes it
> skip where `/etc` is already writable, so a container or a development root is left alone.

> **`occu-extension-dirs.service` was added on 2026-09-23 (task 97, D-66).** No addon unit that runs as
> root has `CAP_SYS_ADMIN` any more — occulited's policy drop-in for a root addon says
> `CapabilityBoundingSet=~CAP_SYS_ADMIN`, and a catalogue entry that truly needs mounting declares it
> back with `runtime.capabilities: ["CAP_SYS_ADMIN"]`. The remount of `/` a CCU-era addon script does
> around its writes therefore answers *permission denied* and the script goes on; what it writes into
> `/firmware/rftypes` — the device descriptions rfd needs for homebrew devices — lands in a writable
> layer the unit mounts before rfd and the addons: an overlay on the userfs where the kernel has
> overlayfs (`CONFIG_OVERLAY_FS=y` in `kernel/6.18/lite.config` from the next build on; the x86_64
> defconfig had none, the Pi defconfigs a module), else a copy of the image's files bound over the
> directory. Either way a firmware update's new descriptions arrive and the addons' links stay.

> **`overlay/lite_systemd` was folded into `overlay/lite` on 2026-09-07.** It existed to hold what
> only the systemd products needed, back when there was also a busybox-init variant; D-39 dropped
> that variant, so the split had nothing left to separate. The 63 files moved with `git mv` and the
> two overlays had no file in common, so the merged rootfs is unchanged - verified by running
> `board/lite/pre-build-systemd.sh`'s own logic over the old and new overlay lists and diffing:
> 233 entries and 212 file checksums, identical for both the x86 list (with `lite_ova`) and the ARM
> one (without). Anything that used to say `overlay/lite_systemd/...` now says `overlay/lite/...`.
> `pre-build-systemd.sh` and `post-build-systemd.sh` keep their names.

| Component | State | Why |
| --- | --- | --- |
| `systemd` (PID 1), `systemctl`, generators, `systemd-tmpfiles`, `systemd-sysctl`, `systemd-modules-load`, `systemd-fsck`, `systemd-remount-fs` | in | the core; not separable |
| `systemd-journald`, `journalctl` | in | D-30: the log viewer's backend; replaces busybox syslogd/klogd (`S07logging`) |
| `systemd-udevd`, `udevadm` | in | replaces eudev (`BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV` off); the OpenCCU rules in `/lib/udev/rules.d` run unchanged |
| `dbus` | in (selected by `BR2_PACKAGE_SYSTEMD`) | occulited's service module talks to PID 1 over D-Bus (D-30); `systemctl` itself does not need it |
| `logind`, `resolved`, `timesyncd`, `hostnamed`, `timedated`, `localed`, `machined`, `importd`, `homed`, `coredump`, `pstore`, `firstboot`, `polkit`, `hwdb`, `boot`, `networkd` | out | named by D-30. chrony keeps time (`S46chronyd`), ifupdown/`eQ3StartNetwork` bring the network up (`S40network`), the hostname comes from `/etc/config/netconfig` through that script |
| `backlight`, `binfmt`, `hibernate`, `nspawn`, `nsresourced`, `myhostname`, `oomd`, `portabled`, `quotacheck`, `randomseed`, `repart`, `rfkill`, `sysext`, `mountfsd`, `sysupdate`, `sysusers`, `userdb`, `utmp`, `vconsole`, `vmspawn`, `analyze`, `journal-remote`, `catalogdb`, `kernel-install`, `initrd`, `efi` | out | nothing in the image uses them. `randomseed`: `S05seedrng` keeps the seed in `/etc/config` as upstream does. `vconsole`: `S06InitSystem` loads the keymap. `utmp`: no logind, no `who`. `analyze`: boot time is read from PID 1's "Startup finished" journal line instead |

Turning one of these on later needs a line in this table saying why.

`kernel/6.18/lite-systemd.config` lists systemd's kernel requirements explicitly (buildroot enables
them itself, but `global.config` has `# CONFIG_AUTOFS_FS is not set`, and a fragment that turns one
off again should be caught here) and switches `CONFIG_RT_GROUP_SCHED` off: multimacd raises its
own real-time priority from inside a service cgroup, which with RT group scheduling needs a
per-cgroup runtime allocation nothing here does.

Merged `/usr` (`BR2_ROOTFS_MERGED_USR`, `BR2_ROOTFS_MERGED_BIN`) comes with `BR2_PACKAGE_SYSTEMD`:
`/bin`, `/sbin`, `/lib` are symlinks into `/usr`. Overlays and packages install through them
unchanged (buildroot's overlay rsync keeps directory links).

## The products

Every lite product with systemd shares the same overlay, the same units and the same kernel
fragments; what differs is the board underneath and how the product is named.

| Product | Derived from | `/VERSION` after `board/lite/post-build.sh` | Release files | Notes |
| --- | --- | --- | --- | --- |
| `x86_64-ova` | `ova.config` | `PRODUCT=ova`, `PLATFORM=ova` | `OpenCCU-<v>-x86_64-ova.{img,zip,ova}` | the first one (task 20, when it was `ova-lite-systemd`); the QEMU boot test runs on it. Adds `BR2_PACKAGE_HOST_QEMU` for `board/ova/post-image.sh`'s `qemu-img` and drops the Wi-Fi/Bluetooth stack (a VM has no radio) |
| `aarch64-rpi3` | `rpi3.config` | `PRODUCT=rpi3`, `PLATFORM=rpi3` | `OpenCCU-<v>-aarch64-rpi3.{img,zip}` + `OpenCCU-<v>-ccu3.tgz` | the CCU3 class — CCU3, CM3, Pi 3 (D-43). `board/aarch64-rpi3/post-release.sh` is a symlink to `board/rpi3`'s; everything else board-specific is read straight out of `board/rpi3`, the `.tgz` included |
| `aarch64-rpi4` | `rpi4.config` | `PRODUCT=rpi4`, `PLATFORM=rpi4` | `OpenCCU-<v>-aarch64-rpi4.{img,zip}` | the Pi 4 class. `board/aarch64-rpi4/post-release.sh` is a symlink to `board/rpi4`'s, which has no in-place update step |
| `aarch64-rpi5` | `rpi5.config` | `PRODUCT=rpi5`, `PLATFORM=rpi5` | `openccu-lite-aarch64-rpi5-<v>.{img,zip}` | the Pi 5 / CM5 class (task 32, 2026-09-09): bcm2712, 16K pages, u-boot 2026.04, no `rpi-firmware` (the Pi 5 boots from its EEPROM). `board/aarch64-rpi5/post-release.sh` is the D-44 copy of `board/rpi4`'s. **Never booted on hardware** |
| `lxc-lite_amd64`, `lxc-lite_arm64` | `lxc_amd64.config`, `lxc_arm64.config` | `PRODUCT=lxc_amd64` / `lxc_arm64`, `PLATFORM=lxc` | `openccu-lite-lxc-amd64-<v>.tar.xz`, `openccu-lite-lxc-arm64-<v>.tar.xz` | the Proxmox CT templates (task 34, 2026-09-09), for an **unprivileged** CT with `nesting=1`. No kernel, no bootloader, no recovery system: `rootfs.tar` is the template and `/usr/local` is a mount point that survives a template swap. `board/lxc-lite/post-build.sh` takes out the watchdog feeder, chrony (not built), the hardware clock and masks udev; the journal is persistent by default like the VM's. `board/lxc-lite/post-release.sh` writes the `.tar.xz`. Not yet built - the runner's disk |

The names come from D-39 and D-43: architecture and form, and the two aarch64 images are one board
class each — both are `BR2_aarch64=y`, exactly as upstream's `rpi3` and `rpi4` are, and what
separates them is device trees, rpi-firmware variant, u-boot, the recovery fragment and rpi-eeprom.
There is no 32-bit ARM product. The `/VERSION` mapping is the `case` in
`board/lite/post-build.sh`, because none of the three carries a `-lite` suffix to strip and the
recovery compares `PLATFORM` on an in-place update (D-31); the same `case` is repeated in
`package/recovery-system/external/board/post-build.sh`, which is the copy `fwinstall.sh` reads
(B-27), and the two must agree. `lite-version.mk` knows all three by name (`LITE_PRODUCTS`) so
their version is `<OpenCCU base>-lite.<release>` (D-37).

Two differences the aarch64 products make to the package set, both because of systemd and D-23:

- The per-board UPS, fan and display daemons that D-23 names — `susvd`, `piusvd`, `picod`,
  `strompi2d`, `pidesktopd`, `argononed`, `raspi-fanshim` and `wiringpi` with it — are `=n`.
  Each installs an `/etc/init.d/S51*` script and nothing else (`_INSTALL_INIT_SYSV` only), so
  under systemd they would be six daemons that never start. Anyone who wants one back needs a
  unit and a line in the table above.
- The Wi-Fi stack stays as upstream's Pi defconfigs have it. `x86_64-ova` drops it because a VM
  has no radio; these boards do, and D-23's exception list keeps `wpa_supplicant` (to be trimmed,
  not dropped). Its package's `wpa_supplicant.service` — the D-Bus supplicant, enabled by
  default because the package's preset disables only the template units — is disabled in
  `50-openccu-lite.preset` (B-99): it ran on every Pi without a Wi-Fi configuration.
  `eQ3StartNetwork` starts a supplicant for an interface that has `/etc/config/wpa_supplicant.conf` - not on openccu-lite
  since task 89: the lite `interfaces` names `eth0` only, and `occu-wifi` owns Wi-Fi.
  **The Bluetooth stack is gone** (D-54, 2026-09-12): `BR2_PACKAGE_BLUEZ5_UTILS` and
  `BR2_PACKAGE_BRCMFMAC_SDIO_FIRMWARE_RPI_BT` are off in the three `aarch64-rpi*` configs, so
  `bluetooth.service` and `bluetoothd` are not in the images. The radio module takes the UART
  Bluetooth would use, and nothing on the box speaks Bluetooth. Upstream's `config.txt` lines about
  the Bluetooth UART stay untouched.

`qemu-guest-agent.service` is in the shared overlay and therefore in the aarch64 images too, but
the package is not built for them and the unit's `ConditionPathExists=/dev/virtio-ports/…` never
holds on a Pi, so it stays inert. `openvmtools`, `xe-guest-utilities` and `acpid` bring their own
units and are not in the Pi configs at all.

## The unit set

All in `overlay/lite/usr/lib/systemd/system/`. Four shapes — the first three for the
setup scripts, the fourth for every daemon the box needs (B-3,
[Essential daemons](#essential-daemons-tracked-and-restarted)):

- **compat oneshot** — `Type=oneshot`, `RemainAfterExit=yes`,
  `ExecStart=/etc/init.d/SXX.script start`, `ExecStop=/etc/init.d/SXX.script stop`,
  `KillMode=control-group`, `UMask=0002` (rcS's umask). The script runs unchanged; whatever it
  backgrounds stays in the unit's cgroup, so stop and status are systemd's. Used for the setup
  scripts — the ones that do their work and exit. **Never for a daemon**: `RemainAfterExit=yes`
  keeps the unit *active (exited)* after everything in it has died, which is bug B-3.
- **forking** — the same `ExecStart`/`ExecStop`, but `Type=forking` so that the daemon the script
  backgrounds becomes the main process: the status line shows its PID and `Restart=` applies when
  it dies. A `PIDFile=` where the daemon always starts and really writes one; where the script may
  decide not to start anything (no hardware, disabled), systemd's single-process guess is used and
  the unit ends active and empty — a `PIDFile=` that never appears would fail the unit and then be
  retried for ever.
- **real unit** — for the daemons whose package installs only a busybox init script (so the script
  does not exist in this image) and whose start is a few lines: `Type=exec`, the script's
  `init()` as `ExecStartPre`, the daemon in the foreground as its user.
- **tracked daemon** — `Type=exec` with the daemon itself in the foreground and the script's
  preparation in front of it, where the init script's own launch can be reproduced without copying
  its logic (lighttpd, the watchdog feeder).

| Unit | Replaces | Shape | Notes |
| --- | --- | --- | --- |
| `occu-ldconfig.service` | `rcS` (`ldconfig -C /var/cache/ld.so.cache`) | oneshot, before `sysinit.target` | `/etc/ld.so.cache` is a symlink into the tmpfs `/var`; `/usr/local/lib` and lib32 are in `ld.so.conf` |
| `occu-watchdog-marker.service` | `S00watchdog` (marker half) | oneshot | `/usr/local/tmp/.watchdog` in, `/var/status/uncleanShutdown` out; runs on boxes without a watchdog device too. See [The unclean-shutdown marker](#the-unclean-shutdown-marker) |
| — | `S00watchdog` (daemon half) | dropped (D-41) | PID 1 feeds `/dev/watchdog` itself: `etc/systemd/system.conf.d/lite-watchdog.conf`, see [The hardware watchdog](#the-hardware-watchdog) |
| `occu-init-host.service` | `S01InitHost` | compat | `/var/hm_mode`, `sysctl -p` (`systemd-sysctl` does not read `/etc/sysctl.conf`), LED triggers |
| `occu-zram-swap.service` | `S01InitZRAMSwap` | compat | |
| `occu-usb-gadget.service` | `S01USBGadgetMode` | compat | ARM only and only with the flag file: `ConditionVirtualization=no`, `ConditionPathExists=/etc/config/usbGadgetModeEnabled` (D-41) |
| `occu-init-rtc.service` | `S02InitRTC` | compat | after `occu-init-host` only (task 135) |
| `occu-userfs-resize.service` | `S03CheckUserFSResize` | compat | unmounts and remounts `/usr/local`; every lite unit orders with `After=` only, never `Requires=`, so nothing is stopped by that |
| `occu-factory-reset.service` | `S04CheckFactoryReset` | compat | |
| `occu-backup-restore.service` | `S05CheckBackupRestore` | compat | |
| `occu-seedrng.service` | `S05seedrng` | compat | the stop action writes the seed back |
| `occu-machine-id.service` | — | oneshot, `Before=systemd-journald.service` | installs the stored ID before journald reads one, see [The machine ID](#the-machine-id) |
| `occu-machine-id-store.service` | — | oneshot, after `S47InitRFHardware` | derives the ID from `/var/board_serial` and stores it on the userfs (D-41) |
| `occu-persist.service` | — | oneshot | journal and timer stamps on the userfs, see below |
| `occu-extension-dirs.service` | — (new, task 97, D-66) | oneshot, `After=occu-init-system.service`, `RequiresMountsFor=/usr/local`, `Before=rfd.service occu-addons.service`, `ConditionPathExists=/firmware/rftypes` | `lite-extension-dirs start`: `/firmware/rftypes` writable before rfd reads it and the addons write to it — an overlay (lower the image's directory, upper and work `/usr/local/etc/config/extensions/rftypes/{upper,work}`; `CONFIG_OVERLAY_FS=y` in `kernel/6.18/lite.config` for every lite kernel) or, without overlayfs, a copy of the image's files on the userfs (`…/copy`, refreshed from the image at every boot) bound over the directory. The image's names go to `…/image-names` before the mount. At every boot a whiteout for an image name is removed (a copy's missing file copied again), so a stray `rm -f /firmware/rftypes/*` costs one boot; `lite-extension-dirs status\|reset /firmware/rftypes` are occulited's (`GET`/`POST /radio/device-descriptions`), the reset also removing an addon's replacements of image files, then rfd restarted. Root addon units run without `CAP_SYS_ADMIN` (occulited's policy drop-in, `CapabilityBoundingSet=~CAP_SYS_ADMIN`), so an addon script's `mount -o remount,rw /` answers *permission denied* and its writes land in the writable layer |
| `occu-init-system.service` | `S06InitSystem` | compat | `/var/*`, config templates, timezone, `rc.init`/`rc.postinit`; `hss_led` only where the binary is, which the lite images no longer ship (task 95, D-63) |
| — | `S07logging` | dropped | journald. `/var/log/messages` does not exist; `logger` and syslog(3) land in the journal. Remote syslog (`LOGHOST` in `/etc/config/syslog`) is not forwarded — a maintainer decision (journal-upload is a sub-option, off) |
| `ca-certificates.service` | `S07ca-certificates` (buildroot package + fork patch 0014, sysv only) | real | `/etc/ssl/certs` is a symlink into `/var`. `lite-ca-certificates` copies the bundle the image ships prebuilt (`board/lite/ca-prebuilt.sh`, `/usr/share/ca-certificates-prebuilt`) when the user has no certificates in `/usr/local/share/ca-certificates`; with some, a copy cached on the userfs (`/usr/local/etc/ca-certificates-cache`, `.nobackup`), rebuilt by `update-ca-certificates --default` only when those certificates or the image changed (task 135, D-89). The userfs file `/usr/local/etc/ca-certificates.conf` deselects image certificates with `!<name>` lines (occulited's Trust stores page writes it and runs the script through its helper after a change): the bundle is then built from a generated configuration instead of `--default`. Ordered before `network-online.target`, occulited, chrony, the syslog forwarder and `occu-addons`; the network does not wait for it |
| — | `S11InitLEDs` | dropped (D-41) | its three sysfs writes are `S02InitRTC`'s, one unit earlier, and once the box is up occulited's status LED controller owns the RPI-RF-MOD's LED (task 95) |
| `irqbalance.service` | `S13irqbalance` | buildroot's own unit | the script skipped single-core boxes; the daemon idles there |
| `occu-network.service` | `S40network` | compat, `After=occu-firewall.service occu-init-system.service` (task 157: the rules are loaded before an interface comes up; B-148: S06 creates `/var/etc`, where the DHCP hook's resolvconf writes `resolv.conf`), `Before=network.target network-online.target` | `ifup -a` with `eQ3StartNetwork` (the link polled every 0.2 s, task 116; no internet check, the image has no `checkInternet`, D-90); udhcpc stays in the cgroup; no networkd; not after the CA bundle |
| `occu-firewall.service` | — (new, task 157) | `DefaultDependencies=no`, `After=local-fs.target occu-backup-restore.service` (task 207, B-188: the final userfs - a restoring boot loads the restored rules), `RequiresMountsFor=/usr/local`, `Before=network-pre.target occu-network.service occulited.service` | `occulited firewall load`: `/etc/config/firewall-rules.json` (converted from `firewall.conf` once, or the defaults) into iptables and ip6tables before the network; replaces libfirewall (`setfirewall.tcl` from `eQ3StartNetwork`, only once `HM_MODE` was `NORMAL`). On a fresh userfs `/etc/config` is a dangling link until the init scripts make its target; occulited creates the directory through the link, and loads the rules even when the file cannot be written (B-188: the first boot's unit failed with exit 1 before any iptables call) |
| `occu-wifi.service` | — (new, task 89) | `After=occu-network.service occulited-helper.service`, `Before=network-online.target` | `occulited wifi up\|reload\|down`: the boot partition's setup file, then - switched on in `/etc/config/wifi` - the onboard driver, rfkill, power save off, `occu-wpa@<if>` and the addressing (`occu-wifi-dhcp@<if>` or static), the route metric by the preferred interface; switched off: rfkill block and the onboard driver unloaded. The lite `interfaces` names `eth0` only, so the hook never starts a supplicant |
| `occu-wpa@.service`, `occu-wifi-dhcp@.service` | — (new, task 89) | `BindsTo=` the interface's device; started and stopped by `occu-wifi` | wpa_supplicant with `/etc/config/wpa_supplicant.conf` (control socket in `/run/wpa_supplicant` for the group `occulite`); udhcpc with `lite-wifi-dhcp` (address, default route 5 or 600, resolvconf) |
| `chrony.service` | `S46chronyd`, buildroot's `chrony.service` | forking, `PIDFile=/run/chrony/chronyd.pid` | `/usr/libexec/occu/lite-chrony` (task 94, B-97): S46chronyd's server list (the user's and the DHCP servers preferred, the gateway when empty, the template's as fallback) into `/var/etc/chrony.conf`, chronyd started at once with `iburst`; no blocking `ntpdate` (10 s of every boot, and no chronyd at all when it failed). `makestep` steps the first offsets; `hasNTP` appears once synchronised |
| `occu-clock-valid.service` | — | oneshot, `ConditionVirtualization=!container` | done when the clock came from an RTC and is not older than the image, when chronyd is synchronised, or after 60 s with a warning; writes `/run/occulite/clock-state` (`rtc`/`ntp`/`timeout`). rfd, hmipserver, hs485d and crond order after it (task 94: they hand the time on to the module and to devices); multimacd does not (task 108: it reads no wall clock). Not after chrony (task 108): on a box with an RTC it passes before the network is up; without one it polls chronyd, and the 60 s count from chronyd's first answer (at most 90 s for that) |
| `occu-clock-save.service` | — | oneshot, `DefaultDependencies=no`, `ConditionVirtualization=!container` | B-192: `lite-clock-save restore` right after the userfs is mounted and the RTC init, before `occu-clock-valid`, chrony, lighttpd, the interface daemons and occulited — sets the clock forward to the time saved at the last shutdown (never back); `save` at the stop, before the userfs is unmounted, into `/usr/local/var/lib/lite-clock/saved`. On a board without an RTC NTP's step after a reboot then stays below lighttpd's `server.clock-jump-restart` (1800 s), so lighttpd keeps its early start without the graceful restart; after a power loss the jump is the downtime. The clock is not trusted for it: `occu-clock-valid` still waits for NTP |
| `occu-clock-save-hourly.timer` / `.service` | — | timer `OnBootSec=1h`, `OnUnitActiveSec=1h`; oneshot, `Requisite=`/`After=occu-clock-save.service`, `RequiresMountsFor=/usr/local`, `ConditionVirtualization=!container` | B-192 (the maintainer, 2026-09-24): `lite-clock-save save` once an hour, so after a power cut (no save at the stop) the restored time is at most an hour behind - fake-hwclock's hourly save. One tiny atomic write to the userfs an hour |
| `occu-init-rf-hardware.service` | `S47InitRFHardware`, `S48UpdateRFHardware`, and the configuration halves of `S49hs485d`, `S60multimacd`, `S61rfd`, `S62HMServer` | real (task 129, D-83): `ExecStart=/usr/bin/occulited radio run` | occulited's own detection (each probe under a limit, the GPIO header's node 6 s first, the second pass of task 138, the HB-RF-ETH connect with a bounded route wait), the plan (upstream's decisions under `auto` from `rfd.conf`, `hs485d.conf`, `hmip_user.conf` and the HMLGW marker) and the render written to the box: `/var/hm_mode` merged atomically with `HM_HOST`/`HM_MODE`/`HM_LED_*`/`HM_RTC` kept, the RF files, `/var/etc/{multimacd,rfd,crRFD,HMServer,hs485d}.conf`, `log4j2.xml`, `/etc/config/rfd.conf` and `InterfacesList.xml` (re-copied from the template, D-97), the environment files and the activation markers `/run/occulite/radio/<daemon>.enabled`. Not after the network (task 108). No firmware flash at boot (D-89): occulited's Interfaces page shows and flashes newer firmware. Refuses to run while an interface daemon holds the module. Stop is `occulited radio stop`: the bootloader handover only with a staged firmware update (D-41), `TimeoutStopSec=300` for that case; an HB-RF-ETH is disconnected either way. The scripts themselves are not in the image (`post-build-systemd.sh` removes them); they stay in the overlays as the oracle of `scripts/testcases/lite-radio-oracle-test.sh` |
| `occulited.service` | `S48occulited` | real, from `package/occulited` (the occulited repository's `deploy/systemd/`) | after the network, beside lighttpd (task 94); the drop-in that pinned it to S48's slot behind the radio hardware is gone. Since occulited `0a1d8c2` (task 208) the unit sandboxes the daemon itself - no capability, `@system-service` plus `syslog(2)`, native ABI, `AF_UNIX AF_INET AF_INET6 AF_NETLINK`, closed device policy, kernel tunables/modules/cgroups read-only, umask 0077 (`systemd-analyze security` 2.1) - and `occulited-helper.service`, root by design, drops what none of its operations needs (7.4). A `~@privileged` line would kill the setuid busybox's applets, `ProtectKernelLogs=` would kill dmesg: both left out with the reason in the unit |
| `occu-init-hs485d.service` | `S49hs485d`'s daemon half | real: `hs485dLoader -ds -dd /var/etc/hs485d.conf` (the loader's init pass, as root), `ConditionPathExists=/run/occulite/radio/hs485d.enabled` | only when the plan runs hs485d; the configuration it once rendered is `occu-init-rf-hardware`'s |
| `occu-radio-shadow-check.service` | — | oneshot, `ConditionPathExists=/usr/local/etc/occulite/radio-shadow` | `occulited radio check` after the interface daemons: the run step's render against the box (`/var/hm_mode`, the RF files, the daemons' files, `InterfacesList.xml`, the units and their command lines); every difference one journal line (`shadow: DIFFERENCE …`), the report `/run/occulite/radio/shadow.json`; the unit fails on a difference. The self-check of the marker boxes (in the shadow phase it compared the plan with upstream's chain; `occu-radio-shadow.service`, the second detection, went with the switch) |
| `lighttpd-prepare.service` | the preparation half of `S50lighttpd` (its `reload` action) | oneshot, root, pulled in by `lighttpd.service` (`Wants=`, `After=`) and started again by its `ExecReload` | `S50lighttpd.script reload` (the certificate check, the `/var/etc/lighttpd_*.conf` includes: HTTPS redirect, HSTS, the host-name redirect, the classic RPC sockets through `lite-classic-rpc-conf`), `lite-starting-page`, `lite-cert-perms`, `occulited -lighttpd-dropins` - every step best effort (`-`), as they were as `+-` lines in `lighttpd.service`. Its own unit because a `+` line runs as root *inside* the daemon's mount namespace, where `/etc/config` and `/var/etc` are read-only for it too (the same finding as rfd's `/var/etc` line, taken the other way: the preparation leaves the sandbox instead of the sandbox opening for it). Carries the sandbox lines that cost root nothing (kernel tunables/modules/logs/cgroups/clock, namespaces, realtime, personality, W+X, native ABI, `AF_UNIX AF_INET AF_INET6 AF_NETLINK`, `@system-service`); `systemd-analyze security` 9.4 → 4.7 |
| `lighttpd.service` | `S50lighttpd`, buildroot's `lighttpd.service` | tracked daemon, **sandboxed** | `ExecStart=/usr/sbin/lighttpd-angel -f /etc/lighttpd/lighttpd.conf -D` — the angel supervises lighttpd and is systemd's main process; `ExecReload` starts `lighttpd-prepare.service` and then `kill -USR1 $MAINPID` (S99SetupLEDs reloads to open the RemoteAPI ports). Skipped in LAN-gateway mode by `ConditionPathExists=!/usr/local/HMLGW`, the script's `HM_MODE` check. The sandbox: `www-data` with `CAP_NET_BIND_SERVICE` alone (ambient, for the angel's re-exec), `ProtectSystem=strict`, `TemporaryFileSystem=/usr/local:ro` with `/usr/local/etc/config` and `/usr/local/addons` bound read-only (the drop-ins, the certificate, the classic RPC pair; the addons' error pages) and `/usr/local/tmp` writable (`server.upload-dirs`), the daemons' and the addons' configuration directories inaccessible, `RuntimeDirectory=lighttpd` for the pid file (`server.pid-file` set by the lite post-build), `NoExecPaths=/` with `ExecPaths=/usr/bin /usr/sbin /usr/lib /usr/libexec`, private `/tmp` and `/dev` (`/dev/shm` stays), `ProtectProc=invisible`/`ProcSubset=pid`, the kernel lines, `AF_UNIX AF_INET AF_INET6`, `SystemCallFilter=@system-service` on the native ABI (no `~@privileged`: the setuid busybox calls `setuid` at every applet's start, and the access log's pipe is `/bin/sh -c systemd-cat`), `MemoryDenyWriteExecute=` (the Lua interpreter, PCRE2 without JIT), `UMask=0077`. `systemd-analyze security` 6.4 → 1.7; no `mod_cgi` (the CGIs run through occulited) |
| `sshd.service` | `S50sshd`, buildroot's `sshd.service` | `Type=exec`, `ExecCondition=/etc/init.d/S50sshd.script init`, `ExecStart=/usr/sbin/sshd -D`, `ConditionPathExists=/etc/config/sshEnabled` | the script's `init` action (task 115, D-80) does the host keys in `/usr/local/etc`, the userdir, the permissions and the compromised-password wipe, and exits 1 when sshd must not start (SSH off, or the wipe just ran): a skip, not a failure. sshd is the main process; `ExecReload` is `HUP $MAINPID`; sshd still writes `/run/sshd.pid` on its own |
| `occu-init-addons.service` | `S55InitAddons` | compat | `lite-init-addons`: `rc.prelocal`, then `init` on the rc.d entries as run-parts did, but never on a `<name>.script` (B-119: busybox run-parts took the dot and ran the addons' own scripts as root); a confined addon's wrapper answers `init` with nothing and its unit runs it as the addon's user; the start/stop half is `addons.target` |
| `occu-lgw-firmware-update.service` | `S58LGWFirmwareUpdate` | real (task 129 phase 4, D-99): `ExecStart=/usr/bin/occulited radio lgw-firmware`, `ExecCondition=` a LAN gateway in `rfd.conf`/`hs485d.conf` | the RF gateways' coprocessor and firmware and the wired gateways' firmware through `eq3configcmd`, once the default gateway answers; a configured gateway whose address answers no ping is skipped with a journal line (the unit a success, the check at the next start again - B-229: an unplugged gateway held the boot in eq3configcmd's timeouts); a failed update fails the unit (the script exited 0). The script is not in the image. UNVERIFIED without a LAN gateway |
| `occu-set-lgw-key.service` | `S59SetLGWKey` with `setlgwkey.sh` | real (D-99): `ExecStart=/usr/bin/occulited radio lgw-keys`, the same condition | each `/etc/config/<serial>.keychange` read by its keys (the script's `grep KEY` also took `CURKEY=`), sent with `eq3configcmd setlgwkey`, removed when that worked; a file of an unknown class is left alone and the others still applied. UNVERIFIED without a LAN gateway |
| `occu-radio-hotplug.service` | — | oneshot, started by `61-openccu-lite-radio-hotplug.rules` (a raw UART node, or the HM-CFG-USB-2, added or removed), `After=occu-init-rf-hardware.service` | `occulited radio hotplug` (task 129 phase 4, D-83): the nodes listed again, only new ones probed, the plan made, and only the interface daemons whose plan changed stopped and started; stands aside while occulited flashes a coprocessor or changes the connections |
| `hs485d.service` | `S60hs485d` | forking, `PIDFile=/run/hs485d/run/hs485dLoader.pid`, **confined** (task 67, D-55, D-93): `User=hs485d`, no capabilities, `ProtectSystem=strict`, a private `/var` (`TemporaryFileSystem=`) with `/var/etc`, `/var/hm_mode` and `/var/status` bound in and `/var/run`, `/var/log` from `RuntimeDirectory=hs485d` | `ConditionPathExists=/run/occulite/radio/hs485d.enabled` is the plan's decision (no wired interface in `hs485d.conf`: unit skipped), `ExecStartPre=+occulited radio prep hs485d` the ownership repair; the daemon's four files directly under `/var` (the loader's pid file, the daemon's pid file, its unix socket, its log) land in the private `/var`. UNVERIFIED without wired hardware |
| `multimacd.service` | `S60multimacd` | `Type=exec`, **confined**: `User=multimacd`, `SupplementaryGroups=raw-uart eq3loop status`, `LimitRTPRIO=99` and `Nice=-15` for its SCHED_RR threads (no `CAP_SYS_NICE`), `PrivateNetwork=yes`, `DevicePolicy=closed` in `multimacd.service.d/20-devices.conf` | `ConditionPathExists=/run/occulite/radio/multimacd.enabled` is the plan's "not required" decision (skip, not failure); `ExecStartPre=+occulited radio prep multimacd` checks the loop device and the module's node and sets the node groups; `ready` waits for the status file and the two `/dev/mmd_*` endpoints and gives them their groups; the loop module stays loaded (modules-load.d) |
| `hmlangw.service` | `S61hmlangw` (`package/hmlangw`, sysv only) | real (`Type=exec`), `ConditionPathExists=/usr/local/HMLGW`, `ConditionVirtualization=no` (ARM only, D-41), **confined**: `User=hmlangw`, `SupplementaryGroups=mmd-bidcos status`, the LAN over IPv4/IPv6 | `EnvironmentFile=/var/hm_mode`; `ConditionPathExists=/run/occulite/radio/hmlangw.enabled` (the plan's LAN-gateway mode), `ExecStartPre=+occulited radio prep hmlangw` gives `/dev/mmd_bidcos` its group; output to the journal instead of `/var/log/hmlangw.log`, and the only daemon unit **not** on the console (it is chatty). UNVERIFIED in LAN-gateway mode |
| `rfd.service` | `S61rfd` | `Type=exec`, **confined**: `User=rfd`, `SupplementaryGroups=mmd-bidcos status`, `ReadWritePaths=` its device files, `/etc/config/keys`, `/var/RFD.handlers`, `/var/status`; `char-eq3loop` and `char-usb_device` (HM-CFG-USB-2) in the device drop-in | `ConditionPathExists=/run/occulite/radio/rfd.enabled` is the plan's "no BidCos-RF hardware found" as a skip; the loopback line and `rfd.conf`'s edits are the render's; `ExecStartPre=+occulited radio prep rfd`: `rfd.conf` root:rfd 0640, the key file pre-created rfd:rfd 0600, the endpoint's group; `ready` waits for `rfd.status` = the main pid |
| `hmipserver.service` | `S62HMServer` | `Type=exec`, `TimeoutStartSec=420`, **confined**: `User=hmipserver`, `SupplementaryGroups=mmd-hmip raw-uart status lock`, `PrivateTmp=yes`, no `MemoryDenyWriteExecute` (JIT), IPv4/IPv6 unfiltered (HAP routing, key server) | `ConditionPathExists=/run/occulite/radio/hmipserver.enabled` (the plan: always in normal mode, the HmIP half with a module, the VirtualDevices half alone without); `crRFD.conf`, `HMServer.conf` (the diagram database in `/var/hmipserver/measurement`, D-93), `log4j2.xml` and the JVM's options in `/run/occulite/radio/hmipserver.env` are the render's; `ExecStartPre=+occulited radio prep hmipserver`: the adapter node, crRFD and eshlight owned, the lock directory; `ready` waits up to 300 s for `HMServerStarted`; `stopped` copies the diagram data back to the stick |
| `crond.service` | `S98crond` | `Type=exec`, `ExecStartPre=/etc/init.d/S98crond.script init`, `ExecStart=/usr/sbin/crond -f -l 9` | the script's `init` action (task 115, D-80) merges `/usr/local/crontabs/root` (addons extend it) with `/etc/crontab.root` (empty in this overlay) into the spool; crond is the main process. The system lines are timers |
| `occu-addons.service` | `S98StartAddons` (the run-parts half) | oneshot | `systemctl daemon-reload` once the userfs is final, then starts `addons.target`; see the generator |
| `addons.target` | `S98StartAddons` | target | the generated `addon-<name>.service` units are `WantedBy=`/`PartOf=` it |
| `occu-rc-local.service` | `S98StartAddons` (the `rc.local` call) | oneshot, `After=addons.target` | same profile.d environment, 120 s timeout, OOM score 100 |
| `occu-board-leds.service` | `S99SetupLEDs` (its LED lines, task 158) | oneshot, `After=occu-init-rf-hardware.service` | `lite-board-leds start`: the board LEDs' `HM_LED_*_MODE2` triggers (or `none` with `disableOnboardLED`) and the HM-LGW blue as soon as the radio is known, not after the addons; stop puts MODE1 back |
| `occu-leds.service` | `S99SetupLEDs` | compat | the boot-finished gate: `rc.postlocal`, `startupFinished`, lighttpd reload (through the wrapper, so it becomes `systemctl reload-or-restart lighttpd.service`); stop runs `rc.shutdown` first at shutdown. It still runs the whole script, whose LED lines write the triggers `occu-board-leds` set once more |
| `occu-boot-message.service` | `rcS`'s closing lines | oneshot, last in the chain | the end-of-boot hint on the splash, the console and `/etc/issue`; quits psplash (B-5, B-4) |
| `qemu-guest-agent.service` | `S11qemu-guest-agent` (`package/qemu-guest-agent`, sysv only) | real, condition on the virtio port | |
| `xe-daemon.service`, `vmtoolsd.service`, `hv_*_daemon.service`, `acpid.service`, `dbus.service`, `psplash-*.service` | their sysv scripts | the packages' own units | conditions on the hypervisor where the packages have them |
| `occu-interface-clock.timer` | crontab `1 3,9,15,21 * * * SetInterfaceClock` | timer (`DefaultDependencies=no`: the implicit `Before=timers.target` would cycle with `After=occu-persist.service`) | `RandomizedDelaySec=5min`; not persistent (a missed slot after a reboot is not worth catching up). The service runs only when rfd runs (`ConditionPathExists=/run/occulite/radio/rfd.enabled`, B-142, D-97: `SetInterfaceClock` talks to rfd's 32001 and failed on an HmIP-only box), see [The interface clock](#the-interface-clock) |
| `occu-cron-backup.timer` | crontab `7 0 * * * cronBackup.sh` | timer, `Persistent=true`, 30 min random delay; since task 86 it starts `occu-backup-create@nightly.service` (`occulited -backup create nightly`, root), which wants `occu-backup-deliver@nightly.service` (`occulited -backup deliver nightly`, occulite): the backup made once and copied to every enabled target (USB directory, NFS, SMB, SFTP); `NoCronBackup` is the nightly switch the pipeline reads; `cronBackup.sh` stays in the image unused | a run caught up at boot waits for `multi-user.target` (task 116) and occulited (the shares' mount units) |
| `occu-fstrim.timer` | crontab `0 4 * * 6 fstrim` | timer, persistent, 1 h random delay | `NoFSTRIM`; util-linux's own `fstrim.timer` is masked in the overlay, see below (B-8); a run caught up at boot waits for `multi-user.target` (task 116) |
| — | crontab `59 1 * * * checkBadBlocks.sh` | dropped (D-41) | a full-disk read every night writing `/tmp/badblocks.txt`, whose only reader was monit (D-23). `/bin/checkBadBlocks.sh` stays in the image; nothing schedules it |

Not in the image (task 115, D-80): `S40bluetoothd`, `S49xinetd`, `S50ser2net`, `S59snmpd`,
`S60openvpn`, `S51nut` — their packages are not in the lite image (D-23), and `board/post-build.sh`
removes the init script of an optional package on every platform whose configuration does not build
it (upstream-shaped: the Kconfig symbol decides; `docs/upstream-delta.md` item 40). `S51ha-proxy` is
deleted by `board/lite/post-build.sh`. `rcS`/`rcK`, busybox init's runners, are removed by
`board/lite/post-build-initscripts.sh`; what they did around the scripts is `occu-ldconfig`,
`lite-psplash` and `occu-boot-message`.

The order was the S-number order until task 94: one `After=` link per unit to its predecessor,
so every step waited for every earlier one (on the Charly the web UI answered at 40 s and HmIP at
89 s). Since then each unit orders after what its script reads, and
`scripts/testcases/lite-unit-order-test.sh` checks the graph:

- the serial base stays: `occu-persist`, `occu-init-host`, `occu-init-rtc` (after `occu-init-host`
  only), `occu-init-system`, `occu-init-rf-hardware` (not after the network since task 108; the
  detection waits for an HB-RF-ETH's route itself) — all of them write `/var/hm_mode` (B-85; the
  detection merges its keys into it, task 129);
- multimacd after the radio hardware (not after the clock gate, task 108); rfd and hmipserver both
  after multimacd and the clock gate, side by side; rfd also after `occu-set-lgw-key`;
- `occu-lgw-firmware-update` after the network and the radio hardware, `occu-set-lgw-key` after it,
  hs485d after that and `occu-init-hs485d`;
- `occu-init-hs485d` and `occu-init-addons` after the radio hardware;
- lighttpd right after the network, beside occulited; while occulited does not answer, occulited's
  `occulite-starting.lua` turns the proxy's 503 into the waiting page. At shutdown it serves until
  the radio stack is down: not by `Before=occu-init-rf-hardware` (which held the radio detection
  back at boot) but by `ExecStop=lite-radio-stop-wait`, which polls hmipserver, rfd, multimacd and
  the detection while the system is stopping, at most 120 s (task 108);
- the CA bundle before `network-online.target` and its consumers, not in front of the network
  (task 135); `scripts/lite-unit-refs.sh`, run by `post-build-systemd.sh`, stops the build when a
  lite unit names a unit the image does not have (task 116);
- crond after the userfs and the clock gate; `occu-addons` after the addon init and
  `occu-etc-writable`, each addon unit carrying its own ordering (below).

Ordering only — `Requires=` is never used between lite units, because `S03`/`S04` unmount
`/usr/local` and a `Requires=` on that mount would stop everything before them.

Two things the scripts got from busybox init that systemd does not give by itself: the umask
(`rcS` set 0002; every unit sets `UMask=0002`) and the environment of the addon scripts
(`S98StartAddons` sourced `/etc/profile.d` and `/usr/local/etc/profile.d`; the generated units source
`/etc/profile`, which does both). `PATH` for the system units is systemd's default, not busybox
init's `/sbin:/usr/sbin:/bin:/usr/bin`; the scripts use absolute paths.

`/bin/setclock` (the only script outside `/etc/init.d` that calls an init script, `S46chronyd
restart`) is shadowed by a copy that restarts `chrony.service`.

### Roadmap references

The overlay's files carry no task, decision or bug ids (B-70): `systemctl cat` puts a unit and its
drop-ins into occulited's unit editor, the scripts' output is the Log page, and `/etc` on the box
is there to be read. `scripts/lite-id-guard.sh` checks every file of `overlay/lite*`, and every
file of the shared overlays that carries an `openccu-lite` edit — whole files, and for scripts the
lines that are not comments plus every here-document — as a step of the `check` job in
`.github/workflows/lite-build.yml`; `scripts/testcases/lite-id-guard-test.sh` tests the guard. The references live here instead, for the
rebase review. Every unit in the table above is task 20 / D-30; what the comments cited besides:

| File | References |
| --- | --- |
| `lighttpd`, `sshd`, `chrony`, `crond`, `rfd`, `hs485d`, `hmipserver`, `multimacd`, `hmlangw` `.service` | B-3 (the comment paragraph "Restart tracking"), B-4 (console output) |
| `hmlangw.service` | D-41 / task 22, Q-4 (ARM only) |
| `lighttpd.service` ("Certificate permissions"), `lite-cert-perms` | D-46 |
| `occu-init-rf-hardware.service`, `lite-rf-stop` | D-41 / task 22, Q-5; D-40 (the container product) |
| `occu-interface-clock.service` | D-41 / task 22, Q-6 |
| `occu-backup-create@.service`, `occu-backup-deliver@.service` | D-41 / task 22, Q-10; task 8; task 86 (D-64, D-65, D-80: the targets, the pipeline; `occu-cron-backup.service` removed) |
| `occu-leds.service` | D-41 / task 22, Q-11 |
| `occu-usb-gadget.service` | D-41 / task 22, Q-2 |
| `occu-machine-id.service`, `occu-machine-id-store.service`, `lite-machine-id` | D-41 / task 22, Q-3 |
| `occu-watchdog-marker.service`, `lite-watchdog-marker`, `system.conf.d/lite-watchdog.conf` | B-3; D-41 / task 22, Q-9 and Q-12; D-23 (monit); B-25 ("Shutdown order"); task 14 (the Pi test) |
| `occu-persist.service`, `lite-journal-persist`, `journald.conf.d/10-openccu-lite.conf` | task 23; B-7; task 34 (the LXC default); B-46 ("Remote syslog"); B-180 (after the restore at boot; S04's mkfs check) |
| `occu-syslog-forward.service`, `lite-syslog-forward` | B-46 |
| `occu-etc-writable.service`, `etc-writable` | B-28 (its rejected option 2), D-36 |
| `occu-extension-dirs.service`, `lite-extension-dirs`, `kernel/6.18/lite.config` (`CONFIG_OVERLAY_FS`) | task 97, D-66; B-90 (the wiped device descriptions the repair at boot answers) |
| `occu-addons.service`, `addons.target`, `occu-init-addons.service`, `lite-init-addons`, the `occu-addons` generator | D-36; B-17 (`Before=addons.target`); B-28; task 28.8 (the addon-rc wrapper step); B-119 (a confined addon's `init` as an `ExecStartPre` of its unit; `lite-init-addons` instead of `run-parts`, which ran the `.script` files) |
| `addon-users` | D-36; B-54 (appends instead of busybox `addgroup`/`adduser`) |
| `addon-rc-wrapper`, `lite-addon-rc` | task 28.8; task 48 (the cgroup test that replaced `INVOCATION_ID`); B-3; B-119 (`init` of a confined addon from root outside the unit runs nothing) |
| `occu-unit-overrides.service`, `lite-unit-overrides` | task 27.4, B-26 |
| `occu-boot-message.service`, `lite-boot-message`, `lite-psplash` | B-5, B-4; D-37 (the `LITE=` line) |
| `initscript-wrapper`, `openccu-lite-initscripts` | B-3; D-41 (`S11InitLEDs` merged); task 41, 41.0.9 (`start` on an active oneshot restarts it) |
| `50-openccu-lite.preset` | B-4 (the psplash units); B-99 (`wpa_supplicant.service` disabled) |
| `bin/triggerAlarm.tcl` | task 22, D-41; task 12 (`post-build.sh` deletes upstream's); D-23; task 8 |
| `etc/config_templates/rfd.conf`, `etc/hmipserver.default`, `lighttpd/conf.d/webui_remoteapi.conf` | D-29 (the interface processes on the loopback) |
| `lighttpd/modules.conf`, `lighttpd/conf.d/webui.conf`, `lighttpd/conf.d/hsts.conf` | D-28 (the session gate), D-1 (no ReGa endpoints), task 36 (HSTS) |
| `lighttpd/occulite-session-header.lua` (set globally in `lighttpd/modules.conf`) | B-94, D-65 (no request reaches a backend with a client-sent `X-Occulite-Session`; the gate sets it behind a validated session) |
| `tmpfiles.d/lite-var-run.conf`, `board/lite/usbmount-run-dir.sh` | B-109 (`/var/run` a link before any early writer; usbmount's lock under `/run`) |
| `board/lite/no-smartd.sh` (not an overlay file; the drop-in `smartd.service.d/10-openccu-lite.conf` it replaces is gone) | task 111; B-57, B-125 (the smartd failures it ends) |
| `sshd.service`, `crond.service` (the daemon started directly, in the foreground) | task 115, D-80 |
| `lighttpd.service` (runs as `www-data`; the drop-ins as validated root-owned copies) | B-120, D-107 |
| `lighttpd.service` (the sandbox; the preparation moved out), `lighttpd-prepare.service`, `lighttpd/modules.conf` (no `mod_cgi`), `board/lite/post-build.sh` (`server.pid-file` into `/run/lighttpd`, `conf.d/cgi.conf` removed) | task 18 (the systemd sandbox instead of AppArmor; `mod_cgi` out); task 208 (the `~@privileged` busybox finding); B-161, B-163 (the `+` prefix and the mount namespace) |
| `hmipserver.service` | task 180 (the heating group store `groups.gson`); B-161 (`log4j2.xml` rendered at every start) |
| `rfd.service` (`/var/etc` writable for the prep step) | B-161, B-163 |
| `hs485d.service`, `occu-init-hs485d.service` | B-163 (the HMW-LGW check on the Charly; `Wants=` the init pass; prep renders `hs485d.conf`); B-165 (`/var/HS485D.handlers`) |
| `tmpfiles.d/00-openccu-lite-radio.conf` | B-165 (`/var/HS485D.handlers`) |
| `occu-board-leds.service`, `occu-leds.service` | task 158 (the board LEDs once the radio is known) |
| `lighttpd/conf.d/fqdnredirect.conf` | task 165 (the UPnP description not redirected) |
| `opt/HMServer/pages/Group*.ftl` | task 180 |
| `overlay/base/etc/lighttpd/conf.d/httpsredirect.conf` | task 35, D-48 (ACME HTTP-01); task 165, D-108 (the UPnP description) |

## Essential daemons: tracked and restarted

Bug B-3: after uninstalling addons on the lab VM, lighttpd and sshd were dead while the box kept
running, and nothing had noticed. Two causes, both fixed here.

**The unit did not follow the daemon.** Every daemon unit carried `RemainAfterExit=yes` — copied
from the compat-oneshot shape, where it is right — so once the processes in the cgroup were gone
the unit still read *active (exited)*. `Restart=` never fires for a unit that systemd considers
active, `systemctl status` said everything was fine, and the death was not even in the journal.
`RemainAfterExit=yes` is gone from every daemon unit; it stays only on the genuine oneshots
(`occu-init-*`, `occu-addons`, `occu-rc-local`, `occu-leds`, `occu-watchdog-marker`, the
timers' services), which have nothing to outlive.

What each of the nine essential daemons — lighttpd, sshd, chrony, rfd, hs485d, hmipserver,
multimacd, hmlangw and crond — now looks like is in the
unit table above. The rule behind it (task 115, D-80): `Type=exec` with the daemon in the
foreground and its command line in the unit, everywhere - lighttpd's `lighttpd-angel -D`, `sshd
-D`, `crond -f -l 9`, chronyd, rfd, multimacd, the JVM, hmlangw - and the script's preparation
in front of it as its `init` action (`ExecStartPre=`, or `ExecCondition=` where the preparation
also decides whether the daemon runs at all: sshd), or as occulited's `radio prep` for the radio
daemons (task 129). The one `Type=forking` left is hs485d, whose loader daemonises itself and
writes a real `PIDFile=`. A daemon a box does not need is a condition skip (`ConditionPathExists=`
on the plan's marker, `ExecCondition=`), never a unit that is active and empty.

**The restart policy.** `Restart=on-failure` with `StartLimitIntervalSec=300`/`StartLimitBurst=5`
gave up after five tries in five minutes and left the daemon down until someone rebooted. Every
one of the twelve now has

```
[Unit]
StartLimitIntervalSec=0

[Service]
Restart=always
RestartSec=2
RestartSteps=8
RestartMaxDelaySec=300
```

— never give up, and systemd 254+'s exponential backoff as the brake against the tight loop a
process that dies immediately would otherwise cause: 2 s, then doubling over eight steps to five
minutes, which is where it stays. A daemon that comes back stays at the 2 s delay for the next
incident (systemd resets the interval once the unit has been running). `TimeoutStartSec` keeps the
value the script needs (420 s for HMServer's `HMServerStarted` wait, 300 s for chrony's ntpdate,
180 s for sshd's key generation) and `TimeoutStopSec` is bounded everywhere.

### The init-script wrapper

Addons and people do call the init scripts by hand — RedMatic's uninstall runs
`/etc/init.d/S50lighttpd restart` after removing its lighttpd config — and under systemd that
started a daemon *outside* the unit, in whatever cgroup the caller happened to be in. When that
cgroup went away (occulited stopping the uninstall's scope), the daemon went with it, and the unit
that "owned" lighttpd had never had it.

`board/lite/post-build-initscripts.sh` (run by `post-build-systemd.sh`; `scripts/testcases/
lite-initscripts-test.sh` runs it on a fake target) renames every init script listed in
`overlay/lite/usr/lib/systemd/openccu-lite-initscripts` — one `<script> <unit>` line per
script the units wrap — to `/etc/init.d/<name>.script`, and puts a symlink to
`/usr/libexec/occu/initscript-wrapper` at the original path. Afterwards `/etc/init.d` holds
wrappers and `.script` files and nothing else (task 115). The wrapper:

| call | what happens |
| --- | --- |
| `start`, `stop`, `restart` | `systemctl <action> <unit>` |
| `reload` | `systemctl reload-or-restart <unit>` — most of these scripts implement reload as a restart, lighttpd and sshd do not |
| `info`, `status`, anything else | the real script, unchanged |
| a script whose table entry is `-` | nothing, exit 0 (`S07logging` is journald's job here, `S11InitLEDs` is part of `occu-leds`); the script itself is not in the image (task 115), so any other action exits 1 |
| from inside the unit that owns the script (`$INVOCATION_ID` equals that unit's `InvocationID`) | the real script |

The units' own `Exec` lines call `/etc/init.d/<name>.script` directly, so systemd never goes
through the wrapper; the `$INVOCATION_ID` comparison is the safety net for an `Exec` line that
points at the wrapper anyway. Being inside *some other* unit — an addon's unit, occulited's
helper, `rc.local`, `S99SetupLEDs` reloading lighttpd — is exactly the case that has to be routed
to systemd, and there the call gets `--no-block`: a blocking `systemctl restart` from a script
that systemd is itself waiting for can deadlock the transaction. From a login shell it blocks as
an init script always did.

`run-parts` over `/usr/local/etc/config/rc.d` is untouched — those are the addon generator's job
(D-36).

**Review on every rebase**: a rebase that adds, renames or deletes an init script has to add,
rename or delete its line in the table as well. A script that is not listed keeps running outside
systemd when someone calls it by hand; `post-build-initscripts.sh` warns about a listed script that
is not in `/etc/init.d` and about a table entry naming a unit that is not in the image.

## The boot screen and the end-of-boot message

Bug B-4: on the systemd product the psplash progress bar moved (buildroot's
`psplash-systemd.service` drives it from systemd's job progress) but the text was gone — "Starting
service xyz…" and everything the init scripts printed. Bug B-5: nothing was left on the console
once the box was up.

- **the scripts' output.** `rcS` ran the init scripts on the console. Every unit that wraps one now
  has `StandardOutput=journal+console` and `StandardError=journal+console`: the lines are in the
  journal *and* on `/dev/console`, which is the tty the kernel cmdline names. `hmlangw.service` is
  the one daemon left out (it is chatty and replaced a log file), and so is `occulited.service`,
  which is `package/occulited`'s.
- **the psplash messages.** `rcS` wrote `MSG Starting <name>...` and `PROGRESS <S-number + 1>` to
  psplash's FIFO before each script. `/usr/libexec/occu/lite-psplash boot SXXname` does the same
  two writes and is the first `ExecStartPre` of every unit that replaces an init script. Units
  start side by side, though, so the last `boot` is not what is still starting (B-126: "Starting
  rfd..." stood for 45 s while hmipserver's JVM started). `boot` therefore notes the unit's message
  under `/run/lite-psplash/` (the unit's name from its cgroup), and `lite-psplash done SXXname`, the
  last `ExecStartPost` of the same units (with the same `+` where the unit runs as a user), shows
  the message of a unit still starting: the HmIP server first ("Starting HmIP server..." for
  `S62HMServer`), otherwise the one that began last, or "Starting services..." when none is left.
  That is one `systemctl list-units --state=activating` per `done`, and only while the splash is
  up. `lite-psplash` never (re)starts psplash — `psplash-start.service` owns it. It writes nothing
  once psplash is gone or the boot has finished (`finish`, below), and a stale FIFO with no reader
  cannot block it (`timeout 2`, plus the `pidof` check). The FIFO is `/run/psplash_fifo`, the same
  path `rcS` uses; on the systemd products `/run` is PID 1's own tmpfs rather than a symlink into
  `/var` (`post-build-systemd.sh`), so it exists before `psplash-start.service`, which is
  `Before=sysinit.target`.
- **the end of the boot.** `occu-boot-message.service` runs after `occu-leds.service`
  ("booted, OK") and the network, still inside the multi-user job, and runs
  `/usr/libexec/occu/lite-boot-message`. The splash stays on the screen with the hint below the
  logo and without the progress bar (the maintainer, B-126):
  - `psplash-systemd` sends `QUIT` as soon as systemd's progress reaches 1.0, which is right after
    this unit, so it is stopped first;
  - `lite-psplash finish` empties the bar (`PROGRESS 0`: the bar's frame image is transparent and
    its background is the splash's black, so nothing of the bar is left) and draws the hint; from
    then on `lite-psplash` writes nothing, so a service restarting at 3 a.m. does not draw on it;
  - the framebuffer console's cursor on the splash's terminal is hidden (`ESC [?25l`), or it
    blinks in the top left corner.

  The hint also goes to `/dev/console`, and its first three lines to `/run/issue`. psplash drew a
  message of n lines as if it had n - 1 (it sized a text by its newlines), so the hint's last line
  went into the bar's rows and the bar painted over it; `patches/psplash/0004-text-height.patch`
  counts the lines, so a message of any height ends above the bar.
- **a console.** The image had no getty (`BR2_TARGET_GENERIC_GETTY_PORT` is unset, and buildroot's
  `getty@.service.d/buildroot-console.conf` empties the default instance) and no logind for
  `autovt@`. The preset enables `getty@.service tty2`, ordered after `occu-boot-message.service`
  (`getty@tty2.service.d/10-openccu-lite.conf`) so that its `/etc/issue` has the hint; the splash
  keeps tty1. Alt+F2 shows the login prompt, and the hint's fourth line says so where it is true:
  the getty on tty2 enabled and `/dev/tty0` present, the getty's own condition, so not in a
  container. psplash does not redraw after a terminal switch: back on tty1 (Alt+F1) the splash is
  gone.

- **the logo** (task 112). The lite products' splash shows OpenCCU's logo with `lite` beside it, like
  the web UI's wordmark: `board/lite/psplash/logo.png` (510x106), which their configurations name in
  `BR2_PACKAGE_PSPLASH_IMAGE`. Upstream's `patches/psplash/logo.png` (415x106) stays for the upstream
  products. The new logo is as tall as the old one, so the message and the bar keep their places, and
  `package/recovery-system` passes the same variable on, so the recovery system's splash shows it
  too. `board/lite/post-build.sh` runs `psplash-logo.sh`, which stops the build when a product with
  psplash names another image. The file is made by the agents repository's
  `scripts/make-splash-logo.mjs`, `make-brand.mjs`'s method in its dark variant. psplash plots every
  pixel whose alpha is not 0 at full colour and blends nothing, so the logo is plotted onto black the
  same way first, and `lite` is antialiased against that black: the PNG is opaque RGB. A build must
  rebuild psplash to pick up a new image or patch (`make psplash-dirclean`).

`scripts/testcases/lite-boot-screen-test.sh` covers both scripts, the units' `done` lines, the
getty and the logo's configuration.

```
openccu-lite 3.89.8.20260719-lite.0-beta.1 is up.
Host: ccu3   Address: 192.168.1.42
Web UI: http://192.168.1.42/
Console: press Alt+F2
```

The version is `VERSION` plus the D-37 `LITE=` line of `/VERSION`, the addresses are
`ip -4 -o addr show scope global`, and LAN-gateway mode gets its serial instead of a URL, as `rcS`
had it. `/etc/issue` is a symlink to `/run/issue` (`post-build-systemd.sh`) because the rootfs is
read only; the getty on tty2 shows the first three lines above its login prompt.

## Addons without changes (D-36)

`overlay/lite/usr/lib/systemd/system-generators/occu-addons` writes, into the generator's
early directory, one `addon-<name>.service` per executable in `/usr/local/etc/config/rc.d/` whose
name busybox `run-parts` would have accepted (letters, digits, `_`, `-`, non-leading `.`):

```
[Unit]
Description=Addon <name> (/usr/local/etc/config/rc.d/<name>)
After=network.target lighttpd.service occulited.service occu-addons.service rfd.service hmipserver.service
PartOf=addons.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c '. /etc/profile; exec /usr/local/etc/config/rc.d/<name> start'
ExecStop=/bin/sh -c '. /etc/profile; exec /usr/local/etc/config/rc.d/<name> stop'
KillMode=control-group
TimeoutStartSec=300
TimeoutStopSec=120
OOMScoreAdjust=100
UMask=0002
```

plus the `addons.target.wants/` symlink. There is no ordering between addons (task 118): until
2026-09-16 an `After=addon-<previous>` link kept run-parts' one-after-another order, so a slow or
hanging start script held back every addon after it by name. `rfd.service hmipserver.service` is the safe default; the catalogue entry's
`runtime.needs`, which occulited writes to `addon-policy/<name>.needs`, changes it (task 94): `none`
drops the interfaces (the addon starts right after the network),
a list of `rfd`, `hmipserver`, `hs485d` becomes `After=` and `Wants=`; anything else keeps the default. An addon
whose catalogue entry declares `runtime.start: "early"` (task 119, D-75: it retries within seconds and logs no errors
while the interfaces come up) gets `addon-policy/<name>.start` with the line `early` from occulited, unless the user
switched the early start off on the Addons page (globally or for the addon). Its unit is then ordered after
`network.target lighttpd.service occulited.service occu-addons.service` only and has `Wants=` for its needs (or `rfd.service
hmipserver.service` when it declares none) without `After=` on them, so it starts before the interfaces are ready; a
file with anything else keeps the ordering above. `lite-unit-order-test.sh` checks that none of those four base units
is itself ordered after an interface daemon. A change of the switches takes effect at the next boot. Safe mode (`/etc/config/safemode`) generates nothing, as
`S98StartAddons` skipped the addons.

**Every addon gets the generated unit; an addon cannot bring its own** (D-69, B-118). Until
2026-09-13 an addon shipping `/usr/local/addons/<name>/etc/systemd/<name>.service` got a symlink to
that unit instead (D-36's opt-in). A confined addon owns that directory, so it could write the file
itself, and a `User=root` or `ExecStartPre=+…` line in it ran as root at the next boot or
`daemon-reload`. The generator now reads nothing from an addon's directory. It only tests whether
such a file, or a `<name>.service.d/` beside it, exists, and then writes one line per addon to
`/dev/kmsg` (stderr where that cannot be written), which journald files under `occu-addons`:
*"addon &lt;name&gt; ships its own unit file; ignored since openccu-lite 1.0.0-alpha.0, the
generated unit is used"*. The line comes at every generation, so at boot and at every reload after
an install. What an addon needs beyond the generated unit is its policy and the catalogue entry's
`runtime` block. `scripts/testcases/occu-addons-generator-test.sh` plants such a unit (`User=root`,
`ExecStartPre=+`, `ExecStartPost=+`, `ExecStopPost=!`, a drop-in, a dangling link) and checks that
the output holds only the generated unit, the policy and the ownership step, and the journal line
once per addon.

Generators run before `/usr/local` is mounted, so at boot this one sees no `rc.d`.
`occu-addons.service`, at S98's place in the chain, runs `systemctl daemon-reload` (which reruns
the generators against the final userfs) and then `systemctl --no-block start addons.target`,
which pulls the freshly generated units into the `addons.target` job that is already queued as
part of `multi-user.target`. occulited runs the same reload after installing an addon.

`TimeoutStartSec=300` is new: run-parts had no timeout. A script that blocks longer than five
minutes on start fails its unit (and the box still finishes booting); `rc.local` had 120 s before.

### Per-addon users (D-36, task 18) and the privilege boundary (task 17)

occulited writes, per addon, `/usr/local/etc/config/addon-policy/<name>.json` (mode `root` or
`confined`, the uid, the catalogue entry's `runtime` grants) and renders `<name>.conf` from it, a
systemd drop-in. The generator copies a `<name>.conf` that has a `[Service]` section to
`addon-<name>.service.d/10-policy.conf`; a root-mode file has none and changes nothing. Confined
means:

```
[Service]
User=addon-<name>
Group=addon-<name>
SupplementaryGroups=<runtime.groups>
AmbientCapabilities=<runtime.capabilities>   (and the same CapabilityBoundingSet; empty set otherwise)
NoNewPrivileges=yes
ProtectSystem=strict
ProtectKernelTunables=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
ReadWritePaths=/usr/local/addons/<name> /usr/local/etc/config/addons/<name> /usr/local/etc/config/rc.d /run /var/log /tmp /var/tmp <runtime.paths>
```

The user `addon-<name>` gets a uid from 30000 upwards, recorded in the JSON so the ownership of
the addon's files on the userfs stays valid across firmware updates, which replace `/etc/passwd`
with the rootfs: `occu-addons.service` runs `/usr/libexec/occu/addon-users` before its
daemon-reload, and that recreates every user the policy files name (busybox `addgroup`/`adduser`,
the same calls occulited makes when it confines an addon). The Services page switches an addon
between root and its user; the box's default for addons without a policy is
`addons.default_mode` in `occulited.json` (root until the maintainer decides, the ⚖ of D-36).

Addon CGIs no longer run under lighttpd: `/addons/<name>/*.cgi` is proxied to occulited, which
runs `tclsh <script>` through its privilege helper as the addon's user (root for an addon in
root mode), with mod_cgi's environment. The session mirror `/run/occulite/sessions` is 0711 with
0644 files so a CGI can verify the sid it holds through the tclrega shim and list nothing.

occulited itself runs as `occulite` (`package/occulited`'s users table) with
`ProtectSystem=strict`; `occulited-helper.service` (root) serves `/run/occulite/helper.sock`
(root:occulite 0660) and performs the enumerated operations — the firmware's scripts and
`systemctl` by name or directory, writes under `/etc/config` and the userfs paths by prefix,
renames out of occulited's staging directory, the CGI runs. Everything else is refused and
logged. `docs/security.md` in openccu-lite is the reference.

Known gap: an addon CGI that restarts its own daemon (`rc.d <name> restart`) starts it outside
the addon's unit; the Services page restart puts it back into the unit's cgroup.

**Nothing of a confined addon runs as root any more, `start` and `stop` in the unit or not** (B-119,
2026-09-23). `rc.d/<name>.script` is the addon's own script in its own directory (a link there, as
a rule), so every action outside the unit was the addon's current code run as root: `info` at
every listing (the shell's navigation, the Addons page, the daily update check), `init` from
`S55InitAddons`' `run-parts` at boot, `uninstall` on the admin's press. Now, for an addon whose
policy has `User=addon-<name>`: occulited runs `info` and `uninstall` through its helper's `RunAs`
with the addon's uid, gid and its one group (the helper admits a script directly in `rc.d` with
`info`, `info.de`, `info.en`, `init` or `uninstall` for an addon uid, nothing else - `start`, `stop`
and `restart` stay the unit's); the generator writes `30-addon-init.conf` with
`ExecStartPre=-/bin/sh -c '. /etc/profile; exec /usr/local/etc/config/rc.d/<name> init'`, which
runs as the unit's user right before its start, after the `+` ownership step of `20-addon-own.conf`
(the drop-ins' `ExecStartPre` lines run in file order), and the wrapper answers `init` from root
outside the unit with exit 0 for such an addon, so the `init` pass at boot runs nothing of it. That
pass is `lite-init-addons` now (`occu-init-addons.service`), not `S55InitAddons.script`'s
`run-parts -a init`: busybox run-parts takes a dot in a name, so it ran every `<name>.script` -
the addon's own script - directly as root at every boot, past the wrapper, since the wrapper exists
(found on the Pi 4 with a test addon: `init uid=0` from `run-parts`, `Usage: node-red …` from
RedMatic's script). `lite-init-addons` keeps S55's behaviour otherwise (HM_MODE, safe mode,
`rc.prelocal`, the OOM score, output dropped) and runs `init` on the entries only;
`lite-init-addons-test.sh` pins it.
A confined addon's `init` thereby moves from S55's slot, before the radio daemons, to right before
its own start; of the first-class addons (D-19) none does anything in `init` (homematic-manager and
hm2mqtt.js `exit 0`, RedMatic and Mosquitto have no such case), so nothing changes for them. After
a user-level `uninstall`, root removes what the script could not - the rc.d entry, the `www/<name>`
link and the standard directories the script emptied. Root addons keep S55's `init` and the root
`uninstall` in the install scope. The install scope is not the way to drop privileges:
`systemd-run --scope --uid=` keeps the caller's supplementary groups. `addon-rc-wrapper-test.sh` and
`occu-addons-generator-test.sh` pin the wrapper's and the generator's halves.

## Logs: journald on the userfs

`/var` is a tmpfs on every OpenCCU product (fstab, `size=50%`), so a "persistent" journal in
`/var/log/journal` would not survive a reboot. `occu-persist.service` bind-mounts
`/usr/local/var/log/journal` there once the userfs is final (after resize, factory reset and backup
restore: `After=occu-backup-restore.service`, which orders after the other two, pinned by
`lite-unit-order-test.sh` - with the bind mount in place the partition stays mounted, `parted
resizepart` and `mkfs.ext4` refuse it, and a fresh x86_64-ova's first boot kept its 2 MB userfs and
its pending factory reset; `S04CheckFactoryReset` now reports a failed `mkfs.ext4` instead of
"cleared, OK") and flushes what journald collected in `/run` since boot (SIGUSR1 to journald: `journalctl
--flush` returns early once `systemd-journal-flush.service`, which ran before the directory existed,
has set its flag); `journald.conf.d/10-openccu-lite.conf`
has `Storage=auto` (so journald does not create the directory on the tmpfs earlier), `SystemMaxUse=32M`,
`RuntimeMaxUse=16M`, `Compress=yes`, no forwarding. `/usr/local/var` carries a `.nobackup` tag:
logs are not configuration. The timer stamps (`Persistent=true`) live next to it.

journald names its directory after the machine ID, and a read-only rootfs means systemd would boot
with a random transient ID every time — a new directory per boot that no size cap ever vacuums.
[The machine ID](#the-machine-id) below is how that is avoided.

What this costs on an SD card: journald appends to one file and syncs every five minutes
(`SyncIntervalSec` default); the userfs is mounted with `commit=30`. Upstream writes no logs to the
card at all. **Maintainer decision**: keep the journal on the userfs (D-30's "persistent") or drop
`occu-persist.service`'s bind mount and live with per-boot logs — the size cap applies either way.

## The machine ID

D-41 (Q-3) settles what the first version of `occu-machine-id.service` left open: the ID is
**derived from the board serial** and **installed with a bind mount**, never by writing to the
rootfs.

What systemd does by itself: `/etc/machine-id` in the image is the empty file buildroot's systemd
package installs (`touch $(TARGET_DIR)/etc/machine-id`), so PID 1 generates a transient ID at
every boot, writes it to `/run/machine-id` and bind-mounts that file over `/etc/machine-id` —
the documented read-only-`/etc` pattern. **Installing an ID is therefore writing `/run/machine-id`**;
no new mount is needed in the normal case, and the previous `mount -o remount,rw /` is gone.

Why the bind source is `/run` and not the userfs: a `.mount` unit binding
`/usr/local/etc/machine-id` over `/etc/machine-id` would be the more declarative form — and it
would hold a reference on the userfs, which `S03CheckUserFSResize` and `S04CheckFactoryReset`
unmount (`umount -f /usr/local`) on the boots where they do their work.

Two units, because `/var` is a tmpfs and `/var/board_serial` is written by `S47InitRFHardware`,
i.e. hours of boot after journald has read the ID:

| Unit | When | What |
| --- | --- | --- |
| `occu-machine-id.service` | `DefaultDependencies=no`, `RequiresMountsFor=/usr/local`, `Before=systemd-journald.service sysinit.target` | takes the ID from `/usr/local/etc/machine-id` and makes it the running one, so **journald starts with the final ID** and nothing has to be restarted |
| `occu-machine-id-store.service` | `After=occu-init-rf-hardware.service` | derives the ID from `/var/board_serial` and stores it on the userfs; on the boot that derives it, applies it in place |

`/usr/libexec/occu/lite-machine-id` is both actions. The derivation is
`sha256("openccu-lite-machine-id:<serial>")` truncated to 128 bit with the UUID version (4) and
variant (8) nibbles systemd's own `sd_id128` helpers set — a valid machine ID, stable for the box,
and not the serial itself. Without a serial (no radio module attached) it generates a random ID
once. A userfs wipe therefore does not change the box's identity as long as the module stays.

The cost of `Before=systemd-journald.service` is that journald starts after the userfs is
mounted. The mount is `nofail` and on the same disk as the rootfs; if it does not come up, the
unit is skipped and journald starts on the transient ID exactly as before — `Before=` orders, it
does not require. What is lost on the very first boot is nothing: the ID is derived and applied
that same boot, journald is restarted on it, and the journal written so far under the transient ID
(flushed to `/var/log/journal/<transient>/` by `occu-persist`) moves into the final ID's directory
as archived files named as journald names its own archives
(`system@<seqnum id>-<head seqnum>-<head realtime>.journal`, from the file's header), so the
vacuum treats them as its own and `journalctl -b` shows the whole boot - the resize, the factory
reset and the restore of a reset boot included (B-182). Until B-182 the directory was removed
instead: journald refuses to *write* a file whose header carries another machine ID, and the
directory of a foreign ID is read only with `--merge`; reading an archived file checks no machine
ID. Every boot after that starts on the stored ID.

PID 1 keeps the ID it read at startup in its own memory either way; journald and everything that
reads `/etc/machine-id` see the final one.

## The unclean-shutdown marker

`occu-watchdog-marker.service` is the half of `S00watchdog` that survives, on every product, and
D-41 (Q-9) gives it back the consumer it lost when monit went (D-23). For the occulited side
(task 8, the Status page), the semantics are:

| Path | Meaning |
| --- | --- |
| `/usr/local/tmp/.watchdog` | on the userfs, written at start and removed at stop. Present at boot ⇒ the previous shutdown did not run the stop action |
| `/var/status/uncleanShutdown` | on the tmpfs `/var`, `root:status` `2775` directory. Created at boot **only** when the box came up after an unclean shutdown; it is a per-boot flag, empty, and its existence is the whole message |
| `/run/occu-watchdog-marker.done` | the guard that keeps a restart of the unit from re-evaluating the marker within one boot; not for consumers |

So: `stat /var/status/uncleanShutdown` is the check, its mtime is the boot it refers to, and it
disappears by itself at the next clean boot. **No consumer reads it yet** — D-41 (Q-9) says
occulited should show it on the Status page and that is still on the open list in openccu-lite's
`BUGS.md`; the marker itself is written on every boot, so the notice can be added without touching
anything here. It says nothing about *why* — a power cut, a watchdog
reset and a kernel panic look the same — and nothing clears it while the box is up, so a UI notice
should be dismissible rather than expect the file to go away.

## The hardware watchdog

D-41 (Q-12): PID 1 feeds the watchdog. `etc/systemd/system.conf.d/lite-watchdog.conf` sets

```
[Manager]
RuntimeWatchdogSec=10s
RebootWatchdogSec=1min
```

and `occu-watchdog.service` — busybox `watchdog -F -T 300 -t 5 /dev/watchdog` — is gone. The
busybox feeder kept writing to the device while PID 1 was wedged, which is the failure a watchdog
exists for; systemd's ping comes from the manager loop, so a hung PID 1 stops it.

Why 10 s and not the feeder's 300 s: on the Pi the device comes from
`modprobe bcm2835_wdt nowayout=1 heartbeat=15` (`S06InitSystem`) and that driver's timeout tops
out at about 15 s, so a larger request is clamped by the driver. systemd pings at half the
timeout. On `x86_64-ova` there is normally no `/dev/watchdog` at all — an emulated i6300esb is not
a Proxmox default and `softdog` is not loaded — and the setting then costs one log line.

**To be tested on a Pi before it is trusted (task 14), while it is already the default per the
maintainer:** `bcm2835_wdt` is a *module*, loaded by `S06InitSystem` well after PID 1 has set its
watchdog up, so the box has to show (a) that PID 1 picks the device up once it appears — systemd
re-opens `/dev/watchdog` on a later ping — and (b) that a `nowayout=1` driver behaves across the
handover. `systemctl show -p RuntimeWatchdogUSec` and a deliberate hang (`echo c >/proc/sysrq-trigger`)
are the two checks. If PID 1 does not pick the device up, the fix is to load the module earlier
(`/etc/modules-load.d/`) or to build the driver in — not to bring the feeder back.

busybox's `watchdog` applet stays in the shared `Busybox.config`: upstream's busybox-init products
still run `S00watchdog`, and since D-39 there is no lite one left that does.

## Conditions: which units run where (D-41)

Task 22 asked, unit by unit, whether it belongs on a product at all (`docs/occu-units-review.md`
in the openccu-lite repository). What the answers became, beyond the table above:

- **USB gadget mode is ARM-only.** `dwc2` and `g_ether` are the Pi's OTG controller and its
  USB-Ethernet gadget; on x86 they do not exist. `occu-usb-gadget.service` carries
  `ConditionVirtualization=no` and, as a second condition, the very flag file the script checks
  (`/etc/config/usbGadgetModeEnabled`), so a box that has not switched gadget mode on does not
  spawn a shell for it. Nothing in the UI writes that file yet; it is on the backlog (D-41, Q-2).
- **HM-LGW mode is ARM-only.** A box running as a HomeMatic LAN gateway instead of a CCU is a Pi
  with a radio module bolted to it; `x86_64-ova` never runs as one. `hmlangw.service` — the one
  unit that exists solely for that mode — has `ConditionVirtualization=no` next to its
  `/usr/local/HMLGW` condition. The four init scripts that branch on `HM_MODE` (`S06InitSystem`,
  `S49hs485d`, `S58`/`S59`, `S99SetupLEDs`) are upstream's and keep their branches (D-4); UI
  support for the mode is on the roadmap, undecided.
- **The coprocessor bootloader handover happens only before a firmware update.**
  `S47InitRFHardware`'s `stop()` sends every coprocessor into its bootloader, up to 120 s per
  module, at every shutdown. `ExecStop` is now `/usr/libexec/occu/lite-rf-stop`: with
  `/usr/local/.firmwareUpdate` or `/usr/local/.recoveryMode` staged it execs upstream's `stop()`
  unchanged; without one it leaves the modules running and only disconnects an HB-RF-ETH, which is
  upstream's own reason for that branch (the module otherwise keeps reconnecting to a box whose
  stack is down).
- **Wired stays in scope** (D-26 extended to `hs485d`/HMW-LGW). `hs485d.service` keeps its
  `ExecCondition` on an `[Interface x]` section in `/var/etc/hs485d.conf`, which is the script's
  own "disabled" branch: no wired hardware, no unit, no restart loop.
- **The nightly backup runs only once a target is set** (history: since task 86 the pipeline of `occu-backup-create@.service` replaces `occu-cron-backup.service`, and a run without an enabled target does nothing). `cronBackup.sh`'s built-in default is
  `/media/usb0/backup`, a symlink a usbmount hook of the WebUI's measurement feature creates, on a
  tmpfs — so on a box where nobody wrote `/etc/config/CronBackupPath` the script's own guard made
  it exit 0 every night and back up nothing. `occu-cron-backup.service` now needs that file
  (`ConditionPathExists=`) and needs it non-empty (an `ExecCondition=`, which is what
  `ConditionPathExists` cannot express), and occulited shows a "no backup target set" notice until
  then (task 8). Its failure path is fixed too: `cronBackup.sh` calls `/bin/triggerAlarm.tcl`,
  which needs ReGa and is deleted by `board/lite/post-build.sh`, so the systemd overlay ships a
  shell stand-in of the same name that writes the alarm to the journal — the callers' ABI, and
  `post-build.sh` recognises it and deletes only upstream's version.
- **The bad-block scan is gone**, the marker above stays. Both wrote files whose only reader was
  monit; one of them was worth a consumer, the other was a full-disk read per night on the medium
  task 23 is trying to protect.
- **smartd is gone** (maintainer, 2026-09-13, task 111). It had nothing to watch on any product:
  an SD card, an eMMC and a USB stick have no SMART, and a VM's or a container's disks are the
  host's, whose own monitoring is where their health belongs. The `/dev/sd*`/`/dev/nvme*` condition
  of the old drop-in (B-57) could not tell a USB stick from a disk, so with a stick plugged at boot
  smartd found nothing, exited 17 and left a failed unit at every boot (B-125). Nothing read its
  reports either: occulited's storage panel reads SMART itself, once an hour, through the privilege
  helper's `smartctl` operation. So the Pi products (`aarch64-rpi3`, `-rpi4`, `-rpi5`) keep
  `BR2_PACKAGE_SMARTMONTOOLS` for `smartctl` alone, and `board/lite/no-smartd.sh`, run at the end
  of `board/lite/post-build.sh` on every lite product, removes the daemon, `smartd.service` with
  any drop-in, its enable links, `/etc/smartd.conf` and `/etc/smartd_warning.*`. It runs after
  every package install, so a reinstall the overlay prune asks for (B-101) cannot bring them back,
  and before the rootfs step's `systemctl preset-all`, which has no unit left to enable. The VM and
  the container products (`x86_64-ova`, `lxc-lite_*`) say
  `# BR2_PACKAGE_SMARTMONTOOLS is not set`, and there the script also removes what an earlier build
  of the same output directory left. The build stops when a smartd file is left anywhere, when a
  preset names smartd, or when `smartctl` is missing where smartmontools is built or present where
  it is not. On a VM or a container the storage panel says that the host monitors the disks
  (`health_source: host`). Tested by `scripts/testcases/lite-smartd-test.sh`, a step of the `check`
  job.

### The interface clock

`occu-interface-clock.timer` stays **unconditional on every product** (maintainer, 2026-09-06).
The review proposed gating it on a configured LAN gateway, like the two `S58`/`S59` units, on the
reading that `/bin/SetInterfaceClock` only serves gateways. That reading is an inference about a
closed eQ-3 binary from the RFD package that nobody has watched on a live box: rfd may well pass
the time to the built-in radio module as well. One XML-RPC call four times a day costs nothing and
rfd decides for itself when there is nothing to update, while a wrong condition would produce
wrong timestamps on gateway-side events days later — the worst class of regression to debug. The
only condition is upstream's own: the crontab line does not run when the box *is* a LAN gateway
(`ConditionPathExists=!/usr/local/HMLGW`).

## First boot (2026-09-06, QEMU without KVM)

The first systemd image — `ova-lite-systemd` then, `x86_64-ova` since D-39 — reached
`multi-user.target` 16 s after the kernel started (the busybox `ova-lite` answers HTTP after 43 s
in the same setup, most of that being lighttpd and occulited starting under TCG). Four findings,
all fixed the same evening:

- `occulited.service` never started: `ProtectSystem=strict` builds the sandbox before
  `ExecStartPre`, and `ReadWritePaths=` must exist by then — `RuntimeDirectory=` and a
  `tmpfiles.d` entry now create the two directories.
- buildroot's own `network.service` (`ifup -a` from the ifupdown-scripts package) ran before
  `/tmp` existed and failed; `occu-network.service` (`S40network`) does the same job three seconds
  later and succeeds. `network.service` is masked in the overlay.
- `eq3configd.service` restarted in a loop on a box without a radio module: its preparation
  step read `/var/rf_address`. Made tolerant (`ExecStartPre=-`) at the time; the unit itself is
  gone since task 163, and what its preparation did is `occulited radio run`'s.
- journald reported "No space left on device": the image's userfs partition is 3 MB until
  `occu-userfs-resize` grows it into the disk, and a QEMU copy the size of the image has no room.
  The test script grows its copy by 2 GB; a real disk is bigger than the image anyway.

`psplash-start.service` (buildroot's boot splash) fails without a framebuffer; harmless, left
as upstream ships it.

The whole unit set was put through `systemd-analyze verify` (systemd 257) on 2026-09-07: every
`.service`, `.target` and `.timer` in this overlay, plus `occulited.service` and
`occulited-helper.service` from `package/occulited`, and a generated `addon-<name>.service` with
the confined policy drop-in `10-policy.conf` beside it. No directive, value or dependency was
rejected; the only complaints were about executables that are not on the machine running the
check, which is every path in the target rootfs.

Two more found on the lab box the night of 2026-09-06/07:

- The Log page answered `journalctl: exit status 1` and nothing else (B-7). `occu-persist.service`
  creates `/usr/local/var/log/journal` itself, so journald never applies its own permissions to it:
  the directory was `root:root 0755` and every flushed journal file `root:root 0640`, which the
  `systemd-journal` group cannot read — and `occulited.service` reaches the journal exactly through
  `SupplementaryGroups=systemd-journal`. The unit now sets group `systemd-journal` and the setgid
  bit on the mount before the flush and fixes what is already there afterwards, which is what
  systemd's own `z /var/log/journal 2755 root systemd-journal` tmpfiles rule would do if the
  directory existed when tmpfiles ran.
- util-linux ships `fstrim.timer`, buildroot's preset enables it, and it trims the same
  filesystems as `occu-fstrim.timer` — ignoring `/etc/config/NoFSTRIM`, so a box that opted out of
  trimming was trimmed weekly anyway (B-8). `fstrim.timer` is masked in the overlay next to
  `network.service`.
- **No Tcl worked at all, and the firewall was therefore never applied** (B-11). `package/openccu-base`'s (`package/occu` until 3.89.8)
  finalize hook ends with `ln -snf /usr/bin/tclsh $(TARGET_DIR)/bin/tclsh` — correct on upstream's
  split-`/usr` target, where tcl has installed `/usr/bin/tclsh -> tclsh8.6`. systemd selects
  `BR2_ROOTFS_MERGED_USR`, so on every lite systemd product `/bin` *is* `/usr/bin` and that command
  overwrote tcl's link with a link to itself: `/usr/bin/tclsh -> /usr/bin/tclsh`, ELOOP for every
  Tcl script in the image. The visible damage: `/etc/network/if-up.d/eQ3StartNetwork` runs
  `/bin/setfirewall.tcl` at every boot and does not check its exit code, so the lab box came up
  with an empty `iptables` ruleset (all policies `ACCEPT`) while the Firewall page showed the
  configuration it thought was applied; `PUT /api/system/v1/ssh` and every other write that runs
  `setfirewall.tcl` answered 500; and lighttpd's `cgi.assign` maps `.cgi` to `/bin/tclsh`, so no
  addon settings page could have worked either. `board/lite/post-build-systemd.sh` points the link
  back at the `tclsh<version>` binary tcl installed and fails the build if there is none. The
  first attempt at that repair did nothing, and it is worth remembering why: it tested
  `[ ! -e "$TARGET_DIR/usr/bin/tclsh" ]`, and the link says `/usr/bin/tclsh` — an *absolute*
  path, which a test on the build host follows out of the target root to the host's own tcl.
  The test is on the link's text now, resolved inside `TARGET_DIR`. The B-12 repair beside it
  was never affected: that link is relative.
- **The 32-bit ELF interpreter link dangled** (B-12), the same merged-`/usr` mistake one package
  further on. `package/multilib32` unpacks a second, non-merged buildroot into `/lib32` and
  `/usr/lib32` and then runs `ln -sf ../lib32/ld-linux.so.2 $(TARGET_DIR)/lib/`
  (`ld-linux-armhf.so.3` on aarch64). On upstream's split-`/usr` target that lands in `/lib` and
  resolves into `/lib32`; here `/lib` is a symlink to `usr/lib`, so it lands in `/usr/lib` and
  resolves into `/usr/lib32`, where the loader is not. `/lib/ld-linux*.so.*` is the interpreter
  path compiled into every 32-bit binary, so any of them would have failed to exec. Nothing 32-bit
  is *executed* on the x86_64 product — `find / -xdev` turns up 32-bit shared libraries only, 21 MB
  of them, and no 32-bit program — but the aarch64 products carry eQ-3's 32-bit pieces, which under
  D-43 is the whole reason `multilib32` is in them, so this had to be right before `aarch64-rpi3`
  and `aarch64-rpi4` ship. `post-build-systemd.sh` relinks it.
- **Every clean shutdown looked unclean, and every stop action that writes to the userfs was a
  no-op** (B-25). `usr-local.mount` was stopped 7.7 s *before* the last of the `occu-*` chain, so
  `S00watchdog stop`'s `rm -f /usr/local/tmp/.watchdog` ran against the empty mount point on the
  read-only rootfs, returned 0, and left the marker behind — the next boot then wrote
  `/var/status/uncleanShutdown`, every time. Measured on the lab box:

      [15993.096] usr-local.mount: Deactivated successfully.
      [16000.790] Stopping Hardware watchdog...

  `After=local-fs.target` does not order a unit against the individual mount units the target
  pulls in. `occu-watchdog-marker.service` is now `After=usr-local.mount` as well, and because
  every other `occu-*` unit is ordered after *it*, that keeps the userfs mounted until the whole
  chain has stopped — which the stop actions of `occu-seedrng` (the RNG seed) and
  `occu-init-rf-hardware` (D-41's coprocessor handover before a firmware update) need just as
  much. Ordering only, deliberately not `RequiresMountsFor=`: the userfs is unmounted and
  remounted by the resize and factory-reset units, and a `Requires=` on it would tear this unit
  down in the middle of a first boot.

- **`addons.target` was reached before the addons had started** (B-17). A unit in
  `addons.target.wants` is pulled in but not ordered, and the generated `addon-<name>.service`
  units said only `PartOf=addons.target` — so the target went active at once, while
  `occu-rc-local.service`, `occu-leds.service` and `occu-boot-message.service` all say
  `After=addons.target` precisely because they are meant to come after the addons, the way they
  came after `S98StartAddons` under busybox init: the "system ready" LEDs and the end-of-boot
  hint could appear while addons were still starting. The generator adds `Before=addons.target`
  (until D-69 also to an addon's own opt-in unit, through a `05-order.conf` drop-in; addons have
  no own units since then).

- **`/var/run` became a directory when a USB stick was plugged in at boot** (B-109, 2026-09-12, the
  Charly). udev runs `usbmount` for every `sd*` device during the coldplug, and
  `systemd-udev-trigger.service` is ordered against nothing but `sysinit.target`. The script began
  with `mkdir -p /var/run/usbmount`. Before `var.mount` that follows the rootfs link into `/run`;
  after it `/var` is an empty tmpfs, the mkdir makes a real directory, and systemd's
  `L /var/run - - - - ../run` (`var.conf`) leaves a directory alone. Every forking daemon then wrote
  its pid file there, `sshd`, `chrony`, `crond` and `hmipserver` hung in `activating` until their
  start timeouts and restarted in loops, and systemd logged `System is tainted: var-run-bad`. The gap
  is about 2 s on the Charly (`var.mount` at 11.0 s, `systemd-tmpfiles-setup` at 13.2 s: tmpfiles
  waits for journald, journald for `occu-machine-id.service` on the userfs). A stick with or without
  a filesystem triggers it - the mkdir comes first - and whether a boot does depends on which side of
  `var.mount` the udev worker lands: the same Charly with the same stick booted cleanly several times
  the same day. `board/lite/usbmount-run-dir.sh` (run by `post-build-systemd.sh`) moves the lock to
  `/run/usbmount` and fails the build if the script still names `/var`; `tmpfiles.d/lite-var-run.conf`
  says `L+ /var/run`, which replaces such a directory with the link and sorts before `var.conf`, so
  its line is the one applied. `scripts/testcases/lite-unit-order-test.sh` checks both, and that no
  unit starting before `systemd-tmpfiles-setup` names `/var/run`. Not changed: usbmount mounts a stick
  inside `systemd-udevd`'s `PrivateMounts=` namespace, where the host never sees it (task 23).

## Measurements

Taken from the build tree and the QEMU boot (`scripts/lite-qemu-test.sh`, TCG, no KVM, on the
build host). *To be filled in from the first successful build.*

The left column is the busybox sibling the systemd product was built beside, and it is what makes
the right one mean anything: the table is the record of what systemd costs, not of how large the
image is. D-39 does not carry that sibling forward — nothing builds `ova-lite` any more, its
defconfig is deleted, and the column can only be filled from a branch that still has
`configs/ova-lite.config`. It stays here rather than being dropped, because the comparison is the
reason the numbers were wanted; the right column is the one a build of `x86_64-ova` fills in today.

| | `ova-lite` (busybox, not carried forward) | `x86_64-ova` (systemd) |
| --- | --- | --- |
| rootfs image, used | | |
| `target/` (`du -sh`) | | |
| systemd + udev + dbus binaries and libraries | — | |
| processes at idle | | |
| RSS at idle (top 10) | | |
| boot to `Startup finished` (PID 1) | — | |
| boot to `booted, OK` (S99SetupLEDs) / HTTP health | | |
| journal size cap | — | 32 MiB (`SystemMaxUse`) |

### What the two ARM builds cost (2026-09-06/07, the 8-core runner, 11 GB RAM)

The first builds of the two board products, made while they were still called `armv7l` and
`aarch64` (the release files therefore carry those names; `/VERSION` in both is already the
final `rpi3`/`rpi4`, and nothing but the file names changes with D-43).

| | `aarch64-rpi3` (then `armv7l`) | `aarch64-rpi4` (then `aarch64`) |
| --- | --- | --- |
| wall time | 345 min, cold, sharing the host with a second buildroot build | 120 min, incremental on an existing tree |
| build tree | ~35 GB | ~30 GB |
| release `.img` | 2,418,991,616 B | 2,418,991,616 B |
| release `.zip` | 288,940,144 B | 289,374,378 B |
| in-place update package | `…-ccu3.tgz`, 285,056,397 B | — (`board/rpi4/post-release.sh` builds none, as upstream) |

Two things the host taught, both worth keeping:

- **One buildroot build at a time.** Two at once on 8 cores and 11 GB is what turned a ~3 h cold
  build into 345 minutes, and it is what filled the 240 GB disk: each ARM product wants its own
  ~35 GB tree beside the x86 ones. The build scripts refuse to start while another
  `make PRODUCT=…` is running.
- **A disk-full during a build corrupts the tree rather than failing it cleanly.** The first
  aarch64 attempt died in `multilib32`'s `host-python3` with
  `pythread.h:37: unknown type name 'NATIVE_TSS_KEY_T'` — a half-written `pyconfig.h`, 74 seconds
  in, nowhere near an out-of-space message. Freeing space and deleting
  `build-<product>/build/multilib32-*` was the whole fix; the finished product's build tree is
  the thing to delete first, its release files being in `release/` already.

## Open for the maintainer

- The journal on the userfs versus SD wear (above).
- Remote syslog (`LOGHOST`) is gone with `S07logging`; `systemd-journal-upload` or a syslog
  forwarder would bring it back as a sub-option with a reason here.
- `systemctl enable`/`disable` at runtime writes `/etc/systemd/system`, which is on the read-only
  rootfs. Persistent disable (D-30, task 8) needs occulited to keep its own state on the userfs and
  apply it with `--runtime` at boot, or a writable `/etc/systemd/system` — not decided here.
- The system console: busybox init put a getty on tty2 (`askfirst`); with systemd, buildroot's
  `BR2_TARGET_GENERIC_GETTY_PORT` decides. Not needed for the HTTP checks; not set up here. The
  end-of-boot hint is already written to `/etc/issue` (→ `/run/issue`), so a getty would show it.
- Everything in [The boot screen and the end-of-boot message](#the-boot-screen-and-the-end-of-boot-message)
  is untested on a screen: it needs a box (or a QEMU run with a framebuffer) to say whether the
  splash text is legible over the console output that now shares `/dev/console` with it.
- The D-41 items that only a running box can settle, all of them:
  [the watchdog on a Pi](#the-hardware-watchdog) (the module is loaded after PID 1 arms itself),
  whether journald starting after the userfs mount costs anything measurable on the first boot
  ([the machine ID](#the-machine-id)), what `S47InitRFHardware`'s `stop()` leaves behind when the
  coprocessors are *not* sent to the bootloader, and — still open from the review — what
  `/bin/SetInterfaceClock` actually talks to.

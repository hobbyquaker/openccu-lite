# openccu-lite: the delta against upstream OpenCCU

This fork exists to build openccu-lite:
a Homematic CCU firmware without `ReGaHSS` and without the CCU WebUI. The radio
and wired stack — `rfd`, `hs485d`, `multimacd`, `hmipserver` — is taken from
upstream unchanged.

This file is the living index of every difference to `upstream/master`. It is
maintained per D-22 of the project roadmap, which is what keeps the weekly
rebase an afternoon and the eventual pull-request series a `git format-patch`
away.

Every entry has one of two statuses:

- **upstreamable** — the change stands on its own merits for a plain OpenCCU
  user, contains nothing openccu-lite-specific, and is destined to become a
  pull request against `OpenCCU/OpenCCU`. It must never depend on anything that
  only exists in this fork.
- **lite-only** — a new file, a new package, a new defconfig or an overlay of
  our own. Upstream has no use for it. It touches no upstream file.

The rule that produces this split is D-4/D-22: *an edit to an existing upstream
file is allowed only in a form upstream could take as-is* — honour a Kconfig
symbol that already exists, add a default-off guard, extend a generic mechanism.
Never a deletion, never a hard-coded assumption that only makes sense here.
Anything that cannot be written that way is done in our own overlay instead.

The fork's history was squashed on 2026-09-11 from 171 commits into 23 with the same tree;
the commits named below are the new ones. The history before the cleanup is kept as the tag
`archive/lite-2026-09-11`, and every new commit's `Squashes:` trailer lists the old commits
it replaces. The changes with an `Upstream: candidate` trailer come first, directly on
upstream: `git log --grep='^Upstream: candidate' upstream/master..lite`.

**The base is OpenCCU `3.89.11.20260919` since 2026-09-25** (task 233: lite's history squashed into area commits and
rebased onto the tag; the 129 commits before are the branch `lite-history-2026-09` on Gitea, and upstream carries
item 1 itself since 3.89.11, so its block is gone). Before: **OpenCCU `3.89.9.20260914` since 2026-09-15** (task 126; the branch before the
rebase is `archive/lite-2026-09-15` on Gitea). That release replaces `package/occu` with
`package/openccu-base`, which builds the base services from source, and lite's history on top
of the tag starts with **a marked block of four commits that are not lite's: the commits of
[OpenCCU/OpenCCU#4183](https://github.com/OpenCCU/OpenCCU/pull/4183)** (`284095298`, `b415eea92`,
`fb91f1b97`, `1d824213e` on the pull request's branch), cherry-picked unchanged. They add
`BR2_PACKAGE_OPENCCU_BASE_REGAHSS` and `BR2_PACKAGE_OPENCCU_BASE_WEBUI` (both default y, so
upstream's images are unchanged), which every lite config switches off. When jens merges the
pull request - he squash-merges - the block is swapped for his squash commit cherry-picked from
`upstream/master`, and the next tag rebase drops that one by patch id. The commit hashes in the
index below are those of the history before the rebase; `git log --grep` by subject finds the
rebased ones.

## Index

| # | Item | Status | Commit |
| --- | --- | --- | --- |
| 1 | ReGaHss and the WebUI are options of `package/openccu-base` (until 3.89.8: `package/occu` honours `BR2_PACKAGE_OCCU_WEBUI`) | **upstream pull request #4183**, carried as a block on the tag | `284095298`…`1d824213e` |
| 2 | `S50lighttpd` moves from the WebUI overlay to the base overlay | upstreamable | `90e0e5d67` (the S50lighttpd half; the `package/occu` half dropped with the package) |
| 3 | `overlay/lite` (`overlay/lite_oci` removed with the OCI product, task 142) | lite-only | `5dd1c9201`, `98edcbb7d` |
| 4 | The `oci-lite_amd64` product — **removed** (D-40, D-94, task 142); upstream's `oci_*` products are untouched | removed | `98edcbb7d` |
| 5 | CI workflow for the openccu-lite runner | lite-only | `b91004861` |
| 6 | `package/occulited` (service, lighttpd wiring, init script, tclrega shim; installs after `openccu-base`, and `board/lite/post-build.sh` stops the build when the shim is not `/lib/tclrega.so` or ReGaHss/the WebUI are in the image) | lite-only | `77d8d96d8`, (3.89.9 rebase) |
| 7 | `overlay/lite/etc/lighttpd/modules.conf` — base + `mod_magnet`, minus `mod_cgi` and its `conf.d/cgi.conf` include (task 18: the CGIs run through occulited; `board/lite/post-build.sh` removes the base overlay's `cgi.conf` from the image and points `server.pid-file` into `lighttpd.service`'s runtime directory) | lite-only, **review on rebase** | `5dd1c9201`, (this commit) |
| 8 | `scripts/lite-boot-test.sh` (the OCI image in Docker) — **removed** with the OCI product (task 142); its checks moved into `scripts/lite-qemu-test.sh` (item 11) | removed | `98edcbb7d` |
| 9 | `S62HMServer` sources `/etc/hmipserver.default` | **upstreamable** | `30c745cea` |
| 10 | The `x86_64-ova` product: `configs/x86_64-ova.config`, `board/x86_64-ova`, `overlay/lite_ova`, `kernel/6.18/lite.config`, `board/lite/post-build.sh` shared by every lite product | lite-only | `5bf66c1d9`, `f565cb167` |
| 9 | `overlay/lite/etc/config_templates/rfd.conf` — rfd on the loopback (D-29) | lite-only, **review on rebase** | `5dd1c9201` |
| 12 | systemd as init on every lite product (task 20, D-30): `BR2_INIT_SYSTEMD=y` in each config, `kernel/6.18/lite-systemd.config`, `overlay/lite` (units, addon generator, journald), `package/occulited`'s systemd hook, the QEMU test's guest checks | lite-only, **review on rebase** (the unit set) | `371d1478a`, `ecfd24f62`, `93f37c797` |
| 11 | `scripts/lite-qemu-test.sh` — boots a disk image headless in QEMU, checks the service through lighttpd | lite-only | `93f37c797` |
| 16 | `board/lite/pre-build-systemd.sh` + the overlay lines of every lite config (`configs/x86_64-ova.config`, `configs/aarch64-rpi3.config`, `configs/aarch64-rpi4.config`): merged-/usr copies of the overlays under the build dir, because buildroot refuses overlays with a real `/bin`/`/lib` once systemd selects `BR2_ROOTFS_MERGED_USR`. The previous copies also say which files left an overlay since the last build: those leave the target before the packages install, and a package that installs the same path (or has no file list) installs again, with one "run make again" stop (B-101; `scripts/testcases/lite-overlay-prune-test.sh`) | lite-only | `371d1478a` |
| 15 | `package/xe-guest-utilities`: `proc-xen.mount`, `xe-daemon.service`, `tmpfile.conf` — the files its `INSTALL_INIT_SYSTEMD` hook has referenced since upstream but never shipped (nobody built it with systemd); `S11xe-daemon`'s behaviour as units | **upstreamable** | `66251bf0c` |
| 14 | `configs/x86_64-ova.config`: `BR2_PACKAGE_HOST_QEMU=y` — `board/ova/post-image.sh` needs `qemu-img`, which upstream's `ova.config` gets only through nodejs' `select`; a config without nodejs fails at post-image (Error 127). Upstream's config should say it explicitly | **upstreamable** | `5bf66c1d9` |
| 17 | The aarch64 board products (D-43, D-39, D-33): `configs/aarch64-rpi3.config`, `configs/aarch64-rpi4.config`, `configs/aarch64-rpi5.config` (task 32, 2026-09-09), `board/{aarch64-rpi3,aarch64-rpi4,aarch64-rpi5}/post-release.sh` (D-44 copies of `board/rpi3`'s and `board/rpi4`'s with the lite names), `release/updatepkg/{aarch64-rpi3,aarch64-rpi4,aarch64-rpi5} -> rpi3`, the D-39/D-43 product map in `board/lite/post-build.sh` and in `package/recovery-system/external/board/post-build.sh`, `LITE_PRODUCTS` in `lite-version.mk` | lite-only | `d1ab5f82c`, `ffcc1a0cf`, `f565cb167`, `a3dadb5de` |
| 18 | Daemon tracking, restart-with-backoff and the init-script wrapper of the systemd products (B-3), the boot messages on the splash and the console (B-4) and the end-of-boot hint (B-5): `overlay/lite/usr/lib/systemd/{system/*.service,openccu-lite-initscripts}`, `overlay/lite/usr/libexec/occu/{initscript-wrapper,lite-psplash,lite-boot-message,lite-watchdog-marker}`, `board/lite/post-build-systemd.sh` | lite-only, **review on rebase** (the unit set and the table) | `371d1478a` |
| 19 | The D-41 unit review (task 22): unit conditions, the machine ID, the watchdog in PID 1, the LED merge, `lite-rf-stop`, the `triggerAlarm.tcl` stand-in | lite-only, **review on rebase** | `371d1478a` |
| 20 | **`package/openccu-base`'s (until 3.89.8 `package/occu`'s) `ln -snf /usr/bin/tclsh $(TARGET_DIR)/bin/tclsh` breaks Tcl on a merged-`/usr` target**: `/bin` *is* `/usr/bin` there, so the command replaces tcl's own `/usr/bin/tclsh -> tclsh8.6` with a link to itself and every Tcl script fails with `ELOOP` — including `setfirewall.tcl`, which `eQ3StartNetwork` runs at every boot without checking its exit code, so the system comes up with no firewall at all (openccu-lite B-11). Repaired for now in `board/lite/post-build-systemd.sh`; upstream's own fix would be to make the link conditional (`[ "$(readlink -f $(TARGET_DIR)/bin)" = "$(readlink -f $(TARGET_DIR)/usr/bin)" ] \|\| ln -snf …`). Hits anyone who builds OpenCCU with `BR2_INIT_SYSTEMD` | **upstreamable** | `371d1478a` |
| 21 | **`package/multilib32`'s loader link lands one directory too shallow on a merged-`/usr` target**: `ln -sf ../lib32/ld-linux.so.2 $(TARGET_DIR)/lib/` resolves into `/usr/lib32` instead of `/lib32` when `/lib` is a symlink to `usr/lib`, so `/lib/ld-linux*.so.*` — the interpreter path compiled into every 32-bit binary — dangles (openccu-lite B-12). Repaired in `board/lite/post-build-systemd.sh`; the same conditional would fix it upstream | **upstreamable** | `371d1478a` |
| 13 | `package/java-azul`: fontconfig/dejavu/liberation are dependencies only when selected (kconfig refused a config without them; upstream's configs select them, so a no-op there) | **upstreamable** | `cb137260a` |
| 12 | `.github/workflows/lite-release.yml` (draft, never run) and `scripts/lite-sbom.py` (CycloneDX from `make show-info`) — task 16 | lite-only | `b91004861` |
| 22 | The Proxmox LXC products (task 34): `configs/lxc-lite_amd64.config`, `configs/lxc-lite_arm64.config` (upstream's `lxc_*.config` plus the lite delta), `board/lxc-lite/{post-build,post-image,post-release}.sh`, `release/updatepkg/lxc-lite_* -> lxc_arm64`, the entries in `board/lite/post-build.sh`'s product map and `lite-version.mk`, the `lxc` journal default in `lite-journal-persist` | lite-only | `43e7ac901` |
| 23 | HSTS on the TLS sockets (task 36): `overlay/lite/etc/lighttpd/conf.d/hsts.conf`; the `/var/etc/lighttpd_hsts.conf` include in both `:443` blocks of `base/…/conf.d/proxy.conf` and the marker→include block in `base/etc/init.d/S50lighttpd` (since task 96 the function `hsts_conf`, with the clearing state: a marker of `0` sends `max-age=0` until `/etc/config/hstsClearUntil`, a marker without digits a week), both guarded by the fragment's existence (task 35's `httpsredirect.conf` and `check_certificate` edits in the same two files, `b16e76f6e`, `8740e47de`, were not listed here before) | the fragment lite-only; the two base edits **upstreamable** (default-off, guarded) | `eea828a62` |
| 24 | `BR2_TAR_OPTIONS="--no-same-owner"` in the top-level `Buildroot.config` and the nested ones of `multilib32` and the recovery system: a build as root in an unprivileged container cannot restore the owners stored in a source archive | **upstreamable** | `be2e70738` |
| 25 | `board/{rpi3,rpi4,rpi5}/boot.cmd`: `cgroup_enable=memory cgroup_memory=1` after the firmware's `${bootargs}`, which carry `cgroup_disable=memory` - the memory cgroup controller for systemd's `MemoryCurrent` and `Memory*=` limits (useful to any OpenCCU user running containers too) | **upstreamable** | (this commit) |
| 26 | The bare host name redirected to `<host>.<domain>` (task 74): `overlay/lite/etc/lighttpd/conf.d/fqdnredirect.conf`; the `/var/etc/lighttpd_fqdnredirect.conf` include in both `:443` blocks of `base/…/conf.d/proxy.conf` and `S50lighttpd`'s `fqdn_redirect` (start and reload; on port 80 it extends the HTTPS redirect's include), guarded by the fragment's existence; `mod_setenv` before `mod_redirect` in `overlay/lite/etc/lighttpd/modules.conf`, so redirects carry HSTS; `scripts/lite-lighttpd-redirect-test.sh` | the fragment, the module order and the test lite-only (the order: **review on rebase**, with item 7); the two base edits **upstreamable** (default-off, guarded) | `fdfd75b43`, `b7d6e4fe7`, (this commit) |
| 27 | `S62HMServer`: `HMIP_LOG_STDOUT=1` starts the JVM as a plain background child that keeps the script's stdout (instead of `start-stop-daemon -b`), writes the pid file from `$!` and skips the `LOGHOST` rewrite of the SYSLOG appender; the `hmipserver.default` files of item 9 are sourced at the top of `init()` now, and the log4j2 setup is a function, `setupLog4j2`, that a test can run | **upstreamable** (default-off) | `6395692d4` |
| 28 | hmipserver logs to the journal (task 83): `overlay/lite/etc/config_templates/log4j2.xml` (one Console appender on the stdout descriptor, every line prefixed with its syslog level), `HMIP_LOG_STDOUT=1` in `overlay/lite/etc/hmipserver.default`, `SyslogIdentifier=hmipserver` and `StandardOutput=journal` in `hmipserver.service`; `scripts/testcases/hmipserver-log4j2-test.sh` | lite-only, **review on rebase** (the template against upstream's `log4j2.xml`: logger names and levels) | `822d058ce` |
| 29 | Where the journal lives (task 85, modes `ram` and `persistent` on the userfs): `STORAGE=`, `TARGET=`, `RUNTIME_MAX_USE` and the product default (`ova`, `lxc`: persistent; `oci` dropped with task 142) in `overlay/lite/usr/libexec/occu/lite-journal-persist` (`PERSIST=` still read); `scripts/testcases/lite-journal-persist-test.sh` | lite-only | `ea8543225` |
| 30 | No log files beside the journal (task 84, D-59): `overlay/lite/etc/lighttpd/conf.d/access_log.conf` (the module without a destination; occulited's switch sets it); in `board/lite/post-build.sh` upstream `lighttpd.conf`'s `server.errorlog` replaced by `server.errorlog-use-syslog` (the build stops when the line is missing), buildroot's `usr/lib/tmpfiles.d/lighttpd.conf`, `lighttpd.annotated.conf` and `etc/logrotate.d/syslogd.conf` removed; `scripts/lite-log-guard.sh` run at the end of that post-build, `scripts/lite-log-inventory.sh` (the lab boot check), `scripts/testcases/lite-log-guard-test.sh`, the CI step | lite-only, **review on rebase** (the `server.errorlog` line; the lighttpd package's tmpfiles file) | `4c78b3eb2` |
| 32 | The status LED (task 95, D-63): `hss_led` and `82-hss_led.rules` removed in `board/lite/post-build.sh`; `dummy_rx8130` loaded only where `/bin/hss_led` is (`base/…/S02InitRTC`, `S47InitRFHardware`); `eQ3StartNetwork`'s blue blink only with the module's RX8130 and before `startupFinished` (`base`, `base-openccu_oci`); `overlay/lite/usr/libexec/occu/lite-status-led`, its `ExecStop` in `occu-leds.service`, `occulited.service.d/20-status-led.conf` | the removal, the script and the units lite-only; the three base edits **upstreamable** | (this commit) |
| 33 | multimacd's own log level (task 101): `LOGLEVEL_MULTIMACD` in `/etc/config/syslog`, read by `overlay/RFD/etc/init.d/S60multimacd` (`multimacdLogLevel`), falling back to `LOGLEVEL_RFD` when unset or not a level; `scripts/testcases/multimacd-loglevel-test.sh`, the CI step | **upstreamable** (a file without the key behaves as before) | (this commit) |
| 35 | The boot path's second pass (tasks 108, 116, 118, 135, 136; D-89, D-90): `S47InitRFHardware` waits for a route to a configured HB-RF-ETH and takes the board-serial fallback from eth0's MAC; `S48UpdateRFHardware` keeps the check but does not flash with `COPRO_UPDATE_AT_BOOT=no`; `eQ3StartNetwork` (`base`, `base-openccu_oci`) polls the link every 0.2 s; `eQ3StartNetwork` and `dhcp.script` call `checkInternet` only where it is installed, and `board/lite/post-build.sh` removes it; the prebuilt CA bundle (`board/lite/ca-prebuilt.sh`, `lite-ca-certificates`); the unit order (radio detection, lighttpd's stop wait, the clock gate, multimacd, `occu-init-rtc`, `occu-network`, the timers) and `scripts/lite-unit-refs.sh`; the addon generator without the name-order chain; `scripts/testcases/lite-boot-path-test.sh` | the five base-script edits **upstreamable** (the HB-RF-ETH wait and the MAC fallback change nothing where the network is up before S47 and eth0 holds the default route; the other three are off by default or only take effect without `checkInternet`); the rest lite-only | (this commit) |
| 34 | No smartd (task 111): `# BR2_PACKAGE_SMARTMONTOOLS is not set` in `configs/x86_64-ova.config`, `configs/lxc-lite_amd64.config`, `configs/lxc-lite_arm64.config`; `board/lite/no-smartd.sh` run at the end of `board/lite/post-build.sh` (the Pi products keep `smartctl` and lose the daemon, its unit, its enable links and its configuration); the `overlay/lite` drop-in `smartd.service.d/10-openccu-lite.conf` removed; `scripts/testcases/lite-smartd-test.sh`, the CI step | lite-only, **review on rebase** (smartmontools' installed file names) | (this commit) |
| 36 | The interface daemons confined (task 67; D-55, D-93): the users `rfd`, `hmipserver`, `multimacd`, `hs485d`, `hmlangw` (8110–8114) and the resource groups `raw-uart`, `eq3loop`, `mmd-bidcos`, `mmd-hmip` (8120–8123) in `package/occulited/occulited.mk`; `overlay/lite/usr/lib/udev/rules.d/60-openccu-lite-radio.rules`; `overlay/lite/usr/lib/tmpfiles.d/00-openccu-lite-radio.conf`; the units `rfd`, `multimacd`, `hmipserver`, `hs485d`, `hmlangw` as direct, sandboxed units with a `20-devices.conf` drop-in each (`board/lxc-lite/post-build.sh` drops the drop-ins); `overlay/lite/usr/libexec/occu/lite-radio-prep`; the confine test `scripts/testcases/lite-radio-confine-test.sh`, the CI step. (The transitional `init)` case in `S60multimacd`, `S61rfd` and `S62HMServer` and the helper `lite-radio-prep` of this item went again with item 38.) | lite-only | (this commit) |
| 37 | The radio chain's differential harness (task 129, D-83): `scripts/testcases/lite-radio-oracle-test.sh` runs upstream's S47InitRFHardware, S49hs485d, S60hs485d, S60multimacd, S61rfd, S62HMServer and S61hmlangw (plus lite's `lite-rfd-listen`) in a sandbox over the hardware matrix and compares their decisions with the expected files under `scripts/testcases/radio-oracle/<case>/` (the template `radio-oracle/templates/crRFD.conf` is OpenCCU-Base 3.89.9's `etc/config_templates/crRFD.conf`); the CI step; the harness's copy of the loopback line `radio-oracle/lite-rfd-listen`; the check unit `occu-radio-shadow-check.service` (`occulited radio check`, behind `/usr/local/etc/occulite/radio-shadow`) | lite-only, **review on rebase**: a changed decision of an upstream script fails a case; `--update` after reading the diff, and a new crRFD.conf template when OpenCCU-Base's changes | (this commit) |
| 38 | The radio stack in occulited, phase 2 (task 129, D-83, D-97): `occu-init-rf-hardware.service` runs `occulited radio run` (the detection, the plan and the render written to the system) and stops with `occulited radio stop`; the daemon units condition on `/run/occulite/radio/<daemon>.enabled` and run `occulited radio prep|ready|stopped <daemon>` as their root steps; `occu-init-hs485d.service` runs the loader's init pass directly; `occu-interface-clock.service` only with rfd (B-142); `occu-update-rf-hardware.service`, `occu-radio-shadow.service`, `lite-radio-prep`, `lite-rf-stop` and `lite-rfd-listen` are gone; **`board/lite/post-build-systemd.sh` removes `S47InitRFHardware`, `S48UpdateRFHardware`, `S49hs485d`, `S60hs485d`, `S60multimacd`, `S61rfd` and `S62HMServer` from the image** and the wrapper table has no row for them (an addon calling `/etc/init.d/S61rfd restart` fails, accepted); `InterfacesList.xml` is re-copied from the template as upstream does (D-97); the switch guarantee in `scripts/lite-qemu-test.sh` (an OpenCCU-shaped userfs with a LAN gateway boots with it) | lite-only. **Review on rebase:** the seven scripts stay in the overlays only as the harness's oracle (item 37); an upstream change in one of them shows as a failing harness case and is carried into occulited's `internal/radio` (the plan), not into the image | (this commit) |
| 39 | The radio stack in occulited, phase 4 (task 129, D-99): `occu-lgw-firmware-update.service` and `occu-set-lgw-key.service` run `occulited radio lgw-firmware` and `radio lgw-keys`; **`board/lite/post-build-systemd.sh` also removes `S58LGWFirmwareUpdate`, `S59SetLGWKey` and `/bin/setlgwkey.sh`** (no wrapper rows any more); the USB hotplug: `occu-radio-hotplug.service` (`occulited radio hotplug`) and `overlay/lite/usr/lib/udev/rules.d/61-openccu-lite-radio-hotplug.rules` | lite-only. **Review on rebase:** an upstream change in the two scripts or `setlgwkey.sh` is carried into occulited's `internal/radio/lgw.go` | (this commit) |
| 40 | The firewall is occulited's (task 157, D-105): `occu-firewall.service` loads `firewall-rules.json` at boot before the network; the lite post-build removes `setfirewall.tcl`, `libfirewall.tcl`, `libsecuritylevel.tcl` and `enforcesecuritylevel.tcl`; `eQ3StartNetwork` (`base`) calls `setfirewall.tcl` only where it is installed; `occu-network.service` orders after `occu-firewall.service` instead of B-152's `occu-init-host.service` | the `eQ3StartNetwork` guard **upstreamable** (it changes nothing where the script is installed); the rest lite-only | (this commit) |
| 41 | systemd with libseccomp (task 121): `BR2_PACKAGE_LIBSECCOMP=y` in every lite systemd config (`aarch64-rpi3/4/5`, `x86_64-ova`, `lxc-lite_amd64/arm64`), so Buildroot builds systemd with `-Dseccomp=enabled` and the units' and occulited's addon drop-in's seccomp lines are enforced | lite-only | this commit |
| 42 | /etc/init.d as the compatibility entry point only (task 115, D-80): **`board/post-build.sh` removes the init script of an optional package (`S40bluetoothd`, `S49xinetd`, `S50ser2net`, `S51nut`, `S59snmpd`, `S60openvpn`) on every platform whose `$BR2_CONFIG` does not set its `BR2_PACKAGE_*=y`**, and **`overlay/base/etc/init.d/S50sshd` and `S98crond` gain an `init` action** (sshd's `start()` split into `init()` + the daemon, exit 1 when sshd must not start; crond's existing `init()` exposed) so a service manager that starts the daemon itself can run the preparation alone; `board/lite/post-build-initscripts.sh` (split out of `post-build-systemd.sh`) removes `rcS`/`rcK` and ships a `-` row's wrapper without its script, the wrapper answers "ignored" for such a row before it looks for the script; `sshd.service` and `crond.service` are `Type=exec` with the daemon's command line (`ExecCondition=…S50sshd.script init`, `ExecStartPre=…S98crond.script init`); `scripts/testcases/lite-initscripts-test.sh` | the `post-build.sh` block and the two `init` actions are **upstreamable** (a Kconfig symbol honoured; an action busybox init never calls, and `start()` unchanged in effect), the rest lite-only. **Review on rebase:** a rebase that changes `S50sshd`'s or `S98crond`'s daemon line changes the unit's `ExecStart=` with it (the testcase pins both); a new optional package with an overlay init script gets a row in the `post-build.sh` loop | (this commit) |
| 42 | hmipserver's HTTP port on the loopback (B-89): `package/lite-bindlo` (an `LD_PRELOAD` shim, `/usr/lib/openccu-lite/libbindlo.so`, turns a wildcard `bind()` to a port in `BINDLO_PORTS` into `::ffff:127.0.0.1` / `127.0.0.1`), selected in every lite systemd config and set in `hmipserver.service` (`LD_PRELOAD`, `BINDLO_PORTS=39292`); hmipserver has no bind-address setting for this port. occulited checks the port after the start and warns | lite-only | this commit |
| 43 | Wi-Fi beside the network start (task 89): the lite `etc/network/interfaces` names `eth0` only (upstream's hook runs one interface and unloads the Wi-Fi driver when there is no `wpa_supplicant.conf`); `occu-wifi.service` runs `occulited wifi up\|reload\|down` after `occu-network`; `occu-wpa@.service` (wpa_supplicant with occulited's `/etc/config/wpa_supplicant.conf`, its control socket for the group `occulite`) and `occu-wifi-dhcp@.service` (udhcpc with `lite-wifi-dhcp`: the address, the default route with the preference's metric, resolvconf; Ethernet's netconfig untouched); `sysctl.d/60-openccu-lite-network.conf` (`ignore_routes_with_linkdown=1`). Upstream's `dhcp.script` and `eQ3StartNetwork` are unchanged: their Ethernet routes (10 by DHCP, 0 static) stay, Wi-Fi's take 5 or 600 | lite-only | this commit |
| 44 | The image's SBOM (task 179): `scripts/lite-sbom.py` rewritten for CycloneDX 1.6 with the licence texts (each once) and every source of the image - the target packages of `show-info` with their licence files, OpenCCU-Base split into its programs, libraries and JARs (with the JARs' libraries), occulited's Go modules and UI packages, linux-firmware per WHENCE entry, the inner builds of `multilib32` and the recovery system - and a `--check` that fails the build on a gap `buildroot-external/sbom-exceptions.txt` does not name; `board/lite/post-build-sbom.sh`, last in every lite config's post-build list, writes `/usr/share/openccu-lite/sbom.cdx.json.gz`. **The top `Makefile` (upstream's) gets a `build-<product>/show-info.json` rule** that `build` runs first, as it runs `legal-info`. `lite-release.yml` attaches the image's SBOM and one sources archive per release (the products' `legal-info` sources merged) | lite-only, plus the Makefile rule | `t179-sbom` |
| 45 | The board LEDs once the radio is known (task 158): `overlay/lite/usr/libexec/occu/lite-board-leds` (the LED lines of `S99SetupLEDs`: `HM_LED_*_MODE2`, `disableOnboardLED`, the HM-LGW blue; MODE1 and the HM-LGW yellow at stop) run by `occu-board-leds.service` `After=occu-init-rf-hardware.service`; `occu-leds.service` stays the boot-finished gate and still runs the whole `S99SetupLEDs`, which writes the same triggers again; `scripts/testcases/lite-board-leds-test.sh`, `lite-unit-order-test.sh` | lite-only; `S99SetupLEDs` byte-identical, **review on rebase** (its LED lines against `lite-board-leds`) | (this commit) |
| 46 | The recovery system's install log for the next boot (task 145, D-64): **`package/recovery-system/.../etc/init.d/S90AutoUpdate` gains `save_install_log()`**, called in both unattended update paths (the staged `/usr/local/.firmwareUpdate` and a USB `ccu-update.bin`) after the update, on success and on failure, while the userfs is still read-write - it copies `/tmp/fwinstall.log` to `/usr/local/var/recovery/<UTC time>.log` (0644), best effort, never failing the update or the reboot; occulited carries every such file into the journal at its next start (identifier `recovery`) and removes it. Not `/usr/local/tmp`: upstream's `S06InitSystem` empties it at every boot (B-137, D-107). `scripts/lite-log-inventory.sh`'s exception follows; `scripts/testcases/lite-recovery-log-test.sh` runs the function in a sandbox | the script edit is **upstreamable** (a persistent copy of the last update's log is useful on a plain OpenCCU too, where nothing removes it: one small file per update), the rest occulited's. **Review on rebase:** a rebase that changes how S90AutoUpdate ends an update keeps the call between `rm -f /usr/local/.firmwareUpdate` and the userfs remount; the testcase pins both call sites. The web UI's `firmware_update.cgi` path has no file log (fwinstall's output is the browser's) and is not covered | (this commit) |
| 47 | Writable extension directories for addons (task 97, D-66): `occu-extension-dirs.service` and `overlay/lite/usr/libexec/occu/lite-extension-dirs` mount `/firmware/rftypes` writable before rfd and the addons — an overlay with upper and work on the userfs (`/usr/local/etc/config/extensions/rftypes/`), or a copy of the image's files bound over the directory where the kernel has no overlayfs; `kernel/6.18/lite.config` gains **`CONFIG_OVERLAY_FS=y`** for every lite kernel (the x86_64 defconfig has no overlayfs, the Pi defconfigs a module); `scripts/testcases/lite-extension-dirs-test.sh`. With it, occulited's policy drop-in takes `CAP_SYS_ADMIN` from every root addon unit, so no addon remounts the system partition | lite-only | see the log |
| 48 | No ntpdate (task 114): `# BR2_PACKAGE_NTP is not set` in every lite product config (`aarch64-rpi3`, `aarch64-rpi4`, `aarch64-rpi5`, `x86_64-ova`, `lxc-lite_amd64`, `lxc-lite_arm64`); chronyd sets the clock (`lite-chrony`, no one-shot sync) and nothing calls `ntpdate`. The shared `Buildroot.config` keeps it for the upstream products, the recovery system's own config too; base `S46chronyd` unchanged (renamed to `.script`, run by no unit). `lite-unit-order-test.sh` checks the configs | lite-only | (this commit) |
| 49 | The journal's copies on a USB stick (task 216): `TARGET=usb:<label>/<dir>` in `/etc/config/journal`, ram-sync only - `lite-journal-sync` looks the stick up by its filesystem label (udev's `ID_FS_LABEL`) among `/media/usb1…8` at every copy and skips the copy without it, `attach`/`detach` for `occu-usb-mount@.service` (`ExecStartPost=`/`ExecStop=` before the unmount; at shutdown the detach waits for `occu-journal-sync`'s own last copy); `lite-journal-persist` mounts nothing for a stick, refuses persistent on one and writes the fallback while it is missing; `scripts/testcases/lite-journal-{sync,persist}-test.sh`, `lite-usb-mount-test.sh` | lite-only | (this commit) |

## 1. ReGaHss and the WebUI are options of `package/openccu-base`

**Status: upstream since OpenCCU 3.89.11** (#4183 merged; nothing of it is carried any more). Before: the upstream pull request [OpenCCU/OpenCCU#4183](https://github.com/OpenCCU/OpenCCU/pull/4183),
carried as a marked block of its four commits directly on top of the tag `3.89.9.20260914`, before
lite's own commits; the switch itself is lite's commit *"lite configs: ReGaHss and the WebUI off
through package/openccu-base's options"*. **Files:** `buildroot-external/package/openccu-base/Config.in`,
`openccu-base.mk`, `S70ReGaHss` (moved from `overlay/WebUI`), the three `monitrc` variants;
lite's seven `configs/*.config`.

Until 3.89.8 this item was `package/occu` honouring its own `BR2_PACKAGE_OCCU_WEBUI` (the
symbol existed and did nothing; the fork's commit `90e0e5d67` wrapped the ReGaHss and WebUI
installs in it). 3.89.9 replaces `package/occu` with `package/openccu-base`, which builds the
base services from source and had no switch at all: it always installed `/www`, `/bin/ReGaHss`
and `/lib/tclrega.so`. The pull request adds two options in the package's own style:

- `BR2_PACKAGE_OPENCCU_BASE_REGAHSS` (default y): `/bin/ReGaHss`, `/etc/init.d/S70ReGaHss` (the
  script moved from `overlay/WebUI` into the package so that the package decides) and
  `/lib/tclrega.so`, the Tcl extension that talks to it;
- `BR2_PACKAGE_OPENCCU_BASE_WEBUI` (default y, depends on REGAHSS): `/www`, the template
  substitution and the `fileupload.ccc` permission. Without it only the `/www/addons` link is
  installed, which addons publish their pages through.

Both are hidden for compat-libraries builds (`multilib32`). The Tcl `homematic` package,
`tclrpc.so`, `/firmware`, `/opt` and the device types stay in every case, CMake still
generates the WebUI (`BUILD_WEBUI_AND_DEVICETYPES` also builds the device types), and
`/www/rega/licenseinfo.htm` is generated without the WebUI too - jens-maus asked for the license
information in every image. (lite's post-build removes it again since task 179: lite's licence
information is its SBOM, `/usr/share/openccu-lite/sbom.cdx.json.gz`, and the file is eQ-3's CCU3
list of 2018.) `monitrc`'s ReGaHss check skips itself when `/bin/ReGaHss` is not
there (CodeRabbit's review). With both options on - every upstream defconfig - the installed set
is byte-identical to 3.89.9's.

Lite sets both to `n` in every product config. The upstream `tclrega` package that the configs
used to switch off with `# BR2_PACKAGE_TCLREGA is not set` no longer exists; REGAHSS off covers
it, and `package/occulited` installs its own `/lib/tclrega.so` (item 6) after `openccu-base`.
The block is swapped for jens' squash commit once the pull request is merged; until then
`git log --format=%s 3.89.9.20260914..lite | head -4` shows the four subjects.

## 2. `S50lighttpd` moves from the WebUI overlay to the base overlay

**Status:** upstreamable. **Commit:** `90e0e5d67`.
**Files:** `buildroot-external/overlay/WebUI/etc/init.d/S50lighttpd` →
`buildroot-external/overlay/base/etc/init.d/S50lighttpd`.

lighttpd is not part of the WebUI. It serves the addon web interfaces below
`/addons`, the XML-RPC ports of `rfd`/`hs485d`/`HMServer`, and the error pages;
`BR2_PACKAGE_LIGHTTPD` is enabled unconditionally in `Buildroot.config`. Its
init script living in `overlay/WebUI` means a product that does not include that
overlay gets no web server at all.

Every product defconfig lists `overlay/base` before `overlay/WebUI` in
`BR2_ROOTFS_OVERLAY`, so the move is a no-op for all fourteen existing
products. The ReGa-specific pieces stay in `overlay/WebUI` where they belong:
`etc/lighttpd/conf.d/auth.conf` (`auth.backend = "rega"`), `etc/rega_http.port`,
`etc/init.d/S70ReGaHss`. `S50lighttpd` already guards the `auth.conf` include
with a file test, so it behaves correctly when the WebUI overlay is absent.

**Why upstream wants this:** it is a file move with no behavioural change that
makes `BR2_PACKAGE_OCCU_WEBUI=n` (item 1) actually produce a working system.

## 3. `overlay/lite`

**Status:** lite-only. **Commits:** `5dd1c9201`, `98edcbb7d`.

A new overlay directory, appended to `BR2_ROOTFS_OVERLAY` by the openccu-lite
defconfigs only (its OCI sibling `overlay/lite_oci` went with the OCI product, task 142). It
contains nothing but replacements for upstream files that assume a WebUI, a `ReGaHss` on 8183 or
a monit — replacement by overlay ordering, which is why no upstream file is edited.

| File | Replaces | Why |
| --- | --- | --- |
| `lite/etc/lighttpd/conf.d/webui.conf` | `base/…/webui.conf` | the upstream file proxies everything that is not `/config/ /webui/ /ise/ /api/ /tools/ /pda /addons` to `127.0.0.1:8183`, which is ReGaHss. Nothing listens there. Also drops the Tailscale proxy block. |
| `lite/etc/lighttpd/conf.d/webui_remoteapi.conf` | `base/…/webui_remoteapi.conf` | D-29: the interface processes are not published to the LAN. Emptied, not deleted, because `S50lighttpd` includes it by name. |
| `lite/etc/lighttpd/conf.d/webui_remoteapi_notready.conf` | same | as above; it also rewrites to `/api/notready.cgi`, which lives in `overlay/WebUI-openccu`. |
| `lite/www/index.html` | — | a document root that answers with something rather than a 404 until `occulited` (roadmap task 4) serves `/`. |

## 4. The `oci-lite_amd64` product — removed

**Status:** removed (task 142, D-94). **Commit:** `98edcbb7d` (added).

The first openccu-lite product, derived from `oci_amd64`. D-40 took it out of the product set; D-94
(2026-09-16) dropped it: it ran busybox init, so it had no units to confine (D-55 point 8), and
LXC (`lxc-lite_amd64`, `lxc-lite_arm64`) is the container product. Task 142 removed
`configs/oci-lite_amd64.config`, `board/oci-lite/`, `overlay/lite_oci/`,
`release/updatepkg/oci-lite_amd64/`, `scripts/lite-boot-test.sh` and the CI steps that used them,
and restored upstream's `board/oci/post-image.sh` (the lite image name it had been given for this
product). Upstream's own OCI files — `configs/oci_*.config`, `board/oci/`,
`overlay/base-openccu_oci/`, `release/updatepkg/oci_*` and the upstream workflows — stay as
upstream has them (D-22); `eQ3StartNetwork` in `base-openccu_oci` keeps the upstreamable edits of
items 32 and 35. Whoever wants a CCU in Docker runs OpenCCU's own OCI image.

## 5. CI workflow for the openccu-lite runner

**Status:** lite-only. **Commit:** `b91004861`.
**Files:** `.github/workflows/lite-build.yml`.

A build workflow for the self-hosted runner described in `BUILDHOST.md`,
written to run unchanged on Gitea Actions today and on GitHub Actions from
release day (D-24). Upstream has its own CI; this is additional, not a
replacement.

## Not yet done, and why it is written here rather than discovered later

- **The XML-RPC proxy drop-ins are neutralised, not deleted.**
  `lite/etc/lighttpd/conf.d/webui_remoteapi*.conf` are empty files rather than
  removals, because `S50lighttpd` includes them by name. Making the include
  conditional in `S50lighttpd` would be an upstreamable change and is the better
  end state; it is not needed to boot.
- **`cronBackup.sh` still calls `/bin/triggerAlarm.tcl`** on failure, and that
  script is now deleted. The call is redirected to `/dev/null` in cron, so the
  failure is silent. It wants replacing by the notification endpoint of roadmap
  task 12.
- **hmipserver still binds `:::39292` and, on a system with radio hardware, `rfd`
  would bind `0.0.0.0:32001` in any image built before item 9.** D-29 is only
  half done: the lighttpd proxies are gone and `rfd` is on the loopback from
  the next build, but `Legacy.BindAddress=127.0.0.1` for hmipserver needs a
  `sed` line in `S62HMServer` behind a default-off marker rather than a copy of
  a 63-line vendor template. It belongs with the services.d work of roadmap
  task 8.
- **Kernel hardening options** (`CONFIG_USER_NS`, `CONFIG_PID_NS`,
  `CONFIG_SECCOMP`, AppArmor) had nothing to attach to in the OCI product,
  which built no kernel; `x86_64-ova` and the Pi products set them (item 10).

## 6. `package/occulited`

**Status:** lite-only. **Files:** `buildroot-external/package/occulited/`,
`buildroot-external/Config.ext.in` (the upstream hook for external packages,
empty upstream), and every lite product config.

A `golang-package` built from a source archive of the occulited repository
at a pinned commit (`OCCULITED_VERSION`), vendored by buildroot's
go-post-process at download time. It installs `/usr/bin/occulited`,
`/etc/lighttpd/conf.d/occulited.conf`, `/etc/lighttpd/occulite-gate.lua`, `/etc/occulite/catalog.json`
(the bundled addon catalogue, the first default index URL),
the units `occulited.service` and `occulited-helper.service` (the busybox
init script `S48occulited` went with task 187) and `/lib/tclrega.so` — the clean-room shim that
answers the addon session check, compiled from `deploy/tclrega/tclrega.c` with
the target toolchain. The product config leaves upstream's `tclrega.so` out
with `BR2_PACKAGE_OPENCCU_BASE_REGAHSS` (item 1; until 3.89.8 by deselecting
the `tclrega` package) and enables `BR2_PACKAGE_LIGHTTPD_LUA` for
`mod_magnet`. Bumping: change `OCCULITED_VERSION`, run
`make occulited-source`, copy the reported hash into `occulited.hash`.

**Since the 3.89.9 rebase (task 126) two guards protect the shim.** `package/openccu-base`
installs the real `tclrega.so` to the same `/lib/tclrega.so` whenever REGAHSS is on, and
buildroot installs packages in dependency order, so `occulited` depends on `openccu-base` and
its install always comes last. And `board/lite/post-build.sh` stops the build when
`/lib/tclrega.so` does not name `/var/run/occulite/sessions` (the shim does), when
`/bin/ReGaHss`, `/etc/init.d/S70ReGaHss` or a WebUI tree (`/www/webui`, `config`, `api`,
`ise`, `pda`) is in the image, or when `/www/rega` is (the step removes `licenseinfo.htm` and the
directory first, task 179).
`merge_config.sh` drops a symbol it does not know without a word; the guards are what makes the
next rename of an option visible instead of a system whose addon settings pages refuse every
session.

## 7. `overlay/lite/etc/lighttpd/modules.conf`

**Status:** lite-only, review on rebase. The base `modules.conf` with
`"mod_magnet"` added to `server.modules`. lighttpd accepts `server.modules`
only at global scope, and the only place the lite tree can reach global scope
without editing an upstream file is an overlay copy of this file. On every
rebase, diff it against `overlay/base/etc/lighttpd/modules.conf` and carry
upstream's changes over. `overlay/lite/etc/lighttpd/conf.d/webui.conf` (item 3)
includes `conf.d/occulited.conf` at the end.

## 9. `overlay/lite/etc/config_templates/rfd.conf`

**Status:** lite-only, review on rebase. **Commit:** `5dd1c9201`.

A copy of `overlay/RFD/etc/config_templates/rfd.conf` with one line added,
`Listen IP = 127.0.0.1`, so that `rfd` binds `127.0.0.1:32001` instead of
`0.0.0.0:32001` (D-29). Verified on the test system that `rfd` honours the setting.
`S61rfd` copies the template into `/etc/config` on first boot only, so an
existing `/etc/config/rfd.conf` is left alone — which is the right behaviour for
an in-place firmware update.

It is a copy of an upstream file and will need re-reviewing whenever upstream
changes the template. That is accepted here because the file is 26 lines and
almost static; the same trick is explicitly *not* used for `crRFD.conf`, which
is a 63-line vendor file that changes with every occu release.

## 12. systemd as init (task 20, D-30)

**Status:** lite-only; the unit set is a **review item on every rebase**. **Files:**
`buildroot-external/configs/x86_64-ova.config` and the two aarch64 configs of item 17 (each carries
`BR2_INIT_SYSTEMD=y` with every `BR2_PACKAGE_SYSTEMD_*` sub-option off and eudev replaced by
systemd-udevd), `buildroot-external/kernel/6.18/lite-systemd.config`,
`buildroot-external/overlay/lite/`, `buildroot-external/board/lite/post-build.sh` (the D-31
product map), `package/occulited/occulited.mk` (`OCCULITED_INSTALL_INIT_SYSTEMD`, buildroot picks
it by `BR2_INIT_*`), `scripts/lite-qemu-test.sh`.

systemd arrived as a second product, `ova-lite-systemd`, beside the busybox `ova-lite`, so that
nothing tested on busybox init changed while it was being built. D-39 ended that split: systemd is
the product, the busybox variant is not carried forward, and what is left is named for what it is
— `x86_64-ova`. `configs/ova-lite.config` and `release/updatepkg/ova-lite` are gone with the
variant, and so is `board/ova-lite-systemd/post-release.sh`, which was a symlink into the directory
that is now `board/x86_64-ova/` and holds the real script. Every lite product runs systemd from
here on; there is no busybox-init lite product left to keep a change safe from. What is built, the
unit that replaces each init script, the addon generator (D-36), the journal on the userfs and the
measurements are in [systemd-scope.md](systemd-scope.md).

Why it is the largest lite-only delta and how the rebase copes: buildroot's systemd does not run
`/etc/init.d/S*`, so every script the lite image keeps has a unit in `overlay/lite` that
names it: the one-time setup scripts run as they are (`ExecStart=/etc/init.d/SXX.script start`,
`Type=oneshot`), the daemons are started by their units directly (task 115, D-80: `Type=exec`
with the daemon's own command line, the script's `init` action as `ExecStartPre=`/`ExecCondition=`
where it has one — the radio daemons' preparation is occulited's, item 38). The scripts
themselves are upstream's, unchanged except for the `init` cases of item 40; a rebase that changes
a script changes the unit's behaviour with it. A rebase that **adds, renames or deletes** a script in `overlay/base/etc/init.d/`,
`overlay/RFD/etc/init.d/`, `overlay/base-openccu/etc/init.d/` or `package/*/S*` needs the table in
`systemd-scope.md` updated: that diff is the review item. The two real units (`hmlangw`,
`qemu-guest-agent`) carry their script's `start()` inline because the packages
install the script for busybox init only; diff them against `package/*/S*` as well. Three files
override buildroot's own units by name (`chrony.service`, `lighttpd.service`, `sshd.service`) and
one overlay file shadows an upstream script (`bin/setclock`).

No upstream file is edited for this beyond one D-4-shaped touch:
`buildroot-external/package/recovery-system/external/board/post-build.sh` carries the same D-31
product map as `board/lite/post-build.sh`, because `fwinstall.sh` runs inside the recovery and
compares the *recovery's* `/VERSION` against the image — a recovery that says `x86_64-ova` while
every lite image says `ova` refuses every update, for ever (B-27). The two maps must be changed
together. The `/VERSION` rewrite itself and the `OCCULITED_INSTALL_INIT_SYSTEMD` hook are in files
the fork owns.

## 18. Daemon tracking, restart policy and the init-script wrapper (B-3, B-4, B-5)

**Status:** lite-only; the unit set and the script→unit table are a **review item on every
rebase**. **Files:** `buildroot-external/overlay/lite/usr/lib/systemd/system/*.service`,
`buildroot-external/overlay/lite/usr/lib/systemd/openccu-lite-initscripts`,
`buildroot-external/overlay/lite/usr/libexec/occu/{initscript-wrapper,lite-psplash,lite-boot-message,lite-watchdog-marker}`,
`buildroot-external/overlay/lite/usr/lib/systemd/system-preset/50-openccu-lite.preset`,
`buildroot-external/board/lite/post-build-systemd.sh`,
`buildroot-external/board/lite/post-build-initscripts.sh`, `scripts/testcases/lite-initscripts-test.sh`.

Nothing upstream is edited for the wrapper: the init scripts are only renamed to `<name>.script`
in the target tree and given a wrapper at the old path (the `init` cases of item 40 are the one
edit to two of them). A `-` row's script is not shipped; the wrapper alone answers for it.
[systemd-scope.md](systemd-scope.md#essential-daemons-tracked-and-restarted) has the design; the
short version is three lite-only decisions a rebase has to keep in mind:

- every daemon unit tracks its daemon (`Type=exec` in the foreground, or `Type=forking` with a
  real `PIDFile=`) and none of them carries `RemainAfterExit=yes` any more, with
  `Restart=always` + `RestartSec=2` + `RestartSteps=8` + `RestartMaxDelaySec=300` and
  `StartLimitIntervalSec=0`. **A rebase that changes what an init script starts changes the unit's
  `ExecStart` with it** — the units that name a binary directly (`lighttpd-angel`, `hmlangw`) are
  the ones to diff against the script;
- `/usr/lib/systemd/openccu-lite-initscripts` maps every wrapped init script to its unit. A script
  that a rebase adds, renames or deletes has to be added, renamed or deleted there too, or a
  hand-invoked `restart` starts a daemon outside systemd again — which is what B-3 was;
- `board/lite/post-build-systemd.sh` does the renaming and the `/etc/issue → /run/issue` link, and
  warns when a table entry has no script or names a unit that is not in the image.

Upstream has no systemd product, so none of this is upstreamable as it stands. The one piece that
would be worth offering upstream if OpenCCU ever grows one is the wrapper itself: it is generic
(name → unit through a table) and nothing in it is lite-specific.

## 19. The D-41 unit review (task 22)

**Status:** lite-only; a **review item on every rebase** where it mirrors upstream logic.
**Files:** `buildroot-external/overlay/lite/usr/lib/systemd/system/*.service` (conditions,
`occu-leds.service`, `occu-machine-id{,-store}.service`),
`buildroot-external/overlay/lite/usr/libexec/occu/{lite-machine-id,lite-rf-stop}`,
`buildroot-external/overlay/lite/bin/triggerAlarm.tcl`,
`buildroot-external/overlay/lite/etc/systemd/system.conf.d/lite-watchdog.conf`,
`buildroot-external/overlay/lite/usr/lib/systemd/{system-preset/50-openccu-lite.preset,openccu-lite-initscripts}`,
`buildroot-external/board/lite/post-build.sh` (the `triggerAlarm.tcl` guard).

Roadmap task 22 reviewed every `occu-*` unit against what the script it wraps does and which of
the D-39 products needs it; D-41 is the maintainer's answer, and
[systemd-scope.md](systemd-scope.md#conditions-which-units-run-where-d-41) has the result. **No
upstream file is edited**: `S01USBGadgetMode`, `S02InitRTC`, `S11InitLEDs`, `S47InitRFHardware`,
`S99SetupLEDs`, `cronBackup.sh` and `checkBadBlocks.sh` stay byte-identical, and what changed is
which unit runs them, when, and with which conditions. (Since item 38 `S47InitRFHardware` is not
in the image at all; occulited's detection replaced it.) (Item 32 later guards the `dummy_rx8130`
load in `S02InitRTC` and `S47InitRFHardware`.)

Three places where lite logic sits next to upstream logic and a rebase has to look at both:

- **`occulited radio stop`** is `occu-init-rf-hardware.service`'s `ExecStop` (item 38; before it
  `lite-rf-stop`). With a staged firmware update it does what `S47InitRFHardware`'s `stop()` did
  (the bootloader handover per node, the HB-RF LED driver unloaded); without one only the HB-RF-ETH
  disconnect. A rebase that changes that `stop()` has to be read against occulited's
  `internal/radio/stop.go`.
- **`occu-leds.service`** is the boot-finished gate; the early "booting" light it dropped with
  `S11InitLEDs` is the identical block inside `S02InitRTC`'s RX8130 branch. A rebase that changes
  either script changes that assumption. Since task 158 the board LEDs are set earlier by
  `occu-board-leds.service` (`lite-board-leds`, the LED lines of `S99SetupLEDs` copied); a rebase
  that changes those lines in `S99SetupLEDs` changes `lite-board-leds` too (item 45).
- **`bin/triggerAlarm.tcl`** is a shell stand-in under upstream's name, because upstream callers
  that stay in the image (`cronBackup.sh`) call it; `board/lite/post-build.sh` deletes the file
  only when it is not ours (`grep -q openccu-lite`). A rebase that adds a caller gets the journal
  entry for free; a rebase that brings ReGa back would drop the stand-in instead.

The `checkBadBlocks.sh` timer, the busybox watchdog feeder and `occu-init-leds.service` are gone
from the lite products only — the scripts and the busybox applet are untouched, so upstream's
busybox-init products behave exactly as before.

## 17. The two aarch64 board products (D-43, D-39, D-33)

**Status:** lite-only. **Files:** `buildroot-external/configs/aarch64-rpi3.config`,
`buildroot-external/configs/aarch64-rpi4.config`,
`buildroot-external/board/aarch64-rpi3/post-release.sh` and
`buildroot-external/board/aarch64-rpi4/post-release.sh` (symlinks),
`release/updatepkg/aarch64-rpi3` and `release/updatepkg/aarch64-rpi4` (symlinks to `rpi3`, as every
board does), plus small edits to files this fork already owns —
`buildroot-external/board/lite/post-build.sh` and `lite-version.mk` — and the same product map in
`buildroot-external/package/recovery-system/external/board/post-build.sh`.

D-43 is why there are two of them. openccu-lite ships two architectures, x86_64 and aarch64, and
there is no 32-bit ARM product — but aarch64 needs two images, because upstream's `rpi3` and `rpi4`
are two *boards*, not two architectures. Both are `BR2_aarch64=y`; what separates them is the
device trees, the `rpi-firmware` variant (`BOOTCODE_BIN` + `VARIANT_PI` against `VARIANT_PI4`), the
u-boot version and fragment, `rpi-eeprom` on the Pi 4 only, the recovery fragment
(`recovery_rpi3.config` against `recovery_rpi4.config`) and the `multilib32` fragment
(`multilib32_arm_a53.config` against `multilib32_arm_a72.config`). The lite products inherit that
split unchanged: `aarch64-rpi3` is the CCU3 class — CCU3, CM3, Raspberry Pi 3 — and `aarch64-rpi4`
is the Pi 4 class, exactly as upstream splits them.

The earlier name `armv7l` for the first of the two, and the bug it produced — B-9, "the product
named armv7l builds an aarch64 rootfs" — were a misunderstanding, not a build error. Nothing was
ever wrong with the image. eQ-3's 32-bit ARM addon binaries keep running on both boards the way
they do upstream, through `package/multilib32` and the `/lib32` tree it installs (item 21).

`aarch64-rpi3.config` is `rpi3.config` and `aarch64-rpi4.config` is `rpi4.config` with
exactly the delta that made `x86_64-ova.config` out of `ova.config`: `BR2_PACKAGE_OCCU_WEBUI`
off, `package/occulited` on (with `lua`/`mod_magnet`, upstream `tclrega` off), the D-23 block of
`is not set` lines, the `lite` overlay through `board/lite/pre-build-systemd.sh`
(item 16 — systemd's merged `/usr`), `board/lite/post-build.sh` and `post-build-systemd.sh`
appended to the post-build list, `BR2_INIT_SYSTEMD=y` with every `BR2_PACKAGE_SYSTEMD_*`
sub-option off and eudev replaced by systemd-udevd, and `kernel/6.18/lite.config` +
`lite-systemd.config` after the board's own fragments. `BR2_PACKAGE_HOST_QEMU` (item 14) is *not*
needed here: `board/rpi3/post-image.sh` builds the card image with `mkfs.ext4` and `genimage`,
never `qemu-img`.

**No upstream board file is touched and nothing board-specific is copied.** The configs point
straight at `board/rpi3` / `board/rpi4` for `kernel.config`, the device trees, u-boot, `boot.cmd`,
`cmdline.txt`, `config.txt`, `genimage.cfg` and `post-image.sh`; the `patches` directory and the
recovery-system config fragment (`recovery_rpi3.config` / `recovery_rpi4.config`) stay upstream's
as well. `board/aarch64-rpi3` and `board/aarch64-rpi4`
contain nothing but a `post-release.sh` symlink, because the Makefile derives `BOARD_DIR` from the
product name and upstream's `post-release.sh` derives every artifact name from its `$2` — the same
trick the removed `board/oci-lite` used for `post-image.sh` (item 4). A rebase that changes the
rpi boards changes these products with it, for free
— including the step that only `board/rpi3/post-release.sh` has: it packs the in-place CCU3 update
from `release/updatepkg/aarch64-rpi3`, so `aarch64-rpi3` produces `OpenCCU-<version>-ccu3.tgz`
beside its card image and `aarch64-rpi4` does not.

Two package-set decisions of our own, both written into the configs:

- the per-board UPS, fan and display daemons D-23 names explicitly (`susvd`, `piusvd`, `picod`,
  `strompi2d`, `pidesktopd`, `argononed`, `raspi-fanshim`, and `wiringpi` which the last one
  depends on) are `is not set`. Beside D-23, every one of them defines only
  `<PKG>_INSTALL_INIT_SYSV`, so with systemd as init buildroot installs nothing at all for them:
  keeping them would ship six daemons that can never start;
- the Wi-Fi stack of upstream's Pi defconfigs **stays**. `x86_64-ova` drops it for a board-specific
  reason ("a VM has neither"), which does not hold here, and D-23's exception list keeps
  `wpa_supplicant` (to be trimmed hard, not dropped). The **Bluetooth stack goes** (D-54,
  2026-09-12): BlueZ and the Pi's Bluetooth firmware are `is not set`.

`board/lite/post-build.sh`: the D-31 rewrite of `/VERSION` used to strip `-lite` / `-lite-systemd`
from `PRODUCT`/`PLATFORM`. The D-39/D-43 names have nothing to strip, so a `case` maps all three to
what upstream's own image writes — `aarch64-rpi3` → `PRODUCT=rpi3 PLATFORM=rpi3`, `aarch64-rpi4` →
`rpi4`, `x86_64-ova` → `ova` — which is what the recovery compares on an in-place update.
`VARIANT=lite` and the D-37 `LITE=` line are appended as before, and the sed for the older names is
kept for a snapshot branch that still builds one. **The same `case` exists a second time**, in
`package/recovery-system/external/board/post-build.sh`, because `fwinstall.sh` runs inside the
recovery and compares the recovery's own `/VERSION` (B-27). A product that is missing from either
map keeps its own name in `PLATFORM` and can never be updated again, so the two are changed
together or not at all.

`lite-version.mk` decided what a lite product is by `-lite` appearing in its name; it now also
accepts a name from `LITE_PRODUCTS` (`x86_64-ova aarch64-rpi3 aarch64-rpi4`), so all three get
D-37's `<OpenCCU base>-lite.<release>` instead of the build date, and the aarch64 release files are
`OpenCCU-<base>-lite.<n>-aarch64-rpi3.img/.zip` and `…-aarch64-rpi4.img/.zip`. **Every future
product has to be added to that list and to both `case` blocks above** (done for `aarch64-rpi5`
on 2026-09-09, task 32: `rpi5.config` with the identical delta — bcm2712, 16K pages, Cortex-A76,
u-boot 2026.04, `rpi-eeprom`'s RPI5 variant and no `rpi-firmware`, which the Pi 5 does not use) — a lite product that is in
none of them would silently get upstream's date version and its own name in `/VERSION`.

**Decided, and the answer to what used to be open here (D-43):** upstream's `rpi3.config` is
`BR2_aarch64=y` (`cortex_a53`), and that is not an oversight — OpenCCU has no 32-bit ARM defconfig
any more, and openccu-lite does not add one. OQ-7 asked how a product named `armv7l` could build
an image whose `uname -m` says `aarch64`; the answer is that it should never have been named that.
The product set is x86_64 and aarch64, the two aarch64 images are a board split and not an
architecture split, `uname -m` reads `aarch64` on both — which is what the addon catalogue's
`architectures` field carries (D-39) — and the 32-bit addon binaries are served by `multilib32`,
not by a 32-bit port nobody has.

## 23. HSTS on the TLS sockets (task 36)

**Status:** the fragment is lite-only; the two edits to base files are **upstreamable** in the
D-4/D-22 form (a default-off guard that a plain OpenCCU never trips). **Files:**
`buildroot-external/overlay/lite/etc/lighttpd/conf.d/hsts.conf` (new),
`buildroot-external/overlay/base/etc/lighttpd/conf.d/proxy.conf`,
`buildroot-external/overlay/base/etc/init.d/S50lighttpd`.

Upstream has the HTTP → HTTPS redirect as a userfs marker: `S50lighttpd` writes
`/var/etc/lighttpd_httpsredirect.conf` from `/etc/config/httpsRedirectEnabled` at start and at
every reload, and `proxy.conf` includes that file on the `:80` sockets. HSTS is done in the same
shape one step further: a marker `/etc/config/hstsEnabled` whose content is the max-age in
seconds, a `/var/etc/lighttpd_hsts.conf` that `S50lighttpd` writes from it (digits only, `tr -dc`
- a hand-edited marker cannot become configuration; an empty value falls back to a week, one year
before task 96), and an include of that file on the two `:443` sockets. The written file sets `var.hsts_max_age` and
includes the lite overlay's `conf.d/hsts.conf`, which appends
`Strict-Transport-Security: max-age=<n>` to `setenv.add-response-header` for that socket only
(`mod_setenv` is loaded already). No `preload`, no `includeSubDomains`: a CCU is one host, and
preload cannot be undone.

The `S50lighttpd` block tests for the fragment as well as the marker, so a product without the
lite overlay writes an empty include file and is unchanged - the same guard upstream's own
`auth.conf` include uses. The include file always exists after `start` or `reload`, which is what
makes the unconditional `include` in `proxy.conf` safe; the systemd unit runs
`S50lighttpd.script reload` as `ExecStartPre` for exactly this reason (item 18). Parsed with the
target's own lighttpd on the runner (`-tt` and `-p`, both shapes) before it went in.

occulited writes and removes both markers from System → Security (occulited `f2b01ad`), reloads
lighttpd, and refuses HSTS while the certificate is self-signed - a browser that has seen the
header refuses an untrusted certificate for the whole max-age, which is the one way to lock the
user out; the switch back to self-signed on the Certificate page removes the HSTS marker in its
own reload.

**Task 96 (D-64): switching HSTS off clears.** A browser keeps its HSTS entry when the header just
stops; it forgets it when it sees `max-age=0` over a certificate it trusts (task 71). So occulited
writes the marker as `0` when HSTS goes off, and the Unix time the clearing ends into a second
userfs file, `/etc/config/hstsClearUntil` (the previous max-age, at most 30 days). `S50lighttpd`'s
HSTS block, now the function `hsts_conf` called from `start` and `reload`, sends `max-age=0` for a
marker of zeros until that time and writes an empty include once it has passed; without the file it
sends `max-age=0` until the marker goes. The deadline is a file of its own and not a second number
in the marker: the script has always read the marker as digits only, so an older `S50lighttpd`
would turn `0 <epoch>` into a max-age of years, while a plain `0` means `max-age=0` to every
version. A clock that is behind only sends `max-age=0` longer. occulited removes both files after
the deadline and reloads; the switch back to self-signed and a staged way back to OpenCCU enter the
same state. `scripts/lite-lighttpd-redirect-test.sh` checks each form with `lighttpd -tt` and the
header on the wire.

**Recorded here at the same time, missing before:** task 35's edits to the same two base files -
`httpsredirect.conf` leaves `/.well-known/acme-challenge/` on port 80 (`b16e76f6e`) and
`check_certificate` leaves a certificate alone when `server.pem.managed` or `server.pem.acme` sits
beside it (`8740e47de`). Both are the same D-4/D-22 shape: a guard that a plain
OpenCCU never trips.

## 26. The bare host name redirected to `<host>.<domain>` (task 74)

**Status:** the fragment, the module order and the test script are lite-only; the two edits to
base files are **upstreamable** in the D-4/D-22 form (a default-off guard that a plain OpenCCU
never trips). **Files:** `buildroot-external/overlay/lite/etc/lighttpd/conf.d/fqdnredirect.conf`
(new), `buildroot-external/overlay/base/etc/lighttpd/conf.d/proxy.conf`,
`buildroot-external/overlay/base/etc/init.d/S50lighttpd`,
`buildroot-external/overlay/lite/etc/lighttpd/modules.conf`,
`scripts/lite-lighttpd-redirect-test.sh` (new).

A third marker in the shape of item 23. `/etc/config/fqdnRedirect` holds the target name.
`S50lighttpd`'s `fqdn_redirect`, called from `start` and `reload` right after the HSTS block,
accepts only a lower-cased DNS name of two labels or more - anything else is ignored, so the
marker cannot become configuration - and only a name the live certificate covers
(`openssl x509 -checkhost`, read by its output: OpenSSL 3.0 exits 0 either way, 3.5 exits 1 on a
mismatch). It writes `/var/etc/lighttpd_fqdnredirect.conf` with `var.fqdn_redirect_host` (the
first label) and `var.fqdn_redirect_target` and includes the fragment. With
`httpsRedirectEnabled` it also appends an include of that file to
`/var/etc/lighttpd_httpsredirect.conf`, so on port 80 the rule comes after upstream's and
overrides it for the bare name only: `http://<host>/` reaches `https://<host>.<domain>/` in one
hop, and without the HTTPS redirect port 80 is untouched. `proxy.conf` includes the file in both
`:443` blocks; the `:80` blocks are unchanged. The include file always exists after `start` or
`reload`, as item 23's does.

The fragment matches `$HTTP["host"] =~ "(?i)^" + var.fqdn_redirect_host + "(?::[0-9]+)?$"` (a
variable concatenated into a condition parses on 1.4.82 and 1.4.85; lighttpd drops a trailing dot
from `Host` before the match, so `ccu.` is redirected as well), `GET` and `HEAD` only, not `/api`
or `/api/...`, not `/.well-known/acme-challenge/`, not the loopback, and answers `302`: a `301`
would stay in browsers after the switch is off or the domain changes. An IP literal, the FQDN
itself and any other name never match.

The certificate check is in the script as well as in occulited because occulited rewrites the
marker at once after a rename or a new domain, and the redirect must not point at a name the
certificate does not carry yet. The install of the certificate for the new name reloads
lighttpd, and that reload brings the redirect back without occulited doing anything.

**The module order.** `mod_redirect` finishes a request in its `uri_clean` hook, so the modules
after it in `server.modules` never see a redirected request - `mod_setenv` among them, which adds
HSTS and the headers of `conf.d/setenv.conf`. Loaded before `mod_redirect` it adds them to the
redirects too, so the bare name's redirect on the TLS socket carries `Strict-Transport-Security`.
`overlay/base` keeps upstream's order; review on rebase with item 7.

**Checked:** `scripts/lite-lighttpd-redirect-test.sh` builds the lighttpd tree of both overlays
with occulited's fragment in an Alpine container (lighttpd 1.4.85), runs `S50lighttpd reload` with
the markers present and absent, `lighttpd -tt`, and curl for who is redirected where: the method,
path and query, capitals and a port in `Host`, an IPv6 literal, other names, the API, the ACME
path, the loopback, the addon gate, HSTS on the redirect and none on port 80, the HTTPS redirect's
own answers, and the markers the script refuses. On an `x86_64-ova` system, lighttpd 1.4.82 parsed a
copy of its full configuration with these files in `/tmp` (`-tt` and `-p`) with no marker, the
marker with and without the HTTPS redirect, and a name the certificate does not cover, the
function run by the system's busybox and openssl.

## The measurement

`docs/base-scope.md` records what this delta buys, measured rather than
estimated: `oci_amd64` against `oci-lite_amd64` built from the same upstream
snapshot on the same host, plus the boot behaviour of the resulting image. That product is gone
(item 4); the numbers stand as a record of what the D-23 reduction bought.

## `S62HMServer` sources `/etc/hmipserver.default`; lite sets `HMIP_BIND_ADDRESS`

**Status:** the init-script hook is **upstreamable**; the file in `overlay/lite/etc/default/` is
lite-only. **Files:** `buildroot-external/overlay/base/etc/init.d/S62HMServer`,
`buildroot-external/overlay/lite/etc/hmipserver.default`.

After generating `/var/etc/crRFD.conf` from the vendor template, `S62HMServer` sources
`/etc/hmipserver.default` (the image) and `/etc/config/hmipserver.default` (the user) when they
exist and, if `HMIP_BIND_ADDRESS` is set, appends
`Legacy.BindAddress=<addr>` (replacing any existing line). Upstream behaviour is unchanged when the
file is absent — no defconfig ships it. `Legacy.BindAddress` is a property the HmIP server reads
(verified on OpenCCU 3.89.8: `::ffff:127.0.0.1:32010`). The alternative — a lite copy of the
63-line vendor template — would need re-reviewing on every occu bump; this is three lines.

**Why upstream wants this:** a CCU whose XML-RPC clients all run on the system (RaspberryMatic with
addons, an HA add-on) has no reason to expose 32010 to the LAN; today the only way is the
firewall. The same hook shape fits `rfd`'s `Listen IP` once someone wants it there.

**What it does not cover:** the BidCos-only branch of `S62HMServer` (no HmIP module detected —
a container without hardware, or a plain HM-only system) starts `HMServer.jar` with
`/var/etc/HMServer.conf` (`hmServerPort=39292`), and that server has no bind property in its
classes. There the firewall's rules keep 39292 off the LAN, as upstream has it. Verified on the
second lite image: `:::39292` listening in a container, `Listen IP = 127.0.0.1` present in
`rfd.conf`, `/etc/hmipserver.default` in place for the HmIP branch. (`/etc/default` is a symlink into the user
partition on a CCU — the first placement there broke the overlay rsync on an incremental build.)

## 10. The `x86_64-ova` product (D-33, D-39, D-43), and `board/lite/post-build.sh`

**Status:** lite-only. **Files:** `buildroot-external/configs/x86_64-ova.config`,
`buildroot-external/board/x86_64-ova/post-release.sh`, `buildroot-external/overlay/lite_ova/etc/{inittab,crontab.root}`,
`buildroot-external/kernel/6.18/lite.config`, `buildroot-external/board/lite/post-build.sh`
`release/updatepkg/x86_64-ova -> rpi3` (as upstream's `ova`).

The one x86_64 product, and the only lite product that is not a Pi (D-43). `x86_64-ova.config` is
`ova.config` with the WebUI overlays replaced by `lite` + `lite_ova`, the D-23
block of the former `oci-lite_amd64.config` (item 4) appended, and the WiFi/Bluetooth stack and wireless firmware
dropped (a VM has neither; a CCU3 has no WiFi). The kernel gets `lite.config` on top of upstream's
fragments: namespaces (`USER_NS`, `PID_NS`, …) and the cgroup controllers tasks 17/18/20 need;
seccomp and AppArmor are already in upstream's `security.config`. `lite_ova` carries
`base-openccu`'s inittab without monit and its crontab without the ReGa consumers, the addon check,
the measurement rsync and logrotate. Both of those files were written for busybox init and neither
is read any more: systemd does not read an inittab, and `overlay/lite`'s own `etc/crontab.root`,
which carries no job at all, comes later in `BR2_ROOTFS_OVERLAY` and wins. They are kept rather
than deleted because the overlay is the product's own and a busybox variant is one config away;
whether that is still worth the two files is the maintainer's call.

The product is named for its architecture and its form, with no `-lite` and no `-systemd` suffix
(D-39). The D-31 rewrite therefore has nothing to strip, and a `case` in `board/lite/post-build.sh`
maps the name to `PRODUCT=ova` / `PLATFORM=ova` — what upstream's own image writes, and what the
recovery compares on an in-place update. The same map exists a second time in
`buildroot-external/package/recovery-system/external/board/post-build.sh`, which is the copy
`fwinstall.sh` reads (B-27, item 12); the two are changed together. The release files carry the
product name: `OpenCCU-<version>-x86_64-ova.{img,zip,ova}`. `board/ova`'s post-build and post-image
run unchanged (the OVA packaging is theirs); `board/x86_64-ova/post-release.sh` is upstream's with
the OVA named per product.

The busybox sibling this product was split from, `ova-lite`, is not carried forward (D-39), and its
`configs/ova-lite.config` and `release/updatepkg/ova-lite` are gone; `board/ova-lite/` is this
directory under its new name. Item 12 has what systemd costs and what it replaced.

`board/lite/post-build.sh` holds what every lite product does after the upstream board scripts:
the `/VERSION` rewrite (D-31), the deletion of the firmware's ReGa consumers, and the removal of
monit's and the HA proxy's leftovers.

## 31. The boot order as a dependency graph, chrony without `ntpdate`, the clock gate (task 94)

**Status:** the unit graph, `lite-chrony` and `occu-clock-valid` are **lite-only** (systemd);
the atomic `/var/hm_mode` write and the missing chronyd start after a failed `ntpdate` (B-97)
are **upstream candidates**. **Files:** `buildroot-external/overlay/lite/usr/lib/systemd/system/*.service`
(the `After=` lines), `…/system/occu-clock-valid.service`, `…/system-preset/50-openccu-lite.preset`,
`buildroot-external/overlay/lite/usr/libexec/occu/{lite-chrony,lite-clock-valid}`,
`buildroot-external/overlay/base/etc/init.d/{S47InitRFHardware,S48UpdateRFHardware}`,
`scripts/testcases/lite-unit-order-test.sh`.

- **The graph.** Item 12 kept upstream's `S40…S98` order as one serial `After=` chain. Each unit now
  orders after what its script reads. The serial base (`occu-persist`, `occu-init-host`,
  `occu-init-rtc`, `occu-init-system`, `occu-init-rf-hardware`, `occu-update-rf-hardware`, all of
  which rewrite `/var/hm_mode`) stays. multimacd follows the radio hardware; rfd and hmipserver both
  follow multimacd; the LAN-gateway steps follow the network and come before rfd and hs485d; lighttpd
  follows the network beside occulited. The test fails on a reintroduced serial link.
- **`S46chronyd`'s blocking `ntpdate`** is not run: `chrony.service` calls `lite-chrony`, which
  writes S46chronyd's server list into `/var/etc/chrony.conf` and starts chronyd at once (`makestep`
  is already in `/etc/chrony.conf`). Upstream's script exits before starting chronyd when both
  `ntpdate` attempts fail, which leaves a system that boots without internet unsynchronised until the
  next reboot; the fix there would be to start chronyd in that branch as well.
- **`occu-clock-valid.service`** finishes when the clock came from an RTC and is not older than the
  image, when chronyd is synchronised, or after 60 s; multimacd, rfd, hmipserver, hs485d and crond
  order after it.
- **`S47InitRFHardware` and `S48UpdateRFHardware`** write `/var/hm_mode` to a temporary file and
  move it into place. Under rcS nothing read the file while they ran; with lighttpd, eq3configd and
  the clock gate starting beside them, a reader could meet the truncated file, and `S50lighttpd`
  exits without `HM_MODE` (the shape of B-85). Harmless upstream, where it only removes a window.

## 32. The status LED: `hss_led` out, the scripts' LED writes narrowed (task 95, D-63)

**Status:** the removal, `lite-status-led` and the unit lines are **lite-only**; the guards in
`S02InitRTC`, `S47InitRFHardware` and `eQ3StartNetwork` are **upstreamable** — on a system with
`hss_led` nothing changes but the network blink, which no longer writes the `rpi_rf_mod:*` devices
the overlay creates on every Pi, nor an LED that is already owned after the boot. **Files:**
`buildroot-external/board/lite/post-build.sh`,
`buildroot-external/overlay/base/etc/init.d/{S02InitRTC,S47InitRFHardware}`,
`buildroot-external/overlay/{base,base-openccu_oci}/etc/network/if-up.d/eQ3StartNetwork`,
`buildroot-external/overlay/lite/usr/libexec/occu/lite-status-led`,
`buildroot-external/overlay/lite/usr/lib/systemd/system/{occu-leds.service,occulited.service.d/20-status-led.conf}`.

- **`hss_led`** can only show red without ReGaHss (its process check), and it rewrites the LED every
  cycle. occulited's status LED controller is the LED's writer after the boot, through its root
  helper; the binary and `82-hss_led.rules` are deleted in the lite post-build. `S06InitSystem` and
  `S47InitRFHardware` start it only when `/bin/hss_led` is executable, so both stay as they are.
  `package/openccu-base` (`package/occu` until 3.89.8) still installs the binary (deleted after) and still creates the `hssled` account:
  removing an auto-allocated account from the users table could move the ids allocated after it,
  which files on the userfs carry.
- **`dummy_rx8130`** exists only for `hss_led`'s `lsmod | grep rx8130`; it is loaded only where the
  binary is.
- **`eQ3StartNetwork`'s blue blink** runs at every `if-up`: after the boot it overwrote the LED's
  owner, and on a Pi without an RPI-RF-MOD it drove GPIOs 16/20/21. It needs `HM_RTC=rx8130`
  (`S02InitRTC`'s detection of the module) and no `/var/status/startupFinished` now.
- **`lite-status-led shutdown|stopped`**: the yellow patterns the controller shows itself, for when
  it is not there — `occu-leds.service`'s stop (the first step of a shutdown) and occulited's
  `ExecStopPost` (yellow slow: not supervised; the shutdown pattern while the system goes down). Only
  with an RPI-RF-MOD in `/var/hm_mode`, never in HM-LGW mode.
- **The recovery system** keeps its own `S02InitRTC`, `S11InitRFHardware` and `S99SetupLEDs`
  unchanged: magenta, driven by its scripts.

A rebase that changes the LED blocks of these scripts has to keep the guards.

## 33. multimacd's own log level (task 101)

**Status:** **upstreamable**. **Files:** `buildroot-external/overlay/RFD/etc/init.d/S60multimacd`,
`scripts/testcases/multimacd-loglevel-test.sh`, `.github/workflows/lite-build.yml`.

- **Before:** multimacd had no level of its own. Its init script started it with `-l ${LOGLEVEL_RFD}`,
  so a user who wanted rfd's debug lines got multimacd's as well, and the other way round.
- **Now:** `LOGLEVEL_MULTIMACD` in `/etc/config/syslog`, the file the script already sources, on the
  same scale as rfd's (eQ-3's 0 to 6). `multimacdLogLevel` answers it when it is a single digit from
  0 to 6, and `LOGLEVEL_RFD` otherwise (unset, empty, a name, two digits). Both `start-stop-daemon`
  lines, the start and the retry in `waitStartupComplete`, take its answer.
- **Compatibility:** a file without the key, and a backup restored from an older system, start multimacd
  exactly as before. The script's defaults reset `LOGLEVEL_MULTIMACD`, so a value inherited from the
  environment does not count.
- **Where it is set:** occulited's Log settings (task 101) write the key, or remove it for *same as
  rfd*. multimacd takes a level only at its start, and it cannot restart under rfd and hmipserver, so
  occulited restarts the radio stack in order (hmipserver, rfd, multimacd stop; multimacd, rfd,
  hmipserver start). Upstream's WebUI has no field for it; the key can be set by hand there.

## 35. The boot path's second pass (tasks 108, 116, 118, 135, 136; D-89, D-90)

**Status:** the base-script edits are **upstreamable**, the units and the lite scripts lite-only.
**Files:** `buildroot-external/overlay/base/etc/init.d/{S47InitRFHardware,S48UpdateRFHardware}`,
`buildroot-external/overlay/{base,base-openccu_oci}/etc/network/if-up.d/eQ3StartNetwork`,
`buildroot-external/overlay/base/bin/dhcp.script`, `buildroot-external/board/lite/{post-build.sh,
post-build-systemd.sh,ca-prebuilt.sh}`, `buildroot-external/overlay/lite/usr/lib/systemd/system/*.service`,
`…/system-generators/occu-addons`, `buildroot-external/overlay/lite/usr/libexec/occu/{lite-ca-certificates,
lite-clock-valid,lite-radio-stop-wait}`, `scripts/lite-unit-refs.sh`,
`scripts/testcases/{lite-unit-order-test,occu-addons-generator-test,lite-boot-path-test}.sh`.

- **`S47InitRFHardware`**: `wait_for_hb_rf_eth_route` polls `ip route get <address>` (a default
  route for a name) every 0.2 s, at most 60 s, before the HB-RF-ETH is connected; `board_mac` gives
  the board-serial fallback eth0's MAC, else the first physical interface's, instead of the MAC of
  whichever interface holds the default route. Under rcS the network is up before S47 and eth0
  holds the default route on every CCU-like system, so upstream sees no change; a systemd image can
  detect a local radio module while the network comes up.
  **`probe_radio_module`** (task 138, D-92): with `RF_GPIO_PROBE_TIMEOUT=<s>` in the caller's
  environment (the lite unit sets 6), a raw-uart node whose `device_type` is `GPIO@…` is probed
  with that limit first; the Pi images create the node whether or not a module is on the header,
  and `detect_radio_module` waits about 18 s on an empty one. When no module was found at all, the
  other raw-uart nodes are reset and probed again (an HmIP-RFUSB probed right after a cut probe
  answered *"did not respond correctly"* in 2 of 5 boots on the Pi 4), then the GPIO nodes that ran
  into the limit, without it and only while nothing was found. Unset or 0, every probe runs without
  a limit and there is no second pass, as before.
- **`S48UpdateRFHardware`**: `COPRO_UPDATE_AT_BOOT=no` in the caller's environment (the lite unit)
  keeps the version check and prints `<old>, <new> available (not flashed at boot)` instead of
  flashing; nothing re-runs S47 then. Unset, the script flashes as before.
- **`eQ3StartNetwork`**: the carrier wait sleeps 0.2 s instead of 2 s, with the same 12 s limit
  and the same dots (one per 2 s). **The internet check** runs only where `/bin/checkInternet` is
  executable (`eQ3StartNetwork`'s two calls and its `inet up/down` output, `dhcp.script`), and the
  lite post-build removes the script (D-90).
- **The CA bundle**: `board/lite/ca-prebuilt.sh` runs the image's own `update-ca-certificates
  --default` against the target's certificates with the host's openssl and points the links at the
  system's paths; checked against a system's boot-time bundle (the same links and certificates; busybox
  `sed '$a\'` adds a blank line after each certificate, GNU sed does not).
- **A rebase** that touches the HB-RF-ETH block, the board-serial fallback, the probe loop or the three flash
  branches of S48 has to keep these edits; the unit-order and boot-path tests fail otherwise.

## 36. The interface daemons confined (task 67; D-55, D-93)

**Status:** the three init-script edits are **transitional and fork-only** — not offered upstream,
because the occulited radio rework (D-83) deletes the scripts from the image and the case with them;
everything else is lite-only. **Files:** `buildroot-external/package/occulited/occulited.mk`
(`OCCULITED_USERS`), `buildroot-external/overlay/lite/usr/lib/udev/rules.d/60-openccu-lite-radio.rules`,
`buildroot-external/overlay/lite/usr/lib/tmpfiles.d/00-openccu-lite-radio.conf`,
`buildroot-external/overlay/lite/usr/lib/systemd/system/{rfd,multimacd,hmipserver,hs485d,hmlangw}.service`
and their `*.service.d/20-devices.conf`, `buildroot-external/overlay/lite/usr/libexec/occu/lite-radio-prep`,
`buildroot-external/overlay/RFD/etc/init.d/{S60multimacd,S61rfd}`,
`buildroot-external/overlay/base/etc/init.d/S62HMServer`, `buildroot-external/board/lxc-lite/post-build.sh`,
`scripts/testcases/lite-radio-confine-test.sh`.

- **The scripts:** each gains one case, `init) init ;;`, so that a service manager that starts the
  daemon itself can run the script's preparation alone (`/var/etc/rfd.conf`, `multimacd.conf` and
  the loop module, `crRFD.conf`/`HMServer.conf`/`log4j2.xml` and the diagram copy). The `start`,
  `stop` and `restart` actions are untouched; under busybox init nothing changes.
- **The units** start the daemons directly as their own users (`Type=exec`; hs485d `Type=forking`
  behind its loader) with `CapabilityBoundingSet=`, `NoNewPrivileges=`, `ProtectSystem=strict`,
  `ReadWritePaths=` for what each daemon writes, `PrivateTmp=`, the kernel protections,
  `DevicePolicy=closed` with the class of its node in a drop-in, and the address families each needs
  (multimacd none: `PrivateNetwork=yes`). multimacd keeps its SCHED_RR threads through
  `LimitRTPRIO=99` and `Nice=-15`, not a capability. The seccomp-backed lines
  (`RestrictAddressFamilies=`, `RestrictSUIDSGID=`, `RestrictNamespaces=`, `LockPersonality=`,
  `RestrictRealtime=`, `MemoryDenyWriteExecute=`, `SystemCallArchitectures=`) are enforced since systemd
  is built with libseccomp (item 41). rfd and hs485d need `AF_NETLINK` besides the internet families:
  their LAN gateway library (`libLanDeviceUtils.so`) lists the interfaces with `getifaddrs()`.
- **`lite-radio-prep <daemon> prep|ready|stopped`** is the root half, from `ExecCondition=+`: the
  script's skip decisions (exit 1: the unit is skipped, not failed), the `init` action, the daemon's
  command-line variables into `/run/occulite/radio/<daemon>.env`, the device nodes' groups (also
  where udev does not run), and the ownership repair at every start (a `.sbk` restore, an update
  from OpenCCU and the LAN gateway page leave root-owned files). `ready` is the script's
  `waitStartupComplete` (the status file carries the main pid; `HMServerStarted`); `stopped` is the
  script's stop action after the kill (the loop module unloaded, the diagram data back on the stick).
- **hmipserver's diagram database** moves from `/tmp/measurement` to `/var/hmipserver/measurement`
  (`diagramDatabasePath` rewritten in the generated `/var/etc/HMServer.conf`): the unit's `/tmp` is
  private, and the copy from and to the USB stick runs as root outside it.
- **hs485d** writes four files directly under `/var` (the loader's pid file, the daemon's pid file,
  the unix socket `/var/socket_hs485d`, `/var/log/hs485d.log`); the unit shows it a private `/var`
  (`TemporaryFileSystem=/var`) with the real `/var/etc`, `/var/hm_mode` and `/var/status` bound in and
  `/var/run`, `/var/log` from its runtime directory. Unverified without wired hardware.
- **The container products** keep the users and the sandbox and lose the device drop-ins
  (`board/lxc-lite/post-build.sh`): no udev inside, and a device policy may not be applied in a
  nested cgroup. The prep helper sets the node groups there. The OCI product ran busybox init and was
  not covered by the units; task 142 removed it (D-94).
- **A rebase** that touches the three scripts' `case` has to keep the `init)` line; the testcase
  fails otherwise. The occulited radio rework deletes the scripts and this case with them.

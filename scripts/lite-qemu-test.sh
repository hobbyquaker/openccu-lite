#!/bin/bash
# openccu-lite: boot a disk image (ova / generic-x86_64 products) headless in QEMU and check that
# occulited answers through lighttpd. Works without KVM (TCG; count on a few minutes to boot).
# Prints the image's /VERSION first, so a wrong PLATFORM is caught before the recovery would.
#
# A systemd image (task 20, D-30) is booted with its kernel taken straight from the rootfs and a
# systemd debug shell on the serial line (systemd.debug_shell=ttyS0 — no login, no password, only
# in this test), through which the script checks the units, the journal on the userfs and the
# addon generator round trip: an rc.d script is dropped in, addons.target is restarted, the box is
# rebooted and the addon unit must be back after the reboot. busybox images boot through grub as
# before; the HTTP checks are the same for both.
#
# Usage: scripts/lite-qemu-test.sh <sdcard.img> [port]
set -u
IMG=${1:?disk image}
PORT=${2:-8090}
say() { printf '%s %s\n' "$(date +%T)" "$*"; }
FAILED=0
fail() { say "FAIL: $*"; FAILED=1; }

say "image $IMG ($(du -h "$IMG" | cut -f1))"
# The rootfs without mounting: buildroot leaves the filesystem that went into the image next to
# it as rootfs.ext4, and debugfs (e2fsprogs) reads that as a plain file - no loop device, no
# root, and no "-o offset", which Debian 13's debugfs does not have.
ROOTFS="$(dirname "$IMG")/rootfs.ext4"
# debugfs lives in /usr/sbin, which a non-root PATH usually omits - and the CI job runs as
# `builder`. When it was only looked for with `command -v`, the whole systemd branch below was
# skipped without a word and the run still said OK: on 2026-09-07 that turned the first beta.2
# boot test into "does it answer HTTP" and nothing else. Look for it properly, and if the rootfs
# is here and debugfs is not, fail rather than degrade.
DEBUGFS="$(command -v debugfs 2>/dev/null || true)"
for c in /usr/sbin/debugfs /sbin/debugfs /usr/local/sbin/debugfs; do
  [ -n "$DEBUGFS" ] && break
  [ -x "$c" ] && DEBUGFS="$c"
done
if [ -f "$ROOTFS" ] && [ -z "$DEBUGFS" ]; then
  say "FAIL: $ROOTFS is here but debugfs (e2fsprogs) is not - install it, or put /usr/sbin on PATH."
  say "      Without it this test checks only that the image answers HTTP, and says OK anyway."
  exit 1
fi
[ -f "$ROOTFS" ] && [ -n "$DEBUGFS" ] || ROOTFS=
if [ -n "$ROOTFS" ]; then
  say "/VERSION in the image:"; "$DEBUGFS" -R 'cat /VERSION' "$ROOTFS" 2>/dev/null | sed 's/^/  | /'
fi
WORK=$(mktemp -d)
GUEST_PID=
# the driver holds the chardev socket and the CI step's stderr; it must not outlive the script
trap 'guest_close 2>/dev/null; [ -f "$WORK/qemu.pid" ] && kill "$(cat "$WORK/qemu.pid")" 2>/dev/null; true' EXIT
cp --sparse=always "$IMG" "$WORK/disk.img"
# a real VM disk is bigger than the image: give the userfs resize room (journald lives there
# on the systemd product; the image's userfs partition is 3 MB until it grows)
truncate -s +2G "$WORK/disk.img"

SYSTEMD=0
if [ -n "$ROOTFS" ] && "$DEBUGFS" -R 'stat /usr/lib/systemd/systemd' "$ROOTFS" >/dev/null 2>&1; then
  SYSTEMD=1
  "$DEBUGFS" -R "dump /zImage $WORK/zImage" "$ROOTFS" >/dev/null 2>&1 || { say "cannot extract /zImage"; rm -rf "$WORK"; exit 1; }
fi

# the guest shell: one command line at a time over the serial socket, output until the marker.
#
# ONE connection for the whole guest phase. QEMU's socket chardev serves a single client at a
# time and drops on the floor whatever the guest writes while no client is attached, so the
# earlier "connect per command" shape lost a marker as soon as a command took long enough for
# the previous connection to have been closed - and the next call then waited its full timeout
# for a marker that had already gone by (diagnosed 2026-09-07, fixed 2026-09-07). The driver
# below connects once, keeps the connection for every command, and tags each command with its
# own sequence number so a late line from the previous one cannot be mistaken for this one's.
#
# guest_open is lazy and guest_close ends the driver; a guest reboot needs a close (the shell on
# the other side is a new process) and the next guest call reopens.
guest_driver() {
  cat >"$WORK/guest-driver.py" <<'PY'
import re, socket, sys, time

sockpath, logpath = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(1.0)
s.connect(sockpath)
log = open(logpath, "a", buffering=1)
buf = b""


def pump(deadline, marker):
    """Read until marker matches what has arrived, or the deadline passes."""
    global buf
    while time.time() < deadline:
        try:
            d = s.recv(4096)
        except socket.timeout:
            if marker is not None and marker.search(buf):
                return True
            continue
        except OSError:
            return False
        if not d:
            return False
        buf += d
        log.write(d.decode("utf-8", "replace").replace("\r", ""))
        if marker is not None and marker.search(buf):
            return True
    return marker is not None and bool(marker.search(buf))


# The prompt of the shell on the other side, which lands in front of the first line a command
# prints and, when a command prints nothing, in front of the marker itself. systemd's debug shell
# gives "sh-5.2# "; a plain busybox ash gives "# " or "$ ". Stripped rather than used to drop the
# whole line, which is what threw away a one-word answer such as "0" or "active".
PROMPT = re.compile(r"^(?:sh-[\d.]+[#$]|[#$])\s*")


def strip_prompts(line):
    prev = None
    while prev != line:
        prev = line
        line = PROMPT.sub("", line, count=1)
    return line


# let the debug shell settle, and throw away whatever it printed before we attached
pump(time.time() + 2, None)
buf = b""
seq = 0
for line in sys.stdin:
    cmd = line.rstrip("\n")
    if cmd == "__QUIT__":
        break
    seq += 1
    tag = "__OLT%d__" % seq
    # not anchored to the line start: with no output before it the shell's prompt sits on the
    # same line ("sh-5.2# __OLT4__=1"), and a serial line ends "\r\n" so the \r is still here.
    # The echoed command line carries "=$?" rather than digits, so it cannot match by accident.
    marker = re.compile((re.escape(tag) + r"=\d+").encode())
    buf = b""
    try:
        s.sendall(("\n" + cmd + "; echo " + tag + "=$?\n").encode())
        ok = pump(time.time() + 240, marker)
    except OSError as e:
        print("  | (the serial connection is gone: %s)" % e)
        print("[rc=disconnected]")
        print("__END__", flush=True)
        break
    out = []
    for l in buf.decode("utf-8", "replace").replace("\r", "").split("\n"):
        if "echo " + tag in l:  # the command line the shell echoes back
            continue
        l = strip_prompts(l)
        m = re.match("^" + re.escape(tag) + r"=(\d+)$", l.strip())
        if m:
            out.append("[rc=%s]" % m.group(1))
            break
        if l.strip():
            out.append("  | " + l)
    if not ok:
        out.append("  | (no marker within 240 s; the guest shell did not answer)")
        out.append("[rc=timeout]")
    print("\n".join(out))
    print("__END__", flush=True)
PY
}

guest_open() {
  [ -n "${GUEST_PID:-}" ] && return 0
  # a SIGPIPE here would kill the script rather than report a failure
  trap '' PIPE
  guest_driver
  rm -f "$WORK/guest.in" "$WORK/guest.out"
  mkfifo "$WORK/guest.in" "$WORK/guest.out"
  python3 "$WORK/guest-driver.py" "$WORK/serial.sock" "$WORK/serial.log" <"$WORK/guest.in" >"$WORK/guest.out" &
  GUEST_PID=$!
  exec 8>"$WORK/guest.in"
  exec 9<"$WORK/guest.out"
  # systemctl and journalctl page on the debug shell's tty and the listing arrives as escape
  # codes, after which the shell is unusable (seen 2026-09-08 on list-timers): no pager, no colour
  guest 'export SYSTEMD_PAGER=cat PAGER=cat SYSTEMD_COLORS=0 TERM=dumb' >/dev/null
  # HTTP answers long before the boot is over (occulited is Before=lighttpd, the addons and the
  # end-of-boot units come after); every check below assumes a finished boot, so wait for it -
  # "degraded" counts, psplash-start fails here (see above)
  guest 'for i in $(seq 1 90); do s=$(systemctl is-system-running 2>/dev/null); case "$s" in starting|initializing) sleep 2;; *) break;; esac; done; echo "system: $s after ${i}x2s"'
}

guest_close() {
  [ -n "${GUEST_PID:-}" ] || return 0
  printf '__QUIT__\n' >&8 2>/dev/null
  exec 8>&-
  wait "$GUEST_PID" 2>/dev/null
  exec 9<&-
  GUEST_PID=
}

guest() {
  guest_open
  printf '%s\n' "$1" >&8
  while IFS= read -r __l <&9; do
    [ "$__l" = "__END__" ] && return 0
    printf '%s\n' "$__l"
  done
  # the driver died: say so rather than return silence that a case statement reads as a pass
  say "guest: the serial driver stopped answering"
  GUEST_PID=
  return 1
}

boot() {
  if [ "$SYSTEMD" = 1 ]; then
    qemu-system-x86_64 -m 2048 -smp 2 -cpu qemu64 \
      -kernel "$WORK/zImage" \
      -append "root=PARTUUID=deedbeef-02 rootfstype=ext4 fsck.repair=yes console=tty2 ro rootwait rootdelay=5 init_on_alloc=1 init_on_free=1 slab_nomerge net.ifnames=0 systemd.debug_shell=ttyS0" \
      -drive file="$WORK/disk.img",format=raw,if=virtio \
      -netdev user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:80 -device virtio-net-pci,netdev=n0 \
      -display none -chardev socket,id=ser0,path="$WORK/serial.sock",server=on,wait=off -serial chardev:ser0 \
      -pidfile "$WORK/qemu.pid" -daemonize >/dev/null 2>&1 || { say "qemu failed to start"; rm -rf "$WORK"; exit 1; }
  else
    qemu-system-x86_64 -m 2048 -smp 2 -cpu qemu64 \
      -drive file="$WORK/disk.img",format=raw,if=virtio \
      -netdev user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:80 -device virtio-net-pci,netdev=n0 \
      -display none -serial file:"$WORK/serial.log" -pidfile "$WORK/qemu.pid" -daemonize >/dev/null 2>&1 || { say "qemu failed to start"; rm -rf "$WORK"; exit 1; }
  fi
  say "$1: booting (TCG, ${WORK}/disk.img is a copy; nothing is written to $IMG)"
  wait_http "$1"
}

wait_http() {
  T0=$(date +%s)
  for i in $(seq 1 180); do
    H=$(curl -s --max-time 3 "http://127.0.0.1:$PORT/api/system/v1/health" 2>/dev/null)
    case "$H" in *'"ok":true'*) break;; esac
    sleep 5
  done
  say "$1: after $(( $(date +%s) - T0 )) s: ${H:-no answer}"
  case "$H" in *'"ok":true'*) ;; *) fail "occulited did not answer through lighttpd";; esac
}

boot "boot 1"
# the HTTP checks the Docker boot test of the dropped OCI product made (task 142, D-94): a fresh
# image asks for its first account, serves the shell, and the addon gate sends a browser without a
# session to the login page and answers an API caller 401
S=$(curl -s --max-time 5 "http://127.0.0.1:$PORT/api/auth/v1/state"); say "auth state: $S"
case "$S" in *'"setup_required":true'*) ;; *) fail "the auth state of a fresh image does not ask for the first account";; esac
curl -s --max-time 5 "http://127.0.0.1:$PORT/" | grep -q '<div id="app">' || fail "the shell is not served at /"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H 'Accept: text/html' "http://127.0.0.1:$PORT/addons/nothing/"); say "/addons/nothing/ as a browser -> $code"
[ "$code" = 302 ] || fail "the addon gate did not redirect a browser (got $code)"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H 'Accept: application/json' "http://127.0.0.1:$PORT/addons/nothing/"); say "/addons/nothing/ as an API caller -> $code"
[ "$code" = 401 ] || fail "the addon gate did not answer 401 to an API caller (got $code)"

if [ "$SYSTEMD" = 1 ] && [ "$FAILED" = 0 ]; then
  # open the driver here, in the script's own shell. Almost every guest call below is inside
  # $( ), which is a subshell: if the first call of a phase were one of those, the driver, its
  # fifos and GUEST_PID would be created and lost inside it, and the next call would start a
  # second driver against a chardev that serves one client at a time.
  guest_open
  # psplash-start.service (buildroot's, not ours) fails here because headless QEMU has no
  # framebuffer; on a box or a VM with a display it does not. occu-interface-clock.service is
  # skipped without rfd since task 129 (B-142); its old failure stays tolerated for older images.
  # --no-pager: systemctl pages on the debug shell's tty and the listing came out as escape codes.
  say "guest: system state"; guest 'systemctl is-system-running; systemctl --failed --no-legend --plain --no-pager'
  R=$(guest 'systemctl --failed --no-legend --plain --no-pager | grep -v "^psplash-start.service \|^occu-interface-clock.service " | wc -l'); case "$R" in *'| 0'*) ;; *) fail "failed units (see above)"
    # what they said: without it a failed unit in a VM that is gone a minute later is a name and nothing else
    guest 'for u in $(systemctl --failed --no-legend --plain --no-pager | cut -d" " -f1); do echo "== $u"; systemctl show -p Result,ExecMainCode,ExecMainStatus "$u"; journalctl -b -u "$u" --no-pager -n 15 -o cat; systemctl status "$u" --no-pager -n 15 | tail -n 15; done';; esac
  say "guest: boot time"; guest 'journalctl -b --no-pager -o short-monotonic | grep -m1 "Startup finished"; journalctl -b -u occu-leds.service --no-pager -o short-monotonic | grep -m1 "booted, OK"'
  say "guest: the lite units"; guest 'systemctl list-units --all --no-legend --plain "occu-*" "addon*" addons.target occulited.service lighttpd.service chrony.service sshd.service hs485d.service multimacd.service rfd.service hmipserver.service crond.service ca-certificates.service qemu-guest-agent.service'
  say "guest: timers"; guest 'systemctl list-timers --all --no-legend --plain "occu-*"'
  say "guest: lighttpd as a tracked daemon"; guest 'systemctl status lighttpd.service --no-pager -n0 | sed -n 1,12p'
  # B-3: the unit has to follow the daemon. RemainAfterExit on a daemon unit is the bug.
  say "guest: no daemon unit keeps RemainAfterExit"; guest 'for u in lighttpd sshd chrony rfd hs485d hmipserver multimacd crond; do printf "%s %s %s\n" "$u" "$(systemctl show -p RemainAfterExit --value $u.service)" "$(systemctl show -p MainPID --value $u.service)"; done'
  R=$(guest 'for u in lighttpd sshd chrony rfd hs485d hmipserver multimacd crond; do systemctl show -p RemainAfterExit --value $u.service; done | grep -c yes'); case "$R" in *'| 0'*) ;; *) fail "a daemon unit still has RemainAfterExit=yes (B-3)";; esac
  # every other check here fails closed; this one used to pass on a timeout or an empty answer
  R=$(guest 'systemctl show -p MainPID --value lighttpd.service'); case "$R" in *'| '[1-9]*) ;; *) fail "lighttpd.service has no main PID, or the guest did not answer (B-3): $R";; esac
  say "guest: killing lighttpd - the unit must notice and restart it"; guest 'P=$(systemctl show -p MainPID --value lighttpd.service); kill -9 $P; sleep 8; systemctl show -p MainPID -p NRestarts -p ActiveState --value lighttpd.service | tr "\n" " "; echo'
  R=$(guest 'sleep 4; systemctl is-active lighttpd.service'); case "$R" in *'| active'*) ;; *) fail "lighttpd.service did not come back after its daemon was killed (B-3)";; esac
  wait_http "after killing lighttpd"
  # B-3: an init script called by hand goes to systemctl, not around it
  say "guest: the init-script wrapper"; guest 'ls -l /etc/init.d/S50lighttpd /etc/init.d/S50lighttpd.script; P=$(systemctl show -p MainPID --value lighttpd.service); /etc/init.d/S50lighttpd restart; sleep 6; Q=$(systemctl show -p MainPID --value lighttpd.service); echo "main pid $P -> $Q"; systemctl show -p ControlGroup --value lighttpd.service; pgrep -x lighttpd-angel | wc -l'
  R=$(guest 'pgrep -x lighttpd-angel | wc -l'); case "$R" in *'| 1'*) ;; *) fail "a hand-invoked S50lighttpd restart left the daemon outside its unit (B-3)";; esac
  R=$(guest 'systemctl is-active lighttpd.service'); case "$R" in *'| active'*) ;; *) fail "lighttpd.service not active after a hand-invoked restart";; esac
  # B-5: the end-of-boot hint
  say "guest: the end-of-boot hint"; guest 'cat /run/issue; ls -l /etc/issue'
  R=$(guest 'grep -c "is up" /run/issue'); case "$R" in *'| 1'*) ;; *) fail "/run/issue has no end-of-boot hint (B-5)";; esac
  say "guest: machine id and journal on the userfs"; guest 'cat /etc/machine-id; cat /usr/local/etc/machine-id; cat /var/board_serial 2>/dev/null; echo; grep " /var/log/journal " /proc/mounts; ls /usr/local/var/log/journal; journalctl --disk-usage; journalctl --list-boots --no-pager'
  # D-41: the ID is derived from the board serial and stored on the userfs on the first boot
  R=$(guest 'test "$(cat /etc/machine-id)" = "$(cat /usr/local/etc/machine-id)" && echo same || echo differs'); case "$R" in *'| same'*) ;; *) fail "the running machine ID is not the one stored on the userfs (D-41)";; esac
  say "guest: the watchdog is PID 1's"; guest 'systemctl show -p RuntimeWatchdogUSec --value; ls -l /dev/watchdog 2>&1 | head -1; systemctl list-units --all --no-legend --plain occu-watchdog-marker.service'
  say "guest: memory and processes"; guest 'free -m; ps -o pid,rss,comm | sort -k2 -n -r | head -12'
  # no ReGaHss in a lite image (D-1), and the tclrega shim still loads for the Tcl scripts
  R=$(guest 'pidof ReGaHss >/dev/null && echo rega-running || echo no-rega'); case "$R" in *'| no-rega'*) ;; *) fail "ReGaHss is running - this is not a lite image";; esac
  R=$(guest 'echo "load tclrega.so" | tclsh && echo shim-ok'); case "$R" in *'| shim-ok'*) ;; *) fail "tclrega.so does not load";; esac
  say "guest: addon generator round trip"; guest 'mkdir -p /usr/local/etc/config/rc.d && printf "#!/bin/sh\ncase \$1 in start) sleep 100000 & echo started;; stop) echo stopped;; esac\n" >/usr/local/etc/config/rc.d/litetest && chmod +x /usr/local/etc/config/rc.d/litetest && systemctl daemon-reload && systemctl start addons.target && systemctl status addon-litetest.service --no-pager -n3'
  R=$(guest 'systemctl is-active addon-litetest.service'); case "$R" in *'| active'*) ;; *) fail "addon-litetest.service not active after daemon-reload";; esac
  R=$(guest 'systemctl stop addon-litetest.service; pgrep -f "sleep 100000" | wc -l'); case "$R" in *'| 0'*) ;; *) fail "the addon's sleeper survived systemctl stop";; esac
  # task 27.4 / B-26: what the Services page stores on the userfs must be in force at the NEXT
  # boot before the units start - occu-unit-overrides.service, not occulited, does that. Seed an
  # override on hmipserver (the one interface daemon that runs on a VM without radio: its
  # VirtualDevices half; rfd is skipped by its marker condition since task 129) and a switch-off of
  # crond the way occulited writes them; boot 2 checks.
  say "guest: seeding a unit override and a switched-off unit for boot 2"; guest 'mkdir -p /usr/local/etc/occulite/unit-overrides && printf "[Service]\nEnvironment=OCCULITE_TEST=boot\n" >/usr/local/etc/occulite/unit-overrides/hmipserver.service.conf && printf "{\"masked\":[\"crond.service\"]}\n" >/usr/local/etc/occulite/unit-switch.json && ls -l /usr/local/etc/occulite/unit-overrides /usr/local/etc/occulite/unit-switch.json'
  # task 129 (D-82, D-97), the switch guarantee: a userfs as a CCU3 or OpenCCU leaves it - an
  # rfd.conf with a BidCos LAN gateway (unreachable here) and an InterfacesList.xml with an entry
  # another program added - boots with those connections and no lite setting: rfd runs on the
  # gateway alone (its local section off, no module), the interface list is the template's cut
  # for the hardware (BidCos-RF for the gateway, no HmIP-RF, the foreign entry lost as on OpenCCU).
  say "guest: seeding an OpenCCU-shaped userfs for boot 2 (a LAN gateway in rfd.conf, a foreign interface entry)"
  guest 'cp /usr/local/etc/config/rfd.conf /usr/local/etc/config/rfd.conf.lite-qemu-test 2>/dev/null; cp /etc/config_templates/rfd.conf /usr/local/etc/config/rfd.conf && printf "\n[Interface 1]\nType = HMLGW2\nSerial Number = KEQ0123456\nEncryption Key = 00000000000000000000000000000000\nIP Address = 192.0.2.1\n\n" >>/usr/local/etc/config/rfd.conf && { grep -v "</interfaces>" /etc/config_templates/InterfacesList.xml; printf "\t<ipc>\n\t \t<name>CCU-Jack</name>\n\t \t<url>xmlrpc://127.0.0.1:2121/RPC3</url> \n\t \t<info>CCU-Jack</info> \n\t</ipc>\n</interfaces>\n"; } >/usr/local/etc/config/InterfacesList.xml && grep -c Interface /usr/local/etc/config/rfd.conf && grep -c "<name>" /usr/local/etc/config/InterfacesList.xml'
  say "guest: rebooting"; guest 'systemctl --no-block reboot' >/dev/null
  # the shell on the other side dies with the reboot: end the driver, the next guest call reopens
  guest_close
  # the VM reboots in place (-kernel boots are not -no-reboot); wait until the endpoint is gone
  for i in $(seq 1 60); do
    curl -s --max-time 2 "http://127.0.0.1:$PORT/api/system/v1/health" >/dev/null 2>&1 || break
    sleep 2
  done
  wait_http "boot 2"
  guest_open # again in this shell, not in the first $( ) that follows
  say "guest (boot 2): the addon unit came back from the generator at boot, the journal remembers boot 1"
  guest 'systemctl is-system-running; systemctl --failed --no-legend --plain --no-pager; systemctl status addon-litetest.service --no-pager -n0 | sed -n 1,8p; journalctl --list-boots --no-pager; cat /etc/machine-id; cat /usr/local/etc/machine-id; journalctl -b --no-pager -o short-monotonic | grep -m1 "Startup finished"'
  R=$(guest 'systemctl is-active addon-litetest.service'); case "$R" in *'| active'*) ;; *) fail "addon-litetest.service not active after the reboot";; esac
  # counted by their rows: systemd 257 prints a header line above them
  R=$(guest 'journalctl --list-boots --no-pager | grep -cE "^ *-?[0-9]+ [0-9a-f]{32} "'); case "$R" in *'| 2'*) ;; *) fail "expected two boots in the persistent journal";; esac
  # D-41: the second boot starts on the stored ID, before journald - so both boots share it
  R=$(guest 'test "$(cat /etc/machine-id)" = "$(cat /usr/local/etc/machine-id)" && echo same || echo differs'); case "$R" in *'| same'*) ;; *) fail "boot 2 did not start on the stored machine ID (D-41)";; esac
  # task 27.4 / B-26, boot 2: the override is in rfd's environment without anyone restarting it,
  # crond is masked and never started, and the replayer finished before rfd began.
  say "guest (boot 2): the unit override and the switch were applied before the units started"
  guest 'systemctl status occu-unit-overrides.service --no-pager -n5 | sed -n 1,12p; systemctl show rfd.service -p Environment -p DropInPaths; systemctl is-enabled crond.service; systemctl is-active crond.service; journalctl -b -u crond.service --no-pager | wc -l; journalctl -b -o short-monotonic -u occu-unit-overrides.service -u rfd.service --no-pager | head -6'
  R=$(guest 'systemctl show hmipserver.service -p Environment --value'); case "$R" in *OCCULITE_TEST=boot*) ;; *) fail "the unit override was not in force at boot (task 27.4): $R";; esac
  R=$(guest 'systemctl is-enabled crond.service'); case "$R" in *masked*) ;; *) fail "crond was not masked at boot from unit-switch.json (B-26): $R";; esac
  R=$(guest 'journalctl -b -q --no-pager _COMM=crond | wc -l'); case "$R" in *'| 0'*) ;; *) fail "crond ran at boot 2 before the mask landed (B-26)";; esac
  R=$(guest 'A=$(systemctl show -p ExecMainExitTimestampMonotonic --value occu-unit-overrides.service); B=$(systemctl show -p InactiveExitTimestampMonotonic --value hmipserver.service); [ -n "$A" ] && [ -n "$B" ] && [ "$A" -lt "$B" ] && echo before || echo "after: $A vs $B"'); case "$R" in *'| before'*) ;; *) fail "occu-unit-overrides did not finish before hmipserver started: $R";; esac
  # task 129, boot 2: the switch guarantee. The plan ran (its markers and files), rfd runs on the
  # gateway alone, the interface list is the template's cut for the hardware, hmipserver runs
  # its VirtualDevices half, multimacd is skipped (inactive, not failed) without a module.
  say "guest (boot 2): the radio plan on an OpenCCU-shaped userfs"
  guest 'journalctl -b -o short-monotonic -u occu-init-rf-hardware.service --no-pager | grep -E "plan:|run:" | head -12; ls /run/occulite/radio; systemctl is-active multimacd.service rfd.service hmipserver.service hs485d.service occu-init-hs485d.service occu-interface-clock.service | tr "\n" " "; echo; grep -E "^#?\[Interface|^#?Type|^Listen" /var/etc/rfd.conf; grep -o "<name>[^<]*</name>" /usr/local/etc/config/InterfacesList.xml | tr "\n" " "; echo'
  R=$(guest 'test -e /run/occulite/radio/rfd.enabled && test ! -e /run/occulite/radio/multimacd.enabled && test -e /run/occulite/radio/hmipserver.enabled && echo markers-ok'); case "$R" in *'| markers-ok'*) ;; *) fail "the plan's markers: rfd and hmipserver expected, no multimacd (task 129): $R";; esac
  R=$(guest 'grep -q "^Type = HMLGW2" /var/etc/rfd.conf && grep -q "^#\[Interface 0\]" /var/etc/rfd.conf && grep -q "^Listen IP = 127.0.0.1" /var/etc/rfd.conf && echo rfdconf-ok'); case "$R" in *'| rfdconf-ok'*) ;; *) fail "rfd.conf on the userfs was not kept with its gateway, the local section off and the loopback line (task 129, D-82)";; esac
  R=$(guest 'grep -o "<name>[^<]*</name>" /usr/local/etc/config/InterfacesList.xml | tr "\n" " "'); case "$R" in *'BidCos-RF'*'VirtualDevices'*) case "$R" in *CCU-Jack*|*HmIP-RF*) fail "InterfacesList.xml must be the template's cut: no foreign entry (D-97), no HmIP-RF without a module: $R";; esac;; *) fail "InterfacesList.xml lost BidCos-RF (the gateway) or VirtualDevices: $R";; esac
  # the gateway here is a documentation address nobody answers: rfd runs and keeps trying it, so its
  # unit may stay "activating"; a refusal is failed or inactive
  R=$(guest 'systemctl is-active rfd.service'); case "$R" in *'| active'*|*'| activating'*) ;; *) fail "rfd did not run on the LAN gateway alone (task 129 measurement 8: does rfd refuse without a local interface?): $R";; esac
  R=$(guest 'systemctl is-active hmipserver.service'); case "$R" in *'| active'*) ;; *) fail "hmipserver (the VirtualDevices half) did not run: $R";; esac
  R=$(guest 'systemctl show -p Result --value multimacd.service; systemctl is-active multimacd.service'); case "$R" in *'| '*inactive*) ;; *) fail "multimacd must be skipped (inactive, not failed) without a module: $R";; esac
  # leave the image's userfs as the next test expects it: nothing switched off, no override, the
  # rfd.conf and interface list as the first boot made them
  guest 'rm -rf /usr/local/etc/occulite/unit-overrides /usr/local/etc/occulite/unit-switch.json /usr/local/etc/config/InterfacesList.xml; if [ -e /usr/local/etc/config/rfd.conf.lite-qemu-test ]; then mv /usr/local/etc/config/rfd.conf.lite-qemu-test /usr/local/etc/config/rfd.conf; else rm -f /usr/local/etc/config/rfd.conf; fi' >/dev/null
  guest 'systemctl --no-block poweroff' >/dev/null; sleep 15
  guest_close
fi

kill "$(cat "$WORK/qemu.pid")" 2>/dev/null; sleep 1
if [ "$FAILED" = 0 ]; then rm -rf "$WORK"; say "OK"; exit 0; fi
say "last serial output:"; tail -n 60 "$WORK/serial.log" 2>/dev/null | sed 's/^/  | /'; say "serial log kept at $WORK/serial.log"; exit 1

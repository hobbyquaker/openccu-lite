#!/bin/sh
# openccu-lite: the recovery frees the rpi_rf_mod:* LED names for an RPI-RF-MOD on an HB-RF-USB
# from whichever driver holds them (task 326).
#
#   - since the header overlay of task 315 the names belong to leds_pwm's rpi_rf_mod_leds, not to
#     leds-gpio's leds: S11InitRFHardware's block unbinds the LED's own device from its own driver
#     before rpi_rf_mod_led loads, and binds it again after, so the adapter's LEDs get the names
#     (the recovery's magenta shows on the adapter) and the header's come back as "..._1";
#   - upstream's leds-gpio case still works the same way, and the other driver is never touched;
#   - an LED without a parent device (rpi_rf_mod_led's own, a second run) or none at all: nothing
#     to unbind, the module loads all the same.
#
# The block runs extracted, in a sandbox: /sys under a temporary directory, modprobe a stand-in.
# Nothing needs root or the recovery image.
#
# Usage: sh scripts/testcases/lite-recovery-hbrf-led-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
S11="$HERE/buildroot-external/package/recovery-system/external/overlay/base/etc/init.d/S11InitRFHardware"

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

sh -n "$S11" && ok "S11InitRFHardware parses" || bad "S11InitRFHardware does not parse"
if grep -q 'leds-gpio/unbind\|leds-gpio/bind' "$S11"; then
  bad "S11InitRFHardware still unbinds leds-gpio by name"
else
  ok "no driver is unbound by name"
fi

# the block from the unbind to the module's rebind, with /sys under the sandbox
sed -n '/# make sure to unbind the driver that holds the rpi_rf_mod/,/# setup the LEDs to show a slowly blinking magenta light/p' "$S11" |
  sed "s|/sys/|$T/sys/|g" >"$T/block.sh"
[ -s "$T/block.sh" ] && ok "the LED block found" || bad "the LED block is not in S11InitRFHardware"

# a sysfs: both drivers, the device bound to $1, its LEDs pointing at it ("" = LEDs without a device)
make_sys() {
  rm -rf "$T/sys"
  for d in leds_pwm leds-gpio; do
    mkdir -p "$T/sys/bus/platform/drivers/$d"
    : >"$T/sys/bus/platform/drivers/$d/bind"
    : >"$T/sys/bus/platform/drivers/$d/unbind"
  done
  mkdir -p "$T/sys/class/leds/rpi_rf_mod:blue"
  [ -n "$1" ] || return 0
  mkdir -p "$T/sys/devices/platform/$2"
  ln -s "../../../bus/platform/drivers/$1" "$T/sys/devices/platform/$2/driver"
  ln -s "../../../../devices/platform/$2" "$T/sys/bus/platform/drivers/$1/$2"
  ln -s "../../../devices/platform/$2" "$T/sys/class/leds/rpi_rf_mod:blue/device"
}

# runs the block under bash (the recovery's ash has [[ ]], dash has not); modprobe records what
# the driver's files held when it ran, and the unbind takes the device out of the driver's directory
run_block() {
  bash -c "
    RED_GPIO_PIN=2 GREEN_GPIO_PIN=1 BLUE_GPIO_PIN=0
    modprobe() {
      for d in leds_pwm leds-gpio; do
        echo \"\$d unbind=\$(cat '$T/sys/bus/platform/drivers/'\$d/unbind) bind=\$(cat '$T/sys/bus/platform/drivers/'\$d/bind)\"
      done >'$T/at-modprobe'
      [ -s '$T/sys/bus/platform/drivers/$1/unbind' ] && rm -f '$T/sys/bus/platform/drivers/$1/$2'
      echo \"\$*\" >'$T/modprobe-args'
    }
    . '$T/block.sh'
  "
}

for c in "leds_pwm rpi_rf_mod_leds" "leds-gpio leds"; do
  # shellcheck disable=SC2086 # the pair splits on purpose
  set -- $c
  other=leds-gpio; [ "$1" = leds-gpio ] && other=leds_pwm
  make_sys "$1" "$2"
  rm -f "$T/at-modprobe" "$T/modprobe-args"
  run_block "$1" "$2"
  grep -q "^$1 unbind=$2 bind=\$" "$T/at-modprobe" && ok "$1: $2 unbound before the module loads, not bound yet" || bad "$1: at modprobe: $(cat "$T/at-modprobe" 2>/dev/null)"
  grep -q "^rpi_rf_mod_led red_gpio_pin=2 green_gpio_pin=1 blue_gpio_pin=0\$" "$T/modprobe-args" && ok "$1: rpi_rf_mod_led loaded with the adapter's pins" || bad "$1: modprobe $(cat "$T/modprobe-args" 2>/dev/null)"
  [ "$(cat "$T/sys/bus/platform/drivers/$1/bind")" = "$2" ] && ok "$1: $2 bound again after it" || bad "$1: bind holds '$(cat "$T/sys/bus/platform/drivers/$1/bind")'"
  [ ! -s "$T/sys/bus/platform/drivers/$other/unbind" ] && [ ! -s "$T/sys/bus/platform/drivers/$other/bind" ] && ok "$1: $other untouched" || bad "$1: $other touched"
done

# LEDs without a parent device: nothing unbound or bound, the module loads
make_sys ""
rm -f "$T/modprobe-args"
run_block none none
[ -s "$T/modprobe-args" ] && ok "no device: the module loads" || bad "no device: no modprobe"
for d in leds_pwm leds-gpio; do
  [ ! -s "$T/sys/bus/platform/drivers/$d/unbind" ] && [ ! -s "$T/sys/bus/platform/drivers/$d/bind" ] || bad "no device: $d touched"
done
ok "no device: no driver touched"

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }

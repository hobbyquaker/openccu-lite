#!/bin/sh
# openccu-lite (task 315): the status LED's device tree and boot files, checked statically and -
# where dtc is on PATH - by compiling the overlay as package/rpi-rf-mod does.
#
#   - package/rpi-rf-mod/dts/rpi-rf-mod.dts: three pwm-gpio providers on GPIO 16, 20, 21, a pwm-leds
#     node with upstream's three labels (the sysfs names every writer uses), max-brightness 255, the
#     4 ms period, red and green on and blue off from the probe, no gpio-leds children left behind,
#     the pin setup and the uart0 fragment unchanged;
#   - board/rpi{3,4,5}/config.txt: GPIO 16 and 20 driven high and 21 low by the firmware, after the
#     overlay line;
#   - board/rpi{3,4}/boot.cmd: rootwait without rootdelay;
#   - the kernel fragments every Pi kernel shares with its recovery kernel: CONFIG_PWM_GPIO=y in
#     board/rpi{3,4,5}/kernel.config, CONFIG_LEDS_TRIGGER_PATTERN=y in kernel/6.18/global.config -
#     built in, because the recovery system loads no modules and the LED must be lit from the probe.
#
# Usage: sh scripts/testcases/lite-status-led-dts-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
EXT="$HERE/buildroot-external"
DTS="$EXT/package/rpi-rf-mod/dts/rpi-rf-mod.dts"
[ -f "$DTS" ] || { echo "rpi-rf-mod.dts not found at $DTS"; exit 2; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }
has() { # <file> <pattern (grep -E)> <what>
  grep -Eq "$2" "$1" && ok "$3" || bad "$3: $2 not in ${1#"$HERE"/}"
}
lacks() { # <file> <pattern (grep -E)> <what>
  grep -Eq "$2" "$1" && bad "$3: $2 still in ${1#"$HERE"/}" || ok "$3"
}

# the overlay's text
for pin in 16 20 21; do
  has "$DTS" "compatible = \"pwm-gpio\";" "a pwm-gpio provider exists"
  has "$DTS" "gpios = <&gpio $pin 0>;" "GPIO $pin is a PWM provider's line"
done
[ "$(grep -c 'compatible = "pwm-gpio";' "$DTS")" = 3 ] && ok "exactly three pwm-gpio providers" || bad "pwm-gpio providers: $(grep -c 'compatible = "pwm-gpio";' "$DTS"), want 3"
[ "$(grep -c '#pwm-cells = <3>;' "$DTS")" = 3 ] && ok "each provider has #pwm-cells = <3>" || bad "#pwm-cells = <3>: $(grep -c '#pwm-cells = <3>;' "$DTS"), want 3"
has "$DTS" 'compatible = "pwm-leds";' "a pwm-leds node"
for c in red green blue; do
  has "$DTS" "label = \"rpi_rf_mod:$c\";" "the label rpi_rf_mod:$c (upstream's sysfs name)"
  has "$DTS" "pwms = <&rpi_rf_mod_pwm_$c 0 4000000 0>;" "$c: its own provider, 4 ms period"
done
[ "$(grep -c 'max-brightness = <255>;' "$DTS")" = 3 ] && ok "max-brightness 255 on all three" || bad "max-brightness = <255>: $(grep -c 'max-brightness = <255>;' "$DTS"), want 3"
red_on=$(awk '/led-red/,/};/' "$DTS" | grep -c 'default-state = "on"')
green_on=$(awk '/led-green/,/};/' "$DTS" | grep -c 'default-state = "on"')
blue_off=$(awk '/led-blue/,/};/' "$DTS" | grep -c 'default-state = "off"')
[ "$red_on$green_on$blue_off" = 111 ] && ok "red and green on, blue off from the probe (the boot's yellow)" || bad "default-state: red on=$red_on green on=$green_on blue off=$blue_off"
lacks "$DTS" 'default-state = "keep"' "no gpio-leds \"keep\" left (pwm-gpio has no state to keep)"
lacks "$DTS" 'gpios = <&gpio (16|20|21) 0>;[[:space:]]*default-state' "no gpio-leds child on the LED pins"
has "$DTS" 'brcm,pins = <19 18 12 16 20 21>;' "the pin setup is upstream's"
has "$DTS" 'pivccu,led-gpios = <&gpio 16 0>, <&gpio 20 0>, <&gpio 21 0>;' "generic_raw_uart still learns the LED pins"
has "$DTS" 'pinctrl-0 = <&rpi_rf_mod_pins>;' "the pin setup is still applied"

# the overlay compiles as the package builds it, and the compiled tree has the nodes
if command -v dtc >/dev/null 2>&1; then
  if dtc -@ -I dts -O dtb -W no-unit_address_vs_reg -o "$T/rpi-rf-mod.dtbo" "$DTS" > "$T/dtc.log" 2>&1; then
    ok "dtc compiles the overlay"
    [ -s "$T/dtc.log" ] && bad "dtc warned: $(head -3 "$T/dtc.log")" || ok "dtc is silent"
    # back to source: the labels and the pwm phandles survive
    dtc -I dtb -O dts -o "$T/back.dts" "$T/rpi-rf-mod.dtbo" 2>/dev/null
    for c in red green blue; do has "$T/back.dts" "label = \"rpi_rf_mod:$c\";" "compiled: the label rpi_rf_mod:$c"; done
    has "$T/back.dts" 'compatible = "pwm-leds";' "compiled: the pwm-leds node"
    [ "$(grep -c 'compatible = "pwm-gpio";' "$T/back.dts")" = 3 ] && ok "compiled: three pwm-gpio providers" || bad "compiled: pwm-gpio providers"
    # the __fixups__ carry the base tree's labels the overlay needs, and only those
    has "$T/back.dts" '__fixups__' "compiled: an overlay with fixups"
    for l in gpio leds i2c1 uart0 chosen; do has "$T/back.dts" "[[:space:]]$l = " "compiled: fixup for &$l"; done
  else
    bad "dtc refused the overlay: $(head -5 "$T/dtc.log")"
  fi
else
  echo "note dtc not on PATH: the overlay's compile check is skipped here (the build host and the images' build run it)"
fi

# config.txt: the firmware lights yellow before the kernel, after the overlay is named
for b in rpi3 rpi4 rpi5; do
  f="$EXT/board/$b/config.txt"
  has "$f" '^gpio=16,20=op,dh$' "$b/config.txt: GPIO 16 and 20 high (yellow) from start.elf"
  has "$f" '^gpio=21=op,dl$' "$b/config.txt: GPIO 21 low (no blue)"
  has "$f" '^dtoverlay=rpi-rf-mod$' "$b/config.txt: the overlay is loaded"
  o=$(grep -n '^dtoverlay=rpi-rf-mod$' "$f" | cut -d: -f1); g=$(grep -n '^gpio=16,20=op,dh$' "$f" | cut -d: -f1)
  [ -n "$o" ] && [ -n "$g" ] && [ "$g" -gt "$o" ] && ok "$b/config.txt: the gpio lines follow the overlay line" || bad "$b/config.txt: gpio lines before the overlay"
  grep -q 'include extraconfig.txt' "$f" && [ "$g" -lt "$(grep -n 'include extraconfig.txt' "$f" | cut -d: -f1)" ] && ok "$b/config.txt: the user's extraconfig.txt still comes last" || bad "$b/config.txt: extraconfig.txt order"
done

# boot.cmd: no fixed five seconds before the root mount
for b in rpi3 rpi4; do
  f="$EXT/board/$b/boot.cmd"
  has "$f" '^setenv bootargs ".* rootwait ' "$b/boot.cmd: rootwait"
  grep -E '^setenv bootargs ' "$f" | grep -q 'rootdelay' && bad "$b/boot.cmd: rootdelay still on the kernel line" || ok "$b/boot.cmd: no rootdelay on the kernel line"
done

# the kernel fragments the recovery kernel shares (its configs name global.config and the board's kernel.config)
for b in rpi3 rpi4 rpi5; do
  has "$EXT/board/$b/kernel.config" '^CONFIG_PWM_GPIO=y$' "$b/kernel.config: pwm-gpio built in"
  rc="$EXT/package/recovery-system/external/configs/recovery_$b.config"
  [ -f "$rc" ] && { grep -q "board/$b/kernel.config" "$rc" && ok "recovery_$b.config shares board/$b/kernel.config" || bad "recovery_$b.config does not name board/$b/kernel.config"; }
done
has "$EXT/kernel/6.18/global.config" '^CONFIG_LEDS_TRIGGER_PATTERN=y$' "global.config: the pattern trigger built in"
for c in "$EXT"/package/recovery-system/external/configs/recovery_rpi*.config "$EXT"/configs/aarch64-rpi*.config; do
  grep -q 'kernel/6.18/global.config' "$c" && ok "${c##*/} names global.config" || bad "${c##*/} does not name global.config"
done

[ "$fails" -eq 0 ] && echo "all ok" || { echo "$fails failure(s)"; exit 1; }

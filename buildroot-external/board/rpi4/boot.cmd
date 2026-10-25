# modify bootargs, load kernel and boot it
# fallback defaults
setenv load_addr ${ramdisk_addr_r}
setenv console "tty2"
setenv loglevel "0"
setenv bootfs 1
setenv rootfs 2
setenv userfs 3
setenv gpio_button "GPIO12"
setenv kernel_img /Image
setenv kernel_bootcmd booti
setenv recoveryfs_initrd "recoveryfs-initrd"
setenv usbstoragequirks "174c:55aa:u,2109:0715:u,152d:0578:u,152d:0579:u,152d:1561:u,174c:0829:u,14b0:0206:u,174c:225c:u,7825:a2a4:u,152d:0562:u,125f:a88a:u,152d:a583:u,152d:a578:u,152d:0583:u,0bda:9201:u,0634:5605:u,174c:235c:u,174c:1156:u"

# openccu-lite (task 381): a reboot from the running system leaves the SoC's PM watchdog armed (Linux arms it
# for its restart, systemd's reboot watchdog keeps it running; about 16 s at most, ~14 s left when this script
# starts), and U-Boot does not service it. Reading the SD card at a fifth of its speed (U-Boot's EMMC2 clock bug,
# fixed by our patch 0008), U-Boot 2026.10 took ~18 s to load the recovery, and the watchdog reset the board
# before the recovery's kernel started - over and over. At full speed the loads take ~4 s; rewinding the watchdog
# to its maximum before every large load and before booting keeps a slow card or a CM4's eMMC inside the window,
# too. Only the timer value is written; the reset configuration (PM_RSTC) is left as it is, and Linux's
# bcm2835-wdt takes the watchdog over from there. PM_WDOG of the BCM2711: 0xfe100024.
setenv wdt_pet "mw.l 0xfe100024 0x5a0fffff"
run wdt_pet

# output where we are booting from
itest.b ${devnum} == 0 && echo "U-boot loaded from SD"
itest.b ${devnum} == 1 && echo "U-boot loaded from eMMC"

# import environment from /boot/bootEnv.txt
if test -e ${devtype} ${devnum}:${bootfs} bootEnv.txt; then
  load ${devtype} ${devnum}:${bootfs} ${load_addr} bootEnv.txt
  env import -t ${load_addr} ${filesize}
fi

# test if the gpio button is 0 (pressed) or if .recoveryMode exists in userfs
# or if Image doesn't exist in the root partition
gpio input ${gpio_button}
if test $? -eq 0 -o -e ${devtype} ${devnum}:${userfs} /.recoveryMode -o ! -e ${devtype} ${devnum}:${rootfs} ${kernel_img}; then
  echo "==== STARTING RECOVERY SYSTEM ===="
  # load the initrd file
  run wdt_pet
  load ${devtype} ${devnum}:${bootfs} ${load_addr} ${recoveryfs_initrd}
  # keep the initrd where it was loaded, as U-Boot 2023.01 did (its initrd_high was ~0): 2026.10's default
  # bootm_size=0x20000000 makes booti copy it below 512 MiB, into the BCM2711's CMA range, and the kernel then
  # cannot reserve its 512 MiB CMA pool (8 MiB fallback; task 381)
  setenv initrd_high "0xffffffffffffffff"
  setenv rootfs_str "/dev/ram0"
  setenv initrd_addr_r ${load_addr}
  setenv kernel_img "/recoveryfs-Image"
  setenv kernel_bootcmd booti
  setenv kernelfs ${bootfs}
else
  echo "==== NORMAL BOOT ===="
  # get partuuid of root_num
  part uuid ${devtype} ${devnum}:${rootfs} partuuid
  setenv rootfs_str "PARTUUID=${partuuid}"
  setenv initrd_addr_r "-"
  setenv kernelfs ${rootfs}
fi

# load devicetree
setenv fdt_org ${fdt_addr}
fdt addr ${fdt_org}
fdt get value bootargs /chosen bootargs

# set bootargs; cgroup_enable=memory stands after the firmware's own ${bootargs}, which carry
# cgroup_disable=memory, so that the memory cgroup controller is available. openccu-lite (task 315):
# no rootdelay=5 - rootwait alone waits for the root device, an SD card or a USB disk, for as long
# as it takes and not a fixed five seconds longer; upstream's line keeps the delay.
setenv bootargs "dwc_otg.lpm_enable=0 sdhci_bcm2708.enable_llm=0 console=${console} root=${rootfs_str} ro rootfstype=ext4 fsck.repair=yes rootwait consoleblank=120 logo.nologo quiet loglevel=${loglevel} init_on_alloc=1 init_on_free=1 slab_nomerge iomem=relaxed net.ifnames=0 usb-storage.quirks=${usbstoragequirks} ${extraargs} ${bootargs} cgroup_enable=memory cgroup_memory=1"

# load kernel
run wdt_pet
load ${devtype} ${devnum}:${kernelfs} ${kernel_addr_r} ${kernel_img}

# Relocate the FDT below the firmware-provided one, otherwise it ends up just
# below 512 MiB and fragments the CMA alloc-range (first 768 MiB on BCM2711)
setenv fdt_high ${fdt_org}

# boot kernel
echo "Starting kernel"
run wdt_pet
${kernel_bootcmd} ${kernel_addr_r} ${initrd_addr_r} ${fdt_addr}

echo "Boot failed, resetting..."
reset

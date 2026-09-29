################################################################################
#
# occulited - the openccu-lite system service (lite-only)
#
# Built from GitHub's source archive of the occulited repository
# (github.com/hobbyquaker/occulited) at a pinned commit, vendored by buildroot's
# Go infrastructure at download time. Everything installed here comes out of that archive: the Go binary
# (the web UI is embedded from internal/ui/dist, which the repository commits
# so that this build needs no Node), deploy/lighttpd/*, deploy/init/* and the
# tclrega shim in deploy/tclrega, compiled with the target toolchain.
#
################################################################################

OCCULITED_VERSION = 5655295691dd13d9528f811cd345f4458405f948
OCCULITED_SITE = $(call github,hobbyquaker,occulited,$(OCCULITED_VERSION))
OCCULITED_LICENSE = GPL-3.0-only
OCCULITED_LICENSE_FILES = LICENSE
# openccu-base is a dependency for the install order, not for the build: buildroot installs the
# packages in dependency order, and package/openccu-base installs /lib/tclrega.so (the real one,
# which asks ReGaHss) whenever BR2_PACKAGE_OPENCCU_BASE_REGAHSS is on. The lite configs switch
# that off, and this dependency is the second guard: the shim below is installed after the base
# package whatever the option says, and board/lite/post-build.sh stops the build when
# /lib/tclrega.so is not the shim (task 126, pitfall 1).
OCCULITED_DEPENDENCIES = tcl openccu-base

OCCULITED_GOMOD = github.com/hobbyquaker/occulited
OCCULITED_BUILD_TARGETS = cmd/occulited
OCCULITED_LDFLAGS = -s -w -X main.version=$(OCCULITED_VERSION)
# a static binary, no cgo, ever (D-15)
OCCULITED_GO_ENV = CGO_ENABLED=0
# Not a PIE (task 261, measured with buildroot's Go 1.26): without cgo, `-buildmode=pie` gives a
# PIE with PT_INTERP - no shared library, but glibc's loader must be at /lib64/ld-linux-x86-64.so.2
# or /lib/ld-linux-aarch64.so.1 to run it - and refuses linux/arm outright; `-ldflags=-d` writes a
# static PIE that segfaults at start (the Go runtime does not relocate itself); a real static PIE
# takes external linking with cgo and glibc's start-up code, which D-15 rules out. So the binary is
# static and not position-independent, and scripts/lite-hardening-guard.sh expects exactly that.

# the tclrega shim: one C file against the target tcl.h; full RELRO like lighttpd's modules
# (lite-hardening.mk), the wrapper adds -fPIE/-z relro, the stack protector and FORTIFY
define OCCULITED_BUILD_TCLREGA
	$(TARGET_CC) $(TARGET_CFLAGS) -fPIC -shared -Wl,-z,now \
		-I$(STAGING_DIR)/usr/include \
		-o $(@D)/deploy/tclrega/tclrega.so $(@D)/deploy/tclrega/tclrega.c
endef
OCCULITED_POST_BUILD_HOOKS += OCCULITED_BUILD_TCLREGA

define OCCULITED_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/bin/occulited $(TARGET_DIR)/usr/bin/occulited
	$(INSTALL) -D -m 0755 $(@D)/deploy/tclrega/tclrega.so $(TARGET_DIR)/lib/tclrega.so
	$(INSTALL) -D -m 0644 $(@D)/deploy/lighttpd/occulited.conf $(TARGET_DIR)/etc/lighttpd/conf.d/occulited.conf
	$(INSTALL) -D -m 0644 $(@D)/deploy/lighttpd/occulite-gate.lua $(TARGET_DIR)/etc/lighttpd/occulite-gate.lua
	$(INSTALL) -D -m 0644 $(@D)/deploy/lighttpd/occulite-starting.lua $(TARGET_DIR)/etc/lighttpd/occulite-starting.lua
	$(INSTALL) -D -m 0644 $(@D)/deploy/lighttpd/occulite-starting.html $(TARGET_DIR)/etc/lighttpd/occulite-starting.html
	$(OCCULITED_INSTALL_UNIT_STATE)
	$(OCCULITED_INSTALL_CATALOG)
endef

# task 283: the script occulited.service's hooks run as root to keep the waiting page's state file
# (/run/occulite/occulited-state.json). The guard is for a pin older than the occulited commit
# that added it: that archive's unit does not call it either (its "-" prefix would skip a missing
# script anyway).
define OCCULITED_INSTALL_UNIT_STATE
	if [ -f $(@D)/deploy/systemd/occulited-unit-state ]; then \
		$(INSTALL) -D -m 0755 $(@D)/deploy/systemd/occulited-unit-state $(TARGET_DIR)/usr/libexec/occulited/unit-state; \
	fi
endef

# The catalogue from the same archive as the binary. The guard is for a pin older than the
# commit that added catalog/ (occulited 594ede7): such an image carries no offline copy and
# occulited reads the published file alone; it goes with the next pin.
define OCCULITED_INSTALL_CATALOG
	if [ -f $(@D)/catalog/catalog.json ]; then \
		$(INSTALL) -D -m 0644 $(@D)/catalog/catalog.json $(TARGET_DIR)/etc/occulite/catalog.json; \
		mkdir -p $(TARGET_DIR)/etc/occulite/manifests; \
		for m in $(@D)/catalog/manifests/*.json; do \
			$(INSTALL) -m 0644 $$m $(TARGET_DIR)/etc/occulite/manifests/; \
		done; \
	fi
endef

# the units from the same archive (task 20, D-30). Every product is systemd (D-39); the busybox
# init script and its SYSV hook went with task 187, and occulited without systemd is a read-only
# development mode, not a product
define OCCULITED_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 $(@D)/deploy/systemd/occulited.service $(TARGET_DIR)/usr/lib/systemd/system/occulited.service
	$(INSTALL) -D -m 0644 $(@D)/deploy/systemd/occulited-helper.service $(TARGET_DIR)/usr/lib/systemd/system/occulited-helper.service
	$(INSTALL) -D -m 0644 $(@D)/deploy/systemd/occulited.tmpfiles.conf $(TARGET_DIR)/usr/lib/tmpfiles.d/occulited.conf
endef

# task 17: the daemon runs as occulite; `occulited helper` (root) does the privileged work.
# The id is pinned, not auto-allocated (B-34): `-1` handed out 106:114, which is `sshd`:`hssled`
# in upstream's own images, so a box that switches back to OpenCCU (D-35) hands the metadata
# store - users.json, the local token - to upstream's sshd privilege-separation user. 8100 is
# outside every id upstream assigns. Ownership is repaired at boot either way (through
# occulited.tmpfiles.conf's `Z`), so an image
# built before this change updates cleanly to one built after it.
# D-46: the certs group may read /etc/config/server.pem (root:certs 0640, set by lite-cert-perms
# after every lighttpd start and reload); occulited puts every confined addon into it. The gid is
# pinned like the occulite uid, for the same reason (B-34).
# B-259: the usbstorage group reads and writes USB sticks with FAT, exFAT or NTFS, which carry no
# owner of their own: usbmount mounts them root:usbstorage with umask 0007
# (overlay/lite/etc/usbmount/usbmount.conf). occulite is its member (it lists and restores the
# backups there) - through /etc/group rather than the unit, so an occulited unit never names a group
# an older image lacks; a confined addon joins by declaring it in its manifest. The gid is pinned
# (B-34).
# D-55 (task 67): the interface daemons run as users of their own - rfd, hmipserver, multimacd,
# hs485d and hmlangw, 8110-8114, each in a group of its own name - and the device nodes carry
# resource groups (raw-uart, eq3loop, mmd-bidcos, mmd-hmip, 990-993) that udev and the
# lite-radio-prep helper set. Those four own device nodes only, so they are system groups (below
# systemd's SYS_GID_MAX of 999): udev deprecates GROUP= on a device node for any other group and
# says so at every rules reload. They sit at the top of the system range, where neither this
# image's nor upstream's automatic allocation (from 100 upwards) reaches, and they own nothing on
# the userfs - the nodes are made at every boot - so moving them from 8120-8123 needs no
# migration. The daemons' own ids stay: they own files on the userfs and no device node. The groups field of each user stays empty: membership is each
# unit's SupplementaryGroups=, so /etc/group says nothing a unit does not. Fixed ids for the
# B-34 reason above: the daemons' files on the userfs (rfd's device files and keys, hmipserver's
# crRFD and eshlight, hs485d's device files) keep these numeric owners across an update, and no
# upstream account, auto-allocated from 100, can inherit them on a box that goes back to OpenCCU.
define OCCULITED_USERS
	occulite 8100 occulite 8100 * /usr/local/etc/occulite - usbstorage openccu-lite system service
	- -1 certs 8101 * - - - TLS certificate readers (D-46)
	- -1 usbstorage 8102 * - - - USB stick readers and writers (B-259)
	rfd 8110 rfd 8110 * - - - BidCos-RF interface daemon (D-55)
	hmipserver 8111 hmipserver 8111 * - - - HmIP interface server (D-55)
	multimacd 8112 multimacd 8112 * - - - radio module multiplexer (D-55)
	hs485d 8113 hs485d 8113 * - - - BidCos-Wired interface daemon (D-55)
	hmlangw 8114 hmlangw 8114 * - - - LAN gateway mode daemon (D-55)
	- -1 raw-uart 990 * - - - radio module raw UART (D-55)
	- -1 eq3loop 991 * - - - eq3loop multiplexer master (D-55)
	- -1 mmd-bidcos 992 * - - - the multiplexer BidCos-RF endpoint (D-55)
	- -1 mmd-hmip 993 * - - - the multiplexer HmIP endpoint (D-55)
endef

$(eval $(golang-package))

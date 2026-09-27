################################################################################
#
# openccu-lite: link flags on top of buildroot's hardening (lite-only)
#
# Buildroot.config asks for PIE, the strong stack protector, FORTIFY_SOURCE and *partial* RELRO
# (BR2_RELRO_PARTIAL): the toolchain wrapper adds `-Wl,-z,relro` to every link, and the GOT's
# non-PLT part is read-only once the program runs. Full RELRO (`-z now` on top) binds every symbol
# at start and makes the whole GOT read-only before the first line of the program runs - the usual
# default of the distributions, at the cost of the symbol lookups moving from the first call to the
# exec (microseconds for busybox, see the roadmap item). sshd and systemd link so on their own;
# chrony's configure would too, but only when nothing sets CFLAGS, and buildroot always does.
#
# Here it is switched on for the C programs this image builds that parse what the network sends or
# run as root at boot: lighttpd (the one LAN-facing daemon, with its modules), busybox (udhcpc as
# root, and hundreds of execs per boot) and chronyd (NTP replies from the internet). Each line sets
# the variable the package's build reads at link time, so a `<pkg>-reconfigure` in a warm tree picks
# it up; scripts/lite-hardening-guard.sh (the lite post-build) fails the build when a binary comes
# out without it. The switch for the whole image is BR2_RELRO_FULL=y in Buildroot.config - it lives
# in the wrapper that gcc-final builds, so it wants a clean build; when that happens these lines go.
#
################################################################################

# busybox: EXTRA_LDFLAGS of the final link (package/busybox/busybox.mk, BUSYBOX_MAKE_OPTS)
BUSYBOX_LDFLAGS += -Wl,-z,now

# lighttpd: the meson cross file's c_link_args, executables and modules alike
LIGHTTPD_LDFLAGS += -Wl,-z,now

# chrony: a hand-written configure that reads $LDFLAGS and takes no VAR=value argument, so the
# recipe is upstream's (package/chrony/chrony.mk) with the flag added behind TARGET_CONFIGURE_OPTS
define CHRONY_CONFIGURE_CMDS
	cd $(@D) && $(TARGET_CONFIGURE_OPTS) LDFLAGS="$(TARGET_LDFLAGS) -Wl,-z,now" ./configure $(CHRONY_CONF_OPTS)
endef

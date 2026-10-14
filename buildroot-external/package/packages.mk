# Load the Base version before generic-package freezes the versions of the
# nested builds. Keep the revision in openccu-base.mk for the update tooling.
OPENCCU_PACKAGE_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

# LITE_INPUTS_STAMP(pkg,PKG): the inputs a package's build takes besides its version and its
# source, $(PKG_INPUTS), are kept in $(PKG_DIR)/.lite_inputs, which is rewritten only when they
# change; the configure stamp depends on it. A changed input reruns the package from its configure
# step on (as <pkg>-reconfigure would) in the same build directory, an unchanged one does not
# (openccu-lite task 353: multilib32 and recovery-system, whose nested builds are incremental
# themselves). The configure step, not the build step: buildroot takes the snapshot of the target
# that the package's file list (packages-file-list.txt, the SBOM's source) is computed against
# there; a rerun from the build step would leave the package with an empty file list. Call it
# after the package's $(eval $(generic-package)).
define LITE_INPUTS_STAMP
.PHONY: $(1)-lite-inputs-check
$(1)-lite-inputs-check:
$$($(2)_DIR)/.stamp_configured: $$($(2)_DIR)/.lite_inputs
$$($(2)_DIR)/.lite_inputs: $(1)-lite-inputs-check
	@mkdir -p $$(@D)
	@if [ "$$$$(cat $$@ 2>/dev/null)" != '$$($(2)_INPUTS)' ]; then \
		test ! -f $$@ || echo "$(1): inputs changed: $$$$(cat $$@) -> $$($(2)_INPUTS)"; \
		printf '%s\n' '$$($(2)_INPUTS)' > $$@; \
	fi
endef

include $(OPENCCU_PACKAGE_DIR)openccu-base/openccu-base.mk
include $(sort $(filter-out %/openccu-base/openccu-base.mk, \
	$(wildcard $(OPENCCU_PACKAGE_DIR)*/*.mk)))

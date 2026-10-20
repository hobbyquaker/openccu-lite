#!/bin/bash
# shellcheck source=/dev/null
# openccu-lite (B-330): generic_raw_uart is built from the piVCCU fork's lite (task 373), pinned to a tag of
# the fork or a commit on lite, never to Alex's master. generic_raw_uart and detect_radio_module
# share the pin: a round runs both scripts. See scripts/utils/pivccu-fork.sh.
#
# Usage: scripts/update-generic_raw_uart.sh [<tag or 40-character commit>]   (from the repository's root)
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/utils.sh"
source "${SCRIPT_DIR}/utils/pivccu-fork.sh"

pivccu_fork_update "generic_raw_uart" "${1:-}"

#!/bin/sh
# openccu-lite: a stand-in for OpenCCU's /bin/triggerAlarm.tcl.
#
# Upstream's script sets a ReGa alarm variable through tclrega; there is no ReGaHss in the lite
# image, so board/lite/post-build.sh deletes it - and left its callers behind. The one
# that survives the lite image's package reductions is cronBackup.sh, which calls it on both of its
# failure paths and then exits 1, so a failed nightly backup used to end in "not found" in the
# journal and no notification anywhere.
#
# This writes the alarm to the journal instead, under its own syslog identifier, so occulited's
# log view and the Status page have something to show. The name is upstream's ABI: it
# is what the callers call, .tcl and all. board/lite/post-build.sh recognises this file by the
# marker below and keeps it where it deletes upstream's.
#
# usage: triggerAlarm.tcl <message> [<alarm variable name>] [<true|false>]
message=${1:-"alarm"}
variable=${2:-}
state=${3:-true}

text="${message}"
[ -n "${variable}" ] && text="${text} [${variable}=${state}]"

if command -v logger >/dev/null 2>&1; then
	logger -t triggerAlarm -p daemon.err -- "${text}"
fi

# stderr as well: when the caller runs inside a unit this is the journal entry that carries the
# unit's identity, which is what makes the failure findable.
echo "triggerAlarm: ${text}" >&2

exit 0

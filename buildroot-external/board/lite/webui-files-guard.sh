#!/bin/sh
# openccu-lite: the WebUI's files in the image (task 331). package/openccu-base installs the files
# of OpenCCU's WebUI that addons read on a CCU, at the CCU's paths: the device pictures
# (/www/config/img/devices/50 and 250), their catalogue /www/config/devdescr/DEVDB.tcl,
# /www/config/stringtable_de.txt and /www/webui/js/lang/<lang>/translate.lang*.js, which lighttpd
# serves read-only (the lite webui.conf). The build stops when /www/config or /www/webui holds
# anything else - another file, a link, a file not 0644 or a directory not 0755 - or when one of
# them is missing.
#
# Usage: webui-files-guard.sh TARGET_DIR    (board/lite/post-build.sh)
set -eu
target=${1:?usage: webui-files-guard.sh TARGET_DIR}
lite_www_files='^(config/img/devices/(50|250)/.+\.png|config/devdescr/DEVDB\.tcl|config/stringtable_de\.txt|webui/js/lang/[^/]+/translate\.lang[^/]*\.js)$'
lite_www_dirs='^(config|config/img|config/img/devices|config/img/devices/(50|250)(/.+)?|config/devdescr|webui|webui/js|webui/js/lang|webui/js/lang/[^/]+)$'
lite_www_extra=$(cd "${target}/www" && {
	# (grep finds nothing in a good image: its status must not end the list under set -e)
	find config webui -type f | grep -Ev "${lite_www_files}" || :
	find config webui -type d | grep -Ev "${lite_www_dirs}" || :
	find config webui ! -type f ! -type d
	find config webui -type f ! -perm 0644
	find config webui -type d ! -perm 0755
} | head -n 5)
if [ -n "${lite_www_extra}" ]; then
	echo "webui-files-guard: ERROR: /www/config or /www/webui holds what is not the WebUI's files for addons (or with another mode): ${lite_www_extra}" >&2
	exit 1
fi
for lite_www in config/devdescr/DEVDB.tcl config/stringtable_de.txt webui/js/lang/de/translate.lang.js webui/js/lang/en/translate.lang.js; do
	if [ ! -s "${target}/www/${lite_www}" ]; then
		echo "webui-files-guard: ERROR: /www/${lite_www} is missing - package/openccu-base installs it for addons" >&2
		exit 1
	fi
done
for lite_www in 50 250; do
	if [ "$(find "${target}/www/config/img/devices/${lite_www}" -name '*.png' | wc -l)" -lt 100 ]; then
		echo "webui-files-guard: ERROR: /www/config/img/devices/${lite_www} holds fewer than 100 device pictures" >&2
		exit 1
	fi
done

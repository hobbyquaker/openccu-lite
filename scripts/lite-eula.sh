#!/bin/sh
# openccu-lite (task 319): the update packages' EULA.de / EULA.en are OpenCCU's, unchanged, with
# openccu-lite's preamble right after <body>: not OpenCCU; support only in openccu-lite's issue
# tracker; no donations, a GitHub star instead (OpenCCU's donation buttons below go to OpenCCU's
# developers). The CCU3 WebUI shows the file before "Install", the zip carries it.
#
# release/updatepkg/lite/EULA.<lang> = release/updatepkg/rpi3/EULA.<lang> (upstream's) with
# release/updatepkg/lite/preamble.<lang>.html inserted after the <body> line. The lite products'
# updatepkg directories (aarch64-rpi3/4/5, x86_64-ova) link to lite/.
#
# Usage: sh scripts/lite-eula.sh          write the two files
#        sh scripts/lite-eula.sh --check  exit 1 when they are not what this would write (an
#                                         upstream change of its EULA after a merge: run it again)
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
U="$HERE/release/updatepkg"
rc=0
for lang in de en; do
  src="$U/rpi3/EULA.$lang"; pre="$U/lite/preamble.$lang.html"; dst="$U/lite/EULA.$lang"
  [ "$(grep -c '^<body>$' "$src")" = 1 ] || { echo "lite-eula: $src has no single <body> line"; exit 2; }
  out=$(awk -v pre="$pre" '{ print } /^<body>$/ { while ((getline l < pre) > 0) print l }' "$src")
  if [ "${1:-}" = --check ]; then
    if [ "$out" = "$(cat "$dst" 2>/dev/null)" ]; then echo "lite-eula: $dst up to date"; else echo "lite-eula: $dst is stale - run scripts/lite-eula.sh"; rc=1; fi
  else
    printf '%s\n' "$out" >"$dst" && echo "lite-eula: wrote $dst"
  fi
done
exit $rc

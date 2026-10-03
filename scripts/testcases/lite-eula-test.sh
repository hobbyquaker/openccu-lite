#!/bin/sh
# openccu-lite (task 319): the lite products' update packages carry OpenCCU's EULA with
# openccu-lite's preamble (not OpenCCU; support only in openccu-lite's issue tracker; no donations,
# a GitHub star, OpenCCU's buttons go to OpenCCU's developers). Checks the generated files against
# scripts/lite-eula.sh, the statements in both languages, that every lite product's updatepkg
# directory is lite/, and builds the -ccu3.tgz's file set the way the board's post-release.sh does
# (files-package.txt through the product's directory, tar -h) to read the EULA out of it.
#
# Usage: sh scripts/testcases/lite-eula-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
U="$HERE/release/updatepkg"
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

sh "$HERE/scripts/lite-eula.sh" --check >/dev/null 2>&1 && ok "lite/EULA.de and .en = upstream's with the preamble (lite-eula.sh --check)" \
  || bad "lite/EULA.* are stale: run scripts/lite-eula.sh"

has() { # <file> <text> <what>
  grep -qF "$2" "$1" && ok "$3" || bad "$3: '$2' not in $1"
}
has "$U/lite/EULA.de" "Sie installieren openccu-lite." "de: you are installing openccu-lite"
has "$U/lite/EULA.de" "<b>nicht OpenCCU</b>" "de: not OpenCCU"
has "$U/lite/EULA.de" "https://github.com/hobbyquaker/openccu-lite/issues" "de: the issue tracker"
has "$U/lite/EULA.de" "nicht</b> im OpenCCU-Forum" "de: not the OpenCCU forum"
has "$U/lite/EULA.de" "nimmt keine Spenden an" "de: no donations"
has "$U/lite/EULA.de" "gehen an die Entwickler von OpenCCU, nicht an den Maintainer von" "de: OpenCCU's buttons are OpenCCU's"
has "$U/lite/EULA.en" "You are installing openccu-lite." "en: you are installing openccu-lite"
has "$U/lite/EULA.en" "<b>not OpenCCU</b>" "en: not OpenCCU"
has "$U/lite/EULA.en" "https://github.com/hobbyquaker/openccu-lite/issues" "en: the issue tracker"
has "$U/lite/EULA.en" "not</b> in the OpenCCU forum" "en: not the OpenCCU forum"
has "$U/lite/EULA.en" "does not accept donations" "en: no donations"
has "$U/lite/EULA.en" "go to OpenCCU's developers, not to openccu-lite's maintainer" "en: OpenCCU's buttons are OpenCCU's"
for lang in de en; do
  # the preamble comes first in the body, OpenCCU's own text after it
  awk '/^<body>$/ { b = NR } /installing openccu-lite|installieren openccu-lite/ && !p { p = NR } /OpenCCU!/ && !o { o = NR }
       END { exit !(b && p == b + 2 && o > p) }' "$U/lite/EULA.$lang" && ok "$lang: the preamble opens the body, OpenCCU's text follows" \
    || bad "$lang: the preamble is not at the top of the body"
done

for p in aarch64-rpi3 aarch64-rpi4 aarch64-rpi5 x86_64-ova; do
  [ "$(readlink "$U/$p")" = lite ] && ok "updatepkg/$p -> lite" || bad "updatepkg/$p -> $(readlink "$U/$p"), want lite"
  grep -q '"./updatepkg/${PRODUCT}/EULA.de" "./updatepkg/${PRODUCT}/EULA.en"' "$HERE/buildroot-external/board/$p/post-release.sh" \
    && ok "$p: the zip takes updatepkg/\${PRODUCT}/EULA.*" || bad "$p: post-release.sh does not zip updatepkg/\${PRODUCT}/EULA.*"
done
[ "$(readlink "$U/rpi3")" = "" ] && ! grep -q "openccu-lite" "$U/rpi3/EULA.en" && ok "upstream's rpi3/EULA.* unchanged (no preamble)" \
  || bad "upstream's rpi3 directory was changed"

# the -ccu3.tgz's file set, as post-release.sh assembles it, for the Charly's product
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/pkg"
while IFS= read -r f; do
  ln -s "$U/aarch64-rpi3/$f" "$T/pkg/"
done < "$U/aarch64-rpi3/files-package.txt"
(cd "$T/pkg" && tar -czhf "$T/x-ccu3.tgz" -- *) 2>"$T/tar.err" || bad "tar: $(cat "$T/tar.err")"
tar -tzf "$T/x-ccu3.tgz" | sort | tr '\n' ' ' | grep -q 'EULA.de EULA.en update_script' && ok "the tgz carries EULA.de, EULA.en and update_script" \
  || bad "the tgz holds $(tar -tzf "$T/x-ccu3.tgz" | tr '\n' ' ')"
tar -xzOf "$T/x-ccu3.tgz" EULA.de | grep -q "Sie installieren openccu-lite." && tar -xzOf "$T/x-ccu3.tgz" EULA.en | grep -q "You are installing openccu-lite." \
  && ok "the tgz's EULA.de and EULA.en carry the preamble" || bad "the tgz's EULA has no preamble"
[ -x "$U/lite/update_script" ] && cmp -s "$U/lite/update_script" "$U/rpi3/update_script" && ok "lite/update_script is upstream's" || bad "lite/update_script"

[ "$fails" = 0 ] && echo "lite-eula-test: all checks passed" || { echo "lite-eula-test: $fails check(s) failed"; exit 1; }

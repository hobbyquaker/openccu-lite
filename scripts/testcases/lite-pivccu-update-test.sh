#!/bin/sh
# openccu-lite (B-330): scripts/update-generic_raw_uart.sh and scripts/update-detect_radio_module.sh
# pin the two packages to the piVCCU fork (task 373), never to Alex's master or a branch name, and
# change nothing but the _VERSION line and the archive's hash line. Offline: a made-up fork (a
# local git repository with lite, tags and a branch) and its archives as file:// URLs.
#
# 1. the real tree: both packages' _SITE is the fork's archive macro, their pins are a tag or a
#    commit, and neither script names alexreinert;
# 2. no argument: the newest v* tag on lite's head (a release after its pre-releases), else lite's
#    head commit; already current: nothing changes;
# 3. a tag or a commit as the argument; the hash is the archive's, the LICENSE line stays;
# 4. refused, with the files unchanged: a branch name, a commit not on lite, a commit older than the
#    current pin (unless PIVCCU_ALLOW_OLDER=1), two downloads that differ, a _SITE that is not the
#    fork's, a LICENSE that no longer hashes as the .hash says.
#
# Usage: sh scripts/testcases/lite-pivccu-update-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
PKG="$HERE/buildroot-external/package"
for f in "$HERE/scripts/update-generic_raw_uart.sh" "$HERE/scripts/update-detect_radio_module.sh" \
  "$HERE/scripts/utils/pivccu-fork.sh" "$HERE/scripts/utils/utils.sh"; do
  [ -f "$f" ] || { echo "$f not found"; exit 2; }
done

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

# 1. the real tree
for p in generic_raw_uart detect_radio_module; do
  v=$(echo "$p" | tr 'a-z' 'A-Z')
  grep -qxF "${v}_SITE = \$(call github,hobbyquaker,piVCCU,\$(${v}_VERSION))" "$PKG/$p/$p.mk" &&
    ok "$p: _SITE is the fork's archive macro" || fail "$p: _SITE is not the fork's archive macro"
  pin=$(sed -n "s/^${v}_VERSION = //p" "$PKG/$p/$p.mk")
  echo "$pin" | grep -qE '^(v[0-9][A-Za-z0-9._-]*|[0-9a-f]{40})$' &&
    ok "$p: pinned to a tag or a commit ($pin)" || fail "$p: pin '$pin' is neither a v* tag nor a commit"
  grep -q "  $p-$pin\.tar\.gz\$" "$PKG/$p/$p.hash" &&
    ok "$p: the .hash names the pinned archive" || fail "$p: the .hash does not name $p-$pin.tar.gz"
  ! grep -q alexreinert "$HERE/scripts/update-$p.sh" &&
    ok "update-$p.sh does not name alexreinert" || fail "update-$p.sh names alexreinert"
done
! grep -q 'alexreinert' "$HERE/scripts/utils/pivccu-fork.sh" &&
  ok "pivccu-fork.sh does not name alexreinert" || fail "pivccu-fork.sh names alexreinert"

# the made-up fork: Alex's commit, ours on lite, a branch off lite
F="$T/fork"
git init -q -b master "$F" || exit 2
g() { git -C "$F" -c user.name=t -c user.email=t@t -c tag.gpgSign=false -c commit.gpgSign=false "$@"; }
mkdir -p "$F/kernel" "$F/detect_radio_module"
cp "$HERE/LICENSE" "$F/LICENSE" 2>/dev/null || echo license >"$F/LICENSE"
echo 'int a;' >"$F/kernel/generic_raw_uart.c"
echo 'int b;' >"$F/detect_radio_module/detect_radio_module.cpp"
g add -A && g commit -qm alex
ALEX=$(g rev-parse HEAD)
g checkout -qb lite
echo 'int c;' >>"$F/kernel/generic_raw_uart.c" && g commit -qam ours1
OURS1=$(g rev-parse HEAD)
g tag -a -m r1 v1.0.0-beta.1
echo 'int d;' >>"$F/kernel/generic_raw_uart.c" && g commit -qam ours2
OURS2=$(g rev-parse HEAD)
g checkout -qb feature && echo 'int e;' >>"$F/kernel/generic_raw_uart.c" && g commit -qam side
SIDE=$(g rev-parse HEAD)
g checkout -q lite
export PIVCCU_FORK_GIT="file://$F" PIVCCU_FORK_ARCHIVE="file://$T/archive"

# the archives buildroot would download, for every ref the cases use
archive() { # <id>
  for q in generic_raw_uart detect_radio_module; do
    mkdir -p "$T/archive/$1"
    g archive --format=tar.gz --prefix="piVCCU-$1/" -o "$T/archive/$1/$q-$1.tar.gz" "$1"
  done
}

# a scratch copy of the repository's files the scripts read and write, pinned at v1.0.0-beta.1
R="$T/repo"
setup() { # [<LICENSE line's hash>]
  rm -rf "$R" && mkdir -p "$R/scripts/utils" || exit 2
  cp "$HERE/scripts/update-generic_raw_uart.sh" "$HERE/scripts/update-detect_radio_module.sh" "$R/scripts/"
  cp "$HERE/scripts/utils/utils.sh" "$HERE/scripts/utils/pivccu-fork.sh" "$R/scripts/utils/"
  lic=${1:-$(sha256sum "$F/LICENSE" | awk '{ print $1 }')}
  for q in generic_raw_uart detect_radio_module; do
    mkdir -p "$R/buildroot-external/package/$q"
    sed "s/^\([A-Z_]*_VERSION\) = .*/\1 = v1.0.0-beta.1/" "$PKG/$q/$q.mk" >"$R/buildroot-external/package/$q/$q.mk"
    printf '# Locally computed\nsha256  %s  LICENSE\nsha256  %s  %s\n' "$lic" \
      0000000000000000000000000000000000000000000000000000000000000000 "$q-v1.0.0-beta.1.tar.gz" \
      >"$R/buildroot-external/package/$q/$q.hash"
  done
  rm -rf "$T/orig" && cp -r "$R/buildroot-external" "$T/orig"
}
run() { # <package> [<arg>]  -> $out, $rc
  out=$(cd "$R" && bash "scripts/update-$1.sh" ${2:+"$2"} 2>&1); rc=$?
}
pin() { sed -n "s/^[A-Z_]*_VERSION = //p" "$R/buildroot-external/package/$1/$1.mk"; }
archline() { awk -v p="$1-" 'index($3, p) == 1 { print $2 "  " $3 }' "$R/buildroot-external/package/$1/$1.hash"; }
sum() { sha256sum "$T/archive/$1/$2-$1.tar.gz" | awk '{ print $1 }'; }
unchanged() { diff -r "$T/orig" "$R/buildroot-external" >/dev/null; }
# only the _VERSION line and the archive line differ from the copy before the run
only_two() { # <package>
  m="package/$1/$1.mk" h="package/$1/$1.hash"
  [ "$(diff "$T/orig/$m" "$R/buildroot-external/$m" | grep -c '^[<>]')" = 2 ] &&
    [ "$(diff "$T/orig/$h" "$R/buildroot-external/$h" | grep -c '^[<>]')" = 2 ] &&
    diff "$T/orig/$m" "$R/buildroot-external/$m" | grep '^>' | grep -q '_VERSION = ' &&
    diff "$T/orig/$h" "$R/buildroot-external/$h" | grep '^>' | grep -q "  $1-.*\.tar\.gz\$"
}
cleanup_tags() { for t in $(g tag --list); do [ "$t" = v1.0.0-beta.1 ] || g tag -d "$t" >/dev/null; done; }

# 2. no argument
for p in generic_raw_uart detect_radio_module; do
  # no tag on lite's head: the commit
  setup; cleanup_tags; archive "$OURS2"; run "$p"
  [ "$rc" = 0 ] && [ "$(pin "$p")" = "$OURS2" ] && [ "$(archline "$p")" = "$(sum "$OURS2" "$p")  $p-$OURS2.tar.gz" ] && only_two "$p" &&
    ok "$p: no tag on lite's head pins its commit, hash and nothing else" || { fail "$p: untagged head"; echo "$out"; }
  # the newest tag on lite's head: a release after its pre-releases
  setup; g tag -a -m x v1.0.0-beta.9 "$OURS2"; g tag -a -m x v1.0.0-beta.10 "$OURS2"; g tag -a -m x v1.0.0-rc.0 "$OURS2"
  g tag -m x other "$OURS2"; archive v1.0.0-rc.0; run "$p"
  [ "$rc" = 0 ] && [ "$(pin "$p")" = v1.0.0-rc.0 ] && [ "$(archline "$p")" = "$(sum v1.0.0-rc.0 "$p")  $p-v1.0.0-rc.0.tar.gz" ] && only_two "$p" &&
    ok "$p: the newest v* tag on lite's head (rc.0 after beta.10 after beta.9)" || { fail "$p: newest tag"; echo "$out"; }
  setup; g tag -a -m x v1.0.0 "$OURS2"; archive v1.0.0; run "$p"
  [ "$rc" = 0 ] && [ "$(pin "$p")" = v1.0.0 ] && ok "$p: v1.0.0 after v1.0.0-rc.0" || { fail "$p: v1.0.0 after rc.0"; echo "$out"; }
  # already current: nothing
  setup; cleanup_tags; g tag -a -m x v1.0.0-beta.2 "$OURS2"
  sed -i "s/v1.0.0-beta.1/v1.0.0-beta.2/" "$R/buildroot-external/package/$p/$p.mk"; cp -r "$R/buildroot-external" "$T/cur"
  rm -rf "$T/orig"; mv "$T/cur" "$T/orig"; run "$p"
  [ "$rc" = 0 ] && unchanged && ok "$p: already current changes nothing" || { fail "$p: already current"; echo "$out"; }
  cleanup_tags
done

# 3. a tag or a commit as the argument
for p in generic_raw_uart detect_radio_module; do
  setup; g tag -a -m x v1.0.0-beta.2 "$OURS2"; archive v1.0.0-beta.2; run "$p" v1.0.0-beta.2
  [ "$rc" = 0 ] && [ "$(pin "$p")" = v1.0.0-beta.2 ] && [ "$(archline "$p")" = "$(sum v1.0.0-beta.2 "$p")  $p-v1.0.0-beta.2.tar.gz" ] && only_two "$p" &&
    grep -q '  LICENSE$' "$R/buildroot-external/package/$p/$p.hash" &&
    ok "$p: a tag as the argument" || { fail "$p: tag argument"; echo "$out"; }
  setup; archive "$OURS1"; run "$p" "$OURS1"
  [ "$rc" = 0 ] && [ "$(pin "$p")" = "$OURS1" ] && only_two "$p" &&
    ok "$p: a commit on lite as the argument (the current tag's own commit)" || { fail "$p: commit argument"; echo "$out"; }
  cleanup_tags
done

# 4. refused, nothing changed
p=generic_raw_uart
setup; run "$p" lite
[ "$rc" != 0 ] && unchanged && ok "a branch name (lite) is refused" || { fail "branch name lite"; echo "$out"; }
setup; run "$p" feature
[ "$rc" != 0 ] && unchanged && echo "$out" | grep -q 'is a branch' && ok "a branch name (feature) is refused" || { fail "branch name feature"; echo "$out"; }
setup; archive "$SIDE"; run "$p" "$SIDE"
[ "$rc" != 0 ] && unchanged && echo "$out" | grep -q 'not on the fork' && ok "a commit not on lite is refused" || { fail "commit off lite"; echo "$out"; }
setup; archive "$ALEX"; run "$p" "$ALEX"
[ "$rc" != 0 ] && unchanged && echo "$out" | grep -q 'does not contain the current pin' &&
  ok "Alex's commit (older than the current pin) is refused" || { fail "older commit"; echo "$out"; }
setup; out=$(cd "$R" && PIVCCU_ALLOW_OLDER=1 bash scripts/update-$p.sh "$ALEX" 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(pin "$p")" = "$ALEX" ] && ok "PIVCCU_ALLOW_OLDER=1 allows the step back" || { fail "PIVCCU_ALLOW_OLDER"; echo "$out"; }
setup; run "$p" "not/a-tag"
[ "$rc" != 0 ] && unchanged && ok "a name with a slash is refused" || { fail "slash name"; echo "$out"; }
setup; run "$p" 0123456789012345678901234567890123456789
[ "$rc" != 0 ] && unchanged && ok "an unknown commit is refused" || { fail "unknown commit"; echo "$out"; }
setup; run "$p" v9.9.9
[ "$rc" != 0 ] && unchanged && ok "an unknown tag is refused" || { fail "unknown tag"; echo "$out"; }
# two downloads that differ: a curl that writes something new each time
mkdir -p "$T/bin"
cat >"$T/bin/curl" <<EOF
#!/bin/sh
while [ \$# -gt 1 ]; do [ "\$1" = -o ] && o=\$2; shift; done
n=\$(cat "$T/bin/n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n >"$T/bin/n"
cp "$T/archive/$OURS2/$p-$OURS2.tar.gz" "\$o" && echo \$n >>"\$o"
EOF
chmod +x "$T/bin/curl"
setup; out=$(cd "$R" && PATH="$T/bin:$PATH" bash scripts/update-$p.sh "$OURS2" 2>&1); rc=$?
[ "$rc" != 0 ] && unchanged && echo "$out" | grep -q 'differ' && ok "two downloads that differ are refused" || { fail "differing downloads"; echo "$out"; }
setup; sed -i 's/hobbyquaker,piVCCU/alexreinert,piVCCU/' "$R/buildroot-external/package/$p/$p.mk"; cp -r "$R/buildroot-external/." "$T/orig/"
run "$p" "$OURS2"
[ "$rc" != 0 ] && unchanged && echo "$out" | grep -q '_SITE' && ok "a _SITE that is not the fork's is refused" || { fail "foreign _SITE"; echo "$out"; }
setup 1111111111111111111111111111111111111111111111111111111111111111; run "$p" "$OURS2"
[ "$rc" != 0 ] && unchanged && echo "$out" | grep -q LICENSE && ok "a LICENSE that hashes otherwise is refused" || { fail "LICENSE"; echo "$out"; }

echo "--- $fails failure(s)"
[ "$fails" = 0 ]

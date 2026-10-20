#!/bin/bash
# openccu-lite (B-330): the bump of generic_raw_uart and detect_radio_module, the two packages
# built from the piVCCU fork https://github.com/hobbyquaker/piVCCU (task 373: Alex's master plus
# our changes as commits on the branch lite). update-generic_raw_uart.sh and
# update-detect_radio_module.sh call pivccu_fork_update; upstream's versions resolved Alex's
# master, which would re-pin the packages without our commits.
#
# pivccu_fork_update <package> [<tag or commit>]
#   - the pin is a tag of the fork or a 40-character commit, never a branch name, and it is on
#     the fork's lite (lite's head or an ancestor of it);
#   - without an argument: the newest v* tag on lite's head (a build round tags it, builds.md),
#     else lite's head commit;
#   - the archive is the one buildroot downloads ($(call github,hobbyquaker,piVCCU,<pin>)),
#     downloaded twice: the two must be the same file, its sha256 is the hash;
#   - only the package's _VERSION line in its .mk and the archive's line in its .hash change. The
#     _SITE must be the fork's archive macro and the LICENSE must hash as the .hash says, or
#     nothing changes.
#
# PIVCCU_FORK_GIT and PIVCCU_FORK_ARCHIVE override the fork's git and archive URLs (the tests).
# shellcheck disable=SC2155

PIVCCU_FORK_OWNER="hobbyquaker"
PIVCCU_FORK_REPO="piVCCU"
PIVCCU_FORK_BRANCH="lite"

function pivccu_fork_fail() {
  echo "${PIVCCU_PACKAGE:-piVCCU}: $*" >&2
  exit 1
}

# the newest of the tags read from stdin: a release (no '-') after its pre-releases
function pivccu_fork_newest_tag() {
  awk '{ k = $0; if (index(k, "-") == 0) k = k "-zzz"; print k "\t" $0 }' | sort -V -k1,1 | tail -n1 | cut -f2
}

function pivccu_fork_update() {
  local package=${1}
  local wanted=${2:-}
  PIVCCU_PACKAGE=${package}
  local git_url=${PIVCCU_FORK_GIT:-https://github.com/${PIVCCU_FORK_OWNER}/${PIVCCU_FORK_REPO}.git}
  local archive_base=${PIVCCU_FORK_ARCHIVE:-https://github.com/${PIVCCU_FORK_OWNER}/${PIVCCU_FORK_REPO}/archive}
  local var=${package^^}
  var=${var//-/_}
  local mk="buildroot-external/package/${package}/${package}.mk"
  local hash="buildroot-external/package/${package}/${package}.hash"
  [[ -f "${mk}" && -f "${hash}" ]] || pivccu_fork_fail "${mk} or ${hash} not found (run from the repository's root)"

  local site current
  site=$(sed -nE "s/^${var}_SITE = (.*)$/\\1/p" "${mk}" | head -n1)
  current=$(sed -nE "s/^${var}_VERSION = (.*)$/\\1/p" "${mk}" | head -n1)
  [[ "${site}" == "\$(call github,${PIVCCU_FORK_OWNER},${PIVCCU_FORK_REPO},\$(${var}_VERSION))" ]] ||
    pivccu_fork_fail "${var}_SITE is not the fork's archive macro \$(call github,${PIVCCU_FORK_OWNER},${PIVCCU_FORK_REPO},\$(${var}_VERSION)): ${site}"
  [[ -n "${current}" ]] || pivccu_fork_fail "no ${var}_VERSION line in ${mk}"

  local work
  work=$(mktemp -d "${TMPDIR:-/tmp}/pivccu-fork.XXXXXX") || exit 1
  # shellcheck disable=SC2064
  trap "rm -rf -- '${work}'" EXIT

  # the fork's lite and its tags, without blobs
  git init -q --bare "${work}/git" || pivccu_fork_fail "git init failed"
  git -C "${work}/git" fetch -q --filter=blob:none --no-tags "${git_url}" \
    "+refs/heads/${PIVCCU_FORK_BRANCH}:refs/heads/${PIVCCU_FORK_BRANCH}" "+refs/tags/*:refs/tags/*" 2>"${work}/fetch.log" ||
    { cat "${work}/fetch.log" >&2; pivccu_fork_fail "fetching ${PIVCCU_FORK_BRANCH} and the tags from ${git_url} failed"; }
  local head
  head=$(git -C "${work}/git" rev-parse "refs/heads/${PIVCCU_FORK_BRANCH}^{commit}")

  local id commit
  if [[ -z "${wanted}" ]]; then
    id=$(git -C "${work}/git" tag --points-at "${head}" --list 'v[0-9]*' | pivccu_fork_newest_tag)
    if [[ -z "${id}" ]]; then
      id=${head}
      echo "${package}: no v* tag on ${PIVCCU_FORK_BRANCH}'s head ${head}: pinning the commit (a build round tags it, builds.md)"
    fi
  elif [[ ! "${wanted}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    pivccu_fork_fail "'${wanted}' is not a tag name or a 40-character commit"
  elif [[ "${wanted}" =~ ^[0-9a-f]{40}$ ]]; then
    id=${wanted}
  elif git -C "${work}/git" rev-parse -q --verify "refs/tags/${wanted}" >/dev/null; then
    id=${wanted}
  elif git ls-remote --exit-code --heads "${git_url}" "refs/heads/${wanted}" >/dev/null 2>&1; then
    pivccu_fork_fail "'${wanted}' is a branch of the fork; a pin is a tag or a 40-character commit"
  else
    pivccu_fork_fail "'${wanted}' is neither a tag of the fork nor a 40-character commit"
  fi
  commit=$(git -C "${work}/git" rev-parse -q --verify "${id}^{commit}") ||
    pivccu_fork_fail "${id} is not a commit of the fork's ${PIVCCU_FORK_BRANCH}"
  git -C "${work}/git" merge-base --is-ancestor "${commit}" "${head}" ||
    pivccu_fork_fail "${id} (${commit}) is not on the fork's ${PIVCCU_FORK_BRANCH} (head ${head})"
  # an older commit on lite (Alex's master is one) would drop our commits: the new pin contains
  # the current one, unless PIVCCU_ALLOW_OLDER=1 says a step back is meant
  local current_commit
  if current_commit=$(git -C "${work}/git" rev-parse -q --verify "${current}^{commit}"); then
    if [[ "${PIVCCU_ALLOW_OLDER:-0}" != 1 ]] && ! git -C "${work}/git" merge-base --is-ancestor "${current_commit}" "${commit}"; then
      pivccu_fork_fail "${id} (${commit}) does not contain the current pin ${current} (${current_commit}); PIVCCU_ALLOW_OLDER=1 if that is meant"
    fi
  else
    echo "${package}: the current pin ${current} is not on the fork's ${PIVCCU_FORK_BRANCH}: not compared"
  fi

  if [[ -z "${wanted}" ]]; then
    exit_if_version_unchanged "${current}" "${id}" "${package}"
  fi

  # the archive buildroot downloads, twice
  local file="${package}-${id}.tar.gz"
  local url="${archive_base}/${id}/${file}"
  curl -fsSL --retry 3 -o "${work}/a1" "${url}" || pivccu_fork_fail "downloading ${url} failed"
  curl -fsSL --retry 3 -o "${work}/a2" "${url}" || pivccu_fork_fail "downloading ${url} a second time failed"
  cmp -s "${work}/a1" "${work}/a2" || pivccu_fork_fail "two downloads of ${url} differ: no stable archive, no hash"
  local sum
  sum=$(sha256sum "${work}/a1" | awk '{ print $1 }')
  [[ "${sum}" =~ ^[0-9a-f]{64}$ ]] || pivccu_fork_fail "no sha256 for ${url}"

  # the archive is the fork's tree at that commit, and its LICENSE is the one the .hash names
  mkdir "${work}/x"
  if ! tar -xzf "${work}/a1" -C "${work}/x" --strip-components=1; then
    pivccu_fork_fail "${url} is not a tar.gz archive"
  fi
  local subdir=${package}
  [[ "${package}" == "generic_raw_uart" ]] && subdir=kernel
  [[ -d "${work}/x/${subdir}" ]] || pivccu_fork_fail "${url} has no ${subdir}/"
  local lic_want lic_have
  lic_want=$(awk '$3 == "LICENSE" { print $2 }' "${hash}")
  lic_have=$(sha256sum "${work}/x/LICENSE" 2>/dev/null | awk '{ print $1 }')
  [[ -n "${lic_want}" && "${lic_want}" == "${lic_have}" ]] ||
    pivccu_fork_fail "LICENSE at ${id} hashes ${lic_have:-to nothing}, ${hash} says ${lic_want:-nothing}: check the licence by hand"

  local n
  n=$(grep -cE "^sha256  [0-9a-f]{64}  ${package}-.*\\.tar\\.gz$" "${hash}")
  [[ "${n}" == 1 ]] || pivccu_fork_fail "${hash} has ${n} archive lines, expected one"

  sed -i -E "s/^${var}_VERSION = .*/${var}_VERSION = ${id}/" "${mk}"
  sed -i -E "s/^sha256  [0-9a-f]{64}  ${package}-.*\\.tar\\.gz$/sha256  ${sum}  ${file}/" "${hash}"
  echo "${package}: ${id} (${commit}), archive sha256 ${sum}"
}

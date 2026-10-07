#!/usr/bin/env bash
#
# Creates an openccu-lite VM on a Proxmox VE host in one go: it downloads the x86_64-ova image of
# an openccu-lite release from GitHub, verifies its sha256, imports it with "qm importovf", sets
# CPU, memory, machine type, network and disk size (the system grows its data partition to the
# disk at the first boot), passes a Homematic radio stick through if asked, and starts the VM.
#
# https://raw.githubusercontent.com/hobbyquaker/openccu-lite/main/scripts/install-proxmox.sh
#
# Based on OpenCCU's install-proxmox.sh, Copyright (c) 2022-2026 Jens Maus <mail@jens-maus.de>
# (inspired by https://github.com/whiskerz007/proxmox_hassos_install). Apache 2.0 License applies.
#
# Usage, on the Proxmox host as root:
#   bash -c "$(wget -qLO - https://raw.githubusercontent.com/hobbyquaker/openccu-lite/main/scripts/install-proxmox.sh)"
# or with options:
#   wget -qO install-proxmox.sh https://raw.githubusercontent.com/hobbyquaker/openccu-lite/main/scripts/install-proxmox.sh
#   bash install-proxmox.sh --help
#

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_VERSION="1.0"
REPO="hobbyquaker/openccu-lite"
API="https://api.github.com/repos/${REPO}"
ASSET_PLATFORM="x86_64-ova"

# the radio sticks offered for pass-through: vendor:product id and name
RADIO_STICKS=(
  "1b1f:c020|HmIP-RFUSB"
  "10c4:8c07|HB-RF-USB-2"
  "0403:6f70|HB-RF-USB"
  "1b1f:c00f|HM-CFG-USB-2"
)

# defaults
VERSION=""
VMID=""
NAME="openccu-lite"
STORAGE=""
DISK_SIZE=8
DISK_MINSIZE=6
MEMORY=2048
CORES=2
MACHINE="pc"
BRIDGE="vmbr0"
VLAN=""
USB_DEVICE=""
USB_MODE="ask"
START=1
ONBOOT=1
ASSUME_YES=0
DRY_RUN=0
WORK_PARENT="/var/tmp"

TAG=""
URL=""
OVF=""
WORK_DIR=""
CREATED_VMID=""

usage() {
  cat <<EOF
openccu-lite Proxmox VM installer v${SCRIPT_VERSION}

Creates an openccu-lite VM on this Proxmox VE host: downloads the ${ASSET_PLATFORM} image of a
release from github.com/${REPO}, verifies its sha256, imports it, sets it up and starts it.
Run it on the Proxmox host as root.

Usage: install-proxmox.sh [options]

Options:
  --version <v>        the release to install, e.g. 1.0.0-dev.42 (default: the newest release,
                       pre-releases included)
  --vmid <id>          the VM id (default: the next free id of the cluster)
  --name <name>        the VM name (default: ${NAME})
  --storage <storage>  the storage for the disk (default: the only storage for disk images, or
                       asked when there are several)
  --disk <GB>          the disk size in GB, at least ${DISK_MINSIZE} (default: ${DISK_SIZE}); the system grows
                       its data partition to it at the first boot
  --memory <MB>        the memory in MB (default: ${MEMORY})
  --cores <n>          the CPU cores (default: ${CORES})
  --machine <type>     the machine type: pc (i440fx) or q35 (default: ${MACHINE})
  --bridge <bridge>    the network bridge (default: ${BRIDGE})
  --vlan <tag>         a VLAN tag for the network interface (default: none)
  --usb <vendor:product>
                       pass this radio stick through to the VM, e.g. 1b1f:c020
  --no-usb             pass no radio stick through (default: the radio sticks found on this host
                       are listed and one can be chosen)
  --no-start           create the VM but do not start it
  --no-onboot          do not start the VM when the host boots
  --tmpdir <dir>       where the image is downloaded and unpacked (default: ${WORK_PARENT};
                       needs about 700 MB, removed afterwards)
  -y, --yes            ask nothing: no confirmation, no radio stick choice
  --dry-run            print the commands instead of running them; downloads and creates nothing
  -h, --help           this text

Radio sticks offered for pass-through (by vendor and product id):
$(for s in "${RADIO_STICKS[@]}"; do printf '  %-10s %s\n' "${s%%|*}" "${s#*|}"; done)

Examples:
  install-proxmox.sh
  install-proxmox.sh --version 1.0.0-dev.42 --vmid 120 --storage local-lvm --disk 16 --usb 1b1f:c020 -y
  install-proxmox.sh --dry-run
EOF
}

msg() { echo -e "$1"; }
info() { msg "\e[36m[INFO]\e[39m $1"; }
warn() { msg "\e[93m[WARNING]\e[39m $1" >&2; }
die() {
  msg "\e[91m[ERROR]\e[39m $1" >&2
  exit 1
}

on_exit() {
  local rc=$?
  if [[ ${rc} -ne 0 ]] && [[ -n "${CREATED_VMID}" ]]; then
    warn "Removing the half-created VM ${CREATED_VMID}"
    qm stop "${CREATED_VMID}" >/dev/null 2>&1 || true
    qm destroy "${CREATED_VMID}" --purge >/dev/null 2>&1 || true
  fi
  if [[ -n "${WORK_DIR}" ]] && [[ -d "${WORK_DIR}" ]]; then
    cd /
    rm -rf "${WORK_DIR}"
  fi
  exit "${rc}"
}
trap on_exit EXIT

# run a command, or print it in a dry run
run() {
  if [[ ${DRY_RUN} -eq 1 ]]; then
    local out="+" a
    for a in "$@"; do
      if [[ "${a}" =~ ^[A-Za-z0-9_./:=,@%+-]+$ ]]; then
        out+=" ${a}"
      else
        out+=" '${a//\'/\'\\\'\'}'"
      fi
    done
    echo "${out}"
  else
    "$@"
  fi
}

# run, with the command's own output (qm's progress lines) dropped; errors still show
run_quiet() {
  if [[ ${DRY_RUN} -eq 1 ]]; then
    run "$@"
  else
    "$@" >/dev/null
  fi
}

# true when we may ask: a terminal and no --yes
interactive() {
  [[ ${ASSUME_YES} -eq 0 ]] && [[ -t 0 ]] && [[ -t 1 ]]
}

# true on a Proxmox host; a dry run elsewhere uses placeholders
on_pve() {
  [[ -d /etc/pve ]]
}

need_value() {
  [[ $# -ge 2 ]] && [[ -n "$2" ]] || die "$1 needs a value (see --help)"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) need_value "$@"; VERSION="${2#v}"; shift 2 ;;
      --vmid) need_value "$@"; VMID="$2"; shift 2 ;;
      --name) need_value "$@"; NAME="$2"; shift 2 ;;
      --storage) need_value "$@"; STORAGE="$2"; shift 2 ;;
      --disk) need_value "$@"; DISK_SIZE="${2%[Gg]}"; shift 2 ;;
      --memory) need_value "$@"; MEMORY="$2"; shift 2 ;;
      --cores) need_value "$@"; CORES="$2"; shift 2 ;;
      --machine) need_value "$@"; MACHINE="$2"; shift 2 ;;
      --bridge) need_value "$@"; BRIDGE="$2"; shift 2 ;;
      --vlan) need_value "$@"; VLAN="$2"; shift 2 ;;
      --usb) need_value "$@"; USB_DEVICE="${2,,}"; USB_MODE="set"; shift 2 ;;
      --no-usb) USB_DEVICE=""; USB_MODE="none"; shift ;;
      --no-start) START=0; shift ;;
      --no-onboot) ONBOOT=0; shift ;;
      --tmpdir) need_value "$@"; WORK_PARENT="$2"; shift 2 ;;
      -y|--yes) ASSUME_YES=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; die "Unknown option: $1" ;;
    esac
  done

  [[ -z "${VERSION}" ]] || [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] ||
    die "--version: '${VERSION}' is not a version like 1.0.0-dev.42"
  [[ -z "${VMID}" ]] || [[ "${VMID}" =~ ^[1-9][0-9]{2,8}$ ]] || die "--vmid: '${VMID}' is not a VM id (100 or more)"
  [[ "${NAME}" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || die "--name: '${NAME}' is not a valid DNS name"
  [[ "${DISK_SIZE}" =~ ^[0-9]+$ ]] && [[ ${DISK_SIZE} -ge ${DISK_MINSIZE} ]] ||
    die "--disk: at least ${DISK_MINSIZE} (GB)"
  [[ "${MEMORY}" =~ ^[0-9]+$ ]] && [[ ${MEMORY} -ge 1024 ]] || die "--memory: at least 1024 (MB)"
  [[ "${CORES}" =~ ^[1-9][0-9]*$ ]] || die "--cores: a number of cores"
  [[ "${MACHINE}" == "pc" ]] || [[ "${MACHINE}" == "q35" ]] || die "--machine: pc or q35"
  [[ "${BRIDGE}" =~ ^[A-Za-z0-9_.-]+$ ]] || die "--bridge: '${BRIDGE}' is not a bridge name"
  [[ -z "${VLAN}" ]] || { [[ "${VLAN}" =~ ^[0-9]+$ ]] && [[ ${VLAN} -ge 1 ]] && [[ ${VLAN} -le 4094 ]]; } ||
    die "--vlan: a tag from 1 to 4094"
  [[ -z "${USB_DEVICE}" ]] || [[ "${USB_DEVICE}" =~ ^[0-9a-f]{4}:[0-9a-f]{4}$ ]] ||
    die "--usb: '${USB_DEVICE}' is not a vendor:product id like 1b1f:c020"
}

check_host() {
  local cmd
  for cmd in python3 sha256sum tar; do
    command -v "${cmd}" >/dev/null 2>&1 || die "'${cmd}' is missing on this host."
  done
  command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 || die "Neither wget nor curl is installed."
  if [[ ${DRY_RUN} -eq 1 ]] && ! on_pve; then
    warn "Not a Proxmox VE host: the dry run uses placeholders for what only Proxmox knows."
    return
  fi
  if ! on_pve || ! command -v qm >/dev/null 2>&1; then
    die "Run this script on a Proxmox VE host."
  fi
  [[ ${EUID} -eq 0 ]] || die "Run this script as root."
  [[ "$(uname -m)" == "x86_64" ]] || die "openccu-lite's VM image is for x86_64 Proxmox hosts."
}

# fetch <url> [file]: to the file with a progress bar, or to stdout
fetch() {
  if command -v wget >/dev/null 2>&1; then
    if [[ $# -ge 2 ]] && [[ -t 2 ]]; then
      wget -q --show-progress -O "$2" "$1"
    elif [[ $# -ge 2 ]]; then
      wget -q -O "$2" "$1"
    else
      wget -qO - "$1"
    fi
  elif [[ $# -ge 2 ]] && [[ -t 2 ]]; then
    curl -fL --progress-bar -o "$2" "$1"
  elif [[ $# -ge 2 ]]; then
    curl -fsSL -o "$2" "$1"
  else
    curl -fsSL "$1"
  fi
}

# prints "<tag> <ova url>" of the chosen release
select_release() {
  local json
  if [[ -n "${VERSION}" ]]; then
    json=$(fetch "${API}/releases/tags/v${VERSION}") || return 1
    json="[${json}]"
  else
    json=$(fetch "${API}/releases?per_page=30") || return 1
  fi
  printf '%s' "${json}" | python3 -c '
import json, sys
platform = sys.argv[1]
try:
    releases = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
for r in releases:
    if not isinstance(r, dict) or r.get("draft"):
        continue
    for a in r.get("assets", []):
        n = a.get("name", "")
        if n.startswith("openccu-lite-" + platform + "-") and n.endswith(".ova"):
            print(r["tag_name"], a["browser_download_url"])
            sys.exit(0)
sys.exit(1)
' "${ASSET_PLATFORM}"
}

select_storage() {
  if ! on_pve; then
    STORAGE=${STORAGE:-local-lvm}
    return
  fi
  local list menu=() tag type
  list=$(pvesm status -content images | awk 'NR>1 && $3 == "active" {print $1, $2}')
  [[ -n "${list}" ]] || die "No active storage holds disk images; enable 'Disk image' on one."
  if [[ -n "${STORAGE}" ]]; then
    awk '{print $1}' <<<"${list}" | grep -qxF -- "${STORAGE}" ||
      die "Storage '${STORAGE}' is not an active storage for disk images: $(awk '{print $1}' <<<"${list}" | xargs)"
    return
  fi
  if [[ $(wc -l <<<"${list}") -eq 1 ]]; then
    STORAGE=${list%% *}
    return
  fi
  interactive || die "Several storages hold disk images; choose one with --storage: $(awk '{print $1}' <<<"${list}" | xargs)"
  while read -r tag type; do
    menu+=("${tag}" "${type}" "OFF")
  done <<<"${list}"
  STORAGE=$(whiptail --title "Storage" --radiolist "Which storage should hold the VM's disk?" \
    16 60 6 "${menu[@]}" 3>&1 1>&2 2>&3) || die "Aborted."
  [[ -n "${STORAGE}" ]] || die "No storage chosen."
}

select_vmid() {
  if ! on_pve; then
    VMID=${VMID:-100}
    return
  fi
  if [[ -z "${VMID}" ]]; then
    VMID=$(pvesh get /cluster/nextid)
  else
    # nextid --vmid fails when the id is taken anywhere in the cluster
    pvesh get /cluster/nextid --vmid "${VMID}" >/dev/null 2>&1 || die "VM id ${VMID} is already in use."
  fi
}

# the radio sticks attached to this host: "<vendor:product> <usb port> <name>" per line
list_radio_sticks() {
  local dev vp s
  for dev in /sys/bus/usb/devices/*; do
    [[ -r "${dev}/idVendor" ]] && [[ -r "${dev}/idProduct" ]] || continue
    vp="$(<"${dev}/idVendor"):$(<"${dev}/idProduct")"
    for s in "${RADIO_STICKS[@]}"; do
      if [[ "${vp}" == "${s%%|*}" ]]; then
        echo "${vp} ${dev##*/} ${s#*|}"
      fi
    done
  done
}

select_usb() {
  [[ "${USB_MODE}" != "none" ]] || return 0
  on_pve || return 0
  local sticks count vp port name menu=()
  sticks=$(list_radio_sticks)
  if [[ "${USB_MODE}" == "set" ]]; then
    count=$(awk -v id="${USB_DEVICE}" '$1 == id' <<<"${sticks}" | grep -c . || true)
    if [[ ${count} -eq 0 ]]; then
      warn "No device ${USB_DEVICE} is attached to this host now; the VM gets it once it is plugged in."
    elif [[ ${count} -gt 1 ]]; then
      warn "${count} devices ${USB_DEVICE} are attached; Proxmox passes the first one it finds through."
    fi
    return 0
  fi
  if [[ -z "${sticks}" ]]; then
    info "No Homematic radio stick found on this host; no USB pass-through."
    return 0
  fi
  info "Homematic radio sticks on this host:"
  while read -r vp port name; do
    msg "  ${vp}  ${name}  (USB ${port})"
    menu+=("${vp}" "${name} (USB ${port})" "OFF")
  done <<<"${sticks}"
  if ! interactive; then
    info "Not asked (no terminal or --yes): no USB pass-through; pass --usb <vendor:product> for one."
    return 0
  fi
  menu+=("none" "no pass-through" "ON")
  USB_DEVICE=$(whiptail --title "Homematic radio stick" --radiolist \
    "Which radio stick should be passed through to the VM?" 16 70 6 "${menu[@]}" 3>&1 1>&2 2>&3) || die "Aborted."
  [[ "${USB_DEVICE}" != "none" ]] || USB_DEVICE=""
}

confirm() {
  local start="no"
  [[ ${START} -eq 0 ]] || start="now"
  [[ ${ONBOOT} -eq 0 ]] || start+=", and when the host boots"
  msg ""
  msg "  Release:  ${TAG}"
  msg "  Image:    ${URL}"
  msg "  VM:       ${VMID} (${NAME}), ${CORES} cores, ${MEMORY} MB, machine ${MACHINE}"
  msg "  Disk:     ${DISK_SIZE} GB on ${STORAGE}"
  msg "  Network:  ${BRIDGE}${VLAN:+, VLAN ${VLAN}}"
  msg "  USB:      ${USB_DEVICE:-none}"
  msg "  Start:    ${start}"
  msg ""
  [[ ${DRY_RUN} -eq 0 ]] || return 0
  interactive || return 0
  local answer
  read -r -p "Create the VM? [y/N] " answer
  [[ "${answer}" =~ ^[YyJj] ]] || die "Aborted."
}

download() {
  local file sum
  file=$(basename "${URL}")
  if [[ ${DRY_RUN} -eq 1 ]]; then
    run wget -q -O "${file}.sha256" "${URL}.sha256"
    run wget -q --show-progress -O "${file}" "${URL}"
    run sha256sum -c "${file}.sha256"
    run tar -xf "${file}"
    OVF="OpenCCU.ovf"
    return 0
  fi
  [[ -d "${WORK_PARENT}" ]] || die "--tmpdir: ${WORK_PARENT} does not exist."
  WORK_DIR=$(mktemp -d "${WORK_PARENT}/openccu-lite-install.XXXXXX")
  cd "${WORK_DIR}"
  info "Downloading ${file}..."
  fetch "${URL}.sha256" "${file}.sha256" 2>/dev/null || die "Could not download ${file}.sha256."
  fetch "${URL}" "${file}" || die "Could not download ${URL}."
  info "Verifying the sha256..."
  sum=$(awk '{print $1; exit}' "${file}.sha256")
  [[ "${sum}" =~ ^[0-9a-f]{64}$ ]] || die "${file}.sha256 holds no sha256 sum."
  echo "${sum}  ${file}" | sha256sum -c --quiet - || die "The download's sha256 does not match; nothing was created."
  info "Unpacking..."
  tar -xf "${file}"
  rm -f "${file}"
  OVF=$(find . -maxdepth 1 -name '*.ovf' -print -quit)
  [[ -n "${OVF}" ]] || die "No .ovf in ${file}."
}

create_vm() {
  local import_opt=() storage_type="lvmthin" disk_id net
  if on_pve; then
    storage_type=$(pvesm status -storage "${STORAGE}" | awk 'NR>1 {print $2}')
  fi
  case "${storage_type}" in
    dir|nfs|cifs|glusterfs|cephfs) import_opt=(--format qcow2) ;;
  esac

  info "Importing the image as VM ${VMID}..."
  [[ ${DRY_RUN} -eq 1 ]] || CREATED_VMID=${VMID}
  run_quiet qm importovf "${VMID}" "${OVF}" "${STORAGE}" "${import_opt[@]}"

  if [[ ${DRY_RUN} -eq 1 ]]; then
    disk_id="${STORAGE}:vm-${VMID}-disk-0"
  else
    disk_id=$(qm config "${VMID}" | awk -F'[ ,]' '/^sata0:/ {print $2; exit}')
    [[ -n "${disk_id}" ]] || die "The imported VM has no sata0 disk."
  fi

  net="virtio,bridge=${BRIDGE},firewall=1${VLAN:+,tag=${VLAN}}"
  info "Setting the VM up..."
  run_quiet qm set "${VMID}" \
    --name "${NAME}" \
    --machine "${MACHINE}" \
    --cores "${CORES}" \
    --memory "${MEMORY}" \
    --acpi 1 \
    --agent 1,fstrim_cloned_disks=1,type=virtio \
    --hotplug network,disk,usb \
    --description "[openccu-lite](https://github.com/${REPO}) ${TAG}" \
    --net0 "${net}" \
    --onboot "${ONBOOT}" \
    --tablet 0 \
    --watchdog model=i6300esb,action=reset \
    --ostype l26 \
    --scsihw virtio-scsi-single \
    --delete sata0 \
    --scsi0 "${disk_id},discard=on,iothread=1"
  run_quiet qm set "${VMID}" --boot order=scsi0
  info "Growing the disk to ${DISK_SIZE} GB..."
  run_quiet qm resize "${VMID}" scsi0 "${DISK_SIZE}G"
  if [[ -n "${USB_DEVICE}" ]]; then
    info "Passing the radio stick ${USB_DEVICE} through as usb0..."
    run_quiet qm set "${VMID}" --usb0 "host=${USB_DEVICE},usb3=1"
  fi
  CREATED_VMID=""
}

# the VM's first IPv4 address as the guest agent reports it, or nothing
guest_ipv4() {
  qm guest cmd "${VMID}" network-get-interfaces 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
for iface in data:
    if iface.get("name") == "lo":
        continue
    for a in iface.get("ip-addresses", []):
        if a.get("ip-address-type") == "ipv4":
            print(a["ip-address"])
            sys.exit(0)
' || true
}

start_vm() {
  if [[ ${START} -eq 0 ]]; then
    info "VM ${VMID} created; start it with: qm start ${VMID}"
    return 0
  fi
  info "Starting VM ${VMID}..."
  run qm start "${VMID}"
  [[ ${DRY_RUN} -eq 0 ]] || return 0
  # the guest agent reports the address once the system is up (the first boot takes a few minutes)
  local i ip=""
  info "Waiting for the system to come up..."
  for i in $(seq 1 60); do
    ip=$(guest_ipv4)
    [[ -z "${ip}" ]] || break
    [[ ${i} -eq 60 ]] || sleep 5
  done
  if [[ -n "${ip}" ]]; then
    info "openccu-lite is up: http://${ip}/"
  else
    info "The VM runs; its address shows in the Proxmox UI (Summary, IPs) once the system is up."
  fi
}

main() {
  parse_args "$@"
  msg "openccu-lite Proxmox VM installer v${SCRIPT_VERSION}"
  [[ ${DRY_RUN} -eq 0 ]] || info "Dry run: the commands are printed; nothing is downloaded or created."
  check_host

  local rel
  info "Looking up ${VERSION:+openccu-lite }${VERSION:-the newest openccu-lite release}..."
  rel=$(select_release) ||
    die "No ${ASSET_PLATFORM} image found for ${VERSION:-the newest release} at github.com/${REPO}/releases (or GitHub did not answer; try again later)."
  TAG=${rel%% *}
  URL=${rel#* }
  info "Release ${TAG}"

  select_storage
  select_vmid
  select_usb
  confirm
  download
  create_vm
  start_vm
  [[ ${DRY_RUN} -eq 1 ]] || info "Done: VM ${VMID} (${NAME}) runs openccu-lite ${TAG}."
}

main "$@"

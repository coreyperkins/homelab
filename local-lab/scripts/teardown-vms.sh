#!/usr/bin/env bash
set -euo pipefail

connection="qemu:///system"
apply=false
assume_yes=false
use_sudo="${LOCAL_LAB_USE_SUDO:-auto}"
sudo_prefix=()

usage() {
  cat <<'USAGE'
Usage: local-lab/scripts/teardown-vms.sh [--apply] [--yes]

Without --apply, show the exact local-lab VMs and qcow2 disks that would be
removed. With --apply, ask for the confirmation phrase and then shut down and
undefine only cks-control and cks-worker, removing only their same-named qcow2
disk files referenced by those VM definitions. Add --yes to skip the phrase
for an explicitly approved non-interactive automation run.

The script uses direct libvirt access when available, otherwise it uses sudo.
Set LOCAL_LAB_USE_SUDO=always or LOCAL_LAB_USE_SUDO=never to override that choice.

The libvirt default network, DHCP reservations, RHEL ISO, and .secrets/ files
are preserved. Existing VMs are never force-powered-off.
USAGE
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

for argument in "$@"; do
  case "$argument" in
    --apply) apply=true ;;
    --yes) assume_yes=true ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ "$assume_yes" != true || "$apply" == true ]] || die "--yes requires --apply."

for utility in virsh python3; do
  command -v "$utility" >/dev/null 2>&1 || die "Install '$utility' before using this script."
done

case "$use_sudo" in
  auto)
    if ! virsh -c "$connection" uri >/dev/null 2>&1; then
      use_sudo=always
    else
      use_sudo=never
    fi
    ;;
  always|never) ;;
  *) die "LOCAL_LAB_USE_SUDO must be auto, always, or never." ;;
esac

if [[ "$use_sudo" == always ]]; then
  command -v sudo >/dev/null 2>&1 || die "Install 'sudo' before using this script."
  sudo -v
  sudo_prefix=(sudo)
fi

run_virsh() {
  "${sudo_prefix[@]}" virsh -c "$connection" "$@"
}

remove_disk() {
  local disk_path="$1" disk_dir
  disk_dir="$(dirname "$disk_path")"
  if [[ -w "$disk_dir" ]]; then
    rm -- "$disk_path"
  elif [[ "$use_sudo" == always ]]; then
    sudo rm -- "$disk_path"
  else
    die "Cannot remove $disk_path without write access to $disk_dir. Run with LOCAL_LAB_USE_SUDO=always."
  fi
}

run_virsh uri >/dev/null

declare -a names=(cks-control cks-worker)
declare -A present=()
declare -A states=()
declare -A disk_candidates=()

domain_disk_files() {
  local domain="$1" xml
  xml="$(run_virsh dumpxml --inactive "$domain")"
  python3 -c '
import sys
import xml.etree.ElementTree as ET

root = ET.fromstring(sys.stdin.read())
for disk in root.findall("./devices/disk"):
    if disk.get("device") != "disk":
        continue
    source = disk.find("source")
    if source is not None and source.get("file"):
        print(source.get("file"))
' <<<"$xml"
}

printf 'Local RKE2 VM teardown plan (%s):\n' "$connection"
for name in "${names[@]}"; do
  if ! run_virsh dominfo "$name" >/dev/null 2>&1; then
    present["$name"]=false
    printf '  %s: no VM definition found\n' "$name"
    continue
  fi

  present["$name"]=true
  states["$name"]="$(run_virsh domstate "$name" | tr -d '[:space:]')"
  snapshots="$(run_virsh snapshot-list "$name" --name | sed '/^[[:space:]]*$/d')"
  [[ -z "$snapshots" ]] || die "$name has VM snapshots. Review/remove those separately before teardown."

  printf '  %s: VM definition and disks (state: %s)\n' "$name" "${states[$name]}"
  while IFS= read -r disk_path; do
    [[ -n "$disk_path" ]] || continue
    disk_base="${disk_path##*/}"
    if [[ "$disk_base" == "$name.qcow2" ]]; then
      [[ ! -L "$disk_path" ]] || die "Refusing to remove symlink disk path: $disk_path"
      if [[ -f "$disk_path" ]]; then
        disk_candidates["$name"]="${disk_candidates[$name]-}${disk_path}"$'\n'
        printf '    remove disk: %s\n' "$disk_path"
      else
        printf '    disk already absent: %s\n' "$disk_path"
      fi
    else
      printf '    preserve other attached storage: %s\n' "$disk_path"
    fi
  done < <(domain_disk_files "$name")
done

if [[ "$apply" != true ]]; then
  printf '\nPreview only; no changes made. Use --apply to request teardown.\n'
  exit 0
fi

if [[ "$assume_yes" != true ]]; then
  printf '\nThis removes the listed VM definitions and disks. Type exactly "TEARDOWN cks-control cks-worker" to continue: '
  IFS= read -r confirmation
  [[ "$confirmation" == "TEARDOWN cks-control cks-worker" ]] || die "Confirmation did not match; nothing was changed."
else
  printf '\n--yes supplied; proceeding with the explicitly requested teardown.\n'
fi

for name in "${names[@]}"; do
  [[ "${present[$name]}" == true ]] || continue
  state="$(run_virsh domstate "$name" | tr -d '[:space:]')"
  if [[ "$state" != "shutoff" ]]; then
    run_virsh shutdown "$name"
  fi
done

for name in "${names[@]}"; do
  [[ "${present[$name]}" == true ]] || continue
  for attempt in $(seq 1 60); do
    state="$(run_virsh domstate "$name" | tr -d '[:space:]')"
    [[ "$state" == "shutoff" ]] && break
    sleep 2
  done
  [[ "$state" == "shutoff" ]] || die "$name did not shut down cleanly. No VM definitions or disks were removed. Shut it down manually and rerun."
done

for name in "${names[@]}"; do
  [[ "${present[$name]}" == true ]] || continue
  run_virsh undefine "$name" --nvram --managed-save
  while IFS= read -r disk_path; do
    [[ -n "$disk_path" ]] || continue
    disk_base="${disk_path##*/}"
    if [[ "$disk_base" == "$name.qcow2" && -f "$disk_path" && ! -L "$disk_path" ]]; then
      remove_disk "$disk_path"
      printf 'Removed disk %s\n' "$disk_path"
    fi
  done <<<"${disk_candidates[$name]-}"
  printf 'Removed VM definition %s\n' "$name"
done

printf '\nTeardown complete. DHCP reservations, ISO files, and .secrets/ were preserved.\n'

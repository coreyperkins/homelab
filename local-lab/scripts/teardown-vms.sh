#!/usr/bin/env bash
set -euo pipefail

connection="qemu:///system"
apply=false

usage() {
  cat <<'USAGE'
Usage: local-lab/scripts/teardown-vms.sh [--apply]

Without --apply, show the exact local-lab VMs and qcow2 disks that would be
removed. With --apply, ask for the confirmation phrase and then shut down and
undefine only cks-control and cks-worker, removing only their same-named qcow2
disk files referenced by those VM definitions.

The libvirt default network, DHCP reservations, RHEL ISO, and .secrets/ files
are preserved. Existing VMs are never force-powered-off.
USAGE
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

case "${1:-}" in
  "") ;;
  --apply) apply=true ;;
  --help|-h) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

for utility in sudo virsh python3; do
  command -v "$utility" >/dev/null 2>&1 || die "Install '$utility' before using this script."
done

sudo -v
sudo virsh -c "$connection" uri >/dev/null

declare -a names=(cks-control cks-worker)
declare -A present=()
declare -A states=()
declare -A disk_candidates=()

domain_disk_files() {
  local domain="$1" xml
  xml="$(sudo virsh -c "$connection" dumpxml --inactive "$domain")"
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
  if ! sudo virsh -c "$connection" dominfo "$name" >/dev/null 2>&1; then
    present["$name"]=false
    printf '  %s: no VM definition found\n' "$name"
    continue
  fi

  present["$name"]=true
  states["$name"]="$(sudo virsh -c "$connection" domstate "$name" | tr -d '[:space:]')"
  snapshots="$(sudo virsh -c "$connection" snapshot-list "$name" --name | sed '/^[[:space:]]*$/d')"
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

printf '\nThis removes the listed VM definitions and disks. Type exactly "TEARDOWN cks-control cks-worker" to continue: '
IFS= read -r confirmation
[[ "$confirmation" == "TEARDOWN cks-control cks-worker" ]] || die "Confirmation did not match; nothing was changed."

for name in "${names[@]}"; do
  [[ "${present[$name]}" == true ]] || continue
  state="$(sudo virsh -c "$connection" domstate "$name" | tr -d '[:space:]')"
  if [[ "$state" != "shutoff" ]]; then
    sudo virsh -c "$connection" shutdown "$name"
  fi
done

for name in "${names[@]}"; do
  [[ "${present[$name]}" == true ]] || continue
  for attempt in $(seq 1 60); do
    state="$(sudo virsh -c "$connection" domstate "$name" | tr -d '[:space:]')"
    [[ "$state" == "shutoff" ]] && break
    sleep 2
  done
  [[ "$state" == "shutoff" ]] || die "$name did not shut down cleanly. No VM definitions or disks were removed. Shut it down manually and rerun."
done

for name in "${names[@]}"; do
  [[ "${present[$name]}" == true ]] || continue
  sudo virsh -c "$connection" undefine "$name" --nvram --managed-save
  while IFS= read -r disk_path; do
    [[ -n "$disk_path" ]] || continue
    disk_base="${disk_path##*/}"
    if [[ "$disk_base" == "$name.qcow2" && -f "$disk_path" && ! -L "$disk_path" ]]; then
      sudo rm -- "$disk_path"
      printf 'Removed disk %s\n' "$disk_path"
    fi
  done <<<"${disk_candidates[$name]-}"
  printf 'Removed VM definition %s\n' "$name"
done

printf '\nTeardown complete. DHCP reservations, ISO files, and .secrets/ were preserved.\n'

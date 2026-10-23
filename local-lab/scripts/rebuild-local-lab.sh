#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
scripts_dir="$repo_root/local-lab/scripts"
secrets_dir="$repo_root/.secrets"
image_dir="$repo_root/images"
iso="$image_dir/rhel-10.2-x86_64-dvd.iso"
expected_iso_sha256="e15cb333529c332e76e4b1b946efe3515c99f996546675aec18e8effdf2540a5"
volume_label="RHEL-10-2-BaseOS-x86_64"

usage() {
  cat <<'USAGE'
Usage: local-lab/scripts/rebuild-local-lab.sh --confirm-destroy

Runs the complete local VM rebuild without interactive prompts:
  1. Tears down only cks-control and cks-worker and their same-named disks.
  2. Installs RHEL and waits for both VMs.
  3. Completes Ansible host configuration.
  4. Installs RKE2 and waits for both Kubernetes nodes to become Ready.
  5. Installs Rancher and waits for its deployments.
  6. Deploys Mattermost through Fleet and waits for bundles and pods to be Ready.

This deletes all cluster data stored on the VM disks. The RHEL ISO and
.secrets/ are preserved. The explicit --confirm-destroy flag authorizes this
destructive rebuild. The script exits at the first failure and saves a log in
.secrets/.
USAGE
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

[[ "${1:-}" == "--confirm-destroy" && $# == 1 ]] || { usage >&2; exit 2; }

umask 077
mkdir -p "$secrets_dir"
chmod 0700 "$secrets_dir"
log_file="$secrets_dir/local-lab-rebuild-$(date +%Y%m%d-%H%M%S)-$$.log"
exec > >(tee -a "$log_file") 2>&1
trap 'result=$?; trap - ERR; printf "\nFAILED (exit %s) near: %s\nLog: %s\n" "$result" "$BASH_COMMAND" "$log_file" >&2; exit "$result"' ERR

cd "$repo_root"
export PATH="/usr/sbin:/usr/bin:/bin:$PATH"
export LOCAL_LAB_USE_SUDO=never
export GIT_TERMINAL_PROMPT=0
export GCM_INTERACTIVE=never

printf 'Local lab full rebuild starting at %s\n' "$(date --iso-8601=seconds)"
printf 'This deletes both VM disks and all cluster data stored on them.\n'
printf 'Progress log: %s\n\n' "$log_file"

for utility in ansible-playbook virsh python3 virt-install sha256sum blkid openssl \
  ssh-keygen ssh-keyscan git tee awk; do
  command -v "$utility" >/dev/null 2>&1 || die "Required command not found: $utility"
done

[[ -r "$iso" ]] || die "RHEL DVD ISO is missing or unreadable: $iso"
actual_iso_sha256="$(sha256sum "$iso" | awk '{print $1}')"
[[ "$actual_iso_sha256" == "$expected_iso_sha256" ]] || die "RHEL ISO checksum mismatch; refusing to delete the existing VMs."
actual_volume_label="$(blkid -p -s LABEL -o value "$iso" 2>/dev/null || true)"
[[ "$actual_volume_label" == "$volume_label" ]] || die "Unexpected RHEL ISO volume label '$actual_volume_label'; refusing teardown."

virsh -c qemu:///system uri >/dev/null 2>&1 || die "Direct access to system libvirt is unavailable. Configure libvirt access first; this script will not stop for a sudo prompt."
[[ -w "$image_dir" ]] || die "The images directory is not writable by the current user; configure disk permissions before rebuilding."
[[ -f local-lab/ansible/ansible.cfg && -f local-lab/ansible/inventory/hosts.yml ]] || die "Local-lab Ansible configuration is missing."
[[ -x "$scripts_dir/deploy-mattermost.sh" ]] || die "The Mattermost deployment script is missing or not executable."

git remote get-url origin >/dev/null 2>&1 || die "Git remote 'origin' is required for Fleet to fetch Mattermost bundles."
git fetch --quiet origin main || die "Could not fetch origin/main; refusing teardown because Fleet needs that branch."
git diff --quiet FETCH_HEAD -- local-lab/fleet || die "Local Fleet files differ from origin/main; push the intended Fleet configuration before rebuilding."
untracked_fleet_files="$(git ls-files --others --exclude-standard -- local-lab/fleet)"
[[ -z "$untracked_fleet_files" ]] || die "Untracked Fleet files exist; commit and push the intended configuration before rebuilding."
for fleet_file in \
  local-lab/fleet/gitrepos/local-lab.yaml \
  local-lab/fleet/bundles/storage/fleet.yaml \
  local-lab/fleet/bundles/cnpg-operator/fleet.yaml \
  local-lab/fleet/bundles/mattermost-operator/fleet.yaml \
  local-lab/fleet/bundles/mattermost/fleet.yaml; do
  git cat-file -e "FETCH_HEAD:$fleet_file" 2>/dev/null || die "origin/main is missing $fleet_file; refusing teardown."
done

printf '%s\n' 'Preflight passed: tools, ISO, libvirt access, Ansible files, and Fleet content are available.'
printf '\n%s\n' 'Stage 1/6: inspect the exact VM teardown scope.'
"$scripts_dir/teardown-vms.sh"

printf '\n%s\n' 'Stage 2/6: tear down the two local VMs and their data disks.'
"$scripts_dir/teardown-vms.sh" --apply --yes

printf '\n%s\n' 'Stage 3/6: install RHEL and wait for both VMs.'
"$scripts_dir/provision-vms.sh"

printf '\n%s\n' 'Stage 4/6: configure RHEL host prerequisites.'
ANSIBLE_CONFIG="$repo_root/local-lab/ansible/ansible.cfg" \
  ansible-playbook --become-password-file "$secrets_dir/rhel-lab-console-password" \
  local-lab/ansible/playbooks/configure-hosts.yml

printf '\n%s\n' 'Stage 5/6: install RKE2 and wait for both nodes.'
ANSIBLE_CONFIG="$repo_root/local-lab/ansible/ansible.cfg" \
  ansible-playbook --become-password-file "$secrets_dir/rhel-lab-console-password" \
  local-lab/ansible/playbooks/install-rke2.yml

"$secrets_dir/kubectl" --kubeconfig "$secrets_dir/rke2.yaml" \
  wait --for=condition=Ready nodes --all --timeout=10m
"$secrets_dir/kubectl" --kubeconfig "$secrets_dir/rke2.yaml" get nodes -o wide

printf '\n%s\n' 'Stage 6/6: install Rancher and deploy Mattermost through Fleet.'
ANSIBLE_CONFIG="$repo_root/local-lab/ansible/ansible.cfg" \
  ansible-playbook local-lab/ansible/playbooks/install-rancher.yml

"$scripts_dir/deploy-mattermost.sh"

printf '\nLocal lab rebuild completed at %s.\n' "$(date --iso-8601=seconds)"
printf 'RHEL host configuration, RKE2, Rancher, and Mattermost are ready.\n'
printf 'Rancher: https://rancher.local-lab.test (admin password file: %s/rancher-bootstrap-password)\n' "$secrets_dir"
printf 'Mattermost: http://mattermost.local-lab.test (database password file: %s/mattermost-db-password)\n' "$secrets_dir"
printf 'Full log: %s\n' "$log_file"

#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
secrets_dir="$repo_root/.secrets"
iso="$repo_root/images/rhel-10.2-x86_64-dvd.iso"
image_dir="$repo_root/images"
iso_sha256="e15cb333529c332e76e4b1b946efe3515c99f996546675aec18e8effdf2540a5"
libvirt_iso="$image_dir/rhel-10.2-x86_64-dvd.iso"
volume_label="RHEL-10-2-BaseOS-x86_64"
use_sudo="${LOCAL_LAB_USE_SUDO:-auto}"
sudo_prefix=()

declare -a names=(cks-control cks-worker)
declare -a ips=(192.168.122.201 192.168.122.202)
declare -a macs=(52:54:00:86:c8:6a 52:54:00:82:33:16)

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

for utility in virsh virt-install sha256sum blkid openssl ssh-keygen ssh-keyscan; do
  command -v "$utility" >/dev/null 2>&1 || die "Install '$utility' before provisioning the local VMs."
done

[[ -f "$iso" ]] || die "RHEL ISO not found at $iso. Download the RHEL 10.2 x86_64 DVD ISO and place it there."
actual_sha256="$(sha256sum "$iso" | awk '{print $1}')"
[[ "$actual_sha256" == "$iso_sha256" ]] || die "Unexpected ISO checksum: $actual_sha256"
actual_label="$(blkid -p -s LABEL -o value "$iso" 2>/dev/null || true)"
[[ "$actual_label" == "$volume_label" ]] || die "Expected ISO volume label '$volume_label'; found '$actual_label'."

mkdir -p "$secrets_dir"
chmod 0700 "$secrets_dir"

ssh_private_key="$secrets_dir/rke2-lab-ed25519"
ssh_public_key_file="$ssh_private_key.pub"
if [[ ! -f "$ssh_private_key" ]]; then
  ssh-keygen -q -t ed25519 -N '' -C homelab-local-rke2 -f "$ssh_private_key"
fi
[[ -f "$ssh_public_key_file" ]] || die "SSH public key missing: $ssh_public_key_file"
ssh_public_key="$(<"$ssh_public_key_file")"

console_password_file="$secrets_dir/rhel-lab-console-password"
if [[ ! -s "$console_password_file" ]]; then
  openssl rand -hex 24 > "$console_password_file"
  chmod 0600 "$console_password_file"
fi
console_password_hash="$(openssl passwd -6 -stdin < "$console_password_file")"

case "$use_sudo" in
  auto)
    if ! virsh -c qemu:///system uri >/dev/null 2>&1; then
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
  "${sudo_prefix[@]}" virsh -c qemu:///system "$@"
}

run_virsh net-info default >/dev/null 2>&1 || die "The libvirt 'default' network must be defined."
run_virsh net-start default >/dev/null 2>&1 || true
run_virsh net-autostart default >/dev/null

ensure_dhcp_reservation() {
  local name="$1" ip="$2" mac="$3" xml
  xml="$(run_virsh net-dumpxml default)"
  if grep -Fq "mac='$mac'" <<<"$xml"; then
    grep -F "mac='$mac'" <<<"$xml" | grep -Fq "ip='$ip'" || die "DHCP reservation for $mac exists with a different address. Review the default libvirt network."
    return
  fi
  run_virsh net-update default add ip-dhcp-host \
    "<host mac='$mac' name='$name' ip='$ip'/>" --live --config
}

write_kickstart() {
  local name="$1" ks_file="$2"
  cat > "$ks_file" <<EOF
#version=RHEL10
text
cdrom
eula --agreed
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us'
timezone America/Chicago --utc
network --bootproto=dhcp --device=link --activate --hostname=${name}
rootpw --lock
user --name=corey --groups=wheel --shell=/bin/bash --password=${console_password_hash} --iscrypted
sshkey --username=corey "${ssh_public_key}"
selinux --enforcing
firewall --disabled
firstboot --disable
zerombr
clearpart --all --initlabel
autopart --type=lvm
bootloader --location=mbr
reboot

%packages
@^minimal-environment
kernel-modules-extra
openssh-server
sudo
%end

%post --erroronfail
echo '%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/99-homelab
chmod 0440 /etc/sudoers.d/99-homelab
systemctl enable sshd
%end
EOF
  chmod 0600 "$ks_file"
}

wait_for_ssh() {
  local name="$1" ip="$2" attempt vm_state restart_attempted=false
  printf 'Waiting for %s (%s) to finish RHEL installation' "$name" "$ip"
  for attempt in $(seq 1 240); do
    if ssh-keyscan -T 3 "$ip" >/dev/null 2>&1; then
      printf '\n'
      ssh-keygen -R "$ip" -f "$secrets_dir/known_hosts" >/dev/null 2>&1 || true
      ssh-keyscan -T 5 -H "$ip" >> "$secrets_dir/known_hosts" 2>/dev/null
      chmod 0600 "$secrets_dir/known_hosts"
      return
    fi
    vm_state="$(run_virsh domstate "$name" | tr -d '[:space:]')"
    if [[ "$vm_state" != running && "$restart_attempted" == false ]]; then
      printf '\n%s powered off after installation; starting it to finish booting.\n' "$name"
      run_virsh start "$name"
      restart_attempted=true
    fi
    printf '.'
    sleep 5
  done
  printf '\n'
  die "Timed out waiting for SSH on $ip. Inspect '$name' in Virtual Machine Manager or with virsh."
}

ensure_dvd_attached() {
  local name="$1" current_iso
  current_iso="$(run_virsh domblklist "$name" --details | awk '$2 == "cdrom" { print $4 }')"
  if [[ "$current_iso" != "$libvirt_iso" ]]; then
    run_virsh change-media "$name" sda "$libvirt_iso" --insert --live --config
  fi
}

[[ -r "$libvirt_iso" ]] || die "RHEL ISO is not readable at $libvirt_iso."
[[ "$(sha256sum "$libvirt_iso" | awk '{print $1}')" == "$iso_sha256" ]] || die "RHEL ISO at $libvirt_iso did not pass checksum verification."

for index in 0 1; do
  name="${names[$index]}"
  ip="${ips[$index]}"
  mac="${macs[$index]}"
  ks_file="$secrets_dir/${name}.ks"
  disk_file="$image_dir/${name}.qcow2"

  ensure_dhcp_reservation "$name" "$ip" "$mac"

  if run_virsh dominfo "$name" >/dev/null 2>&1; then
    printf '%s already exists; leaving its VM and disk untouched.\n' "$name"
    vm_state="$(run_virsh domstate "$name" | tr -d '[:space:]')"
    if [[ "$vm_state" != "running" ]]; then
      run_virsh start "$name"
    fi
    run_virsh autostart "$name" >/dev/null
  else
    if [[ -e "$disk_file" ]]; then
      die "Disk $disk_file exists without a VM definition. Inspect it before removing or reusing it."
    fi
    write_kickstart "$name" "$ks_file"
    printf 'Creating %s at %s with unattended RHEL installation.\n' "$name" "$ip"
    "${sudo_prefix[@]}" virt-install \
      --connect qemu:///system \
      --name "$name" \
      --memory 4096 \
      --vcpus 2 \
      --os-variant rhel10.0 \
      --disk "path=${disk_file},size=30,format=qcow2,bus=virtio" \
      --network "network=default,model=virtio,mac=${mac}" \
      --location "$libvirt_iso" \
      --initrd-inject "$ks_file" \
      --extra-args "inst.ks=file:/$(basename "$ks_file") inst.repo=hd:LABEL=${volume_label} inst.text console=ttyS0,115200n8" \
      --graphics none \
      --console pty,target_type=serial \
      --noautoconsole \
      --autostart
  fi

  wait_for_ssh "$name" "$ip"
  ensure_dvd_attached "$name"
done

printf '\nVMs are ready for Ansible. Local console password: %s\n' "$console_password_file"
printf 'Run the playbooks with ANSIBLE_CONFIG=local-lab/ansible/ansible.cfg from the repository root.\n'

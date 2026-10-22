# Local VM RKE2 exercise

This is the reproducible setup for the two disposable libvirt VMs. It is intentionally separate from the physical homelab configuration under [`../ansible/`](../ansible/README.md).

The provisioning script creates the VMs and installs RHEL 10.2 unattended with Kickstart. Ansible then configures RHEL and installs RKE2.

## What this automates

- Configures the attached RHEL DVD as persistent local BaseOS and AppStream repositories.
- Checks RHEL 10 and SELinux enforcing mode, installs `kernel-modules-extra`, excludes Canal interfaces from NetworkManager, and disables firewalld for this isolated NAT exercise.
- Installs the pinned RKE2 server and agent RPMs, configures the server and joins the worker, and keeps the join token out of Ansible output.
- Retrieves the cluster kubeconfig and bundled `kubectl` into the ignored `.secrets/` directory.

The script expects a Linux host with libvirt's `default` NAT network (`192.168.122.0/24`) and the RHEL 10.2 x86_64 DVD ISO at `images/rhel-10.2-x86_64-dvd.iso`. It checks the ISO checksum and volume label, creates DHCP reservations for `.201` and `.202`, and creates two 2-vCPU, 4-GiB, 30-GiB VMs. It creates a lab SSH key and console password in ignored `.secrets/`, injects the public key into the RHEL install, and records the new SSH host keys there. RHEL remains unregistered, so it will not receive Red Hat CDN updates.

The provisioner never deletes or overwrites an existing VM or disk. Existing VMs are started and left intact. If a VM definition is missing while its disk remains, the script stops for manual review. If both laptop and VMs are lost, download the ISO again from Red Hat; it is not stored in Git.

## Prepare the Ansible controller

On Debian or Ubuntu, install libvirt, the VM tools, Ansible, and the SSH client:

```sh
sudo apt update
sudo apt install libvirt-daemon-system libvirt-clients virtinst qemu-utils ansible-core openssh-client openssl util-linux
```

Download the RHEL 10.2 x86_64 DVD ISO from Red Hat, put it at `images/rhel-10.2-x86_64-dvd.iso`, then provision the VMs from the repository root:

```sh
local-lab/scripts/provision-vms.sh
```

The script asks for sudo when it needs access to system libvirt, installs the ISO under `/var/lib/libvirt/images`, and waits for both RHEL installs to accept SSH. It generates a lab-only SSH key and console password if they do not already exist; the password is in `.secrets/rhel-lab-console-password`. Keep `.secrets/` private; it is ignored by Git.

When you want to remove the VMs, preview the teardown first:

```sh
local-lab/scripts/teardown-vms.sh
```

To proceed, add `--apply` and type the requested confirmation phrase:

```sh
local-lab/scripts/teardown-vms.sh --apply
```

It shuts down and undefines only `cks-control` and `cks-worker`, then removes only same-named qcow2 disks referenced by those VM definitions. It never force-powers-off a VM. DHCP reservations, ISO files, and `.secrets/` are preserved. If the guests do not shut down cleanly or have snapshots, it stops for manual review.

## Run the playbooks

After the script finishes, run these from the repository root. The local-lab inventory, SSH settings, and variable values are loaded from `local-lab/ansible/`:

```sh
ANSIBLE_CONFIG=local-lab/ansible/ansible.cfg ansible-playbook local-lab/ansible/playbooks/configure-hosts.yml
ANSIBLE_CONFIG=local-lab/ansible/ansible.cfg ansible-playbook local-lab/ansible/playbooks/install-rke2.yml
```

Then inspect the cluster:

```sh
.secrets/kubectl --kubeconfig .secrets/rke2.yaml get nodes -o wide
```

If `k9s` is installed, open this cluster without changing your default kubeconfig with `k9s --kubeconfig .secrets/rke2.yaml`.

The inventory, RHEL DVD label, RKE2 version, network ranges, and firewalld behavior are in `local-lab/ansible/`. Change them there when intentionally changing this local VM exercise. Do not copy these VM addresses or variables into the physical homelab inventory.

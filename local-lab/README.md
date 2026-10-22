# Local VM RKE2 exercise

This is the reproducible configuration for the two disposable libvirt VMs. It is intentionally separate from the physical homelab configuration under [`../ansible/`](../ansible/README.md).

## What this automates

- Configures the attached RHEL DVD as persistent local BaseOS and AppStream repositories.
- Checks RHEL 10 and SELinux enforcing mode, installs `kernel-modules-extra`, excludes Canal interfaces from NetworkManager, and disables firewalld for this isolated NAT exercise.
- Installs the pinned RKE2 server and agent RPMs, configures the server and joins the worker, and keeps the join token out of Ansible output.
- Retrieves the cluster kubeconfig and bundled `kubectl` into the ignored `.secrets/` directory.

The playbooks configure already installed RHEL VMs. They do not create libvirt VMs or install RHEL. Recreating the environment also requires the RHEL 10.2 DVD ISO, libvirt with its default `192.168.122.0/24` network, two VMs with the documented CPU/memory/disk settings, DHCP reservations for `.201` and `.202`, and RHEL installed with the `corey` account and Ansible SSH key authorized. Attach the DVD to each VM and confirm it is labeled `RHEL-10-2-BaseOS-x86_64`.

If the VMs survive but the laptop is replaced, generate a new SSH key and add its public key to the `corey` account on both nodes through the VM console before running Ansible. If both laptop and VMs are lost, rebuild the VMs and RHEL baseline first; the ISO can be downloaded again from Red Hat, but is not stored in Git.

## Prepare the Ansible controller

On Debian or Ubuntu, install Ansible and the SSH client:

```sh
sudo apt update
sudo apt install ansible-core openssh-client
```

From the repository root, create local credentials and accept the VM host keys:

```sh
mkdir -p .secrets
ssh-keygen -t ed25519 -f .secrets/rke2-lab-ed25519 -C homelab-local-rke2
ssh-keyscan -H 192.168.122.201 192.168.122.202 > .secrets/known_hosts
```

Install the public key in `~corey/.ssh/authorized_keys` on both VMs. Keep the private key in `.secrets/`; that directory is ignored by Git. For an existing setup, use the key already authorized on the VMs if it is available.

## Run the playbooks

Run these from the repository root. The local-lab inventory, SSH settings, and variable values are loaded from `local-lab/ansible/`:

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

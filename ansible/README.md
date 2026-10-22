# Physical homelab Ansible

This directory is reserved for the future cluster on the physical homelab machines. It is deliberately separate from the disposable libvirt VMs in [`../local-lab/`](../local-lab/README.md).

Do not put the VM inventory, `192.168.122.0/24` addresses, or local-lab settings here. Add the physical machines' inventory and playbooks only after their switch/VLAN, addressing, RHEL release, and roles have been decided.

The starter inventory has no hosts, and its playbooks are empty. It is not currently runnable. Keep private keys, passwords, join tokens, and kubeconfigs out of version control.

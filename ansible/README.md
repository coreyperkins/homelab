# Ansible starter

This directory is for deployment steps 3 and 4 in the root README:

1. Configure the installed RHEL hosts.
2. Install and configure RKE2 on the selected server and agent nodes.

The inventory and playbooks are intentionally scaffolding. No server names, addresses, RHEL release, RKE2 version, network ranges, or access credentials have been chosen yet. Fill those in after the machines arrive and the topology is decided.

## Layout

- `ansible.cfg` sets this directory's inventory and role paths.
- `inventory/hosts.yml` defines empty RKE2 server and agent groups for the future host inventory.
- `group_vars/all.yml` is for shared, non-secret configuration.
- `playbooks/configure-hosts.yml` is the entry point for host setup.
- `playbooks/install-rke2.yml` is the entry point for RKE2 installation.

Do not put passwords, tokens, private keys, or vault password files in version control. Use Ansible Vault for secret variables and keep its password outside this repository. The configured inventory contains no hosts yet, so the playbooks are not ready to run.

## Next steps when the servers arrive

1. Add host names, management addresses, and server/agent roles to `inventory/hosts.yml`.
2. Decide the Ansible controller, SSH user, and privilege escalation approach.
3. Confirm the RHEL version and required host configuration.
4. Choose RKE2 version and topology, then add their variables and role tasks.
5. Define and check pod/service network ranges before installing the cluster.

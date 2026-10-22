# PXE provisioning starter

This directory holds the first PXE boot and Kickstart templates for installing RHEL. The homelab network, DHCP owner, RHEL release, and PXE server have not been selected yet, so these files are examples and are not a deployable PXE service configuration.

## Current approach

- Use iPXE to fetch an RHEL kernel and initrd over HTTP.
- Use the RHEL installer tree as the installation source.
- Pass a per-host Kickstart URL to Anaconda. The Kickstart template uses Ansible/Jinja variables and must be rendered for each machine.
- Leave disk selection and partitioning interactive until the target hardware and desired disk layout are known. Do not add `clearpart`, `autopart`, or `ignoredisk` without reviewing the effect on the target machine.
- Do not configure a DHCP server here yet. First decide whether the homelab is isolated or how the existing DHCP service will provide PXE boot information. Do not run a second DHCP server on the household LAN.

## Files

- `boot.ipxe.example` is an iPXE menu with local boot as the timeout default and a separately selected RHEL installer entry.
- `kickstarts/rhel.ks.j2` is a Kickstart template. Render host-specific values such as the hostname, installation-tree URL, and package selection before serving it to a machine.

The example boot script uses `192.0.2.10` and a RHEL 9 path as documentation placeholders. Replace them with the address and install tree selected for this lab. The HTTP installation tree must contain the RHEL installer files, including `.treeinfo` and `images/pxeboot/{vmlinuz,initrd.img}`. The tree must be reachable by the target during installation.

## Next decisions

1. Decide the switch topology and whether PXE traffic will be isolated from the home LAN.
2. Identify which service owns DHCP and how it will direct UEFI and (if needed) legacy BIOS clients to iPXE.
3. Select RHEL release, architecture, and installation tree location.
4. Choose how the boot server hosts the iPXE script, installer tree, and per-host Kickstart files.
5. Define host inventory and disk layout before enabling unattended storage changes.

The RHEL installer supports `inst.repo=` for the installation tree and `inst.ks=` for a Kickstart file. See Red Hat's documentation for [PXE Kickstart installation](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/automatically_installing_rhel/starting-kickstart-installations_rhel-installer) and [installation source boot options](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/interactively_installing_rhel_over_the_network/custom-boot-options_rhel-installer).

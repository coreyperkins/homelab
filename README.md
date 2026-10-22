# Kubernetes Homelab

Early requirements and deployment outline for a small, self-managed Kubernetes homelab.

## Goals

- Connect the homelab machines to a small network switch.
- Install Red Hat Enterprise Linux (RHEL) on the machines.
- Use PXE network boot to make operating system installation repeatable.
- Use Ansible to automate host configuration and cluster setup.
- Install RKE2 as the Kubernetes distribution.

## Initial deployment flow

1. Connect the machines and the provisioning host to the switch.
2. Prepare a PXE environment to boot the machines and install RHEL.
3. Use Ansible to configure the installed systems and their prerequisites.
4. Use Ansible to install and configure RKE2 on the selected server and agent nodes.
5. Verify that the nodes join the cluster and report Ready.

PXE boot and Kickstart starting files are in [`pxe/`](pxe/README.md). They are templates for development, not ready-to-enable network services; the DHCP owner, RHEL release, and lab network still need to be chosen.

Ansible starter files for host configuration and RKE2 deployment are in [`ansible/`](ansible/README.md). Inventory and playbooks are scaffolding until the servers and their roles are known.

PXE requires a boot and installation service on the network. Decide where that service will run and how it will coexist with the existing DHCP service before enabling it; avoid introducing a second, conflicting DHCP server on a shared LAN.

## Early requirements

### Hardware and networking

- A small Ethernet switch connects all homelab machines.
- A provisioning host or service must be reachable by the machines during PXE boot.
- The switch uplink, VLAN use, and whether the lab is isolated from the household LAN are not yet specified.
- Reserve stable addresses or DHCP reservations for the hosts and document their names and addresses.

### Operating system provisioning

- RHEL is the host operating system.
- Machines should be installable by PXE so rebuilds do not require individual installation media.
- Select the RHEL release, installation source, boot mode, and provisioning implementation before building the PXE workflow.
- Keep credentials, subscription details, and other secrets out of this repository.

### Configuration management

- Ansible is the automation tool for repeatable host configuration and RKE2 installation.
- Maintain an inventory of host names, addresses, and intended roles.
- Store reusable configuration in playbooks and roles; keep site-specific values in inventory or variables.
- Define how Ansible reaches newly provisioned hosts and where its controller runs.

### Kubernetes

- RKE2 is the Kubernetes distribution for the cluster.
- Decide the number of server and agent nodes, the RKE2 version, and whether the first deployment is single-server or highly available.
- Define the pod and service network ranges and confirm they do not overlap with the home network.
- Document how cluster credentials and join tokens are generated, distributed, and protected.

## Decisions to make

- Number and specifications of machines, including which will be RKE2 server and agent nodes.
- RHEL release and entitlement or subscription approach.
- Whether the homelab uses a dedicated subnet or VLAN, and its address ranges.
- PXE firmware modes (UEFI/BIOS), DHCP responsibilities, and the host or service that provides PXE/TFTP/HTTP.
- Ansible controller location and inventory format.
- RKE2 version, topology, and pod/service CIDRs.
- Storage, ingress, DNS, backups, and external access requirements for workloads.

## Working principles

- Make provisioning and configuration repeatable so a host can be rebuilt from documented inputs.
- Keep secrets out of version control.
- Record chosen versions, network ranges, host roles, and operational steps here as the design is settled.

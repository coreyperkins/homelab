# Homelab session handoff

Last updated: 2026-10-23

## Current local lab state

- `cks-control` is RHEL 10.2 at `192.168.122.201`.
- `cks-worker` is RHEL 10.2 at `192.168.122.202`.
- Both nodes are configured with SELinux enforcing, the RHEL DVD repositories, and host prerequisites for RKE2.
- RKE2 `v1.36.5+rke2r1` is installed; both nodes were verified `Ready`.
- Rancher `2.15.2` is installed at <https://rancher.local-lab.test>.
- Mattermost Team Edition `12.0.0` is deployed at <http://mattermost.local-lab.test> through Fleet. The GitRepo reports 4/4 ready bundle deployments, the app and database pods were Ready, and both PVCs were Bound.
- `/etc/hosts` maps both `rancher.local-lab.test` and `mattermost.local-lab.test` to `192.168.122.201`.

## Kubeconfig

- The default `/home/corey/.kube/config` now selects `rancher-local`, which uses Rancher’s proxy endpoint for the local cluster. Its direct `rke2-lab` context remains available.
- The original kubeconfig backup is `/home/corey/.kube/config.bak-20261023-094404`.
- `.secrets/rke2.yaml` remains the direct RKE2 kubeconfig used by the local scripts. `.secrets/kubectl` is the bundled client.
- The Rancher-generated kubeconfig token may expire according to Rancher’s kubeconfig-token TTL. If it stops authenticating, download/regenerate a cluster kubeconfig from Rancher and merge it into `~/.kube/config` while preserving both contexts.

## Mattermost account and secrets

- No Mattermost application admin account or password is preconfigured. Create the first account through the Mattermost UI; Mattermost assigns the first user the System Admin role.
- `.secrets/mattermost-db-password` is only the PostgreSQL password and cannot be used to log into Mattermost.
- Rancher username is `admin`; bootstrap and any updated admin password files are under `.secrets/`.
- Never print or commit any `.secrets/` contents.

## One-command rebuild

The complete local stack is rebuilt with:

```sh
local-lab/scripts/rebuild-local-lab.sh --confirm-destroy
```

This deletes both VM disks and cluster data, then provisions RHEL, configures hosts, installs RKE2 and Rancher, and deploys Mattermost. It checks the ISO, direct libvirt access, and remote Fleet files before teardown. It stops on the first failure and records output in `.secrets/local-lab-rebuild-*.log`. Do not run this unless the user explicitly requests a destructive rebuild.

The Mattermost-only deploy command is `local-lab/scripts/deploy-mattermost.sh`. It preserves existing DB credentials, applies the Fleet GitRepo, and waits for all four bundles and Mattermost pods. Its Fleet readiness check uses the bundle deployment `1/1` count; Fleet leaves the display state blank for ready bundles.

## Recent fixes

- Removed the inventory-wide `ansible_become: true` setting so delegated localhost tasks do not try to use the VM sudo password. Host and RKE2 plays enable become explicitly.
- Added a bounded wait for Rancher to create its webhook deployment before checking its rollout.
- Fixed Fleet readiness parsing in the Mattermost script and added periodic status output and a grace period for transient dependency errors.
- Fixed the Kickstart sudoers rule, persistent DVD attachment, host-playbook ordering, and Ansible variable-file loading. Details are in `local-lab/README.md`.

## Working tree

Documentation, Ansible, and local-lab scripts have uncommitted changes from the rebuild and prompt/readiness fixes. Review `git status` before committing. Root-level `kubectl` and `kubectl.sha256` artifacts are ignored and should not be committed.

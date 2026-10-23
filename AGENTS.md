# Repository guidance for Codex

## Start here

- Read [`README.md`](README.md) for the project structure.
- Read [`HANDOFF.md`](HANDOFF.md) before resuming operational work; it records the current lab state and recent decisions.
- Use [`local-lab/README.md`](local-lab/README.md) for the disposable VM workflow and [`ansible/README.md`](ansible/README.md) for the future physical cluster boundary.

## Keep the two environments separate

- `ansible/` is reserved for future physical machines. Do not put local VM addresses, inventory, or settings there.
- `local-lab/` contains the disposable libvirt VMs, their Ansible configuration, Fleet bundles, and local scripts.
- The local VMs use `192.168.122.201` (`cks-control`) and `192.168.122.202` (`cks-worker`). Do not reuse those addresses for physical hardware.

## Secrets and kubeconfigs

- Never print, commit, or copy values from `.secrets/` into tracked files. The directory is ignored by Git.
- `.secrets/rke2.yaml` is the direct RKE2 kubeconfig. The default `~/.kube/config` currently selects `rancher-local`, which accesses the cluster through Rancher; its `rke2-lab` context is preserved as a direct endpoint.
- The Mattermost database password is not an application login. Mattermost has no seeded admin password; its first registered user receives the System Admin role.
- Root-level downloaded `kubectl` artifacts are ignored; do not add them to commits.

## Running the local lab

- The full destructive rebuild is `local-lab/scripts/rebuild-local-lab.sh --confirm-destroy`. It deletes both VM disks and all cluster data on them, then rebuilds RHEL, host configuration, RKE2, Rancher, and Mattermost.
- Run the full rebuild only when the user explicitly asks. It is designed to execute as one command with no interactive prompts: direct libvirt access is required, host sudo is disabled, Ansible reads the private VM password file, and teardown receives `--yes`.
- If Codex runs a multi-stage operation, use one elevated command invocation for the entire authorized pipeline. Do not ask for separate approval between stages.
- If a stage fails, stop and report the failed stage and log path. Do not launch separate elevated inspection or recovery commands without user direction; include safe diagnostics in the original run where practical.
- The standalone `local-lab/scripts/deploy-mattermost.sh` is idempotent and waits for Fleet bundles and Mattermost pods to become Ready. Do not run it as an implicit part of a host-only task.
- Do not commit or push unless the user asks.
- Do not add or run tests unless the user asks.

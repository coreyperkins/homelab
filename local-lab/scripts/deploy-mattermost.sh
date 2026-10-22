#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
secrets_dir="${repo_root}/.secrets"
kubeconfig="${secrets_dir}/rke2.yaml"
kubectl="${secrets_dir}/kubectl"
db_password_file="${secrets_dir}/mattermost-db-password"

if [[ ! -x "${kubectl}" || ! -r "${kubeconfig}" ]]; then
  echo "Missing local cluster credentials. Run local-lab/ansible/playbooks/install-rke2.yml first." >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to generate the local database password." >&2
  exit 1
fi

chmod 0700 "${secrets_dir}"

"${kubectl}" --kubeconfig "${kubeconfig}" create namespace mattermost \
  --dry-run=client -o yaml | "${kubectl}" --kubeconfig "${kubeconfig}" apply -f -

db_secret_exists=false
connection_secret_exists=false
if "${kubectl}" --kubeconfig "${kubeconfig}" -n mattermost get secret mattermost-db-app >/dev/null 2>&1; then
  db_secret_exists=true
fi
if "${kubectl}" --kubeconfig "${kubeconfig}" -n mattermost get secret mattermost-db-credentials >/dev/null 2>&1; then
  connection_secret_exists=true
fi

if [[ "${db_secret_exists}" == false && "${connection_secret_exists}" == false ]]; then
  umask 077
  db_password="$(openssl rand -hex 24)"
  printf '%s' "${db_password}" > "${db_password_file}"
  chmod 0600 "${db_password_file}"

  secret_env_file="$(mktemp "${secrets_dir}/mattermost-db.XXXXXX")"
  trap 'rm -f "${secret_env_file}"' EXIT
  printf 'username=mattermost\npassword=%s\n' "${db_password}" > "${secret_env_file}"
  "${kubectl}" --kubeconfig "${kubeconfig}" -n mattermost create secret generic mattermost-db-app \
    --from-env-file="${secret_env_file}" --dry-run=client -o yaml \
    | "${kubectl}" --kubeconfig "${kubeconfig}" apply -f -

  printf 'DB_CONNECTION_STRING=postgres://mattermost:%s@mattermost-db-rw:5432/mattermost?sslmode=disable\n' \
    "${db_password}" > "${secret_env_file}"
  "${kubectl}" --kubeconfig "${kubeconfig}" -n mattermost create secret generic mattermost-db-credentials \
    --from-env-file="${secret_env_file}" --dry-run=client -o yaml \
    | "${kubectl}" --kubeconfig "${kubeconfig}" apply -f -
elif [[ "${db_secret_exists}" != true || "${connection_secret_exists}" != true ]]; then
  echo "Only one Mattermost database secret exists; refusing to rotate credentials automatically." >&2
  echo "Review the mattermost namespace secrets before retrying." >&2
  exit 1
fi

"${kubectl}" --kubeconfig "${kubeconfig}" apply -f \
  "${repo_root}/local-lab/fleet/gitrepos/local-lab.yaml"

echo "Fleet GitRepo applied. Fleet will sync the Mattermost bundles from origin/main."
echo "The generated database password is in ${db_password_file} (mode 0600)."

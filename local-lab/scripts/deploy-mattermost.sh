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

echo "Fleet GitRepo applied. Waiting for its bundles and Mattermost workloads to become Ready."

deadline=$((SECONDS + 1800))
error_since=0
last_error_state=""
next_status_report=$((SECONDS + 60))
printf 'Waiting up to 30 minutes for all four Fleet bundles and Mattermost pods'
while (( SECONDS < deadline )); do
  bundle_states="$("${kubectl}" --kubeconfig "${kubeconfig}" -n fleet-local \
    get bundles --no-headers 2>/dev/null || true)"

  error_state="$(grep -E 'Err[A-Za-z]+' <<<"${bundle_states}" || true)"
  if [[ -n "${error_state}" ]]; then
    if [[ "${error_state}" != "${last_error_state}" ]]; then
      error_since="${SECONDS}"
      last_error_state="${error_state}"
      printf '\nFleet is still reconciling dependencies; allowing up to three minutes for this error to clear.\n' >&2
    elif (( SECONDS - error_since >= 180 )); then
      printf '\nFleet bundle error persisted for three minutes:\n%s\n' "${bundle_states}" >&2
      "${kubectl}" --kubeconfig "${kubeconfig}" -n fleet-local get gitrepo,bundles >&2 || true
      exit 1
    fi
  else
    error_since=0
    last_error_state=""
  fi

  bundle_count="$(awk 'NF { count++ } END { print count + 0 }' <<<"${bundle_states}")"
  ready_bundle_count="$(awk '$2 ~ /^[0-9]+\/[0-9]+$/ { split($2, counts, "/"); if (counts[1] > 0 && counts[1] == counts[2]) count++ } END { print count + 0 }' <<<"${bundle_states}")"
  if (( bundle_count >= 4 && ready_bundle_count == bundle_count )); then
    mattermost_pods="$("${kubectl}" --kubeconfig "${kubeconfig}" -n mattermost \
      get pods --no-headers 2>/dev/null || true)"
    if [[ -n "${mattermost_pods}" ]] && \
      "${kubectl}" --kubeconfig "${kubeconfig}" -n mattermost \
        wait --for=condition=Ready pods --all --timeout=30s >/dev/null 2>&1; then
      printf '\nAll Fleet bundles and Mattermost namespace pods are Ready.\n'
      break
    fi
  fi

  printf '.'
  if (( SECONDS >= next_status_report )); then
    printf '\nFleet bundle readiness: %s/%s\n' "${ready_bundle_count}" "${bundle_count}"
    "${kubectl}" --kubeconfig "${kubeconfig}" -n mattermost get pods,pvc >&2 || true
    next_status_report=$((SECONDS + 60))
  fi
  sleep 10
done

if (( SECONDS >= deadline )); then
  printf '\nMattermost did not become Ready before the timeout. Current status:\n' >&2
  "${kubectl}" --kubeconfig "${kubeconfig}" -n fleet-local get gitrepo,bundles >&2 || true
  "${kubectl}" --kubeconfig "${kubeconfig}" -n mattermost get pods,pvc >&2 || true
  exit 1
fi

echo "Mattermost is ready at http://mattermost.local-lab.test."
echo "The generated database password is in ${db_password_file} (mode 0600)."

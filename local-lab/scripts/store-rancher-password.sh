#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
secrets_dir="${repo_root}/.secrets"
password_file="${secrets_dir}/rancher-admin-password"

umask 077
mkdir -p "${secrets_dir}"

IFS= read -r -s -p 'Enter the new Rancher admin password: ' first_password
printf '\n'
IFS= read -r -s -p 'Confirm the Rancher admin password: ' second_password
printf '\n'

if [[ -z "${first_password}" ]]; then
  printf 'Password cannot be empty.\n' >&2
  exit 1
fi

if [[ "${first_password}" != "${second_password}" ]]; then
  printf 'Passwords do not match; nothing was saved.\n' >&2
  exit 1
fi

printf '%s' "${first_password}" > "${password_file}"
chmod 600 "${password_file}"
unset first_password second_password

printf 'Saved securely to %s\n' "${password_file}"

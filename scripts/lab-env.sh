#!/usr/bin/env bash

# Load local Floci AWS credentials into the current shell.
# Usage: source scripts/lab-env.sh
#
# Do not execute this script directly.
# Do not enable set -euo pipefail here: this file is sourced.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf '[STOP] This script must be sourced, not executed.\n' >&2
  printf 'Usage: source scripts/lab-env.sh\n' >&2
  exit 2
fi

_lab_env_init() {
  local script_dir tf_dir access_key secret_key

  if ! command -v terraform >/dev/null 2>&1; then
    printf '[STOP] Terraform CLI unavailable\n' >&2
    return 2
  fi

  script_dir="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
  )" || return 2

  tf_dir="$script_dir/../terraform/platform"

  if [[ ! -s "$tf_dir/terraform.tfstate" ]]; then
    printf '[STOP] Platform Terraform state missing\n' >&2
    return 2
  fi

  if ! access_key="$(
    terraform -chdir="$tf_dir" \
      output -raw platform_admin_access_key_id
  )"; then
    printf '[STOP] Could not retrieve Floci access key\n' >&2
    return 2
  fi

  if ! secret_key="$(
    terraform -chdir="$tf_dir" \
      output -raw platform_admin_secret_access_key
  )"; then
    printf '[STOP] Could not retrieve Floci secret key\n' >&2
    return 2
  fi

  if [[ -z "$access_key" || -z "$secret_key" ]]; then
    printf '[STOP] Floci credentials are empty\n' >&2
    return 2
  fi

  export AWS_ACCESS_KEY_ID="$access_key"
  export AWS_SECRET_ACCESS_KEY="$secret_key"
  export AWS_DEFAULT_REGION=us-east-1
  export AWS_ENDPOINT_URL=http://localhost:4566

  unset AWS_SESSION_TOKEN

  printf '[OK] Floci AWS environment loaded\n'
  printf '[INFO] Endpoint: %s\n' "$AWS_ENDPOINT_URL"
  printf '[INFO] Credentials loaded without displaying secrets\n'
}

if _lab_env_init; then
  unset -f _lab_env_init
else
  unset -f _lab_env_init
  return 2
fi

#!/usr/bin/env bash

# Read-only validation of existing K3s authentication webhooks.
# Works with running or stopped Docker containers.

set -euo pipefail


TEMP_DIR="$(mktemp -d)"
chmod 700 "$TEMP_DIR"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

for cluster in devops-mgmt devops-nonprod devops-prod; do
  container="floci-eks-$cluster"
  file="$TEMP_DIR/$cluster.yaml"

  if ! docker cp \
    "$container:/etc/token-webhook.yaml" \
    "$file" >/dev/null 2>&1; then

    echo "[STOP] $cluster: cannot inspect webhook configuration" >&2
    exit 2
  fi

  count="$(
    grep -Ec '^[[:space:]]*server:[[:space:]]*' "$file" || true
  )"

  if [[ "$count" != "1" ]]; then
    echo "[STOP] $cluster: unexpected webhook configuration" >&2
    exit 2
  fi

  if ! grep -Eq \
    '^[[:space:]]*server:[[:space:]]*http://floci:4566/_floci/eks/token-webhook[[:space:]]*$' \
    "$file"; then

    echo "[STOP] $cluster: webhook endpoint is not the approved hostname" >&2
    exit 2
  fi

  echo "[OK] $cluster: authentication webhook uses Floci hostname"
done

echo "[OK] All EKS authentication webhook configurations verified"

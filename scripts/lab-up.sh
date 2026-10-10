#!/usr/bin/env bash

# Safely resume the existing local DevOps lab.
# Never create, recreate, delete, or prune infrastructure.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
FLOCI_DIR="$HOME/tools/floci-ui"

CLUSTERS=(devops-mgmt devops-nonprod devops-prod)

stop() {
  printf '[STOP] %s\n' "$1" >&2
  exit 2
}

info() {
  printf '[INFO] %s\n' "$1"
}

ok() {
  printf '[OK] %s\n' "$1"
}

start_existing() {
  local name="$1"
  local running

  running="$(docker inspect "$name" \
    --format '{{.State.Running}}')" \
    || stop "Cannot inspect container: $name"

  if [[ "$running" == "true" ]]; then
    ok "$name already running"
  else
    info "Starting existing container: $name"
    docker start "$name" >/dev/null \
      || stop "Cannot start existing container: $name"
    ok "$name started"
  fi
}

printf '\n=== DevOps Lab Safe Startup ===\n'

# Docker Engine must be available before inspecting volumes.
if ! docker info >/dev/null 2>&1; then
  info "Docker unavailable; attempting to start Docker Engine"
  sudo systemctl start docker \
    || stop "Could not start Docker Engine"
fi

docker info >/dev/null 2>&1 \
  || stop "Docker Engine unavailable"

ok "Docker Engine reachable"

# Preflight: do not start Floci until existing storage is verified.
info "Verifying persistent-volume identities"

"$SCRIPT_DIR/lab-volume-baseline.sh" --verify \
  || stop "Persistent-volume verification failed"

# Require the existing Docker network and Floci metadata.
docker network inspect floci_default >/dev/null 2>&1 \
  || stop "Existing floci_default network missing"

[[ -f "$FLOCI_DIR/data/eks-clusters.json" ]] \
  || stop "Floci EKS metadata missing"

ok "Floci network and metadata present"

# Require existing containers. Never silently recreate missing ones.
CONTAINERS=(
  floci-eks-devops-mgmt
  floci-eks-devops-nonprod
  floci-eks-devops-prod
  floci-ui-floci-1
  floci-ui-floci-api-1
  floci-ui-floci-ui-1
)

for container in "${CONTAINERS[@]}"; do
  docker container inspect "$container" >/dev/null 2>&1 \
    || stop "Expected container missing: $container"
done

ok "All expected containers exist"

# The active Floci container must already use the safe settings.
floci_env="$(docker inspect floci-ui-floci-1 \
  --format '{{range .Config.Env}}{{println .}}{{end}}')"

grep -Fxq \
  'FLOCI_SERVICES_EKS_KEEP_RUNNING_ON_SHUTDOWN=true' \
  <<< "$floci_env" \
  || stop "Unsafe Floci shutdown setting"

grep -Fxq \
  'FLOCI_STORAGE_PRUNE_VOLUMES_ON_DELETE=false' \
  <<< "$floci_env" \
  || stop "Unsafe Floci volume-pruning setting"

ok "Floci persistence settings verified"

# Start the existing k3s containers before Floci attempts adoption.
for cluster in "${CLUSTERS[@]}"; do
  start_existing "floci-eks-$cluster"
done

# Start only the existing Floci stack containers.
start_existing floci-ui-floci-1
start_existing floci-ui-floci-api-1
start_existing floci-ui-floci-ui-1

# Verify storage has not changed during startup.
"$SCRIPT_DIR/lab-volume-baseline.sh" --verify \
  || stop "Persistent volumes changed during startup"

# Load operator credentials into this process only.
TF_DIR="$INFRA_DIR/terraform/platform"

command -v terraform >/dev/null 2>&1 \
  || stop "Terraform CLI unavailable"

AWS_ACCESS_KEY_ID="$(terraform -chdir="$TF_DIR" \
  output -raw platform_admin_access_key_id)" \
  || stop "Cannot load platform access key"

AWS_SECRET_ACCESS_KEY="$(terraform -chdir="$TF_DIR" \
  output -raw platform_admin_secret_access_key)" \
  || stop "Cannot load platform secret key"

export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=us-east-1
export AWS_ENDPOINT_URL=http://localhost:4566
unset AWS_SESSION_TOKEN

# Allow the local APIs a bounded startup window.
info "Waiting for Kubernetes API readiness"

ready=false

for attempt in {1..20}; do
  all_ready=true

  for cluster in "${CLUSTERS[@]}"; do
    response="$(kubectl --context "$cluster" \
      --request-timeout=3s \
      get --raw=/readyz 2>/dev/null || true)"

    if [[ "$response" != "ok" ]]; then
      all_ready=false
      break
    fi
  done

  if [[ "$all_ready" == "true" ]]; then
    ready=true
    break
  fi

  sleep 3
done

if [[ "$ready" == "true" ]]; then
  ok "All three Kubernetes APIs ready"
else
  info "Some Kubernetes APIs are not ready; checking diagnostics"
fi

printf '\n=== Final Lab Health Check ===\n'

# Exit code reflects actual lab health, including missing GitOps resources.
if "$SCRIPT_DIR/lab-status.sh"; then
  status=0
else
  status=$?
fi

printf '\n[INFO] Lab health-check exit code: %s\n' "$status"
exit "$status"

#!/usr/bin/env bash

# DevOps Platform Lab - Read-only health and persistence checks.
# This script must never create, restart, or delete infrastructure.

set -u
set -o pipefail

FLOCI_URL="http://localhost:4566"
CLUSTERS=(devops-mgmt devops-nonprod devops-prod)

warnings=0
failures=0

declare -A api_ready

ok() {
  printf '[OK] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1"
  warnings=$((warnings + 1))
}

fail() {
  printf '[FAIL] %s\n' "$1"
  failures=$((failures + 1))
}

section() {
  printf '\n=== %s ===\n' "$1"
}

section "DevOps Platform Lab Status"

# Check required local tools.
for tool in docker kubectl jq curl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    fail "Required tool unavailable: $tool"
    exit 2
  fi
done

# Docker availability.
section "Docker Engine"

if ! docker info >/dev/null 2>&1; then
  fail "Docker Engine is unavailable"
  exit 2
fi

ok "Docker Engine reachable"

# Floci runtime.
section "Floci"

if docker inspect floci-ui-floci-1 >/dev/null 2>&1; then
  running="$(docker inspect floci-ui-floci-1 \
    --format '{{.State.Running}}')"

  if [[ "$running" == "true" ]]; then
    ok "Floci container running"
  else
    fail "Floci container is stopped"
  fi
else
  fail "Floci container is missing"
fi

health="$(curl -fsS --connect-timeout 3 --max-time 8 \
  "$FLOCI_URL/_floci/health" 2>/dev/null || true)"

if [[ -n "$health" ]]; then
  eks_health="$(printf '%s' "$health" \
    | jq -r '.services.eks // "unknown"' 2>/dev/null)"

  if [[ "$eks_health" == "running" ]]; then
    ok "Floci EKS service running"
  else
    warn "Floci EKS service: ${eks_health:-unknown}"
  fi
else
  warn "Floci health endpoint unavailable"
fi

# Persistent volume and container attachment checks.
section "Kubernetes Persistent Storage"

for cluster in "${CLUSTERS[@]}"; do
  volume="floci-eks-$cluster"
  container="floci-eks-$cluster"

  if ! docker volume inspect "$volume" >/dev/null 2>&1; then
    fail "$cluster: persistent volume missing"
    continue
  fi

  created="$(docker volume inspect "$volume" \
    --format '{{.CreatedAt}}')"

  ok "$cluster: volume present (created $created)"

  if ! docker inspect "$container" >/dev/null 2>&1; then
    fail "$cluster: k3s container missing"
    continue
  fi

  mounted="$(docker inspect "$container" \
    --format '{{range .Mounts}}{{if eq .Destination "/var/lib/rancher/k3s"}}{{.Name}}{{end}}{{end}}')"

  if [[ "$mounted" == "$volume" ]]; then
    ok "$cluster: correct persistent volume attached"
  else
    fail "$cluster: unexpected k3s volume attachment"
  fi
done

# Kubernetes readiness is independent of Floci EKS status.
section "Kubernetes API and Nodes"

for cluster in "${CLUSTERS[@]}"; do
  api_ready["$cluster"]=0

  if [[ "$(kubectl --context "$cluster" \
    --request-timeout=8s get --raw=/readyz 2>/dev/null)" == "ok" ]]; then
    ok "$cluster: Kubernetes API ready"
    api_ready["$cluster"]=1
  else
    fail "$cluster: Kubernetes API unavailable or authentication failed"
    continue
  fi

  if kubectl --context "$cluster" --request-timeout=8s \
    get nodes -o json 2>/dev/null \
    | jq -e '(.items | length) > 0 and all(.items[]; any(.status.conditions[]?; .type == "Ready" and .status == "True"))' >/dev/null; then
    ok "$cluster: all Kubernetes nodes Ready"
  else
    fail "$cluster: one or more nodes not Ready"
  fi
done

# Floci EKS reporting is diagnostic, not the source of truth
# for Kubernetes API health.
section "Floci EKS Reporting"

if command -v aws >/dev/null 2>&1; then
  for cluster in "${CLUSTERS[@]}"; do
    status="$(aws \
      --endpoint-url "$FLOCI_URL" \
      --region us-east-1 \
      eks describe-cluster \
      --name "$cluster" \
      --query 'cluster.status' \
      --output text 2>/dev/null)" || status="UNKNOWN"

    case "$status" in
      ACTIVE)
        ok "$cluster: Floci EKS ACTIVE"
        ;;
      CREATING)
        warn "$cluster: Floci reports CREATING; Kubernetes checked separately"
        ;;
      *)
        warn "$cluster: Floci EKS status $status"
        ;;
    esac
  done
else
  warn "AWS CLI unavailable; EKS status checks skipped"
fi

# Expected environment resources.
section "GitOps Resources"

if [[ "${api_ready[devops-nonprod]:-0}" == "1" ]]; then
  for ns in dev uat; do
    if kubectl --context devops-nonprod --request-timeout=8s \
      get namespace "$ns" >/dev/null 2>&1; then
      ok "Nonprod namespace present: $ns"
    else
      fail "Nonprod namespace missing: $ns"
    fi
  done
else
  warn "Nonprod namespaces not checked; API unavailable"
fi

if [[ "${api_ready[devops-prod]:-0}" == "1" ]]; then
  if kubectl --context devops-prod --request-timeout=8s \
    get namespace prod >/dev/null 2>&1; then
    ok "Production namespace present: prod"
  else
    fail "Production namespace missing: prod"
  fi
else
  warn "Production namespace not checked; API unavailable"
fi

if [[ "${api_ready[devops-mgmt]:-0}" == "1" ]]; then
  if kubectl --context devops-mgmt --request-timeout=8s \
    get crd applications.argoproj.io >/dev/null 2>&1; then

    ok "Argo CD Application CRD present"

    if kubectl --context devops-mgmt --request-timeout=8s \
      -n argocd get deployment argocd-server >/dev/null 2>&1; then
      ok "Argo CD server Deployment present"
    else
      fail "Argo CD server Deployment missing"
    fi

    for app in devops-nonprod devops-prod devops-platform-apps; do
      if kubectl --context devops-mgmt --request-timeout=8s \
        -n argocd get application "$app" >/dev/null 2>&1; then
        ok "Argo CD Application present: $app"
      else
        fail "Argo CD Application missing: $app"
      fi
    done
  else
    fail "Argo CD Application CRD missing; bootstrap required"
  fi
else
  warn "Argo CD not checked; management API unavailable"
fi

section "Summary"

printf 'Warnings: %d\n' "$warnings"
printf 'Failures: %d\n' "$failures"

if (( failures > 0 )); then
  printf 'Result: RECOVERY REQUIRED\n'
  exit 2
elif (( warnings > 0 )); then
  printf 'Result: DEGRADED\n'
  exit 1
else
  printf 'Result: HEALTHY\n'
  exit 0
fi

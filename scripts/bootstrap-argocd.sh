#!/usr/bin/env bash

# Bootstrap Argo CD into the existing management cluster.
# Never create or replace Kubernetes clusters.

set -euo pipefail

CONTEXT="devops-mgmt"
NAMESPACE="argocd"
VERSION="v3.5.3"

MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${VERSION}/manifests/install.yaml"

stop() {
  printf '[STOP] %s\n' "$1" >&2
  exit 2
}

case "${1:-}" in
  --check|--apply)
    MODE="$1"
    ;;
  *)
    echo "Usage: $0 --check | --apply"
    exit 2
    ;;
esac

for tool in kubectl curl; do
  command -v "$tool" >/dev/null 2>&1 \
    || stop "Required tool missing: $tool"
done

echo "=== Argo CD Bootstrap ==="
echo "Context: $CONTEXT"
echo "Namespace: $NAMESPACE"
echo "Version: $VERSION"
echo "Mode: $MODE"

# Never rely on the operator's current kubectl context.
ready="$(kubectl --context "$CONTEXT" \
  --request-timeout=10s \
  get --raw=/readyz 2>/dev/null)" \
  || stop "Management Kubernetes API unavailable"

[[ "$ready" == "ok" ]] \
  || stop "Management Kubernetes API not ready"

echo "[OK] Management Kubernetes API ready"

# Prevent accidental installation over existing state.
if kubectl --context "$CONTEXT" \
  get namespace "$NAMESPACE" >/dev/null 2>&1; then
  namespace_exists=true
else
  namespace_exists=false
fi

if kubectl --context "$CONTEXT" \
  get crd applications.argoproj.io >/dev/null 2>&1; then
  crd_exists=true
else
  crd_exists=false
fi

echo "Argo CD namespace exists: $namespace_exists"
echo "Argo CD Application CRD exists: $crd_exists"

if [[ "$MODE" == "--check" ]]; then
  echo "[OK] Read-only bootstrap preflight completed"
  exit 0
fi

if [[ "$namespace_exists" == "true" || "$crd_exists" == "true" ]]; then
  stop "Existing or partial Argo CD installation detected; inspect before applying"
fi

# Download the pinned installation manifest before changing Kubernetes.
manifest="$(mktemp)"
trap 'rm -f -- "$manifest"' EXIT

curl --fail --location --silent --show-error \
  --retry 3 \
  --output "$manifest" \
  "$MANIFEST_URL" \
  || stop "Cannot download pinned Argo CD manifest"

grep -q '^kind: CustomResourceDefinition$' "$manifest" \
  || stop "Downloaded manifest failed validation"

echo "[OK] Argo CD installation manifest downloaded"

kubectl --context "$CONTEXT" \
  create namespace "$NAMESPACE"

kubectl --context "$CONTEXT" \
  -n "$NAMESPACE" \
  apply --server-side --force-conflicts \
  -f "$manifest"

echo "[INFO] Waiting for Argo CD server"

kubectl --context "$CONTEXT" \
  -n "$NAMESPACE" \
  rollout status deployment/argocd-server \
  --timeout=300s

echo "[OK] Argo CD server rollout completed"

kubectl --context "$CONTEXT" \
  -n "$NAMESPACE" \
  get deployments,statefulsets

echo "[OK] Bootstrap installation finished"

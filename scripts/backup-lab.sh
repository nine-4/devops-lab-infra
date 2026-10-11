#!/usr/bin/env bash

# Encrypted recovery checkpoint for the existing local DevOps lab.
# Does not stop, recreate, or modify infrastructure.

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
FLOCI_DIR="$HOME/tools/floci-ui"
BACKUP_DIR="$HOME/lab-backups"
BASELINE="${XDG_STATE_HOME:-$HOME/.local/state}/devops-platform-lab/volume-baseline.tsv"

stop() {
  printf '[STOP] %s\n' "$1" >&2
  exit 2
}

[[ "$#" -eq 1 ]] || stop "Usage: $0 WINDOWS_BACKUP_DIRECTORY"

MIRROR_DIR="$1"

for tool in docker sudo python3 tar gpg cmp sha256sum; do
  command -v "$tool" >/dev/null 2>&1 \
    || stop "Required tool missing: $tool"
done

[[ -d "$BACKUP_DIR" ]] || stop "Linux backup directory missing"
[[ -d "$MIRROR_DIR" ]] || stop "Windows backup directory missing"
[[ -w "$MIRROR_DIR" ]] || stop "Windows backup directory not writable"
[[ -f "$BASELINE" ]] || stop "Volume identity baseline missing"
[[ -f "$FLOCI_DIR/data/eks-clusters.json" ]] \
  || stop "Floci metadata missing"

for env in platform poc; do
  [[ -s "$INFRA_DIR/terraform/$env/terraform.tfstate" ]] \
    || stop "Terraform state missing: $env"
done

for file in docker-compose.yml docker-compose.local.yml; do
  [[ -f "$FLOCI_DIR/$file" ]] \
    || stop "Floci configuration missing: $file"
done

echo "=== DevOps Lab Recovery Backup ==="

"$SCRIPT_DIR/lab-volume-baseline.sh" --verify \
  || stop "Persistent-volume verification failed"

sudo -v || stop "Root access required for K3s snapshots"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
FILENAME="r1-restored-${STAMP}.tar.gz.gpg"
OUTPUT="$BACKUP_DIR/$FILENAME"
PART="$OUTPUT.part"
MIRROR_PART="$MIRROR_DIR/$FILENAME.part"
MIRROR_OUTPUT="$MIRROR_DIR/$FILENAME"

for file in "$OUTPUT" "$PART" "$MIRROR_PART" "$MIRROR_OUTPUT"; do
  [[ ! -e "$file" ]] || stop "Backup destination already exists: $file"
done

STAGE="$(mktemp -d "$BACKUP_DIR/.checkpoint-stage.XXXXXXXX")"

cleanup() {
  rm -f -- "$PART" "$MIRROR_PART"

  if [[ "${STAGE:-}" == "$BACKUP_DIR"/.checkpoint-stage.* &&
        -d "$STAGE" ]]; then
    sudo rm -rf -- "$STAGE"
  fi
}

trap cleanup EXIT

mkdir -p "$STAGE/k3s" "$STAGE/floci" "$STAGE/terraform"

cp "$BASELINE" "$STAGE/volume-baseline.tsv"

for env in platform poc; do
  mkdir -p "$STAGE/terraform/$env"

  cp "$INFRA_DIR/terraform/$env/terraform.tfstate" \
    "$STAGE/terraform/$env/"
done

echo "[INFO] Capturing Floci metadata and Compose configuration"

sudo cp -a "$FLOCI_DIR/data" "$STAGE/floci/"

sudo cp -a \
  "$FLOCI_DIR/docker-compose.yml" \
  "$FLOCI_DIR/docker-compose.local.yml" \
  "$STAGE/floci/"

for cluster in devops-mgmt devops-nonprod devops-prod; do
  echo "[INFO] Snapshotting $cluster"

  volume="floci-eks-$cluster"

  mountpoint="$(
    docker volume inspect "$volume" \
      --format '{{.Mountpoint}}'
  )" || stop "Cannot inspect $volume"

  [[ -n "$mountpoint" ]] || stop "Missing mountpoint for $volume"

  sudo test -s "$mountpoint/server/db/state.db" \
    || stop "$cluster: SQLite datastore missing"

  sudo test -f "$mountpoint/server/token" \
    || stop "$cluster: K3s server token missing"

  dest="$STAGE/k3s/$cluster"
  mkdir -p "$dest"

  docker volume inspect "$volume" > "$dest/volume-inspect.json"

  # SQLite online backup, safe to perform while K3s is running.
  sudo python3 - \
    "$mountpoint/server/db/state.db" \
    "$dest/state.db" <<'PY'
import sqlite3
import sys

source_path, destination_path = sys.argv[1:3]

source = sqlite3.connect(
    f"file:{source_path}?mode=ro",
    uri=True,
    timeout=30
)
destination = sqlite3.connect(destination_path)

try:
    source.backup(destination, pages=256, sleep=0.05)

    result = destination.execute(
        "PRAGMA integrity_check"
    ).fetchone()[0]

    if result != "ok":
        raise RuntimeError("SQLite integrity verification failed")
finally:
    destination.close()
    source.close()
PY

  # Preserve server certificates, credentials, and configuration.
  # The live database and its WAL files are intentionally excluded.
  sudo tar \
    -C "$mountpoint" \
    --exclude='server/db' \
    -cf "$dest/server-files.tar" \
    server

  echo "[OK] $cluster snapshot captured"
done

{
  echo "Snapshot UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Infrastructure Git commit:"
  git -C "$INFRA_DIR" rev-parse HEAD
  echo "GitOps Git commit:"
  git -C "$HOME/projects/devops-platform-lab/devops-lab-gitops" \
    rev-parse HEAD
} > "$STAGE/checkpoint-info.txt"

# Include recovery work not yet merged into Git.
mkdir -p "$STAGE/recovery-tooling"

for file in \
  "$INFRA_DIR/scripts/bootstrap-argocd.sh" \
  "$INFRA_DIR/kubernetes/recovery/coredns-github-temporary.yaml"; do
  if [[ -f "$file" ]]; then
    cp "$file" "$STAGE/recovery-tooling/"
  fi
done

echo "[INFO] Encrypting recovery checkpoint"
echo "[INFO] GPG will prompt for an encryption passphrase"

if tty -s; then
  export GPG_TTY="$(tty)"
fi

# Stream into GPG; do not create a plaintext combined tarball.
sudo tar -C "$STAGE" -czf - . |
  gpg --symmetric \
    --cipher-algo AES256 \
    --no-symkey-cache \
    --output "$PART"

echo "[INFO] Verifying encrypted archive"

# Validate both GPG decryption and the compressed tar structure.
gpg --decrypt --quiet "$PART" |
  tar -tzf - >/dev/null

mv -- "$PART" "$OUTPUT"

echo "[INFO] Copying encrypted checkpoint to Windows"

cp -- "$OUTPUT" "$MIRROR_PART"

cmp -s "$OUTPUT" "$MIRROR_PART" \
  || stop "Windows copy failed verification"

mv -- "$MIRROR_PART" "$MIRROR_OUTPUT"

echo
echo "[OK] Encrypted recovery checkpoint created"
echo "Linux: $OUTPUT"
echo "Windows: $MIRROR_OUTPUT"

sha256sum "$OUTPUT" "$MIRROR_OUTPUT"

echo "[OK] Both encrypted copies match"

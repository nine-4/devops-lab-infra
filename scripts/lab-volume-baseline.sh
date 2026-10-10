#!/usr/bin/env bash

# Verify local Kubernetes volume identities before starting the lab.
# Baseline creation is explicit; verification is read-only.

set -euo pipefail
umask 077

CLUSTERS=(devops-mgmt devops-nonprod devops-prod)

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/devops-platform-lab"
BASELINE="$STATE_DIR/volume-baseline.tsv"

stop() {
  printf '[STOP] %s\n' "$1" >&2
  exit 2
}

snapshot() {
  local cluster="$1"
  local volume="floci-eks-$cluster"
  local container="floci-eks-$cluster"
  local created mounted

  created="$(docker volume inspect \
    --format '{{.CreatedAt}}' "$volume" 2>/dev/null)" \
    || stop "$cluster: named volume missing"

  [[ -n "$created" ]] \
    || stop "$cluster: volume creation time unavailable"

  docker container inspect "$container" >/dev/null 2>&1 \
    || stop "$cluster: k3s container missing"

  mounted="$(docker container inspect \
    --format '{{range .Mounts}}{{if eq .Destination "/var/lib/rancher/k3s"}}{{.Name}}{{end}}{{end}}' \
    "$container")" \
    || stop "$cluster: cannot inspect container mounts"

  [[ "$mounted" == "$volume" ]] \
    || stop "$cluster: unexpected k3s volume attachment"

  printf '%s\t%s\n' "$volume" "$created"
}

command -v docker >/dev/null 2>&1 \
  || stop "Docker CLI unavailable"

docker info >/dev/null 2>&1 \
  || stop "Docker Engine unavailable"

case "${1:-}" in
  --init)
    [[ ! -e "$BASELINE" ]] \
      || stop "Baseline already exists; refusing to overwrite"

    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"

    temp_file="$(mktemp "$STATE_DIR/.volumes.XXXXXX")"
    trap 'rm -f -- "$temp_file"' EXIT

    for cluster in "${CLUSTERS[@]}"; do
      snapshot "$cluster" >> "$temp_file"
    done

    ln "$temp_file" "$BASELINE" \
      || stop "Could not create baseline"

    chmod 600 "$BASELINE"

    printf '[OK] Volume baseline initialized\n'
    printf 'Location: %s\n' "$BASELINE"
    ;;

  --verify)
    [[ -f "$BASELINE" ]] \
      || stop "Baseline missing; automatic initialization forbidden"

    declare -A expected=()

    while IFS=$'\t' read -r name created extra; do
      [[ -n "$name" && -n "$created" && -z "${extra:-}" ]] \
        || stop "Malformed baseline entry"

      [[ -z "${expected[$name]+x}" ]] \
        || stop "Duplicate baseline entry: $name"

      expected["$name"]="$created"
    done < "$BASELINE"

    [[ "${#expected[@]}" -eq "${#CLUSTERS[@]}" ]] \
      || stop "Unexpected baseline entry count"

    for cluster in "${CLUSTERS[@]}"; do
      volume="floci-eks-$cluster"

      observed="$(snapshot "$cluster")"
      created="${observed#*$'\t'}"

      [[ -n "${expected[$volume]+x}" ]] \
        || stop "$cluster: missing baseline identity"

      [[ "$created" == "${expected[$volume]}" ]] \
        || stop "$cluster: VOLUME IDENTITY CHANGED"

      printf '[OK] %s identity verified (%s)\n' \
        "$cluster" "$created"
    done

    printf '[OK] All expected volumes verified\n'
    ;;

  *)
    printf 'Usage: %s --init | --verify\n' "$0" >&2
    exit 2
    ;;
esac

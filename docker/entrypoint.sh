#!/bin/bash
# GT Mesh Docker Entrypoint
# Modes: sync-loop, init, join, oneshot, shell

set -e

GT_ROOT="${GT_ROOT:-/home/gt/gt}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"
SYNC_INTERVAL="${SYNC_INTERVAL:-120}"

export GT_ROOT MESH_YAML

# Initialize dolt credentials if not mounted
if [ ! -d "$HOME/.dolt" ]; then
  if [ -n "$DOLT_CREDS_PUB" ] && [ -n "$DOLT_CREDS_PRIV" ]; then
    mkdir -p "$HOME/.dolt/creds"
    echo "$DOLT_CREDS_PRIV" > "$HOME/.dolt/creds/${DOLT_CREDS_PUB}.jwk"
    dolt creds use "$DOLT_CREDS_PUB" 2>/dev/null || true
  else
    dolt creds new 2>/dev/null || true
  fi
fi

# Configure git identity for dolt
if [ -n "$GT_OWNER_NAME" ]; then
  dolt config --global --add user.name "$GT_OWNER_NAME" 2>/dev/null || true
fi
if [ -n "$GT_OWNER_EMAIL" ]; then
  dolt config --global --add user.email "$GT_OWNER_EMAIL" 2>/dev/null || true
fi

case "${1:-sync-loop}" in
  init)
    shift
    bash "$GT_ROOT/.gt-mesh/scripts/mesh.sh" init "$@"
    ;;

  join)
    shift
    bash "$GT_ROOT/.gt-mesh/scripts/mesh.sh" join "$@"
    ;;

  sync-loop)
    echo "[docker] Starting mesh sync loop (interval: ${SYNC_INTERVAL}s)"

    # Run init if mesh.yaml doesn't exist and env vars are set
    if [ ! -f "$MESH_YAML" ] && [ -n "$MESH_INVITE_CODE" ]; then
      echo "[docker] Auto-joining mesh with invite $MESH_INVITE_CODE..."
      bash "$GT_ROOT/.gt-mesh/scripts/mesh.sh" join "$MESH_INVITE_CODE" \
        --github "${GT_OWNER_GITHUB:-unknown}" \
        --name "${GT_NAME:-gt-docker-$(hostname -s)}" || true
    elif [ ! -f "$MESH_YAML" ] && [ -n "$GT_NAME" ]; then
      echo "[docker] Auto-initializing mesh..."
      bash "$GT_ROOT/.gt-mesh/scripts/mesh.sh" init \
        --github "${GT_OWNER_GITHUB:-unknown}" \
        --name "$GT_NAME" || true
    fi

    if [ ! -f "$MESH_YAML" ]; then
      echo "[error] No mesh.yaml found. Provide MESH_INVITE_CODE or GT_NAME env vars."
      exit 1
    fi

    # Sync loop
    while true; do
      bash "$GT_ROOT/.gt-mesh/scripts/mesh-sync.sh" 2>&1 || echo "[warn] Sync cycle failed"

      # Auto-sync config if enabled
      if [ "${AUTO_SYNC_CONFIG:-true}" = "true" ]; then
        bash "$GT_ROOT/.gt-mesh/scripts/mesh-config.sh" pull --quiet 2>/dev/null || true
      fi

      sleep "$SYNC_INTERVAL"
    done
    ;;

  oneshot)
    shift
    bash "$GT_ROOT/.gt-mesh/scripts/mesh-sync.sh" 2>&1
    ;;

  shell)
    exec /bin/bash
    ;;

  *)
    # Pass through to mesh CLI
    bash "$GT_ROOT/.gt-mesh/scripts/mesh.sh" "$@"
    ;;
esac

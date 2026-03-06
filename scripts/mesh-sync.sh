#!/bin/bash
# GT Mesh — Force sync with DoltHub
#
# Usage: mesh-sync.sh

set -e

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"

if [ ! -f "$MESH_YAML" ]; then
  echo "[error] Not in a mesh. Run: gt mesh init"
  exit 1
fi

GT_ID=$(grep "^  id:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR=$(grep "clone_dir:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"
DOLTHUB_DB="deepwork/gt-agent-mail"

echo "[sync] Starting mesh sync for $GT_ID..."

# Ensure clone exists
if [ ! -d "$CLONE_DIR" ]; then
  echo "[sync] Cloning $DOLTHUB_DB..."
  dolt clone "$DOLTHUB_DB" "$CLONE_DIR" 2>&1
fi

cd "$CLONE_DIR"

# Pull
echo "[sync] Pulling from DoltHub..."
dolt pull 2>/dev/null || echo "[warn] Pull had issues, continuing..."

# Update heartbeat
dolt sql -q "UPDATE peers SET last_seen = NOW() WHERE gt_id = '$GT_ID';" 2>/dev/null || true

# Commit and push any local changes
dolt add . 2>/dev/null
if dolt diff --stat 2>/dev/null | grep -q "rows"; then
  dolt commit -m "mesh: sync from $GT_ID" --allow-empty 2>/dev/null
fi
dolt push 2>/dev/null || echo "[warn] Push deferred"

# Count stats
UNREAD=$(dolt sql -q "SELECT COUNT(*) FROM messages WHERE to_gt = '$GT_ID' AND read_at IS NULL;" -r csv 2>/dev/null | tail -n +2 | head -1)
PEERS=$(dolt sql -q "SELECT COUNT(*) FROM peers WHERE status = 'active';" -r csv 2>/dev/null | tail -n +2 | head -1)

cd "$GT_ROOT"

echo "[sync] Done. Unread: ${UNREAD:-0} | Active peers: ${PEERS:-0}"

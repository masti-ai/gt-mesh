#!/bin/bash
# GT Mesh — Force sync with DoltHub
#
# Usage: mesh-sync.sh

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

# Commit any uncommitted local changes BEFORE pulling (prevents "cannot merge with uncommitted changes")
dolt add . 2>/dev/null
if dolt diff --staged --stat 2>/dev/null | grep -qi "row"; then
  dolt commit -m "mesh: pre-sync commit from $GT_ID" --allow-empty 2>/dev/null || true
fi

# Pull
echo "[sync] Pulling from DoltHub..."
dolt pull 2>/dev/null || echo "[warn] Pull had issues, continuing..."

# Update heartbeat
dolt sql -q "UPDATE peers SET last_seen = NOW() WHERE gt_id = '$GT_ID';" 2>/dev/null || true

# Commit and push
dolt add . 2>/dev/null
if dolt diff --staged --stat 2>/dev/null | grep -qi "row"; then
  dolt commit -m "mesh: sync from $GT_ID" --allow-empty 2>/dev/null
fi
dolt push 2>/dev/null || echo "[warn] Push deferred"

# Count stats
UNREAD=$(dolt sql -q "SELECT COUNT(*) FROM messages WHERE to_gt = '$GT_ID' AND read_at IS NULL;" -r csv 2>/dev/null | tail -n +2 | head -1)
PEERS=$(dolt sql -q "SELECT COUNT(*) FROM peers WHERE status = 'active';" -r csv 2>/dev/null | tail -n +2 | head -1)

cd "$GT_ROOT"

# Check for config updates
MESH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_CACHE="$GT_ROOT/.mesh-config"
LOCAL_HASH=""
[ -f "$CONFIG_CACHE/version" ] && LOCAL_HASH=$(cat "$CONFIG_CACHE/version")
REMOTE_HASH=$(cd "$CLONE_DIR" && dolt sql -q "SELECT config_hash FROM mesh_config LIMIT 1;" -r csv 2>/dev/null | tail -n +2 | head -1)
if [ -n "$REMOTE_HASH" ] && [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
  echo "[sync] Config updated — pulling..."
  GT_ROOT="$GT_ROOT" MESH_YAML="$MESH_YAML" bash "$MESH_DIR/scripts/mesh-config.sh" pull --quiet 2>/dev/null
fi

# Pull new knowledge entries
KNOWLEDGE_DIR="$GT_ROOT/.mesh-config/knowledge"
LEARNINGS="$KNOWLEDGE_DIR/mesh-learnings.md"
LAST_KNOWLEDGE_SYNC=""
[ -f "$KNOWLEDGE_DIR/.last-sync" ] && LAST_KNOWLEDGE_SYNC=$(cat "$KNOWLEDGE_DIR/.last-sync")
NEW_KNOWLEDGE=$(cd "$CLONE_DIR" && dolt sql -q "SELECT COUNT(*) FROM mesh_knowledge_entries WHERE updated_at > '${LAST_KNOWLEDGE_SYNC:-1970-01-01}';" -r csv 2>/dev/null | tail -n +2 | head -1)
if [ "${NEW_KNOWLEDGE:-0}" -gt 0 ] 2>/dev/null; then
  echo "[sync] $NEW_KNOWLEDGE new knowledge entries — pulling..."
  mkdir -p "$KNOWLEDGE_DIR"
  # Pull entries, dedup by checking if title already exists in file
  cd "$CLONE_DIR"
  ENTRIES=$(dolt sql -q "SELECT CONCAT(title, '|||', content) FROM mesh_knowledge_entries WHERE updated_at > '${LAST_KNOWLEDGE_SYNC:-1970-01-01}' ORDER BY created_at;" -r csv 2>/dev/null | tail -n +2 | sed 's/^"//;s/"$//' | sed 's/""/"/g')
  while IFS='|||' read -r ktitle kcontent; do
    [ -z "$ktitle" ] && continue
    # Skip if already in file
    if [ -f "$LEARNINGS" ] && grep -qF "$ktitle" "$LEARNINGS" 2>/dev/null; then
      continue
    fi
    echo "" >> "$LEARNINGS"
    echo "### $ktitle" >> "$LEARNINGS"
    echo "$kcontent" | sed 's/\\n/\n/g' >> "$LEARNINGS"
    echo "" >> "$LEARNINGS"
  done <<< "$ENTRIES"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$KNOWLEDGE_DIR/.last-sync"
  cd "$GT_ROOT"
fi

# Handle incoming mail (route P0/P1 to mayor, auto-reply to pings)
MESH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ "${UNREAD:-0}" -gt 0 ] 2>/dev/null; then
  bash "$MESH_DIR/scripts/mesh-mail-handler.sh" --auto-reply 2>/dev/null || true
fi

# Log sync activity to auto-sync (lightweight — no broadcast, just local+dolt log)
MESH_DIR_SYNC="$(cd "$(dirname "$0")/.." && pwd)"
GT_ROOT="$GT_ROOT" MESH_YAML="$MESH_YAML" bash "$MESH_DIR_SYNC/scripts/mesh-auto-sync.sh" log "sync completed: unread=${UNREAD:-0} peers=${PEERS:-0}" 2>/dev/null || true

# Run self-improving loop review (check for new improvements to graduate)
GT_ROOT="$GT_ROOT" MESH_YAML="$MESH_YAML" bash "$MESH_DIR_SYNC/scripts/mesh-improve.sh" review 2>/dev/null | head -5 || true

echo "[sync] Done. Unread: ${UNREAD:-0} | Active peers: ${PEERS:-0}"

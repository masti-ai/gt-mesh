#!/bin/bash
# GT Mesh Pack Auto-Updater
# Runs every 2 hours via cron. Detects changes to mesh config/learnings
# and publishes updated pack to DoltHub for all agents to pull.
#
# Cron: 0 */2 * * * bash /home/pratham2/gt/.gt-mesh/scripts/mesh-pack-updater.sh

GT_ROOT="/home/pratham2/gt"
CLONE_DIR="/tmp/mesh-sync-clone"
LOG="/tmp/mesh-pack-updater.log"
HASH_FILE="/tmp/mesh-pack-last-hash"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%S) $1" >> "$LOG"; }

log "=== Pack update check ==="

# Files that constitute the "mesh pack"
PACK_FILES=(
  "$GT_ROOT/CLAUDE.md"
  "$GT_ROOT/mesh.yaml"
  "$GT_ROOT/.gt-mesh/backlog.jsonl"
)

# Compute hash of all pack files
CURRENT_HASH=""
for f in "${PACK_FILES[@]}"; do
  if [ -f "$f" ]; then
    CURRENT_HASH="${CURRENT_HASH}$(md5sum "$f" 2>/dev/null | cut -d' ' -f1)"
  fi
done
CURRENT_HASH=$(echo "$CURRENT_HASH" | md5sum | cut -d' ' -f1)

# Compare with last known hash
LAST_HASH=$(cat "$HASH_FILE" 2>/dev/null || echo "none")

if [ "$CURRENT_HASH" = "$LAST_HASH" ]; then
  log "No changes detected"
  exit 0
fi

log "Changes detected (old=$LAST_HASH new=$CURRENT_HASH)"

# Push updated config to DoltHub
cd "$CLONE_DIR" 2>/dev/null || exit 1

# Update mesh_config table with latest pack content
CLAUDE_MD_B64=$(base64 -w0 "$GT_ROOT/CLAUDE.md" 2>/dev/null || echo "")
MESH_YAML_B64=$(base64 -w0 "$GT_ROOT/mesh.yaml" 2>/dev/null || echo "")

dolt sql -q "REPLACE INTO mesh_config (\`key\`, repos, updated_at) VALUES ('pack_hash', '$CURRENT_HASH', NOW());" 2>/dev/null

# Notify all agents about the update
dolt sql -q "INSERT INTO messages (id, from_gt, from_addr, to_gt, to_addr, subject, body, priority, created_at) VALUES ('msg-pack-$(date +%s)', 'gt-local', 'mayor/', 'all', 'broadcast/', 'MESH PACK UPDATED', 'Mesh configuration updated. Pull latest config on next sync cycle. Hash: $CURRENT_HASH', 2, NOW());" 2>/dev/null

dolt add . 2>/dev/null && dolt commit -m "mesh: pack updated ($CURRENT_HASH)" --allow-empty 2>/dev/null && dolt push 2>/dev/null

# Save new hash
echo "$CURRENT_HASH" > "$HASH_FILE"

log "Pack published to DoltHub"
log "=== Pack update complete ==="

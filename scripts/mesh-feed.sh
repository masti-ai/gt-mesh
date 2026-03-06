#!/bin/bash
# GT Mesh — Activity feed
#
# Usage: mesh-feed.sh [--since 1h] [--gt <id>] [--limit N]

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"

if [ ! -f "$MESH_YAML" ]; then
  echo "[error] Not in a mesh. Run: gt mesh init"
  exit 1
fi

GT_ID=$(grep "^  id:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR=$(grep "clone_dir:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"

SINCE=""
FILTER_GT=""
LIMIT=20

while [[ $# -gt 0 ]]; do
  case $1 in
    --since) SINCE="$2"; shift 2 ;;
    --gt) FILTER_GT="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

cd "$CLONE_DIR"
dolt pull 2>/dev/null || true

echo "==========================================="
echo "  Mesh Feed"
echo "==========================================="
echo ""

# Build feed from multiple sources: messages, peers, invites
# Recent messages (cross-GT activity)
WHERE="1=1"
if [ -n "$SINCE" ]; then
  case "$SINCE" in
    *h) HOURS="${SINCE%h}"; WHERE="$WHERE AND created_at > DATE_SUB(NOW(), INTERVAL $HOURS HOUR)" ;;
    *d) DAYS="${SINCE%d}"; WHERE="$WHERE AND created_at > DATE_SUB(NOW(), INTERVAL $DAYS DAY)" ;;
  esac
fi
if [ -n "$FILTER_GT" ]; then
  WHERE="$WHERE AND (from_gt = '$FILTER_GT' OR to_gt = '$FILTER_GT')"
fi

MESSAGES=$(dolt sql -q "SELECT CAST(created_at AS CHAR) as ts, from_gt, to_gt, subject FROM messages WHERE $WHERE ORDER BY created_at DESC LIMIT $LIMIT;" -r csv 2>/dev/null | tail -n +2)

if [ -n "$MESSAGES" ]; then
  while IFS= read -r line; do
    ts=$(echo "$line" | cut -d',' -f1)
    from=$(echo "$line" | cut -d',' -f2)
    to=$(echo "$line" | cut -d',' -f3)
    subj=$(echo "$line" | cut -d',' -f4-)
    # Trim time to HH:MM
    time_short=$(echo "$ts" | sed 's/.*\([0-9][0-9]:[0-9][0-9]\).*/\1/')
    echo "  [$time_short] $from → $to: $subj"
  done <<< "$MESSAGES"
else
  echo "  (no recent activity)"
fi

echo ""

# Show peer status
echo "  Peers online:"
PEERS=$(dolt sql -q "SELECT gt_id, role, CAST(last_seen AS CHAR) as ls FROM peers WHERE status = 'active' ORDER BY last_seen DESC;" -r csv 2>/dev/null | tail -n +2)
while IFS=',' read -r id role ls; do
  [ -z "$id" ] && continue
  echo "    $id ($role) — last seen $ls"
done <<< "$PEERS"
echo ""

cd "$GT_ROOT"

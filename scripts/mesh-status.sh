#!/bin/bash
# GT Mesh — Status dashboard
#
# Usage: mesh-status.sh [--peers]

set -e

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"

if [ ! -f "$MESH_YAML" ]; then
  echo "[error] Not in a mesh. Run: gt mesh init"
  exit 1
fi

# Parse mesh.yaml (basic — no yq dependency)
GT_ID=$(grep "^  id:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
ROLE=$(grep "^  role:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR=$(grep "clone_dir:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"

SHOW_PEERS=false
if [[ "$1" == "--peers" ]]; then
  SHOW_PEERS=true
fi

echo "==========================================="
echo "  GT Mesh Status"
echo "==========================================="
echo ""
echo "  Instance:  $GT_ID"
echo "  Role:      $ROLE"
echo "  Config:    $MESH_YAML"
echo "  Sync dir:  $CLONE_DIR"
echo ""

# Check DoltHub connectivity
if [ -d "$CLONE_DIR" ]; then
  echo "  DoltHub:   connected"
  LAST_SYNC=$(cd "$CLONE_DIR" && dolt log -n 1 --oneline 2>/dev/null | head -1 || echo "unknown")
  echo "  Last sync: $LAST_SYNC"
else
  echo "  DoltHub:   NOT CONNECTED (run gt mesh sync)"
fi
echo ""

# Show peers
if [ "$SHOW_PEERS" = true ] || [ -d "$CLONE_DIR" ]; then
  echo "  Peers:"
  if [ -d "$CLONE_DIR" ]; then
    cd "$CLONE_DIR"
    PEERS=$(dolt sql -q "SELECT gt_id, role, status, last_seen FROM peers ORDER BY last_seen DESC;" -r csv 2>/dev/null | tail -n +2)
    if [ -n "$PEERS" ]; then
      echo "  ┌──────────────────┬──────────────┬────────┬─────────────────────┐"
      printf "  │ %-16s │ %-12s │ %-6s │ %-19s │\n" "GT ID" "Role" "Status" "Last Seen"
      echo "  ├──────────────────┼──────────────┼────────┼─────────────────────┤"
      while IFS=',' read -r id role status last_seen; do
        [ -z "$id" ] && continue
        printf "  │ %-16s │ %-12s │ %-6s │ %-19s │\n" "$id" "$role" "$status" "$last_seen"
      done <<< "$PEERS"
      echo "  └──────────────────┴──────────────┴────────┴─────────────────────┘"
    else
      echo "    (no peers registered)"
    fi
    cd "$GT_ROOT"
  fi
fi

echo ""

# Show unread messages count
if [ -d "$CLONE_DIR" ]; then
  cd "$CLONE_DIR"
  UNREAD=$(dolt sql -q "SELECT COUNT(*) as c FROM messages WHERE to_gt = '$GT_ID' AND read_at IS NULL;" -r csv 2>/dev/null | tail -1)
  echo "  Unread messages: ${UNREAD:-0}"
  cd "$GT_ROOT"
fi
echo ""

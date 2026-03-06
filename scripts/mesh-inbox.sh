#!/bin/bash
# GT Mesh — Check mesh inbox
#
# Usage: mesh-inbox.sh [--unread] [--all]

set -e

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"

if [ ! -f "$MESH_YAML" ]; then
  echo "[error] Not in a mesh. Run: gt mesh init"
  exit 1
fi

FILTER="unread"
if [[ "$1" == "--all" ]]; then
  FILTER="all"
fi

GT_ID=$(grep "^  id:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR=$(grep "clone_dir:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"

if [ ! -d "$CLONE_DIR" ]; then
  echo "[error] Sync clone not found. Run: gt mesh sync"
  exit 1
fi

cd "$CLONE_DIR"
dolt pull 2>/dev/null || true

if [ "$FILTER" = "unread" ]; then
  WHERE="to_gt = '$GT_ID' AND read_at IS NULL"
else
  WHERE="to_gt = '$GT_ID'"
fi

echo "==========================================="
echo "  Mesh Inbox: $GT_ID ($FILTER)"
echo "==========================================="
echo ""

MSG_IDS=$(dolt sql -q "SELECT id FROM messages WHERE $WHERE ORDER BY created_at DESC LIMIT 20;" -r csv 2>/dev/null | tail -n +2)

if [ -z "$MSG_IDS" ]; then
  echo "  (no messages)"
  cd "$GT_ROOT"
  exit 0
fi

COUNT=0
while IFS= read -r msg_id; do
  [ -z "$msg_id" ] && continue
  COUNT=$((COUNT + 1))

  from_gt=$(dolt sql -q "SELECT from_gt FROM messages WHERE id = '$msg_id';" -r csv 2>/dev/null | tail -n +2 | head -1)
  subject=$(dolt sql -q "SELECT subject FROM messages WHERE id = '$msg_id';" -r csv 2>/dev/null | tail -n +2 | head -1)
  created=$(dolt sql -q "SELECT created_at FROM messages WHERE id = '$msg_id';" -r csv 2>/dev/null | tail -n +2 | head -1)
  priority=$(dolt sql -q "SELECT priority FROM messages WHERE id = '$msg_id';" -r csv 2>/dev/null | tail -n +2 | head -1)

  PRI_LABEL="P${priority}"
  case "$priority" in
    0) PRI_LABEL="P0!" ;;
    1) PRI_LABEL="P1" ;;
    2) PRI_LABEL="P2" ;;
    3) PRI_LABEL="P3" ;;
  esac

  echo "  $COUNT. [$PRI_LABEL] From: $from_gt"
  echo "     Subject: $subject"
  echo "     Date: $created"
  echo "     ID: $msg_id"
  echo ""
done <<< "$MSG_IDS"

echo "  Total: $COUNT message(s)"
echo ""
echo "  To read a message body:"
echo "    cd $CLONE_DIR && dolt sql -q \"SELECT body FROM messages WHERE id = '<msg-id>';\" -r csv"
cd "$GT_ROOT"

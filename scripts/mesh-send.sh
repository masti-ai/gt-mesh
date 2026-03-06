#!/bin/bash
# GT Mesh — Send a message to another GT
#
# Usage: mesh-send.sh <to_gt> <subject> <body> [priority]

set -e

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"

if [ ! -f "$MESH_YAML" ]; then
  echo "[error] Not in a mesh. Run: gt mesh init"
  exit 1
fi

TO_GT="$1"
SUBJECT="$2"
BODY="$3"
PRIORITY="${4:-2}"

if [ -z "$TO_GT" ] || [ -z "$SUBJECT" ]; then
  echo "Usage: gt mesh send <to_gt> <subject> <body> [priority]"
  echo ""
  echo "Priority: 0=critical, 1=high, 2=normal (default), 3=low"
  exit 1
fi

# Read identity from mesh.yaml
GT_ID=$(grep "^  id:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR=$(grep "clone_dir:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"

if [ ! -d "$CLONE_DIR" ]; then
  echo "[error] Sync clone not found at $CLONE_DIR. Run: gt mesh sync"
  exit 1
fi

MSG_ID="msg-$(date +%s)-$(head -c4 /dev/urandom | xxd -p)"

cd "$CLONE_DIR"
dolt pull 2>/dev/null || true

# Escape single quotes in body for SQL
BODY_ESC=$(echo "$BODY" | sed "s/'/''/g")
SUBJECT_ESC=$(echo "$SUBJECT" | sed "s/'/''/g")

dolt sql -q "INSERT INTO messages (id, from_gt, from_addr, to_gt, to_addr, subject, body, priority, created_at) VALUES ('$MSG_ID', '$GT_ID', 'mayor/', '$TO_GT', 'mayor/', '$SUBJECT_ESC', '$BODY_ESC', $PRIORITY, NOW());" 2>/dev/null

dolt add . 2>/dev/null
dolt commit -m "mesh: $GT_ID -> $TO_GT: $SUBJECT_ESC" --allow-empty 2>/dev/null
dolt push 2>/dev/null || echo "[warn] Push deferred — will sync on next cycle"

cd "$GT_ROOT"
echo "Sent to $TO_GT: $SUBJECT (id: $MSG_ID)"

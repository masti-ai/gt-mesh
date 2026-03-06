#!/bin/bash
# GT Mesh — Access control management
#
# Usage: mesh-access.sh list | set <gt-id> --role <role> | revoke <gt-id>

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"

if [ ! -f "$MESH_YAML" ]; then
  echo "[error] Not in a mesh. Run: gt mesh init"
  exit 1
fi

GT_ID=$(grep "^  id:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR=$(grep "clone_dir:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"

SUBCMD="${1:-list}"
shift 2>/dev/null || true

case "$SUBCMD" in
  list)
    cd "$CLONE_DIR"
    dolt pull 2>/dev/null || true
    echo "==========================================="
    echo "  Mesh Access — Peers & Roles"
    echo "==========================================="
    echo ""
    PEERS=$(dolt sql -q "SELECT gt_id, role, status, COALESCE(invited_by, '-') as invited_by, COALESCE(CAST(last_seen AS CHAR), '-') as last_seen FROM peers WHERE status = 'active' ORDER BY role, gt_id;" -r csv 2>/dev/null | tail -n +2)
    if [ -n "$PEERS" ]; then
      printf "  %-16s %-14s %-8s %-14s %s\n" "GT ID" "Role" "Status" "Invited By" "Last Seen"
      echo "  ────────────── ──────────── ────── ──────────── ───────────────────"
      while IFS=',' read -r id role status invited last; do
        [ -z "$id" ] && continue
        printf "  %-16s %-14s %-8s %-14s %s\n" "$id" "$role" "$status" "$invited" "$last"
      done <<< "$PEERS"
    else
      echo "  (no active peers)"
    fi
    echo ""

    # Show pending invites
    INVITES=$(dolt sql -q "SELECT code, role, COALESCE(CAST(expires_at AS CHAR), 'never') as expires FROM invites WHERE status = 'active';" -r csv 2>/dev/null | tail -n +2)
    if [ -n "$INVITES" ]; then
      echo "  Pending Invites:"
      printf "  %-18s %-10s %s\n" "Code" "Role" "Expires"
      echo "  ──────────────── ──────── ───────────────────"
      while IFS=',' read -r code role expires; do
        [ -z "$code" ] && continue
        printf "  %-18s %-10s %s\n" "$code" "$role" "$expires"
      done <<< "$INVITES"
      echo ""
    fi
    cd "$GT_ROOT"
    ;;

  set)
    TARGET="$1"
    shift
    NEW_ROLE=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --role) NEW_ROLE="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    if [ -z "$TARGET" ] || [ -z "$NEW_ROLE" ]; then
      echo "Usage: gt mesh access set <gt-id> --role <planner|worker|reviewer>"
      exit 1
    fi
    cd "$CLONE_DIR"
    dolt pull 2>/dev/null || true
    dolt sql -q "UPDATE peers SET role = '$NEW_ROLE' WHERE gt_id = '$TARGET';" 2>/dev/null
    dolt add . 2>/dev/null || true
    dolt commit -m "mesh: $GT_ID changed $TARGET role to $NEW_ROLE" --allow-empty 2>/dev/null || true
    dolt push 2>/dev/null || true
    cd "$GT_ROOT"
    echo "Updated $TARGET → role: $NEW_ROLE"
    ;;

  revoke)
    TARGET="$1"
    if [ -z "$TARGET" ]; then
      echo "Usage: gt mesh access revoke <gt-id>"
      exit 1
    fi
    cd "$CLONE_DIR"
    dolt pull 2>/dev/null || true
    dolt sql -q "UPDATE peers SET status = 'revoked' WHERE gt_id = '$TARGET';" 2>/dev/null
    dolt add . 2>/dev/null || true
    dolt commit -m "mesh: $GT_ID revoked access for $TARGET" --allow-empty 2>/dev/null || true
    dolt push 2>/dev/null || true
    cd "$GT_ROOT"
    echo "Revoked access for $TARGET"
    ;;

  *)
    echo "Usage: gt mesh access <list|set|revoke>"
    echo ""
    echo "  list                          Show all peers and roles"
    echo "  set <gt-id> --role <role>     Change a peer's role"
    echo "  revoke <gt-id>                Revoke a peer's access"
    exit 1
    ;;
esac

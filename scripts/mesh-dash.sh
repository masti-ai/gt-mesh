#!/bin/bash
# GT Mesh — Dashboard CLI
#
# Usage: mesh-dash.sh [--refresh N] [--compact]
#
# One-screen overview of the entire mesh: identity, peers, work, messages, rules.

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"

if [ ! -f "$MESH_YAML" ]; then
  echo "[error] Not in a mesh. Run: gt mesh init"
  exit 1
fi

# Parse mesh.yaml
_yaml_val() { grep "$1" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/'; }

GT_ID=$(_yaml_val "^  id:")
GT_ROLE=$(_yaml_val "^  role:")
GT_GITHUB=$(_yaml_val "github:")
BEHAVIORAL=$(_yaml_val "this_gt:" | awk '{print $1}' | tr -d '"')
CLONE_DIR=$(_yaml_val "clone_dir:")
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"

# Parse args
REFRESH=0
COMPACT=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --refresh) REFRESH="$2"; shift 2 ;;
    --compact) COMPACT=true; shift ;;
    *) shift ;;
  esac
done

_render() {
  # Pull latest data
  cd "$CLONE_DIR" 2>/dev/null || { echo "[error] Sync dir missing: $CLONE_DIR"; exit 1; }
  dolt pull 2>/dev/null || true

  # Gather data
  PEER_COUNT=$(dolt sql -q "SELECT COUNT(*) FROM peers WHERE status = 'active';" -r csv 2>/dev/null | tail -n +2 | head -1)
  UNREAD=$(dolt sql -q "SELECT COUNT(*) FROM messages WHERE to_gt = '$GT_ID' AND read_at IS NULL;" -r csv 2>/dev/null | tail -n +2 | head -1)
  TOTAL_MSGS=$(dolt sql -q "SELECT COUNT(*) FROM messages WHERE to_gt = '$GT_ID' OR from_gt = '$GT_ID';" -r csv 2>/dev/null | tail -n +2 | head -1)
  RULE_COUNT=$(dolt sql -q "SELECT COUNT(*) FROM mesh_rules;" -r csv 2>/dev/null | tail -n +2 | head -1)
  INVITE_COUNT=$(dolt sql -q "SELECT COUNT(*) FROM invites WHERE status = 'active';" -r csv 2>/dev/null | tail -n +2 | head -1)
  LAST_COMMIT=$(dolt log -n 1 --oneline 2>/dev/null | head -1 | sed 's/\x1b\[[0-9;]*m//g' | cut -c1-60)

  # Daemon status
  PIDFILE="/tmp/gt-mesh-daemon.pid"
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    DAEMON_STATUS="running (PID $(cat "$PIDFILE"))"
  else
    DAEMON_STATUS="stopped"
  fi

  NOW=$(date '+%Y-%m-%d %H:%M:%S')

  # Clear screen for refresh mode
  [ "$REFRESH" -gt 0 ] && clear

  # === RENDER ===
  echo ""
  echo "  ╔═══════════════════════════════════════════════════════════╗"
  echo "  ║                   GT MESH DASHBOARD                      ║"
  echo "  ╚═══════════════════════════════════════════════════════════╝"
  echo ""

  # Identity section
  echo "  ┌─ Identity ──────────────────────────────────────────────┐"
  printf "  │  GT ID:    %-20s  Role: %-14s │\n" "$GT_ID" "$GT_ROLE"
  printf "  │  GitHub:   %-20s  Mode: %-14s │\n" "$GT_GITHUB" "$BEHAVIORAL"
  echo "  └─────────────────────────────────────────────────────────┘"

  # Stats row
  echo ""
  echo "  ┌─ Stats ─────────────────────────────────────────────────┐"
  printf "  │  Peers: %-4s  │  Unread: %-4s  │  Invites: %-4s       │\n" "$PEER_COUNT" "$UNREAD" "$INVITE_COUNT"
  printf "  │  Rules: %-4s  │  Msgs:   %-4s  │  Daemon:  %-11s │\n" "$RULE_COUNT" "$TOTAL_MSGS" "$DAEMON_STATUS"
  echo "  └─────────────────────────────────────────────────────────┘"

  if [ "$COMPACT" = false ]; then
    # Peers section
    echo ""
    echo "  ┌─ Active Peers ────────────────────────────────────────┐"
    PEERS=$(dolt sql -q "SELECT gt_id, role, CAST(last_seen AS CHAR) as ls FROM peers WHERE status = 'active' ORDER BY last_seen DESC;" -r csv 2>/dev/null | tail -n +2)
    if [ -n "$PEERS" ]; then
      while IFS=',' read -r id role ls; do
        [ -z "$id" ] && continue
        # Calculate rough "ago" (minutes since last_seen)
        if [ -n "$ls" ] && [ "$ls" != "NULL" ]; then
          ls_short=$(echo "$ls" | sed 's/ /T/' | cut -c1-16)
        else
          ls_short="never"
        fi
        if [ "$id" = "$GT_ID" ]; then
          marker="*"
        else
          marker=" "
        fi
        printf "  │  %s %-16s %-14s last: %s\n" "$marker" "$id" "($role)" "$ls_short"
      done <<< "$PEERS"
    else
      echo "  │  (no active peers)"
    fi
    echo "  └────────────────────────────────────────────────────────┘"

    # Recent messages
    echo ""
    echo "  ┌─ Recent Messages (last 5) ────────────────────────────┐"
    MSGS=$(dolt sql -q "SELECT from_gt, to_gt, subject, priority, CAST(created_at AS CHAR) as ts FROM messages WHERE to_gt = '$GT_ID' OR from_gt = '$GT_ID' ORDER BY created_at DESC LIMIT 5;" -r csv 2>/dev/null | tail -n +2)
    if [ -n "$MSGS" ]; then
      while IFS=',' read -r from to subj prio ts; do
        [ -z "$from" ] && continue
        ts_short=$(echo "$ts" | sed 's/.*\([0-9][0-9]:[0-9][0-9]\).*/\1/')
        case "$prio" in
          0) plabel="P0!" ;;
          1) plabel="P1" ;;
          3) plabel="P3" ;;
          *) plabel="P2" ;;
        esac
        if [ "$from" = "$GT_ID" ]; then
          arrow="-> $to"
        else
          arrow="<- $from"
        fi
        printf "  │  [%s] %-4s %-12s %s\n" "$ts_short" "$plabel" "$arrow" "$subj"
      done <<< "$MSGS"
    else
      echo "  │  (no messages)"
    fi
    echo "  └────────────────────────────────────────────────────────┘"

    # Rules summary
    echo ""
    echo "  ┌─ Governance Rules ────────────────────────────────────┐"
    RULES=$(dolt sql -q "SELECT rule_name, rule_value FROM mesh_rules ORDER BY category, rule_name LIMIT 6;" -r csv 2>/dev/null | tail -n +2)
    if [ -n "$RULES" ]; then
      while IFS=',' read -r name val; do
        [ -z "$name" ] && continue
        printf "  │  %-30s = %s\n" "$name" "$val"
      done <<< "$RULES"
      [ "$RULE_COUNT" -gt 6 ] 2>/dev/null && echo "  │  ... and $((RULE_COUNT - 6)) more"
    else
      echo "  │  (no rules configured)"
    fi
    echo "  └────────────────────────────────────────────────────────┘"
  fi

  echo ""
  printf "  Last sync: %s\n" "$LAST_COMMIT"
  printf "  Updated:   %s\n" "$NOW"

  if [ "$REFRESH" -gt 0 ]; then
    echo ""
    echo "  [Auto-refreshing every ${REFRESH}s — Ctrl+C to exit]"
  else
    echo ""
    echo "  Commands: gt mesh send | inbox | invite | feed | rules | sync"
  fi
  echo ""

  cd "$GT_ROOT" 2>/dev/null || true
}

# Render once or loop
if [ "$REFRESH" -gt 0 ]; then
  while true; do
    _render
    sleep "$REFRESH"
  done
else
  _render
fi

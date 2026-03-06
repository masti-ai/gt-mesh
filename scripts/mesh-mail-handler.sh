#!/bin/bash
# GT Mesh — Mail Handler
# Runs on every sync cycle. Checks for unread mail, routes to local agents.
#
# Routing:
#   P0/P1 messages → nudge mayor immediately
#   Handoff messages → nudge mayor with context
#   Status requests → auto-reply with mesh status
#   All unread → log to local inbox file for next session pickup
#
# Usage: mesh-mail-handler.sh [--auto-reply]

GT_ROOT="${GT_ROOT:-$HOME/gt}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"
CLONE_DIR=$(grep "clone_dir:" "$MESH_YAML" 2>/dev/null | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"
INBOX_FILE="$GT_ROOT/.mesh-inbox-pending.log"
AUTO_REPLY=false
[ "$1" = "--auto-reply" ] && AUTO_REPLY=true

if [ ! -f "$MESH_YAML" ]; then
  exit 0
fi

GT_ID=$(grep "^  id:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')

# Check we have a clone
[ ! -d "$CLONE_DIR/.dolt" ] && exit 0

cd "$CLONE_DIR"

# Count unread
UNREAD_COUNT=$(dolt sql -q "SELECT COUNT(*) FROM messages WHERE to_gt = '$GT_ID' AND read_at IS NULL;" -r csv 2>/dev/null | tail -n +2 | head -1)

[ "${UNREAD_COUNT:-0}" -eq 0 ] && exit 0

# Get unread messages
MESSAGES=$(dolt sql -q "SELECT CONCAT(id, '|', from_gt, '|', priority, '|', subject) FROM messages WHERE to_gt = '$GT_ID' AND read_at IS NULL ORDER BY priority ASC, created_at DESC;" -r csv 2>/dev/null | tail -n +2 | sed 's/^"//;s/"$//')

# Process each message
while IFS='|' read -r msg_id from_gt priority subject; do
  [ -z "$msg_id" ] && continue

  # Log to pending inbox file
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [P${priority:-2}] from:$from_gt subject:$subject id:$msg_id" >> "$INBOX_FILE"

  # Route based on priority
  case "$priority" in
    0|1)
      # P0/P1 — try to nudge mayor
      if tmux has-session -t hq-mayor 2>/dev/null; then
        PANE_DEAD=$(tmux list-panes -t hq-mayor -F '#{pane_dead}' 2>/dev/null | head -1)
        if [ "$PANE_DEAD" = "0" ]; then
          gt nudge hq-mayor "[MESH MAIL] P${priority} from $from_gt: $subject — check with: gt-mesh inbox" 2>/dev/null
        fi
      fi
      ;;
  esac

  # Auto-reply to status requests
  if [ "$AUTO_REPLY" = true ]; then
    SUBJECT_LOWER=$(echo "$subject" | tr '[:upper:]' '[:lower:]')
    case "$SUBJECT_LOWER" in
      *status*|*ping*|*alive*|*heartbeat*)
        # Auto-reply with basic status
        PEERS=$(dolt sql -q "SELECT COUNT(*) FROM peers WHERE status = 'active';" -r csv 2>/dev/null | tail -n +2 | head -1)
        REPLY_BODY="Auto-reply from $GT_ID: Online. Active peers: ${PEERS:-?}. Last sync: $(date -u +%H:%M:%S). Use gt mesh send for full conversation."
        REPLY_ID="msg-auto-$(date +%s)-${RANDOM}"
        REPLY_ESC=$(echo "$REPLY_BODY" | sed "s/'/''/g")
        dolt sql -q "INSERT INTO messages (id, from_gt, from_addr, to_gt, subject, body, priority, created_at)
          VALUES ('$REPLY_ID', '$GT_ID', 'mayor/', '$from_gt', 'RE: $subject', '$REPLY_ESC', 2, NOW());" 2>/dev/null
        # Mark original as read
        dolt sql -q "UPDATE messages SET read_at = NOW() WHERE id = '$msg_id';" 2>/dev/null
        ;;
    esac
  fi

done <<< "$MESSAGES"

# Commit any auto-replies
if [ "$AUTO_REPLY" = true ]; then
  dolt add . 2>/dev/null
  if dolt diff --staged --stat 2>/dev/null | grep -qi "row"; then
    dolt commit -m "mesh: $GT_ID auto-replied to messages" --allow-empty 2>/dev/null || true
    dolt push 2>/dev/null || true
  fi
fi

cd "$GT_ROOT"

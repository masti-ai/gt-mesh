#!/bin/bash
# GT Mesh — Auto-sync: broadcast work context to mesh peers
#
# Usage: mesh-auto-sync.sh <subcommand>
#   broadcast <subject> <body>     Send update to all active peers
#   log <message>                  Append to local activity log + broadcast
#   digest                         Generate and send work digest to peers
#   history                        Show local activity log

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"
CLONE_DIR=$(grep "clone_dir:" "$MESH_YAML" 2>/dev/null | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"
DOLTHUB_DB="deepwork/gt-agent-mail"

if [ ! -f "$MESH_YAML" ]; then
  echo "[error] Not in a mesh. Run: gt mesh init"
  exit 1
fi

GT_ID=$(grep "^  id:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
ACTIVITY_LOG="$GT_ROOT/.mesh-activity.log"

_ensure_clone() {
  if [ ! -d "$CLONE_DIR/.dolt" ]; then
    dolt clone "$DOLTHUB_DB" "$CLONE_DIR" 2>/dev/null || {
      echo "[error] Failed to connect to DoltHub"
      exit 1
    }
  fi
  cd "$CLONE_DIR"
  # Commit any stale changes before pulling
  dolt add . 2>/dev/null
  if dolt diff --staged --stat 2>/dev/null | grep -q "rows"; then
    dolt commit -m "mesh: pre-broadcast commit from $GT_ID" --allow-empty 2>/dev/null || true
  fi
  dolt pull 2>/dev/null || true

  # Ensure activity_log table exists
  dolt sql -q "CREATE TABLE IF NOT EXISTS activity_log (
    id VARCHAR(64) PRIMARY KEY,
    gt_id VARCHAR(64) NOT NULL,
    action VARCHAR(32) NOT NULL,
    subject VARCHAR(256),
    body TEXT,
    created_at DATETIME,
    INDEX idx_gt_created (gt_id, created_at)
  );" 2>/dev/null || true
}

_send_to_all_peers() {
  local SUBJECT="$1"
  local BODY="$2"
  local PRIORITY="${3:-P2}"

  PEERS=$(dolt sql -q "SELECT gt_id FROM peers WHERE status = 'active' AND gt_id != '$GT_ID';" -r csv 2>/dev/null | tail -n +2)

  SENT=0
  while IFS= read -r peer; do
    [ -z "$peer" ] && continue
    peer=$(echo "$peer" | tr -d '"')
    MSG_ID="msg-auto-$(date +%s)-${RANDOM}"
    BODY_ESC=$(echo "$BODY" | sed "s/'/''/g")
    SUBJECT_ESC=$(echo "$SUBJECT" | sed "s/'/''/g")

    dolt sql -q "INSERT INTO messages (id, from_gt, to_gt, subject, body, priority, sent_at)
      VALUES ('$MSG_ID', '$GT_ID', '$peer', '$SUBJECT_ESC', '$BODY_ESC', '$PRIORITY', NOW());" 2>/dev/null
    SENT=$((SENT + 1))
  done <<< "$PEERS"

  dolt add . 2>/dev/null || true
  dolt commit -m "mesh: $GT_ID broadcast to $SENT peers" --allow-empty 2>/dev/null || true
  dolt push 2>/dev/null || true

  echo "[auto-sync] Sent to $SENT peer(s)"
}

_log_activity() {
  local ACTION="$1"
  local SUBJECT="$2"
  local BODY="$3"

  # Local log
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [$ACTION] $SUBJECT" >> "$ACTIVITY_LOG"

  # DoltHub log
  LOG_ID="log-$(date +%s)-${RANDOM}"
  SUBJECT_ESC=$(echo "$SUBJECT" | sed "s/'/''/g")
  BODY_ESC=$(echo "$BODY" | sed "s/'/''/g")

  dolt sql -q "INSERT INTO activity_log (id, gt_id, action, subject, body, created_at)
    VALUES ('$LOG_ID', '$GT_ID', '$ACTION', '$SUBJECT_ESC', '$BODY_ESC', NOW());" 2>/dev/null || true
}

SUBCMD="${1:-help}"
shift 2>/dev/null || true

case "$SUBCMD" in
  broadcast)
    SUBJECT="$1"
    BODY="$2"
    PRIORITY="${3:-P2}"

    if [ -z "$SUBJECT" ] || [ -z "$BODY" ]; then
      echo "Usage: gt mesh auto-sync broadcast <subject> <body> [priority]"
      exit 1
    fi

    _ensure_clone

    echo "[auto-sync] Broadcasting to mesh..."
    echo "  Subject: $SUBJECT"
    echo ""

    _log_activity "broadcast" "$SUBJECT" "$BODY"
    _send_to_all_peers "$SUBJECT" "$BODY" "$PRIORITY"
    ;;

  log)
    MESSAGE="$1"
    if [ -z "$MESSAGE" ]; then
      echo "Usage: gt mesh auto-sync log <message>"
      exit 1
    fi

    _ensure_clone

    _log_activity "log" "$MESSAGE" ""
    dolt add . 2>/dev/null || true
    dolt commit -m "mesh: activity log from $GT_ID" --allow-empty 2>/dev/null || true
    dolt push 2>/dev/null || true

    echo "[auto-sync] Logged: $MESSAGE"
    ;;

  digest)
    # Generate a work digest from recent activity and broadcast it
    _ensure_clone

    echo "[auto-sync] Generating work digest..."

    # Gather recent activity from this GT
    RECENT=$(dolt sql -q "SELECT CONCAT(action, ': ', subject) FROM activity_log WHERE gt_id = '$GT_ID' AND created_at > DATE_SUB(NOW(), INTERVAL 4 HOUR) ORDER BY created_at DESC LIMIT 10;" -r csv 2>/dev/null | tail -n +2 | sed 's/^"//;s/"$//')

    # Gather recent sent messages
    SENT_MSGS=$(dolt sql -q "SELECT CONCAT('-> ', to_gt, ': ', subject) FROM messages WHERE from_gt = '$GT_ID' AND sent_at > DATE_SUB(NOW(), INTERVAL 4 HOUR) ORDER BY sent_at DESC LIMIT 5;" -r csv 2>/dev/null | tail -n +2 | sed 's/^"//;s/"$//')

    # Gather git activity if in a repo
    GIT_LOG=""
    if [ -d "$GT_ROOT/.git" ] || [ -d "$GT_ROOT/mayor/.git" ]; then
      GIT_DIR="$GT_ROOT"
      [ -d "$GT_ROOT/mayor/.git" ] && GIT_DIR="$GT_ROOT/mayor"
      GIT_LOG=$(cd "$GIT_DIR" && git log --oneline --since="4 hours ago" 2>/dev/null | head -5)
    fi

    # Build digest
    DIGEST="Work digest from $GT_ID (last 4 hours)

Recent activity:
${RECENT:-  (none)}

Messages sent:
${SENT_MSGS:-  (none)}

Git commits:
${GIT_LOG:-  (none)}

-- auto-generated by mesh auto-sync"

    echo "$DIGEST"
    echo ""

    _log_activity "digest" "Work digest" "$DIGEST"
    _send_to_all_peers "[Digest] $GT_ID work update" "$DIGEST"
    ;;

  history)
    LIMIT="${1:-20}"

    if [ -f "$ACTIVITY_LOG" ]; then
      echo "=== Local Activity Log (last $LIMIT entries) ==="
      tail -n "$LIMIT" "$ACTIVITY_LOG"
    else
      echo "(no local activity log)"
    fi

    echo ""
    echo "=== Mesh Activity Feed ==="

    _ensure_clone

    dolt sql -q "SELECT gt_id, action, subject, CAST(created_at AS CHAR) as time FROM activity_log ORDER BY created_at DESC LIMIT $LIMIT;" 2>/dev/null || echo "(no mesh activity)"

    cd "$GT_ROOT"
    ;;

  *)
    echo "GT Mesh Auto-Sync — Keep peers informed automatically"
    echo ""
    echo "Usage: gt mesh auto-sync <command>"
    echo ""
    echo "Commands:"
    echo "  broadcast <subject> <body>   Send update to all active peers"
    echo "  log <message>                Log activity (local + mesh)"
    echo "  digest                       Generate & broadcast work digest"
    echo "  history [N]                  Show activity log (default: last 20)"
    ;;
esac

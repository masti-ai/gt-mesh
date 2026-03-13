#!/bin/bash
# GT Mesh Mayor Daemon
# Runs every 10 min via cron. Processes mesh inbox automatically.
# - "need work" messages → creates Gitea issues from backlog
# - Watchdog alerts → logs for next mayor session
# - Work complete notifications → logs PR URLs for review
#
# Cron: */10 * * * * bash /home/pratham2/gt/.gt-mesh/scripts/mesh-mayor-daemon.sh

GT_ROOT="/home/pratham2/gt"
GITEA_URL="${GITEA_URL:-http://localhost:3300}"
GITEA_TOKEN="${GITEA_TOKEN:?Set GITEA_TOKEN env var}"
CLONE_DIR="/tmp/mesh-sync-clone"
LOG="/tmp/mesh-mayor-daemon.log"
LOCK="/tmp/mesh-mayor-daemon.lock"
BACKLOG="/home/pratham2/gt/.gt-mesh/backlog.jsonl"

# Lock
if [ -f "$LOCK" ]; then
  AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
  [ "$AGE" -lt 600 ] && exit 0
  rm -f "$LOCK"
fi
touch "$LOCK"
trap "rm -f $LOCK" EXIT

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%S) $1" >> "$LOG"; }

# ─── Sync DoltHub ───
cd "$CLONE_DIR" 2>/dev/null || exit 1
timeout 30 dolt pull 2>/dev/null

# ─── Process unread messages to mayor ───
UNREAD=$(timeout 10 dolt sql -q "SELECT id, from_gt, subject, body FROM messages WHERE to_gt = 'gt-local' AND read_at IS NULL ORDER BY created_at DESC LIMIT 10;" -r csv 2>/dev/null | tail -n +2)

while IFS=',' read -r msg_id from_gt subject body_start; do
  [ -z "$msg_id" ] && continue
  log "Processing: $msg_id from=$from_gt subj=$subject"

  # Mark as read
  timeout 5 dolt sql -q "UPDATE messages SET read_at = NOW() WHERE id = '$msg_id';" 2>/dev/null

  case "$subject" in
    *"need"*"work"*|*"Need"*"issues"*|*"0 issues"*|*"WATCHDOG"*)
      log "WORK REQUEST from $from_gt — checking backlog"

      # Count open issues
      OPEN=0
      for repo in OfficeWorld alc-ai-villa ai-planogram; do
        count=$(curl -s "$GITEA_URL/api/v1/repos/Deepwork-AI/$repo/issues?state=open&type=issues" \
          -H "Authorization: token $GITEA_TOKEN" 2>/dev/null | \
          python3 -c "import sys,json;print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
        OPEN=$((OPEN + count))
      done

      if [ "$OPEN" -eq 0 ] && [ -f "$BACKLOG" ]; then
        # Create issues from backlog
        CREATED=0
        while IFS= read -r line && [ "$CREATED" -lt 3 ]; do
          repo=$(echo "$line" | python3 -c "import sys,json;print(json.load(sys.stdin)['repo'])" 2>/dev/null)
          title=$(echo "$line" | python3 -c "import sys,json;print(json.load(sys.stdin)['title'])" 2>/dev/null)
          body=$(echo "$line" | python3 -c "import sys,json;print(json.load(sys.stdin).get('body',''))" 2>/dev/null)
          priority=$(echo "$line" | python3 -c "import sys,json;print(json.load(sys.stdin).get('priority',2))" 2>/dev/null)

          [ -z "$repo" ] || [ -z "$title" ] && continue

          curl -s -X POST "$GITEA_URL/api/v1/repos/Deepwork-AI/$repo/issues" \
            -H "Authorization: token $GITEA_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"title\":\"$title\",\"body\":\"$body\",\"labels\":[$priority]}" -o /dev/null 2>/dev/null

          CREATED=$((CREATED + 1))
          log "Created issue: $title on $repo"
        done < "$BACKLOG"

        # Remove created items from backlog
        if [ "$CREATED" -gt 0 ]; then
          tail -n +$((CREATED + 1)) "$BACKLOG" > "$BACKLOG.tmp" && mv "$BACKLOG.tmp" "$BACKLOG"
        fi

        # Notify worker
        cd "$GT_ROOT"
        bash .gt-mesh/scripts/mesh-send.sh "$from_gt" \
          "Work created: $CREATED new issues" \
          "Created $CREATED issues from backlog. Poll Gitea now." 1 2>/dev/null
        cd "$CLONE_DIR"
      else
        log "Queue not empty ($OPEN open) or no backlog"
      fi
      ;;

    *"PR"*"ready"*|*"PR #"*)
      log "PR notification from $from_gt: $subject"
      # Log for mayor to review next session
      echo "{\"type\":\"review\",\"from\":\"$from_gt\",\"subject\":\"$subject\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%S)\"}" >> /tmp/mesh-mayor-review-queue.jsonl
      ;;

    *"BLOCKED"*|*"blocked"*)
      log "BLOCKED alert from $from_gt: $subject"
      echo "{\"type\":\"blocked\",\"from\":\"$from_gt\",\"subject\":\"$subject\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%S)\"}" >> /tmp/mesh-mayor-review-queue.jsonl
      ;;

    *)
      log "Info message from $from_gt: $subject"
      ;;
  esac
done <<< "$UNREAD"

timeout 10 dolt add . 2>/dev/null && timeout 10 dolt commit -m "mesh: mayor daemon processed messages" --allow-empty 2>/dev/null && timeout 30 dolt push 2>/dev/null

log "Daemon cycle complete"

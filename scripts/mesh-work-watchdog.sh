#!/bin/bash
# GT Mesh Work Watchdog
# Runs as cron every 5 min. Checks if worker agents have work.
# If a worker's Gitea queue is empty, sends mesh mail to mayor.
# If mayor has unread "need work" messages, logs for next session.
#
# Install: */5 * * * * bash /home/pratham2/gt/.gt-mesh/scripts/mesh-work-watchdog.sh

GT_ROOT="${GT_ROOT:-/home/pratham2/gt}"
GITEA_URL="http://localhost:3300"
GITEA_ADMIN_TOKEN="4156997c1c8b8583b0000833c39fd582c1591640"
DOLTHUB_DB="deepwork/gt-agent-mail"
CLONE_DIR="/tmp/mesh-sync-clone"
LOCK_FILE="/tmp/mesh-watchdog.lock"
LOG_FILE="/tmp/mesh-watchdog.log"

# Prevent concurrent runs
if [ -f "$LOCK_FILE" ]; then
  LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
  if [ "$LOCK_AGE" -lt 300 ]; then
    exit 0
  fi
  rm -f "$LOCK_FILE"
fi
touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%S) $1" >> "$LOG_FILE"
}

# ─── Check each worker's Gitea queue ───
check_worker_queue() {
  local worker="$1"
  local token="$2"
  local total_open=0

  for repo in OfficeWorld alc-ai-villa ai-planogram; do
    count=$(curl -s "$GITEA_URL/api/v1/repos/Deepwork-AI/$repo/issues?state=open&type=issues" \
      -H "Authorization: token $GITEA_ADMIN_TOKEN" 2>/dev/null | \
      python3 -c "import sys,json;print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    total_open=$((total_open + count))
  done

  echo "$total_open"
}

# ─── Check if worker session is alive ───
check_worker_alive() {
  local container="$1"
  local session="$2"
  docker exec "$container" tmux has-session -t "$session" 2>/dev/null && echo "alive" || echo "unreachable"
}

# ─── Main ───

# Check gasclaw-1 (container: gasclaw-1-worker, session: worker1)
GASCLAW_QUEUE=$(check_worker_queue "gasclaw-1" "16a77301ab0786eeaba893405bc3da3343fcc861")
GASCLAW_STATUS=$(check_worker_alive "gasclaw-1-worker" "worker1")

log "gasclaw-1: queue=$GASCLAW_QUEUE session=$GASCLAW_STATUS"

# Check gasclaw-2 (container: gasclaw-2, session: worker1)
GASCLAW2_QUEUE=$(check_worker_queue "gasclaw-2" "16a77301ab0786eeaba893405bc3da3343fcc861")
GASCLAW2_STATUS=$(check_worker_alive "gasclaw-2" "worker1")

log "gasclaw-2: queue=$GASCLAW2_QUEUE session=$GASCLAW2_STATUS"

if [ "$GASCLAW_QUEUE" -eq 0 ] && [ "$GASCLAW_STATUS" = "alive" ]; then
  # Worker is alive but has no work — alert mayor
  log "ALERT: gasclaw-1 has 0 issues, session alive. Sending work request."

  # Check if we already sent a request recently (within 30 min)
  LAST_REQUEST=$(grep "work-request-sent" "$LOG_FILE" 2>/dev/null | tail -1 | cut -d' ' -f1)
  if [ -n "$LAST_REQUEST" ]; then
    LAST_TS=$(date -d "$LAST_REQUEST" +%s 2>/dev/null || echo 0)
    NOW_TS=$(date +%s)
    if [ $((NOW_TS - LAST_TS)) -lt 1800 ]; then
      log "Skipping — already requested within 30 min"
      exit 0
    fi
  fi

  # Send mesh mail
  cd "$GT_ROOT"
  bash .gt-mesh/scripts/mesh-send.sh gt-local \
    "WATCHDOG: gasclaw-1 has 0 issues" \
    "gasclaw-1 is alive but has no Gitea issues to work on. Create issues for: OfficeWorld, alc-ai-villa, or ai-planogram." \
    1 2>/dev/null

  log "work-request-sent"
fi

if [ "$GASCLAW_STATUS" = "unreachable" ] || [ "$GASCLAW_STATUS" = "dead" ]; then
  log "ALERT: gasclaw-1 session=$GASCLAW_STATUS"
fi

if [ "$GASCLAW2_STATUS" = "unreachable" ] || [ "$GASCLAW2_STATUS" = "dead" ]; then
  log "ALERT: gasclaw-2 session=$GASCLAW2_STATUS"
fi

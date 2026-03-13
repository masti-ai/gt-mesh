#!/bin/bash
# GT Mesh — Mayor Work Dispatcher
# Runs on gt-local (mayor) every 5 min.
#
# Responsibilities:
#   1. Check DoltHub for "IDLE" messages from workers → dispatch work
#   2. Check Gitea for open PRs that need review → notify mayor session
#   3. Check for stale in_progress beads with no activity → re-dispatch
#
# This replaces the old mesh-work-watchdog.sh with a more comprehensive approach.

set -o pipefail

GT_ROOT="${GT_ROOT:-/home/pratham2/gt}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"
CLONE_DIR="/tmp/mesh-sync-clone"
GITEA_URL="${GITEA_URL:-http://localhost:3300}"
GITEA_TOKEN="${GITEA_TOKEN:?Set GITEA_TOKEN env var}"
LOG="/tmp/mayor-dispatcher.log"
LOCK="/tmp/mayor-dispatcher.lock"
STATE_DIR="/tmp/mayor-dispatcher-state"

mkdir -p "$STATE_DIR"

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%S) $1" >> "$LOG"
}

# Prevent concurrent runs
if [ -f "$LOCK" ]; then
  AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
  [ "$AGE" -lt 300 ] && exit 0
  rm -f "$LOCK"
fi
touch "$LOCK"
trap "rm -f $LOCK" EXIT

# ─── 1. Check for idle worker messages ───
check_idle_workers() {
  if [ ! -d "$CLONE_DIR/.dolt" ]; then
    log "[error] No DoltHub clone at $CLONE_DIR"
    return
  fi

  cd "$CLONE_DIR" || return
  timeout 30 dolt pull 2>/dev/null || true

  # Find idle notifications from workers
  IDLE_MSGS=$(timeout 10 dolt sql -q "SELECT id, from_gt FROM messages WHERE to_gt = 'gt-local' AND subject LIKE 'IDLE:%' AND read_at IS NULL;" -r csv 2>/dev/null | tail -n +2)

  if [ -z "$IDLE_MSGS" ]; then
    return
  fi

  while IFS=',' read -r msg_id from_gt; do
    [ -z "$msg_id" ] && continue
    log "[idle-worker] $from_gt is idle (msg: $msg_id)"

    # Find ready beads to dispatch
    cd "$GT_ROOT"
    READY_BEADS=$(bd ready --json 2>/dev/null | python3 -c "
import sys,json
try:
    beads=json.load(sys.stdin)
    # Sort by priority
    beads.sort(key=lambda b: b.get('priority', 2))
    for b in beads[:3]:
        print(f\"{b['id']}|{b['title'][:100]}|{b.get('priority',2)}\")
except:
    pass
" 2>/dev/null)

    if [ -n "$READY_BEADS" ]; then
      # Build work dispatch message
      WORK_LIST=""
      COUNT=0
      while IFS='|' read -r bead_id title priority; do
        [ -z "$bead_id" ] && continue
        COUNT=$((COUNT + 1))
        WORK_LIST="${WORK_LIST}${COUNT}. [P${priority}] ${bead_id}: ${title}\n"
      done <<< "$READY_BEADS"

      DISPATCH_BODY="You reported idle. Here are your next tasks:\n\n${WORK_LIST}\nPick the highest priority one first. Claim with: bd update <id> --claim\nCreate PRs targeting dev on Gitea (port 3300).\nBranch format: gt/${from_gt}/<bead-id>-<desc>"

      cd "$CLONE_DIR"
      DISPATCH_ID="dispatch-${from_gt}-$(date +%s)"
      DISPATCH_BODY_ESC=$(echo -e "$DISPATCH_BODY" | sed "s/'/''/g")

      timeout 10 dolt sql -q "INSERT INTO messages (id, from_gt, from_addr, to_gt, to_addr, subject, body, priority, created_at) VALUES ('$DISPATCH_ID', 'gt-local', 'mayor/', '$from_gt', 'worker/', 'WORK DISPATCH: $COUNT tasks assigned', '$DISPATCH_BODY_ESC', 1, NOW());" 2>/dev/null

      log "[dispatched] $COUNT beads to $from_gt"
    else
      log "[no-work] No ready beads to dispatch to $from_gt"
    fi

    # Mark idle message as read
    cd "$CLONE_DIR"
    timeout 5 dolt sql -q "UPDATE messages SET read_at = NOW() WHERE id = '$msg_id';" 2>/dev/null

  done <<< "$IDLE_MSGS"

  # Commit and push
  cd "$CLONE_DIR"
  timeout 15 dolt add . 2>/dev/null
  if timeout 10 dolt diff --staged --stat 2>/dev/null | grep -qi "row"; then
    timeout 15 dolt commit -m "mayor: work dispatch from gt-local" 2>/dev/null
  fi
  timeout 30 dolt push 2>/dev/null || log "[warn] Push deferred"
}

# ─── 2. Check for pending PRs on Gitea ───
check_pending_prs() {
  REPOS="ai-planogram alc-ai-villa OfficeWorld deepwork-site gt-mesh deepwork-base"
  PR_SUMMARY=""
  TOTAL_PRS=0

  for repo in $REPOS; do
    PRS=$(curl -s "$GITEA_URL/api/v1/repos/Deepwork-AI/$repo/pulls?state=open&limit=20" \
      -H "Authorization: token $GITEA_TOKEN" 2>/dev/null)

    PR_COUNT=$(echo "$PRS" | python3 -c "
import sys,json,os
repo='$repo'
try:
    prs=json.load(sys.stdin)
    if not isinstance(prs, list): prs=[]
    for pr in prs:
        num=pr['number']
        title=pr['title'][:80]
        author=pr['user']['login']
        created=pr['created_at'][:10]
        print(f'  {repo} #{num}: {title} (by {author}, {created})')
    print(f'COUNT:{len(prs)}')
except:
    print('COUNT:0')
" 2>/dev/null)

    COUNT=$(echo "$PR_COUNT" | grep "^COUNT:" | cut -d: -f2)
    TOTAL_PRS=$((TOTAL_PRS + ${COUNT:-0}))

    DETAILS=$(echo "$PR_COUNT" | grep -v "^COUNT:")
    if [ -n "$DETAILS" ]; then
      PR_SUMMARY="${PR_SUMMARY}${DETAILS}\n"
    fi
  done

  # Write PR state file (for mayor session to pick up)
  if [ "$TOTAL_PRS" -gt 0 ]; then
    LAST_PR_COUNT=$(cat "$STATE_DIR/pr-count" 2>/dev/null || echo 0)
    echo "$TOTAL_PRS" > "$STATE_DIR/pr-count"
    echo -e "$PR_SUMMARY" > "$STATE_DIR/pending-prs.txt"

    # Only notify if PR count changed
    if [ "$TOTAL_PRS" != "$LAST_PR_COUNT" ]; then
      log "[prs] $TOTAL_PRS open PRs across repos (was $LAST_PR_COUNT)"

      # Nudge mayor session if it exists
      if tmux has-session -t mayor 2>/dev/null; then
        # Don't interrupt — write to a file the mayor can check
        echo "[$(date -u +%H:%M)] $TOTAL_PRS open PRs need review. See /tmp/mayor-dispatcher-state/pending-prs.txt" >> /tmp/mayor-pr-alerts.txt
      fi
    fi
  else
    echo "0" > "$STATE_DIR/pr-count"
    rm -f "$STATE_DIR/pending-prs.txt"
  fi
}

# ─── 3. Check worker liveness via Docker ───
check_worker_liveness() {
  for container_session in "gasclaw-1-worker:worker1" "gasclaw-2:worker1"; do
    container=$(echo "$container_session" | cut -d: -f1)
    session=$(echo "$container_session" | cut -d: -f2)

    # Check container running
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
      log "[dead] Container $container is not running"
      continue
    fi

    # Check tmux session
    if ! docker exec "$container" tmux has-session -t "$session" 2>/dev/null; then
      log "[dead] $container session $session is dead"
      continue
    fi

    log "[alive] $container:$session"
  done
}

# ─── Main ───
log "=== Dispatcher run ==="
check_idle_workers
check_pending_prs
check_worker_liveness
log "=== Done ==="

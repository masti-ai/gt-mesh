#!/bin/bash
# Sync gt-local ↔ DoltHub (deepwork/gt-agent-mail)
# Cross-GT mail via dedicated messages + peers tables
#
# IMPORTANT: Uses /tmp/mesh-sync-clone (same as mesh-sync.sh)
# and shares the lock file to prevent concurrent access.
# The old /tmp/hq-clone is no longer used.

CLONE_DIR="/tmp/mesh-sync-clone"
GT_ID="gt-local"
GT_ROOT="/home/pratham2/gt"
DELIVERED_LOG="/tmp/gt-mesh-delivered.log"
DOLTHUB_DB="deepwork/gt-agent-mail"

# SHARED lock with mesh-sync.sh — prevents both from running simultaneously
LOCK="/tmp/mesh-sync.lock"
if [ -f "$LOCK" ]; then
  AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
  [ "$AGE" -lt 120 ] && exit 0
  rm -f "$LOCK"
fi
touch "$LOCK"
trap "rm -f $LOCK" EXIT

# Ensure clone exists
if [ ! -d "$CLONE_DIR/.dolt" ]; then
  echo "[setup] Cloning $DOLTHUB_DB..."
  rm -rf "$CLONE_DIR"
  timeout 90 dolt clone "$DOLTHUB_DB" "$CLONE_DIR" 2>&1
  if [ $? -ne 0 ]; then
    echo "[error] Clone failed"
    exit 1
  fi
fi

cd "$CLONE_DIR" || exit 1

touch "$DELIVERED_LOG"

# 1. Commit local changes before pull
timeout 15 dolt add . 2>/dev/null
if timeout 10 dolt diff --staged --stat 2>/dev/null | grep -qi "row"; then
  timeout 15 dolt commit -m "sync: pre-pull commit from $GT_ID" --author "Pratham's Agent <prathamonchain@gmail.com>" 2>/dev/null || true
fi

# 2. Pull remote changes (from other GTs)
timeout 45 dolt pull origin main 2>/dev/null

# 2b. Auto-resolve any conflicts (peers/messages table conflicts are harmless)
for table in peers messages; do
  if timeout 5 dolt conflicts cat "$table" >/dev/null 2>&1; then
    timeout 10 dolt conflicts resolve --theirs "$table" 2>/dev/null
    timeout 10 dolt add . 2>/dev/null
    timeout 10 dolt commit -m "auto-resolve $table conflict (theirs wins)" --author "Pratham's Agent <prathamonchain@gmail.com>" 2>/dev/null
  fi
done

# 3. Find new undelivered messages addressed to us
MSG_IDS=$(timeout 10 dolt sql -q "SELECT id FROM messages WHERE to_gt = '$GT_ID' AND read_at IS NULL;" -r csv 2>/dev/null | tail -n +2)

if [ -n "$MSG_IDS" ]; then
  while IFS= read -r msg_id; do
    [ -z "$msg_id" ] && continue

    if grep -qF "$msg_id" "$DELIVERED_LOG" 2>/dev/null; then
      continue
    fi

    from_gt=$(timeout 5 dolt sql -q "SELECT from_gt FROM messages WHERE id = '$msg_id';" -r csv 2>/dev/null | tail -1)
    from_addr=$(timeout 5 dolt sql -q "SELECT from_addr FROM messages WHERE id = '$msg_id';" -r csv 2>/dev/null | tail -1)
    subject=$(timeout 5 dolt sql -q "SELECT subject FROM messages WHERE id = '$msg_id';" -r csv 2>/dev/null | tail -1)
    body=$(timeout 5 dolt sql -q "SELECT body FROM messages WHERE id = '$msg_id';" -r csv 2>/dev/null | tail -1)

    cd "$GT_ROOT"
    gt mail send mayor/ -s "[mesh:${from_gt}] ${subject}" -m "From: ${from_gt}/${from_addr}
---
${body}
---
[Mesh message ID: ${msg_id}]" 2>/dev/null

    echo "$msg_id" >> "$DELIVERED_LOG"

    cd "$CLONE_DIR"
    timeout 5 dolt sql -q "UPDATE messages SET read_at = NOW() WHERE id = '${msg_id}';" 2>/dev/null

    echo "[$(date)] Delivered mesh mail: ${from_gt} -> ${subject}"
  done <<< "$MSG_IDS"
fi

cd "$CLONE_DIR"

# 4. Update our last_seen in peers table
timeout 5 dolt sql -q "UPDATE peers SET last_seen = NOW() WHERE gt_id = '$GT_ID';" 2>/dev/null

# 5. Commit and push if changes
timeout 15 dolt add . 2>/dev/null
if timeout 10 dolt diff --staged --stat 2>/dev/null | grep -qi "row"; then
  timeout 10 dolt commit -m "sync: $GT_ID $(date +%Y-%m-%dT%H:%M)" --author "Pratham's Agent <prathamonchain@gmail.com>" 2>/dev/null
  timeout 30 dolt push origin main 2>/dev/null
fi

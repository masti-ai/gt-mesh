#!/bin/bash
# GT Mesh GitHub Sync
# Runs daily via cron. Pushes latest code to GitHub and nudges gasclaw-1 to update.
# Also creates releases when milestones are hit.
#
# Cron: 0 6 * * * bash /home/pratham2/gt/.gt-mesh/scripts/mesh-github-sync.sh

GT_ROOT="/home/pratham2/gt"
GITEA_URL="http://localhost:3300"
GITEA_TOKEN="4156997c1c8b8583b0000833c39fd582c1591640"
LOG="/tmp/mesh-github-sync.log"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%S) $1" >> "$LOG"; }

log "=== GitHub sync started ==="

# ─── Push all repos from gasclaw (has pratham-bhatnagar auth) ───
for repo in OfficeWorld ai-planogram alc-ai-villa; do
  log "Syncing $repo..."

  # First pull latest from Gitea into gasclaw's local
  docker exec gasclaw su - gasclaw -c "
    cd /workspace/gt/$repo && \
    git remote add gitea http://172.17.0.1:3300/Deepwork-AI/$repo.git 2>/dev/null; \
    git fetch gitea dev 2>/dev/null && \
    git checkout dev 2>/dev/null && \
    git merge gitea/dev --no-edit 2>/dev/null
  " 2>/dev/null

  # Push to GitHub
  RESULT=$(docker exec gasclaw su - gasclaw -c "
    cd /workspace/gt/$repo && \
    gh auth setup-git 2>/dev/null && \
    git push origin dev 2>&1
  " 2>&1)

  if echo "$RESULT" | grep -q "Everything up-to-date"; then
    log "$repo: already up-to-date"
  elif echo "$RESULT" | grep -q "->"; then
    log "$repo: pushed to GitHub"
  else
    log "$repo: push failed — $RESULT"
  fi
done

# ─── Check if a release is due ───
# Count merged PRs since last release on each repo
for repo in OfficeWorld ai-planogram alc-ai-villa; do
  MERGED=$(curl -s "$GITEA_URL/api/v1/repos/Deepwork-AI/$repo/pulls?state=closed&sort=updated&limit=50" \
    -H "Authorization: token $GITEA_TOKEN" 2>/dev/null | \
    python3 -c "import sys,json;print(len([p for p in json.load(sys.stdin) if p.get('merged')]))" 2>/dev/null || echo "0")

  log "$repo: $MERGED merged PRs"

  # If 5+ merged PRs, suggest a release
  if [ "$MERGED" -ge 5 ]; then
    log "$repo: release candidate (5+ merged PRs)"
    echo "{\"type\":\"release\",\"repo\":\"$repo\",\"merged_prs\":$MERGED,\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%S)\"}" >> /tmp/mesh-mayor-review-queue.jsonl
  fi
done

# ─── Nudge gasclaw-1 to update READMEs ───
cd "$GT_ROOT"
bash .gt-mesh/scripts/mesh-send.sh gasclaw-1 \
  "Daily: update READMEs if stale" \
  "Check if READMEs on OfficeWorld, ai-planogram, alc-ai-villa reflect current state. If not, update them. Also check if any PR descriptions need cleanup for human readability." \
  2 2>/dev/null

log "=== GitHub sync complete ==="

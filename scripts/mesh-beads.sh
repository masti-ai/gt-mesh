#!/bin/bash
# GT Mesh — Shared beads (cross-GT work items)
#
# Usage: mesh-beads.sh list [--unclaimed] [--rig <rig>]
#        mesh-beads.sh share <bead-id> [--rig <rig>]
#        mesh-beads.sh claim <bead-id>
#        mesh-beads.sh unclaim <bead-id>
#        mesh-beads.sh status <bead-id> <open|in-progress|done|closed>

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"

if [ ! -f "$MESH_YAML" ]; then
  echo "[error] Not in a mesh. Run: gt mesh init"
  exit 1
fi

_yaml_val() { grep "$1" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/'; }

GT_ID=$(_yaml_val "^  id:")
CLONE_DIR=$(_yaml_val "clone_dir:")
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"

SUBCMD="${1:-list}"
shift 2>/dev/null || true

_ensure_tables() {
  cd "$CLONE_DIR"
  dolt pull 2>/dev/null || true

  dolt sql -q "CREATE TABLE IF NOT EXISTS shared_beads (
    bead_id VARCHAR(16) PRIMARY KEY,
    title VARCHAR(512),
    description TEXT,
    status VARCHAR(32) DEFAULT 'open',
    priority INT DEFAULT 2,
    issue_type VARCHAR(32) DEFAULT 'task',
    rig VARCHAR(128),
    shared_by VARCHAR(64),
    claimed_by VARCHAR(64),
    claimed_at DATETIME,
    created_at DATETIME,
    updated_at DATETIME,
    labels VARCHAR(512),
    gh_issue_url VARCHAR(256)
  );" 2>/dev/null || true

  dolt sql -q "CREATE TABLE IF NOT EXISTS claims (
    id VARCHAR(64) PRIMARY KEY,
    bead_id VARCHAR(16),
    gt_id VARCHAR(64),
    status VARCHAR(32) DEFAULT 'active',
    claimed_at DATETIME,
    released_at DATETIME
  );" 2>/dev/null || true
}

_check_max_claims() {
  local gt="$1"
  local max=$(dolt sql -q "SELECT rule_value FROM mesh_rules WHERE rule_name = 'max_concurrent_claims';" -r csv 2>/dev/null | tail -n +2 | head -1)
  max="${max:-3}"
  local current=$(dolt sql -q "SELECT COUNT(*) FROM claims WHERE gt_id = '$gt' AND status = 'active';" -r csv 2>/dev/null | tail -n +2 | head -1)
  current="${current:-0}"
  if [ "$current" -ge "$max" ] 2>/dev/null; then
    echo "[error] $gt has $current active claims (max: $max)"
    echo "        Release a claim first: gt mesh beads unclaim <bead-id>"
    return 1
  fi
  return 0
}

case "$SUBCMD" in
  list)
    UNCLAIMED=false
    RIG_FILTER=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --unclaimed) UNCLAIMED=true; shift ;;
        --rig) RIG_FILTER="$2"; shift 2 ;;
        *) shift ;;
      esac
    done

    _ensure_tables

    echo "==========================================="
    echo "  Mesh Shared Beads"
    echo "==========================================="
    echo ""

    WHERE="1=1"
    if [ "$UNCLAIMED" = true ]; then
      WHERE="$WHERE AND (claimed_by IS NULL OR claimed_by = '')"
    fi
    if [ -n "$RIG_FILTER" ]; then
      WHERE="$WHERE AND rig = '$RIG_FILTER'"
    fi

    BEADS=$(dolt sql -q "SELECT bead_id, title, status, priority, COALESCE(rig, '-') as rig, COALESCE(claimed_by, '-') as claimed, shared_by FROM shared_beads WHERE $WHERE ORDER BY priority ASC, created_at DESC LIMIT 30;" -r csv 2>/dev/null | tail -n +2)

    if [ -n "$BEADS" ]; then
      printf "  %-10s %-6s %-4s %-16s %-14s %s\n" "ID" "Status" "P" "Rig" "Claimed By" "Title"
      echo "  ──────── ────── ──── ──────────────── ────────────── ─────────────────────"
      while IFS=',' read -r id title status prio rig claimed shared; do
        [ -z "$id" ] && continue
        case "$prio" in
          0) plabel="P0!" ;;
          1) plabel="P1" ;;
          3) plabel="P3" ;;
          *) plabel="P2" ;;
        esac
        # Truncate title
        title_short=$(echo "$title" | cut -c1-40)
        printf "  %-10s %-6s %-4s %-16s %-14s %s\n" "$id" "$status" "$plabel" "$rig" "$claimed" "$title_short"
      done <<< "$BEADS"
    else
      if [ "$UNCLAIMED" = true ]; then
        echo "  (no unclaimed beads)"
      else
        echo "  (no shared beads)"
      fi
    fi
    echo ""
    cd "$GT_ROOT"
    ;;

  share)
    BEAD_ID="$1"
    shift 2>/dev/null || true
    RIG=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --rig) RIG="$2"; shift 2 ;;
        *) shift ;;
      esac
    done

    if [ -z "$BEAD_ID" ]; then
      echo "Usage: gt mesh beads share <bead-id> [--rig <rig>]"
      exit 1
    fi

    # Read bead from local bd
    if ! command -v bd &>/dev/null; then
      echo "[error] bd (bead daemon) not found. Cannot read local beads."
      exit 1
    fi

    BEAD_JSON=$(bd show "$BEAD_ID" --json 2>/dev/null)
    if [ -z "$BEAD_JSON" ] || echo "$BEAD_JSON" | grep -q "not found"; then
      echo "[error] Bead '$BEAD_ID' not found locally"
      exit 1
    fi

    TITLE=$(echo "$BEAD_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)[0].get('title',''))" 2>/dev/null)
    DESC=$(echo "$BEAD_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)[0].get('description','')[:500])" 2>/dev/null)
    STATUS=$(echo "$BEAD_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)[0].get('status','open'))" 2>/dev/null)
    PRIORITY=$(echo "$BEAD_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)[0].get('priority',2))" 2>/dev/null)
    ISSUE_TYPE=$(echo "$BEAD_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)[0].get('issue_type','task'))" 2>/dev/null)
    LABELS=$(echo "$BEAD_JSON" | python3 -c "import json,sys; labels=json.load(sys.stdin)[0].get('labels',[]); print(','.join(labels) if isinstance(labels,list) else str(labels))" 2>/dev/null)

    _ensure_tables

    # Check if already shared
    EXISTING=$(dolt sql -q "SELECT bead_id FROM shared_beads WHERE bead_id = '$BEAD_ID';" -r csv 2>/dev/null | tail -n +2 | head -1)
    if [ -n "$EXISTING" ]; then
      echo "[warn] Bead '$BEAD_ID' is already shared on the mesh"
      echo "       Updating..."
      dolt sql -q "UPDATE shared_beads SET title = '$(echo "$TITLE" | sed "s/'/''/g")', description = '$(echo "$DESC" | sed "s/'/''/g")', status = '$STATUS', priority = $PRIORITY, updated_at = NOW() WHERE bead_id = '$BEAD_ID';" 2>/dev/null
    else
      # Escape single quotes in title/desc for SQL
      TITLE_ESC=$(echo "$TITLE" | sed "s/'/''/g")
      DESC_ESC=$(echo "$DESC" | sed "s/'/''/g")
      dolt sql -q "INSERT INTO shared_beads (bead_id, title, description, status, priority, issue_type, rig, shared_by, created_at, updated_at, labels) VALUES ('$BEAD_ID', '$TITLE_ESC', '$DESC_ESC', '$STATUS', $PRIORITY, '$ISSUE_TYPE', '$RIG', '$GT_ID', NOW(), NOW(), '$LABELS');" 2>/dev/null
    fi

    dolt add . 2>/dev/null || true
    dolt commit -m "mesh: $GT_ID shared bead $BEAD_ID" --allow-empty 2>/dev/null || true
    dolt push 2>/dev/null || true
    cd "$GT_ROOT"
    echo "Shared on mesh: $BEAD_ID — $TITLE"
    ;;

  claim)
    BEAD_ID="$1"
    if [ -z "$BEAD_ID" ]; then
      echo "Usage: gt mesh beads claim <bead-id>"
      exit 1
    fi

    _ensure_tables

    # Check bead exists
    BEAD_STATUS=$(dolt sql -q "SELECT status FROM shared_beads WHERE bead_id = '$BEAD_ID';" -r csv 2>/dev/null | tail -n +2 | head -1)
    if [ -z "$BEAD_STATUS" ]; then
      echo "[error] Bead '$BEAD_ID' not found on mesh"
      exit 1
    fi

    # Check not already claimed
    CURRENT_CLAIM=$(dolt sql -q "SELECT claimed_by FROM shared_beads WHERE bead_id = '$BEAD_ID';" -r csv 2>/dev/null | tail -n +2 | head -1)
    if [ -n "$CURRENT_CLAIM" ] && [ "$CURRENT_CLAIM" != "NULL" ] && [ "$CURRENT_CLAIM" != "" ]; then
      echo "[error] Bead '$BEAD_ID' already claimed by $CURRENT_CLAIM"
      exit 1
    fi

    # Check max claims
    if ! _check_max_claims "$GT_ID"; then
      exit 1
    fi

    # Claim it
    CLAIM_ID="claim-$(date +%s)-$(head -c 4 /dev/urandom | od -An -tx4 | tr -d ' ')"
    dolt sql -q "UPDATE shared_beads SET claimed_by = '$GT_ID', claimed_at = NOW(), status = 'in-progress', updated_at = NOW() WHERE bead_id = '$BEAD_ID';" 2>/dev/null
    dolt sql -q "INSERT INTO claims (id, bead_id, gt_id, status, claimed_at) VALUES ('$CLAIM_ID', '$BEAD_ID', '$GT_ID', 'active', NOW());" 2>/dev/null

    dolt add . 2>/dev/null || true
    dolt commit -m "mesh: $GT_ID claimed bead $BEAD_ID" --allow-empty 2>/dev/null || true
    dolt push 2>/dev/null || true
    cd "$GT_ROOT"
    echo "Claimed: $BEAD_ID (claim: $CLAIM_ID)"
    ;;

  unclaim)
    BEAD_ID="$1"
    if [ -z "$BEAD_ID" ]; then
      echo "Usage: gt mesh beads unclaim <bead-id>"
      exit 1
    fi

    _ensure_tables

    # Verify this GT owns the claim
    CURRENT_CLAIM=$(dolt sql -q "SELECT claimed_by FROM shared_beads WHERE bead_id = '$BEAD_ID';" -r csv 2>/dev/null | tail -n +2 | head -1)
    if [ "$CURRENT_CLAIM" != "$GT_ID" ]; then
      echo "[error] Bead '$BEAD_ID' is not claimed by you (claimed by: ${CURRENT_CLAIM:-nobody})"
      exit 1
    fi

    dolt sql -q "UPDATE shared_beads SET claimed_by = NULL, claimed_at = NULL, status = 'open', updated_at = NOW() WHERE bead_id = '$BEAD_ID';" 2>/dev/null
    dolt sql -q "UPDATE claims SET status = 'released', released_at = NOW() WHERE bead_id = '$BEAD_ID' AND gt_id = '$GT_ID' AND status = 'active';" 2>/dev/null

    dolt add . 2>/dev/null || true
    dolt commit -m "mesh: $GT_ID released bead $BEAD_ID" --allow-empty 2>/dev/null || true
    dolt push 2>/dev/null || true
    cd "$GT_ROOT"
    echo "Released: $BEAD_ID (now unclaimed)"
    ;;

  status)
    BEAD_ID="$1"
    NEW_STATUS="$2"
    if [ -z "$BEAD_ID" ] || [ -z "$NEW_STATUS" ]; then
      echo "Usage: gt mesh beads status <bead-id> <open|in-progress|done|closed>"
      exit 1
    fi

    _ensure_tables

    dolt sql -q "UPDATE shared_beads SET status = '$NEW_STATUS', updated_at = NOW() WHERE bead_id = '$BEAD_ID';" 2>/dev/null

    dolt add . 2>/dev/null || true
    dolt commit -m "mesh: $GT_ID set $BEAD_ID status to $NEW_STATUS" --allow-empty 2>/dev/null || true
    dolt push 2>/dev/null || true
    cd "$GT_ROOT"
    echo "Updated: $BEAD_ID → $NEW_STATUS"
    ;;

  *)
    echo "Usage: gt mesh beads <list|share|claim|unclaim|status>"
    echo ""
    echo "  list [--unclaimed] [--rig <rig>]     List shared beads"
    echo "  share <bead-id> [--rig <rig>]        Share a local bead to mesh"
    echo "  claim <bead-id>                       Claim an unclaimed bead"
    echo "  unclaim <bead-id>                     Release a claimed bead"
    echo "  status <bead-id> <status>             Update bead status"
    exit 1
    ;;
esac

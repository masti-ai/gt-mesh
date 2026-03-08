#!/bin/bash
# GT Mesh — Self-Improving Loop
#
# Every bug, friction point, and insight gets logged, fixed, and shared.
# The mesh gets smarter every time an agent uses it.
#
# Usage:
#   mesh-improve.sh report <title> [--fix <desc>] [--severity <level>] [--command <cmd>]
#   mesh-improve.sh status                Show improvement stats
#   mesh-improve.sh review                Review pending improvements
#   mesh-improve.sh graduate <id>         Graduate a finding to shared knowledge
#   mesh-improve.sh history [N]           Show recent improvements

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"
CLONE_DIR=$(grep "clone_dir:" "$MESH_YAML" 2>/dev/null | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"
DOLTHUB_DB="deepwork/gt-agent-mail"
TELEMETRY_FILE="$GT_ROOT/.mesh-telemetry.jsonl"
KNOWLEDGE_DIR="$GT_ROOT/.mesh-config/knowledge"

if [ ! -f "$MESH_YAML" ]; then
  echo "[error] Not in a mesh. Run: gt mesh init"
  exit 1
fi

GT_ID=$(grep "^  id:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')

_ensure_clone() {
  if [ ! -d "$CLONE_DIR/.dolt" ]; then
    dolt clone "$DOLTHUB_DB" "$CLONE_DIR" 2>/dev/null || {
      echo "[error] Failed to connect to DoltHub"
      exit 1
    }
  fi
  cd "$CLONE_DIR"
  dolt add . 2>/dev/null
  if dolt diff --staged --stat 2>/dev/null | grep -qi "row"; then
    dolt commit -m "mesh: pre-improve commit from $GT_ID" --allow-empty 2>/dev/null || true
  fi
  dolt pull 2>/dev/null || true
}

_ensure_tables() {
  dolt sql -q "CREATE TABLE IF NOT EXISTS mesh_improvements (
    id VARCHAR(64) PRIMARY KEY,
    gt_id VARCHAR(64) NOT NULL,
    category VARCHAR(32) NOT NULL,
    severity VARCHAR(16) NOT NULL DEFAULT 'medium',
    command VARCHAR(64),
    title VARCHAR(256) NOT NULL,
    description TEXT,
    error_output TEXT,
    proposed_fix TEXT,
    fix_script VARCHAR(256),
    status VARCHAR(32) DEFAULT 'reported',
    confirmed_by VARCHAR(64),
    fixed_by VARCHAR(64),
    fix_commit VARCHAR(128),
    votes INT DEFAULT 1,
    created_at DATETIME,
    updated_at DATETIME,
    INDEX idx_status (status),
    INDEX idx_command (command)
  );" 2>/dev/null || true

  dolt sql -q "CREATE TABLE IF NOT EXISTS mesh_knowledge_entries (
    id VARCHAR(64) PRIMARY KEY,
    category VARCHAR(32) NOT NULL,
    title VARCHAR(256) NOT NULL,
    content TEXT NOT NULL,
    source_improvement_id VARCHAR(64),
    contributed_by VARCHAR(64),
    confirmed_count INT DEFAULT 1,
    pack_name VARCHAR(128),
    created_at DATETIME,
    updated_at DATETIME
  );" 2>/dev/null || true
}

SUBCMD="${1:-help}"
shift 2>/dev/null || true

case "$SUBCMD" in

  report)
    TITLE="$1"
    shift 2>/dev/null || true

    FIX="" SEVERITY="medium" COMMAND="" CATEGORY="insight" DESCRIPTION=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --fix) FIX="$2"; shift 2 ;;
        --severity) SEVERITY="$2"; shift 2 ;;
        --command) COMMAND="$2"; shift 2 ;;
        --category) CATEGORY="$2"; shift 2 ;;
        --desc) DESCRIPTION="$2"; shift 2 ;;
        *) shift ;;
      esac
    done

    if [ -z "$TITLE" ]; then
      echo "Usage: gt mesh improve report <title> [--fix <desc>] [--severity critical|high|medium|low] [--command <cmd>] [--category bug|friction|insight|pattern]"
      exit 1
    fi

    # Validate severity
    case "$SEVERITY" in
      critical|high|medium|low) ;;
      *) SEVERITY="medium" ;;
    esac

    # Validate category
    case "$CATEGORY" in
      bug|friction|insight|pattern) ;;
      *) CATEGORY="insight" ;;
    esac

    # Validate/sanitize command if provided
    if [ -n "$COMMAND" ] && ! echo "$COMMAND" | grep -qE "^[a-zA-Z0-9_-]+$"; then
      echo "[warn] Invalid command format, ignoring"
      COMMAND=""
    fi

    _ensure_clone
    _ensure_tables

    IMP_ID="imp-$(date +%s)-${RANDOM}"

    # Escape for SQL (defense in depth)
    TITLE_ESC=$(echo "$TITLE" | sed "s/'/''/g")
    FIX_ESC=$(echo "$FIX" | sed "s/'/''/g")
    DESC_ESC=$(echo "$DESCRIPTION" | sed "s/'/''/g")
    CATEGORY_ESC=$(echo "$CATEGORY" | sed "s/'/''/g")
    SEVERITY_ESC=$(echo "$SEVERITY" | sed "s/'/''/g")
    COMMAND_ESC=$(echo "$COMMAND" | sed "s/'/''/g")

    dolt sql -q "INSERT INTO mesh_improvements (id, gt_id, category, severity, command, title, description, proposed_fix, status, votes, created_at, updated_at)
      VALUES ('$IMP_ID', '$GT_ID', '$CATEGORY_ESC', '$SEVERITY_ESC', '$COMMAND_ESC', '$TITLE_ESC', '$DESC_ESC', '$FIX_ESC', 'reported', 1, NOW(), NOW());" 2>/dev/null

    dolt add . 2>/dev/null || true
    dolt commit -m "mesh: $GT_ID reported improvement: $TITLE" --allow-empty 2>/dev/null || true
    dolt push 2>/dev/null || true

    echo "[improve] Reported: $TITLE"
    echo "  ID:       $IMP_ID"
    echo "  Category: $CATEGORY"
    echo "  Severity: $SEVERITY"
    [ -n "$FIX" ] && echo "  Fix:      $FIX"
    echo ""

    # Also log to auto-sync activity
    MESH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
    GT_ROOT="$GT_ROOT" MESH_YAML="$MESH_YAML" bash "$MESH_DIR/scripts/mesh-auto-sync.sh" log "Improvement reported: $TITLE" 2>/dev/null || true

    cd "$GT_ROOT"
    ;;

  status)
    _ensure_clone
    _ensure_tables

    REPORTED=$(dolt sql -q "SELECT COUNT(*) FROM mesh_improvements WHERE status = 'reported';" -r csv 2>/dev/null | tail -n +2 | head -1)
    CONFIRMED=$(dolt sql -q "SELECT COUNT(*) FROM mesh_improvements WHERE status = 'confirmed';" -r csv 2>/dev/null | tail -n +2 | head -1)
    FIXED=$(dolt sql -q "SELECT COUNT(*) FROM mesh_improvements WHERE status = 'fixed';" -r csv 2>/dev/null | tail -n +2 | head -1)
    PUBLISHED=$(dolt sql -q "SELECT COUNT(*) FROM mesh_improvements WHERE status = 'published';" -r csv 2>/dev/null | tail -n +2 | head -1)
    KNOWLEDGE=$(dolt sql -q "SELECT COUNT(*) FROM mesh_knowledge_entries;" -r csv 2>/dev/null | tail -n +2 | head -1)

    # Telemetry stats
    TOTAL_CMDS=0 FAILURES=0
    if [ -f "$TELEMETRY_FILE" ]; then
      TOTAL_CMDS=$(wc -l < "$TELEMETRY_FILE")
      FAILURES=$(grep -c '"exit":[^0]' "$TELEMETRY_FILE" 2>/dev/null || echo 0)
    fi

    echo "==========================================="
    echo "  Mesh Self-Improving Loop — Status"
    echo "==========================================="
    echo ""
    echo "  Improvements:"
    echo "    Reported:   ${REPORTED:-0}"
    echo "    Confirmed:  ${CONFIRMED:-0}"
    echo "    Fixed:      ${FIXED:-0}"
    echo "    Published:  ${PUBLISHED:-0}"
    echo ""
    echo "  Knowledge entries: ${KNOWLEDGE:-0}"
    echo ""
    echo "  Telemetry:"
    echo "    Commands tracked: $TOTAL_CMDS"
    echo "    Failures:         $FAILURES"
    echo ""

    cd "$GT_ROOT"
    ;;

  review)
    _ensure_clone
    _ensure_tables

    echo "==========================================="
    echo "  Pending Improvements"
    echo "==========================================="
    echo ""

    ITEMS=$(dolt sql -q "SELECT CONCAT(id, '|', category, '|', severity, '|', gt_id, '|', COALESCE(command, ''), '|', title) FROM mesh_improvements WHERE status IN ('reported', 'confirmed') ORDER BY FIELD(severity, 'critical', 'high', 'medium', 'low'), created_at;" -r csv 2>/dev/null | tail -n +2 | sed 's/^"//;s/"$//')

    if [ -z "$ITEMS" ]; then
      echo "  No pending improvements."
    else
      printf "  %-16s %-10s %-8s %-12s %-10s %s\n" "ID" "CATEGORY" "SEV" "REPORTER" "CMD" "TITLE"
      printf "  %-16s %-10s %-8s %-12s %-10s %s\n" "--" "--------" "---" "--------" "---" "-----"
      while IFS='|' read -r id cat sev reporter cmd title; do
        [ -z "$id" ] && continue
        printf "  %-16s %-10s %-8s %-12s %-10s %s\n" "${id:0:16}" "$cat" "$sev" "$reporter" "${cmd:-—}" "${title:0:40}"
      done <<< "$ITEMS"
    fi
    echo ""

    cd "$GT_ROOT"
    ;;

  graduate)
    IMP_ID="$1"
    if [ -z "$IMP_ID" ]; then
      echo "Usage: gt mesh improve graduate <improvement-id>"
      exit 1
    fi

    # Validate improvement ID format
    if ! echo "$IMP_ID" | grep -qE "^[a-zA-Z0-9_-]+$"; then
      echo "[error] Invalid improvement ID format"
      exit 1
    fi

    _ensure_clone
    _ensure_tables

    # Escape for SQL
    IMP_ID_ESC=$(echo "$IMP_ID" | sed "s/'/''/g")

    # Check improvement exists
    IMP_TITLE=$(dolt sql -q "SELECT title FROM mesh_improvements WHERE id = '$IMP_ID_ESC';" -r csv 2>/dev/null | tail -n +2 | head -1 | sed 's/^"//;s/"$//')
    if [ -z "$IMP_TITLE" ]; then
      echo "[error] Improvement '$IMP_ID' not found"
      exit 1
    fi

    IMP_CAT=$(dolt sql -q "SELECT category FROM mesh_improvements WHERE id = '$IMP_ID_ESC';" -r csv 2>/dev/null | tail -n +2 | head -1)
    IMP_DESC=$(dolt sql -q "SELECT COALESCE(description, '') FROM mesh_improvements WHERE id = '$IMP_ID_ESC';" -r csv 2>/dev/null | tail -n +2 | head -1 | sed 's/^"//;s/"$//')
    IMP_FIX=$(dolt sql -q "SELECT COALESCE(proposed_fix, '') FROM mesh_improvements WHERE id = '$IMP_ID_ESC';" -r csv 2>/dev/null | tail -n +2 | head -1 | sed 's/^"//;s/"$//')

    # Build knowledge content (sanitize markdown - remove # prefix from title)
    IMP_TITLE_SAFE=$(printf '%s' "$IMP_TITLE" | sed 's/^#*//g')
    KNOWLEDGE_CONTENT="### $IMP_TITLE_SAFE"
    [ -n "$IMP_DESC" ] && KNOWLEDGE_CONTENT="$KNOWLEDGE_CONTENT
$IMP_DESC"
    [ -n "$IMP_FIX" ] && KNOWLEDGE_CONTENT="$KNOWLEDGE_CONTENT
**Fix:** $IMP_FIX"

    KNOWLEDGE_CONTENT_ESC=$(echo "$KNOWLEDGE_CONTENT" | sed "s/'/''/g")
    IMP_TITLE_ESC=$(echo "$IMP_TITLE_SAFE" | sed "s/'/''/g")
    IMP_CAT_ESC=$(echo "$IMP_CAT" | sed "s/'/''/g")

    # Create knowledge entry
    K_ID="k-$(date +%s)-${RANDOM}"
    dolt sql -q "INSERT INTO mesh_knowledge_entries (id, category, title, content, source_improvement_id, contributed_by, created_at, updated_at)
      VALUES ('$K_ID', '$IMP_CAT_ESC', '$IMP_TITLE_ESC', '$KNOWLEDGE_CONTENT_ESC', '$IMP_ID_ESC', '$GT_ID', NOW(), NOW());" 2>/dev/null

    # Update improvement status
    dolt sql -q "UPDATE mesh_improvements SET status = 'published', fixed_by = '$GT_ID', updated_at = NOW() WHERE id = '$IMP_ID_ESC';" 2>/dev/null

    # Append to local knowledge file
    mkdir -p "$KNOWLEDGE_DIR"
    LEARNINGS="$KNOWLEDGE_DIR/mesh-learnings.md"
    if [ ! -f "$LEARNINGS" ]; then
      echo "# Mesh Learnings — Auto-accumulated" > "$LEARNINGS"
      echo "" >> "$LEARNINGS"
      echo "_This file is automatically updated as the mesh learns from usage._" >> "$LEARNINGS"
      echo "" >> "$LEARNINGS"
    fi
    echo "" >> "$LEARNINGS"
    echo "$KNOWLEDGE_CONTENT" >> "$LEARNINGS"
    echo "" >> "$LEARNINGS"

    dolt add . 2>/dev/null || true
    dolt commit -m "mesh: graduated improvement $IMP_ID to knowledge" --allow-empty 2>/dev/null || true
    dolt push 2>/dev/null || true

    echo "[improve] Graduated to knowledge:"
    echo "  Title: $IMP_TITLE"
    echo "  Knowledge ID: $K_ID"
    echo "  Written to: $LEARNINGS"
    echo ""

    # Broadcast to peers
    MESH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
    GT_ROOT="$GT_ROOT" MESH_YAML="$MESH_YAML" bash "$MESH_DIR/scripts/mesh-auto-sync.sh" broadcast "[Knowledge] New learning: $IMP_TITLE" "$KNOWLEDGE_CONTENT" 2>/dev/null || true

    cd "$GT_ROOT"
    ;;

  history)
    LIMIT="${1:-20}"

    _ensure_clone
    _ensure_tables

    echo "==========================================="
    echo "  Improvement History (last $LIMIT)"
    echo "==========================================="
    echo ""

    dolt sql -q "SELECT id, gt_id, category, severity, status, title, CAST(created_at AS CHAR) as time FROM mesh_improvements ORDER BY created_at DESC LIMIT $LIMIT;" 2>/dev/null || echo "(no improvements yet)"
    echo ""

    KNOWLEDGE_COUNT=$(dolt sql -q "SELECT COUNT(*) FROM mesh_knowledge_entries;" -r csv 2>/dev/null | tail -n +2 | head -1)
    echo "  Total knowledge entries: ${KNOWLEDGE_COUNT:-0}"
    echo ""

    cd "$GT_ROOT"
    ;;

  *)
    echo "GT Mesh Self-Improving Loop"
    echo ""
    echo "Usage: gt mesh improve <command>"
    echo ""
    echo "Commands:"
    echo "  report <title>      Report a finding (bug, friction, insight, pattern)"
    echo "  status              Show improvement stats & telemetry"
    echo "  review              Review pending improvements"
    echo "  graduate <id>       Graduate a finding to shared knowledge"
    echo "  history [N]         Show recent improvements"
    echo ""
    echo "Options for report:"
    echo "  --fix <description>     Proposed fix"
    echo "  --severity <level>      critical|high|medium|low (default: medium)"
    echo "  --command <cmd>         Which mesh command triggered this"
    echo "  --category <type>       bug|friction|insight|pattern (default: insight)"
    echo ""
    echo "The loop: USE -> DETECT -> LOG -> FIX -> PUBLISH -> PROPAGATE"
    echo "Every finding makes the mesh smarter for all nodes."
    ;;
esac

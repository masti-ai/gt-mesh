#!/bin/bash
# GT Mesh — Mesh rules management
#
# Usage: mesh-rules.sh list | set <rule> <value> | reset

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"

if [ ! -f "$MESH_YAML" ]; then
  echo "[error] Not in a mesh. Run: gt mesh init"
  exit 1
fi

GT_ID=$(grep "^  id:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR=$(grep "clone_dir:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"

SUBCMD="${1:-list}"
shift 2>/dev/null || true

# Ensure mesh_rules table exists
_ensure_table() {
  cd "$CLONE_DIR"
  dolt pull 2>/dev/null || true
  dolt sql -q "CREATE TABLE IF NOT EXISTS mesh_rules (
    rule_name VARCHAR(128) PRIMARY KEY,
    rule_value VARCHAR(512),
    category VARCHAR(32),
    set_by VARCHAR(64),
    updated_at DATETIME
  );" 2>/dev/null || true
}

# Seed defaults if table is empty
_seed_defaults() {
  local COUNT=$(dolt sql -q "SELECT COUNT(*) FROM mesh_rules;" -r csv 2>/dev/null | tail -1)
  if [ "$COUNT" = "0" ] || [ -z "$COUNT" ]; then
    dolt sql -q "INSERT INTO mesh_rules VALUES
      ('branch_format', 'gt/{id}/{issue}-{desc}', 'work', '$GT_ID', NOW()),
      ('pr_target', 'dev', 'work', '$GT_ID', NOW()),
      ('commit_format', 'conventional', 'work', '$GT_ID', NOW()),
      ('require_issue_reference', 'true', 'work', '$GT_ID', NOW()),
      ('max_concurrent_claims', '3', 'work', '$GT_ID', NOW()),
      ('require_review', 'true', 'review', '$GT_ID', NOW()),
      ('no_force_push', 'true', 'security', '$GT_ID', NOW()),
      ('no_secrets_in_commits', 'true', 'security', '$GT_ID', NOW());" 2>/dev/null || true
    dolt add . 2>/dev/null || true
    dolt commit -m "mesh: seed default rules" --allow-empty 2>/dev/null || true
  fi
}

case "$SUBCMD" in
  list)
    _ensure_table
    _seed_defaults
    echo "==========================================="
    echo "  Mesh Rules"
    echo "==========================================="
    echo ""
    RULES=$(dolt sql -q "SELECT rule_name, rule_value, category FROM mesh_rules ORDER BY category, rule_name;" -r csv 2>/dev/null | tail -n +2)
    LAST_CAT=""
    while IFS=',' read -r name value cat; do
      [ -z "$name" ] && continue
      if [ "$cat" != "$LAST_CAT" ]; then
        echo "  [$cat]"
        LAST_CAT="$cat"
      fi
      printf "    %-30s = %s\n" "$name" "$value"
    done <<< "$RULES"
    echo ""
    echo "  Change a rule: gt mesh rules set <name> <value>"
    cd "$GT_ROOT"
    ;;

  set)
    RULE_NAME="$1"
    RULE_VALUE="$2"
    if [ -z "$RULE_NAME" ] || [ -z "$RULE_VALUE" ]; then
      echo "Usage: gt mesh rules set <rule_name> <value>"
      exit 1
    fi
    _ensure_table
    # Preserve category if rule exists, default to 'custom'
    EXISTING_CAT=$(dolt sql -q "SELECT COALESCE(category, 'custom') FROM mesh_rules WHERE rule_name = '$RULE_NAME';" -r csv 2>/dev/null | tail -1)
    CATEGORY="${EXISTING_CAT:-custom}"
    dolt sql -q "REPLACE INTO mesh_rules (rule_name, rule_value, category, set_by, updated_at) VALUES ('$RULE_NAME', '$RULE_VALUE', '$CATEGORY', '$GT_ID', NOW());" 2>/dev/null
    dolt add . 2>/dev/null || true
    dolt commit -m "mesh: $GT_ID set rule $RULE_NAME = $RULE_VALUE" --allow-empty 2>/dev/null || true
    dolt push 2>/dev/null || true
    cd "$GT_ROOT"
    echo "Rule set: $RULE_NAME = $RULE_VALUE"
    ;;

  reset)
    _ensure_table
    dolt sql -q "DELETE FROM mesh_rules;" 2>/dev/null
    _seed_defaults
    dolt push 2>/dev/null || true
    cd "$GT_ROOT"
    echo "Rules reset to defaults"
    ;;

  *)
    echo "Usage: gt mesh rules <list|set|reset>"
    exit 1
    ;;
esac

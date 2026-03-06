#!/bin/bash
# GT Mesh — Shared skills registry
#
# Usage: mesh-skills.sh list
#        mesh-skills.sh publish <skill-name> <skill-path>
#        mesh-skills.sh install <skill-name>
#        mesh-skills.sh info <skill-name>

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
SKILLS_DIR="${HOME}/.claude/skills"

SUBCMD="${1:-list}"
shift 2>/dev/null || true

_ensure_table() {
  cd "$CLONE_DIR"
  dolt pull 2>/dev/null || true

  dolt sql -q "CREATE TABLE IF NOT EXISTS shared_skills (
    name VARCHAR(128) PRIMARY KEY,
    description VARCHAR(512),
    published_by VARCHAR(64),
    version VARCHAR(16) DEFAULT '1.0',
    content TEXT,
    installs INT DEFAULT 0,
    published_at DATETIME,
    updated_at DATETIME
  );" 2>/dev/null || true
}

case "$SUBCMD" in
  list)
    _ensure_table

    echo "==========================================="
    echo "  Mesh Skills Registry"
    echo "==========================================="
    echo ""

    SKILLS=$(dolt sql -q "SELECT CONCAT(name, '|', published_by, '|', version, '|', installs) FROM shared_skills ORDER BY installs DESC, name;" -r csv 2>/dev/null | tail -n +2 | sed 's/^"//;s/"$//')

    if [ -n "$SKILLS" ]; then
      printf "  %-24s %-8s %-14s %s\n" "Name" "Version" "Published By" "Installs"
      echo "  ────────────────────── ──────── ────────────── ────────"
      while IFS='|' read -r name pub ver installs; do
        [ -z "$name" ] && continue
        printf "  %-24s %-8s %-14s %s\n" "$name" "$ver" "$pub" "$installs"
      done <<< "$SKILLS"
    else
      echo "  (no shared skills — be the first to publish!)"
    fi
    echo ""
    echo "  Publish:  gt mesh skills publish <name> <path/to/SKILL.md>"
    echo "  Install:  gt mesh skills install <name>"
    cd "$GT_ROOT"
    ;;

  publish)
    SKILL_NAME="$1"
    SKILL_PATH="$2"

    if [ -z "$SKILL_NAME" ] || [ -z "$SKILL_PATH" ]; then
      echo "Usage: gt mesh skills publish <skill-name> <path/to/SKILL.md>"
      exit 1
    fi

    if [ ! -f "$SKILL_PATH" ]; then
      echo "[error] Skill file not found: $SKILL_PATH"
      exit 1
    fi

    # Read skill content
    CONTENT=$(cat "$SKILL_PATH")
    CONTENT_ESC=$(echo "$CONTENT" | sed "s/'/''/g")

    # Extract description from YAML frontmatter
    DESC=$(echo "$CONTENT" | sed -n '/^---$/,/^---$/p' | grep "description:" | head -1 | sed "s/.*description: *['\"]\\{0,1\\}\\(.*\\)['\"]\\{0,1\\}/\\1/" | cut -c1-500)
    DESC_ESC=$(echo "$DESC" | sed "s/'/''/g")

    _ensure_table

    # Upsert
    EXISTING=$(dolt sql -q "SELECT name FROM shared_skills WHERE name = '$SKILL_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1)
    if [ -n "$EXISTING" ]; then
      dolt sql -q "UPDATE shared_skills SET description = '$DESC_ESC', content = '$CONTENT_ESC', published_by = '$GT_ID', updated_at = NOW() WHERE name = '$SKILL_NAME';" 2>/dev/null
      echo "Updated skill: $SKILL_NAME"
    else
      dolt sql -q "INSERT INTO shared_skills (name, description, published_by, version, content, installs, published_at, updated_at) VALUES ('$SKILL_NAME', '$DESC_ESC', '$GT_ID', '1.0', '$CONTENT_ESC', 0, NOW(), NOW());" 2>/dev/null
      echo "Published skill: $SKILL_NAME"
    fi

    dolt add . 2>/dev/null || true
    dolt commit -m "mesh: $GT_ID published skill $SKILL_NAME" --allow-empty 2>/dev/null || true
    dolt push 2>/dev/null || true
    cd "$GT_ROOT"
    ;;

  install)
    SKILL_NAME="$1"
    if [ -z "$SKILL_NAME" ]; then
      echo "Usage: gt mesh skills install <skill-name>"
      exit 1
    fi

    _ensure_table

    # Fetch skill content
    CONTENT=$(dolt sql -q "SELECT content FROM shared_skills WHERE name = '$SKILL_NAME';" -r csv 2>/dev/null | tail -n +2)
    if [ -z "$CONTENT" ]; then
      echo "[error] Skill '$SKILL_NAME' not found on mesh"
      echo "        Run: gt mesh skills list"
      exit 1
    fi

    # Install to Claude Code skills directory
    DEST="$SKILLS_DIR/$SKILL_NAME"
    mkdir -p "$DEST"

    # Write content (dolt CSV wraps in quotes — strip them)
    echo "$CONTENT" | sed 's/^"//;s/"$//' | sed 's/""/"/g' > "$DEST/SKILL.md"

    # Increment install count
    dolt sql -q "UPDATE shared_skills SET installs = installs + 1 WHERE name = '$SKILL_NAME';" 2>/dev/null
    dolt add . 2>/dev/null || true
    dolt commit -m "mesh: $GT_ID installed skill $SKILL_NAME" --allow-empty 2>/dev/null || true
    dolt push 2>/dev/null || true

    cd "$GT_ROOT"
    echo "Installed: $SKILL_NAME → $DEST/SKILL.md"
    echo "Claude Code will pick it up on next session."
    ;;

  info)
    SKILL_NAME="$1"
    if [ -z "$SKILL_NAME" ]; then
      echo "Usage: gt mesh skills info <skill-name>"
      exit 1
    fi

    _ensure_table

    # Query each field separately to avoid CSV comma issues
    _skill_field() {
      dolt sql -q "SELECT $1 FROM shared_skills WHERE name = '$SKILL_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1 | sed 's/^"//;s/"$//'
    }
    S_NAME=$(_skill_field "name")
    if [ -z "$S_NAME" ]; then
      echo "[error] Skill '$SKILL_NAME' not found"
      exit 1
    fi
    S_PUB=$(_skill_field "published_by")
    S_VER=$(_skill_field "version")
    S_DL=$(_skill_field "installs")
    S_PDATE=$(_skill_field "CAST(published_at AS CHAR)")
    S_UDATE=$(_skill_field "CAST(updated_at AS CHAR)")

    echo "==========================================="
    echo "  Skill: $S_NAME"
    echo "==========================================="
    echo ""
    echo "  Published by: $S_PUB"
    echo "  Version:      $S_VER"
    echo "  Installs:     $S_DL"
    echo "  Published:    $S_PDATE"
    echo "  Updated:      $S_UDATE"
    echo ""

    # Check if installed locally
    if [ -f "$SKILLS_DIR/$SKILL_NAME/SKILL.md" ]; then
      echo "  Status: Installed locally"
    else
      echo "  Status: Not installed — run: gt mesh skills install $SKILL_NAME"
    fi
    echo ""
    cd "$GT_ROOT"
    ;;

  *)
    echo "Usage: gt mesh skills <list|publish|install|info>"
    echo ""
    echo "  list                                  List all shared skills"
    echo "  publish <name> <path/to/SKILL.md>     Publish a skill to mesh"
    echo "  install <name>                        Install a skill from mesh"
    echo "  info <name>                           Show skill details"
    exit 1
    ;;
esac

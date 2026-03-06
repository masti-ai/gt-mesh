#!/bin/bash
# GT Mesh — Packs: shareable bundles of mesh knowledge
#
# A pack bundles skills, roles, rules, templates, and knowledge into
# a single installable unit. Published to DoltHub, browsable by any node.
#
# Usage:
#   mesh-packs.sh list                          Browse available packs
#   mesh-packs.sh info <pack-name>              Show pack details
#   mesh-packs.sh install <pack-name>           Install a pack
#   mesh-packs.sh uninstall <pack-name>         Remove an installed pack
#   mesh-packs.sh publish <dir>                 Publish a pack from a directory
#   mesh-packs.sh create <name>                 Scaffold a new pack
#   mesh-packs.sh installed                     List installed packs
#   mesh-packs.sh search <query>                Search packs by keyword

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"
CLONE_DIR=$(grep "clone_dir:" "$MESH_YAML" 2>/dev/null | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"
DOLTHUB_DB="deepwork/gt-agent-mail"
PACKS_DIR="$GT_ROOT/.mesh-packs"

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
    dolt commit -m "mesh: pre-pack commit from $GT_ID" --allow-empty 2>/dev/null || true
  fi
  dolt pull 2>/dev/null || true
}

_ensure_tables() {
  dolt sql -q "CREATE TABLE IF NOT EXISTS mesh_packs (
    name VARCHAR(128) PRIMARY KEY,
    version VARCHAR(16) NOT NULL DEFAULT '1.0.0',
    description VARCHAR(512),
    author VARCHAR(64),
    author_github VARCHAR(64),
    tags VARCHAR(512),
    contains_skills INT DEFAULT 0,
    contains_roles INT DEFAULT 0,
    contains_rules INT DEFAULT 0,
    contains_templates INT DEFAULT 0,
    contains_knowledge INT DEFAULT 0,
    installs INT DEFAULT 0,
    pack_hash VARCHAR(128),
    published_at DATETIME,
    updated_at DATETIME
  );" 2>/dev/null || true

  dolt sql -q "CREATE TABLE IF NOT EXISTS mesh_pack_files (
    pack_name VARCHAR(128) NOT NULL,
    path VARCHAR(256) NOT NULL,
    file_type VARCHAR(32) NOT NULL,
    content LONGTEXT,
    hash VARCHAR(128),
    PRIMARY KEY (pack_name, path)
  );" 2>/dev/null || true
}

_read_pack_yaml() {
  local PACK_DIR="$1"
  local FIELD="$2"
  grep "^${FIELD}:" "$PACK_DIR/pack.yaml" 2>/dev/null | head -1 | sed 's/^[^:]*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/'
}

_read_pack_yaml_list() {
  local PACK_DIR="$1"
  local SECTION="$2"
  # Extract items under a section (lines starting with "  - ")
  awk "/^${SECTION}:/{found=1;next} /^[^ ]/{found=0} found && /^  - /{gsub(/^  - /,\"\"); print}" "$PACK_DIR/pack.yaml" 2>/dev/null
}

SUBCMD="${1:-help}"
shift 2>/dev/null || true

case "$SUBCMD" in

  list)
    _ensure_clone
    _ensure_tables

    echo "==========================================="
    echo "  Mesh Pack Registry"
    echo "==========================================="
    echo ""

    PACKS=$(dolt sql -q "SELECT CONCAT(name, '|', version, '|', author, '|', installs, '|', COALESCE(description, '')) FROM mesh_packs ORDER BY installs DESC, name;" -r csv 2>/dev/null | tail -n +2 | sed 's/^"//;s/"$//')

    if [ -z "$PACKS" ]; then
      echo "  No packs published yet."
      echo ""
      echo "  Create one:  gt mesh packs create my-pack"
      echo "  Publish it:  gt mesh packs publish ./my-pack"
    else
      printf "  %-24s %-8s %-14s %-6s %s\n" "NAME" "VER" "AUTHOR" "INST" "DESCRIPTION"
      printf "  %-24s %-8s %-14s %-6s %s\n" "----" "---" "------" "----" "-----------"
      while IFS='|' read -r name ver author inst desc; do
        [ -z "$name" ] && continue
        # Truncate description
        [ ${#desc} -gt 40 ] && desc="${desc:0:37}..."
        # Mark installed packs
        MARKER=" "
        [ -d "$PACKS_DIR/$name" ] && MARKER="*"
        printf "  %s%-23s %-8s %-14s %-6s %s\n" "$MARKER" "$name" "$ver" "$author" "$inst" "$desc"
      done <<< "$PACKS"
      echo ""
      echo "  * = installed locally"
    fi
    echo ""
    cd "$GT_ROOT"
    ;;

  search)
    QUERY="$1"
    if [ -z "$QUERY" ]; then
      echo "Usage: gt mesh packs search <query>"
      exit 1
    fi

    _ensure_clone
    _ensure_tables

    echo "Searching for '$QUERY'..."
    echo ""

    RESULTS=$(dolt sql -q "SELECT CONCAT(name, '|', version, '|', author, '|', COALESCE(description, '')) FROM mesh_packs WHERE name LIKE '%${QUERY}%' OR description LIKE '%${QUERY}%' OR tags LIKE '%${QUERY}%' ORDER BY installs DESC;" -r csv 2>/dev/null | tail -n +2 | sed 's/^"//;s/"$//')

    if [ -z "$RESULTS" ]; then
      echo "  No packs found matching '$QUERY'"
    else
      while IFS='|' read -r name ver author desc; do
        [ -z "$name" ] && continue
        MARKER=" "
        [ -d "$PACKS_DIR/$name" ] && MARKER="*"
        echo "  ${MARKER}${name} (v${ver}) by ${author}"
        [ -n "$desc" ] && echo "    $desc"
      done <<< "$RESULTS"
    fi
    echo ""
    cd "$GT_ROOT"
    ;;

  info)
    PACK_NAME="$1"
    if [ -z "$PACK_NAME" ]; then
      echo "Usage: gt mesh packs info <pack-name>"
      exit 1
    fi

    _ensure_clone
    _ensure_tables

    # Check if pack exists
    EXISTS=$(dolt sql -q "SELECT name FROM mesh_packs WHERE name = '$PACK_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1)
    if [ -z "$EXISTS" ]; then
      echo "[error] Pack '$PACK_NAME' not found"
      exit 1
    fi

    # Fetch fields individually to avoid CSV mangling
    VER=$(dolt sql -q "SELECT version FROM mesh_packs WHERE name = '$PACK_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1)
    DESC=$(dolt sql -q "SELECT COALESCE(description, '') FROM mesh_packs WHERE name = '$PACK_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1 | sed 's/^"//;s/"$//')
    AUTHOR=$(dolt sql -q "SELECT author FROM mesh_packs WHERE name = '$PACK_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1)
    AUTHOR_GH=$(dolt sql -q "SELECT COALESCE(author_github, '') FROM mesh_packs WHERE name = '$PACK_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1)
    TAGS=$(dolt sql -q "SELECT COALESCE(tags, '') FROM mesh_packs WHERE name = '$PACK_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1 | sed 's/^"//;s/"$//')
    INSTALLS=$(dolt sql -q "SELECT installs FROM mesh_packs WHERE name = '$PACK_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1)
    N_SKILLS=$(dolt sql -q "SELECT contains_skills FROM mesh_packs WHERE name = '$PACK_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1)
    N_ROLES=$(dolt sql -q "SELECT contains_roles FROM mesh_packs WHERE name = '$PACK_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1)
    N_RULES=$(dolt sql -q "SELECT contains_rules FROM mesh_packs WHERE name = '$PACK_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1)
    N_TEMPLATES=$(dolt sql -q "SELECT contains_templates FROM mesh_packs WHERE name = '$PACK_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1)
    N_KNOWLEDGE=$(dolt sql -q "SELECT contains_knowledge FROM mesh_packs WHERE name = '$PACK_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1)
    PUBLISHED=$(dolt sql -q "SELECT CAST(published_at AS CHAR) FROM mesh_packs WHERE name = '$PACK_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1)

    echo "==========================================="
    echo "  Pack: $PACK_NAME"
    echo "==========================================="
    echo ""
    echo "  Version:     $VER"
    echo "  Author:      $AUTHOR${AUTHOR_GH:+ (@$AUTHOR_GH)}"
    echo "  Published:   $PUBLISHED"
    echo "  Installs:    $INSTALLS"
    [ -n "$DESC" ] && echo "  Description: $DESC"
    [ -n "$TAGS" ] && echo "  Tags:        $TAGS"
    echo ""
    echo "  Contents:"
    [ "${N_SKILLS:-0}" -gt 0 ] 2>/dev/null && echo "    Skills:     $N_SKILLS"
    [ "${N_ROLES:-0}" -gt 0 ] 2>/dev/null && echo "    Roles:      $N_ROLES"
    [ "${N_RULES:-0}" -gt 0 ] 2>/dev/null && echo "    Rules:      $N_RULES"
    [ "${N_TEMPLATES:-0}" -gt 0 ] 2>/dev/null && echo "    Templates:  $N_TEMPLATES"
    [ "${N_KNOWLEDGE:-0}" -gt 0 ] 2>/dev/null && echo "    Knowledge:  $N_KNOWLEDGE"
    echo ""

    # List files in pack
    FILES=$(dolt sql -q "SELECT CONCAT(file_type, '|', path) FROM mesh_pack_files WHERE pack_name = '$PACK_NAME' ORDER BY file_type, path;" -r csv 2>/dev/null | tail -n +2 | sed 's/^"//;s/"$//')
    if [ -n "$FILES" ]; then
      echo "  Files:"
      while IFS='|' read -r ftype fpath; do
        [ -z "$ftype" ] && continue
        printf "    [%-10s] %s\n" "$ftype" "$fpath"
      done <<< "$FILES"
      echo ""
    fi

    # Show install status
    if [ -d "$PACKS_DIR/$PACK_NAME" ]; then
      LOCAL_VER=""
      [ -f "$PACKS_DIR/$PACK_NAME/pack.yaml" ] && LOCAL_VER=$(_read_pack_yaml "$PACKS_DIR/$PACK_NAME" "version")
      echo "  Status: INSTALLED (local v${LOCAL_VER:-unknown})"
    else
      echo "  Status: NOT INSTALLED"
      echo "  Install: gt mesh packs install $PACK_NAME"
    fi
    echo ""
    cd "$GT_ROOT"
    ;;

  install)
    PACK_NAME="$1"
    if [ -z "$PACK_NAME" ]; then
      echo "Usage: gt mesh packs install <pack-name>"
      exit 1
    fi

    _ensure_clone
    _ensure_tables

    # Check if pack exists
    EXISTS=$(dolt sql -q "SELECT name FROM mesh_packs WHERE name = '$PACK_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1)
    if [ -z "$EXISTS" ]; then
      echo "[error] Pack '$PACK_NAME' not found in registry"
      exit 1
    fi

    VER=$(dolt sql -q "SELECT version FROM mesh_packs WHERE name = '$PACK_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1)

    echo "Installing pack: $PACK_NAME v$VER..."
    echo ""

    mkdir -p "$PACKS_DIR/$PACK_NAME"

    # Pull all pack files
    PATHS=$(dolt sql -q "SELECT path FROM mesh_pack_files WHERE pack_name = '$PACK_NAME';" -r csv 2>/dev/null | tail -n +2)

    FILE_COUNT=0
    SKILLS_INSTALLED=0
    ROLES_INSTALLED=0
    RULES_APPLIED=0

    while IFS= read -r fpath; do
      [ -z "$fpath" ] && continue
      fpath=$(echo "$fpath" | sed 's/^"//;s/"$//')

      FILE_TYPE=$(dolt sql -q "SELECT file_type FROM mesh_pack_files WHERE pack_name = '$PACK_NAME' AND path = '$fpath';" -r csv 2>/dev/null | tail -n +2 | head -1)

      # Create parent dir in pack cache
      mkdir -p "$PACKS_DIR/$PACK_NAME/$(dirname "$fpath")"

      # Pull content
      dolt sql -q "SELECT content FROM mesh_pack_files WHERE pack_name = '$PACK_NAME' AND path = '$fpath';" -r csv 2>/dev/null | tail -n +2 | sed 's/^"//;s/"$//' | sed 's/""/"/g' > "$PACKS_DIR/$PACK_NAME/$fpath"

      # Apply based on type
      case "$FILE_TYPE" in
        skill)
          # Install skill to Claude Code skills dir
          SKILL_NAME=$(basename "$(dirname "$fpath")" 2>/dev/null)
          [ "$SKILL_NAME" = "." ] && SKILL_NAME=$(basename "$fpath" .md)
          SKILL_DIR="$HOME/.claude/skills/$SKILL_NAME"
          mkdir -p "$SKILL_DIR"
          cp "$PACKS_DIR/$PACK_NAME/$fpath" "$SKILL_DIR/SKILL.md"
          SKILLS_INSTALLED=$((SKILLS_INSTALLED + 1))
          echo "  [skill]     $SKILL_NAME -> $SKILL_DIR/"
          ;;
        role)
          # Install role to mesh-config cache
          mkdir -p "$GT_ROOT/.mesh-config/roles"
          cp "$PACKS_DIR/$PACK_NAME/$fpath" "$GT_ROOT/.mesh-config/roles/"
          ROLES_INSTALLED=$((ROLES_INSTALLED + 1))
          echo "  [role]      $(basename "$fpath")"
          ;;
        rule)
          mkdir -p "$GT_ROOT/.mesh-config/rules"
          cp "$PACKS_DIR/$PACK_NAME/$fpath" "$GT_ROOT/.mesh-config/rules/"
          RULES_APPLIED=$((RULES_APPLIED + 1))
          echo "  [rule]      $(basename "$fpath")"
          ;;
        template)
          mkdir -p "$GT_ROOT/.mesh-config/templates"
          cp "$PACKS_DIR/$PACK_NAME/$fpath" "$GT_ROOT/.mesh-config/templates/"
          echo "  [template]  $(basename "$fpath")"
          ;;
        knowledge)
          mkdir -p "$GT_ROOT/.mesh-config/knowledge"
          cp "$PACKS_DIR/$PACK_NAME/$fpath" "$GT_ROOT/.mesh-config/knowledge/"
          echo "  [knowledge] $(basename "$fpath")"
          ;;
        *)
          echo "  [file]      $fpath"
          ;;
      esac

      FILE_COUNT=$((FILE_COUNT + 1))
    done <<< "$PATHS"

    # Save pack.yaml locally for tracking
    cat > "$PACKS_DIR/$PACK_NAME/pack.yaml" <<YAML
name: "$PACK_NAME"
version: "$VER"
installed_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
installed_by: "$GT_ID"
YAML

    # Update install count
    dolt sql -q "UPDATE mesh_packs SET installs = installs + 1 WHERE name = '$PACK_NAME';" 2>/dev/null
    dolt add . 2>/dev/null || true
    dolt commit -m "mesh: $GT_ID installed pack $PACK_NAME" --allow-empty 2>/dev/null || true
    dolt push 2>/dev/null || true

    echo ""
    echo "Installed: $PACK_NAME v$VER ($FILE_COUNT files)"
    [ $SKILLS_INSTALLED -gt 0 ] && echo "  Skills installed: $SKILLS_INSTALLED"
    [ $ROLES_INSTALLED -gt 0 ] && echo "  Roles installed: $ROLES_INSTALLED"
    echo ""
    cd "$GT_ROOT"
    ;;

  uninstall)
    PACK_NAME="$1"
    if [ -z "$PACK_NAME" ]; then
      echo "Usage: gt mesh packs uninstall <pack-name>"
      exit 1
    fi

    if [ ! -d "$PACKS_DIR/$PACK_NAME" ]; then
      echo "[error] Pack '$PACK_NAME' is not installed"
      exit 1
    fi

    echo "Uninstalling: $PACK_NAME..."

    if [ -d "$PACKS_DIR/$PACK_NAME" ]; then
      # Remove skills
      find "$PACKS_DIR/$PACK_NAME" -name "SKILL.md" -type f 2>/dev/null | while read -r skill_file; do
        SKILL_NAME=$(basename "$(dirname "$skill_file")")
        [ "$SKILL_NAME" = "$PACK_NAME" ] && continue
        if [ -d "$HOME/.claude/skills/$SKILL_NAME" ]; then
          rm -rf "$HOME/.claude/skills/$SKILL_NAME"
          echo "  Removed skill: $SKILL_NAME"
        fi
      done

      # Remove roles
      find "$PACKS_DIR/$PACK_NAME/roles" -type f 2>/dev/null | while read -r role_file; do
        BASENAME=$(basename "$role_file")
        if [ -f "$GT_ROOT/.mesh-config/roles/$BASENAME" ]; then
          rm -f "$GT_ROOT/.mesh-config/roles/$BASENAME"
          echo "  Removed role: $BASENAME"
        fi
      done

      # Remove rules
      find "$PACKS_DIR/$PACK_NAME/rules" -type f 2>/dev/null | while read -r rule_file; do
        BASENAME=$(basename "$rule_file")
        if [ -f "$GT_ROOT/.mesh-config/rules/$BASENAME" ]; then
          rm -f "$GT_ROOT/.mesh-config/rules/$BASENAME"
          echo "  Removed rule: $BASENAME"
        fi
      done

      # Remove templates
      find "$PACKS_DIR/$PACK_NAME/templates" -type f 2>/dev/null | while read -r tmpl_file; do
        BASENAME=$(basename "$tmpl_file")
        if [ -f "$GT_ROOT/.mesh-config/templates/$BASENAME" ]; then
          rm -f "$GT_ROOT/.mesh-config/templates/$BASENAME"
          echo "  Removed template: $BASENAME"
        fi
      done

      # Remove knowledge
      find "$PACKS_DIR/$PACK_NAME/knowledge" -type f 2>/dev/null | while read -r know_file; do
        BASENAME=$(basename "$know_file")
        if [ -f "$GT_ROOT/.mesh-config/knowledge/$BASENAME" ]; then
          rm -f "$GT_ROOT/.mesh-config/knowledge/$BASENAME"
          echo "  Removed knowledge: $BASENAME"
        fi
      done
    fi

    rm -rf "$PACKS_DIR/$PACK_NAME"
    echo "Uninstalled: $PACK_NAME"
    echo ""
    ;;

  installed)
    echo "==========================================="
    echo "  Installed Packs"
    echo "==========================================="
    echo ""

    if [ ! -d "$PACKS_DIR" ] || [ -z "$(ls -A "$PACKS_DIR" 2>/dev/null)" ]; then
      echo "  No packs installed."
      echo ""
      echo "  Browse: gt mesh packs list"
      echo ""
      exit 0
    fi

    for pack_dir in "$PACKS_DIR"/*/; do
      [ ! -d "$pack_dir" ] && continue
      PNAME=$(basename "$pack_dir")
      PVER=""
      PDATE=""
      if [ -f "$pack_dir/pack.yaml" ]; then
        PVER=$(_read_pack_yaml "$pack_dir" "version")
        PDATE=$(_read_pack_yaml "$pack_dir" "installed_at")
      fi
      FILE_COUNT=$(find "$pack_dir" -type f | wc -l)
      printf "  %-24s v%-8s %3d files  %s\n" "$PNAME" "${PVER:-?}" "$FILE_COUNT" "${PDATE:-unknown}"
    done
    echo ""
    ;;

  create)
    PACK_NAME="$1"
    if [ -z "$PACK_NAME" ]; then
      echo "Usage: gt mesh packs create <pack-name>"
      echo ""
      echo "Creates a pack scaffold in ./<pack-name>/ ready to fill in."
      exit 1
    fi

    if [ -d "$PACK_NAME" ]; then
      echo "[error] Directory '$PACK_NAME' already exists"
      exit 1
    fi

    echo "Creating pack scaffold: $PACK_NAME/"
    echo ""

    mkdir -p "$PACK_NAME"/{skills,roles,rules,templates,knowledge}

    cat > "$PACK_NAME/pack.yaml" <<YAML
# GT Mesh Pack Manifest
# Publish with: gt mesh packs publish ./$PACK_NAME

name: "$PACK_NAME"
version: "1.0.0"
description: "A short description of what this pack provides"
author: "$GT_ID"
author_github: "$(grep 'github:' "$MESH_YAML" 2>/dev/null | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')"
tags: "tag1, tag2, tag3"

# What this pack includes (leave sections empty if unused)
skills:
  # - skills/my-skill/SKILL.md

roles:
  # - roles/my-role.yaml

rules:
  # - rules/my-rules.yaml

templates:
  # - templates/my-template.md

knowledge:
  # - knowledge/patterns.md
  # - knowledge/conventions.md
YAML

    cat > "$PACK_NAME/skills/.gitkeep" <<< ""
    cat > "$PACK_NAME/roles/.gitkeep" <<< ""
    cat > "$PACK_NAME/rules/.gitkeep" <<< ""
    cat > "$PACK_NAME/templates/.gitkeep" <<< ""
    cat > "$PACK_NAME/knowledge/.gitkeep" <<< ""

    echo "  $PACK_NAME/"
    echo "  ├── pack.yaml          (manifest — edit this)"
    echo "  ├── skills/            (SKILL.md files)"
    echo "  ├── roles/             (role .yaml definitions)"
    echo "  ├── rules/             (governance rule sets)"
    echo "  ├── templates/         (PR, config, workflow templates)"
    echo "  └── knowledge/         (docs, patterns, conventions)"
    echo ""
    echo "Next steps:"
    echo "  1. Edit pack.yaml with your details"
    echo "  2. Add files to the appropriate directories"
    echo "  3. List files in pack.yaml under each section"
    echo "  4. Publish: gt mesh packs publish ./$PACK_NAME"
    echo ""
    ;;

  publish)
    PACK_DIR="$1"
    if [ -z "$PACK_DIR" ] || [ ! -f "$PACK_DIR/pack.yaml" ]; then
      echo "Usage: gt mesh packs publish <directory>"
      echo ""
      echo "The directory must contain a pack.yaml manifest."
      exit 1
    fi

    PACK_DIR=$(cd "$PACK_DIR" && pwd)

    # Read manifest
    PACK_NAME=$(_read_pack_yaml "$PACK_DIR" "name")
    PACK_VER=$(_read_pack_yaml "$PACK_DIR" "version")
    PACK_DESC=$(_read_pack_yaml "$PACK_DIR" "description")
    PACK_AUTHOR=$(_read_pack_yaml "$PACK_DIR" "author")
    PACK_AUTHOR_GH=$(_read_pack_yaml "$PACK_DIR" "author_github")
    PACK_TAGS=$(_read_pack_yaml "$PACK_DIR" "tags")

    if [ -z "$PACK_NAME" ]; then
      echo "[error] pack.yaml missing 'name' field"
      exit 1
    fi

    _ensure_clone
    _ensure_tables

    echo "==========================================="
    echo "  Publishing Pack: $PACK_NAME v$PACK_VER"
    echo "==========================================="
    echo ""

    # Collect files by type
    N_SKILLS=0 N_ROLES=0 N_RULES=0 N_TEMPLATES=0 N_KNOWLEDGE=0
    ALL_HASHES=""

    # Clear old files for this pack
    dolt sql -q "DELETE FROM mesh_pack_files WHERE pack_name = '$PACK_NAME';" 2>/dev/null || true

    _publish_files() {
      local SECTION="$1"
      local FILE_TYPE="$2"

      _read_pack_yaml_list "$PACK_DIR" "$SECTION" | while IFS= read -r relpath; do
        [ -z "$relpath" ] && continue
        relpath=$(echo "$relpath" | sed 's/^"//;s/"$//' | xargs)
        local FULL="$PACK_DIR/$relpath"

        if [ ! -f "$FULL" ]; then
          echo "  [warn] File not found: $relpath"
          return
        fi

        local HASH=$(sha256sum "$FULL" 2>/dev/null | cut -d' ' -f1)
        local CONTENT=$(cat "$FULL")
        local CONTENT_ESC=$(echo "$CONTENT" | sed "s/'/''/g")

        dolt sql -q "REPLACE INTO mesh_pack_files (pack_name, path, file_type, content, hash)
          VALUES ('$PACK_NAME', '$relpath', '$FILE_TYPE', '$CONTENT_ESC', '$HASH');" 2>/dev/null

        printf "  [%-10s] %s\n" "$FILE_TYPE" "$relpath"
        echo "$HASH"
      done
    }

    echo "  Files:"

    # Publish each section's files
    for SECTION_TYPE in "skills:skill" "roles:role" "rules:rule" "templates:template" "knowledge:knowledge"; do
      SECTION="${SECTION_TYPE%%:*}"
      FTYPE="${SECTION_TYPE##*:}"

      _read_pack_yaml_list "$PACK_DIR" "$SECTION" | while IFS= read -r relpath; do
        [ -z "$relpath" ] && continue
        relpath=$(echo "$relpath" | sed 's/^"//;s/"$//' | xargs)
        FULL="$PACK_DIR/$relpath"

        if [ ! -f "$FULL" ]; then
          echo "  [warn] File not found: $relpath"
          continue
        fi

        HASH=$(sha256sum "$FULL" 2>/dev/null | cut -d' ' -f1)
        CONTENT_ESC=$(cat "$FULL" | sed "s/'/''/g")

        dolt sql -q "REPLACE INTO mesh_pack_files (pack_name, path, file_type, content, hash)
          VALUES ('$PACK_NAME', '$relpath', '$FTYPE', '$CONTENT_ESC', '$HASH');" 2>/dev/null

        printf "  [%-10s] %s\n" "$FTYPE" "$relpath"
      done
    done

    # Count by type
    N_SKILLS=$(dolt sql -q "SELECT COUNT(*) FROM mesh_pack_files WHERE pack_name = '$PACK_NAME' AND file_type = 'skill';" -r csv 2>/dev/null | tail -n +2 | head -1)
    N_ROLES=$(dolt sql -q "SELECT COUNT(*) FROM mesh_pack_files WHERE pack_name = '$PACK_NAME' AND file_type = 'role';" -r csv 2>/dev/null | tail -n +2 | head -1)
    N_RULES=$(dolt sql -q "SELECT COUNT(*) FROM mesh_pack_files WHERE pack_name = '$PACK_NAME' AND file_type = 'rule';" -r csv 2>/dev/null | tail -n +2 | head -1)
    N_TEMPLATES=$(dolt sql -q "SELECT COUNT(*) FROM mesh_pack_files WHERE pack_name = '$PACK_NAME' AND file_type = 'template';" -r csv 2>/dev/null | tail -n +2 | head -1)
    N_KNOWLEDGE=$(dolt sql -q "SELECT COUNT(*) FROM mesh_pack_files WHERE pack_name = '$PACK_NAME' AND file_type = 'knowledge';" -r csv 2>/dev/null | tail -n +2 | head -1)

    TOTAL=$((${N_SKILLS:-0} + ${N_ROLES:-0} + ${N_RULES:-0} + ${N_TEMPLATES:-0} + ${N_KNOWLEDGE:-0}))

    # Compute pack hash
    PACK_HASH=$(dolt sql -q "SELECT GROUP_CONCAT(hash ORDER BY path) FROM mesh_pack_files WHERE pack_name = '$PACK_NAME';" -r csv 2>/dev/null | tail -n +2 | head -1 | sha256sum | cut -d' ' -f1)

    # Escape for SQL
    PACK_DESC_ESC=$(echo "$PACK_DESC" | sed "s/'/''/g")
    PACK_TAGS_ESC=$(echo "$PACK_TAGS" | sed "s/'/''/g")

    # Upsert pack metadata
    dolt sql -q "REPLACE INTO mesh_packs (name, version, description, author, author_github, tags, contains_skills, contains_roles, contains_rules, contains_templates, contains_knowledge, installs, pack_hash, published_at, updated_at)
      VALUES ('$PACK_NAME', '$PACK_VER', '$PACK_DESC_ESC', '${PACK_AUTHOR:-$GT_ID}', '$PACK_AUTHOR_GH', '$PACK_TAGS_ESC', ${N_SKILLS:-0}, ${N_ROLES:-0}, ${N_RULES:-0}, ${N_TEMPLATES:-0}, ${N_KNOWLEDGE:-0}, COALESCE((SELECT installs FROM mesh_packs WHERE name = '$PACK_NAME'), 0), '$PACK_HASH', COALESCE((SELECT published_at FROM mesh_packs WHERE name = '$PACK_NAME'), NOW()), NOW());" 2>/dev/null

    dolt add . 2>/dev/null || true
    dolt commit -m "mesh: $GT_ID published pack $PACK_NAME v$PACK_VER ($TOTAL files)" --allow-empty 2>/dev/null || true
    dolt push 2>/dev/null || true

    echo ""
    echo "  Published: $PACK_NAME v$PACK_VER"
    echo "  Files: $TOTAL (skills:${N_SKILLS:-0} roles:${N_ROLES:-0} rules:${N_RULES:-0} templates:${N_TEMPLATES:-0} knowledge:${N_KNOWLEDGE:-0})"
    echo "  Hash: ${PACK_HASH:0:16}..."
    echo ""
    echo "  Others can install: gt mesh packs install $PACK_NAME"
    echo ""
    cd "$GT_ROOT"
    ;;

  *)
    echo "GT Mesh Packs — Shareable bundles of mesh knowledge"
    echo ""
    echo "Usage: gt mesh packs <command>"
    echo ""
    echo "Commands:"
    echo "  list                    Browse available packs"
    echo "  search <query>          Search packs by keyword"
    echo "  info <pack-name>        Show pack details & contents"
    echo "  install <pack-name>     Install a pack (skills, roles, etc.)"
    echo "  uninstall <pack-name>   Remove an installed pack"
    echo "  installed               List locally installed packs"
    echo "  create <name>           Scaffold a new pack directory"
    echo "  publish <dir>           Publish a pack to the registry"
    echo ""
    echo "A pack bundles skills, roles, rules, templates, and knowledge"
    echo "into a single installable unit shared across the mesh."
    echo ""
    ;;
esac

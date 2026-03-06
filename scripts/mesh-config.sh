#!/bin/bash
# GT Mesh — Config distribution system
#
# Usage: mesh-config.sh publish     (coordinator pushes config to mesh)
#        mesh-config.sh pull        (pull latest config from mesh)
#        mesh-config.sh diff        (compare local vs remote)
#        mesh-config.sh status      (show config sync status)

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"
MESH_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -f "$MESH_YAML" ]; then
  echo "[error] Not in a mesh. Run: gt mesh init"
  exit 1
fi

_yaml_val() { grep "$1" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/'; }

GT_ID=$(_yaml_val "^  id:")
CLONE_DIR=$(_yaml_val "clone_dir:")
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"
CONFIG_SOURCE="$MESH_DIR/mesh-config"
CONFIG_CACHE="$GT_ROOT/.mesh-config"
MESH_ID=$(_yaml_val "mesh_id:" || echo "default-mesh")
MESH_ID="${MESH_ID:-default-mesh}"

SUBCMD="${1:-status}"
shift 2>/dev/null || true

_ensure_tables() {
  cd "$CLONE_DIR"
  dolt pull 2>/dev/null || true

  dolt sql -q "CREATE TABLE IF NOT EXISTS mesh_config (
    mesh_id VARCHAR(64) PRIMARY KEY,
    manifest TEXT,
    version INT DEFAULT 1,
    config_hash VARCHAR(128),
    file_count INT DEFAULT 0,
    updated_by VARCHAR(64),
    updated_at DATETIME
  );" 2>/dev/null || true

  dolt sql -q "CREATE TABLE IF NOT EXISTS mesh_config_files (
    mesh_id VARCHAR(64) NOT NULL,
    path VARCHAR(256) NOT NULL,
    content TEXT,
    hash VARCHAR(128),
    size_bytes INT DEFAULT 0,
    updated_by VARCHAR(64),
    updated_at DATETIME,
    PRIMARY KEY (mesh_id, path)
  );" 2>/dev/null || true
}

_hash_file() {
  sha256sum "$1" 2>/dev/null | cut -d' ' -f1
}

case "$SUBCMD" in
  publish)
    if [ ! -d "$CONFIG_SOURCE" ]; then
      echo "[error] No mesh-config/ directory found at $CONFIG_SOURCE"
      echo "        Only coordinators publish config."
      exit 1
    fi

    _ensure_tables

    echo "==========================================="
    echo "  Publishing Mesh Config"
    echo "==========================================="
    echo ""
    echo "  Source: $CONFIG_SOURCE"
    echo "  Mesh:   $MESH_ID"
    echo ""

    # Collect all files
    FILE_COUNT=0
    ALL_HASHES=""

    while IFS= read -r file; do
      [ -z "$file" ] && continue
      REL_PATH="${file#$CONFIG_SOURCE/}"
      HASH=$(_hash_file "$file")
      SIZE=$(wc -c < "$file")
      CONTENT=$(cat "$file")
      CONTENT_ESC=$(echo "$CONTENT" | sed "s/'/''/g")

      dolt sql -q "REPLACE INTO mesh_config_files (mesh_id, path, content, hash, size_bytes, updated_by, updated_at)
        VALUES ('$MESH_ID', '$REL_PATH', '$CONTENT_ESC', '$HASH', $SIZE, '$GT_ID', NOW());" 2>/dev/null

      FILE_COUNT=$((FILE_COUNT + 1))
      ALL_HASHES="${ALL_HASHES}${HASH}"
      printf "  [%2d] %-40s %s\n" "$FILE_COUNT" "$REL_PATH" "${HASH:0:12}..."
    done < <(find "$CONFIG_SOURCE" -type f | sort)

    # Compute overall config hash
    CONFIG_HASH=$(echo -n "$ALL_HASHES" | sha256sum | cut -d' ' -f1)

    # Get current version
    CUR_VER=$(dolt sql -q "SELECT version FROM mesh_config WHERE mesh_id = '$MESH_ID';" -r csv 2>/dev/null | tail -n +2 | head -1)
    NEW_VER=$((${CUR_VER:-0} + 1))

    # Read manifest
    MANIFEST=""
    if [ -f "$CONFIG_SOURCE/manifest.yaml" ]; then
      MANIFEST=$(cat "$CONFIG_SOURCE/manifest.yaml" | sed "s/'/''/g")
    fi

    dolt sql -q "REPLACE INTO mesh_config (mesh_id, manifest, version, config_hash, file_count, updated_by, updated_at)
      VALUES ('$MESH_ID', '$MANIFEST', $NEW_VER, '$CONFIG_HASH', $FILE_COUNT, '$GT_ID', NOW());" 2>/dev/null

    dolt add . 2>/dev/null || true
    dolt commit -m "mesh-config: $GT_ID published v$NEW_VER ($FILE_COUNT files)" --allow-empty 2>/dev/null || true
    dolt push 2>/dev/null || true

    echo ""
    echo "  Published: v$NEW_VER ($FILE_COUNT files)"
    echo "  Hash: ${CONFIG_HASH:0:16}..."
    echo ""

    cd "$GT_ROOT"
    ;;

  pull)
    QUIET=false
    [ "$1" = "--quiet" ] && QUIET=true

    _ensure_tables

    # Check if config exists
    REMOTE_HASH=$(dolt sql -q "SELECT config_hash FROM mesh_config WHERE mesh_id = '$MESH_ID';" -r csv 2>/dev/null | tail -n +2 | head -1)

    if [ -z "$REMOTE_HASH" ]; then
      [ "$QUIET" = false ] && echo "[info] No mesh config published yet for mesh '$MESH_ID'"
      cd "$GT_ROOT"
      exit 0
    fi

    # Check if already up to date
    LOCAL_HASH=""
    [ -f "$CONFIG_CACHE/version" ] && LOCAL_HASH=$(cat "$CONFIG_CACHE/version")

    if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
      [ "$QUIET" = false ] && echo "[ok] Config already up to date"
      cd "$GT_ROOT"
      exit 0
    fi

    VERSION=$(dolt sql -q "SELECT version FROM mesh_config WHERE mesh_id = '$MESH_ID';" -r csv 2>/dev/null | tail -n +2 | head -1)

    [ "$QUIET" = false ] && echo "Pulling mesh config v${VERSION}..."

    # Create cache directory
    mkdir -p "$CONFIG_CACHE"

    # Pull all files
    FILE_COUNT=0
    # Get file list first
    PATHS=$(dolt sql -q "SELECT path FROM mesh_config_files WHERE mesh_id = '$MESH_ID';" -r csv 2>/dev/null | tail -n +2)

    while IFS= read -r path; do
      [ -z "$path" ] && continue
      # Strip any quotes
      path=$(echo "$path" | sed 's/^"//;s/"$//')

      # Create parent directory
      mkdir -p "$CONFIG_CACHE/$(dirname "$path")"

      # Pull content (individual query to avoid CSV mangling)
      dolt sql -q "SELECT content FROM mesh_config_files WHERE mesh_id = '$MESH_ID' AND path = '$path';" -r csv 2>/dev/null | tail -n +2 | sed 's/^"//;s/"$//' | sed 's/""/"/g' > "$CONFIG_CACHE/$path"

      FILE_COUNT=$((FILE_COUNT + 1))
      [ "$QUIET" = false ] && echo "  [$FILE_COUNT] $path"
    done <<< "$PATHS"

    # Save version hash
    echo "$REMOTE_HASH" > "$CONFIG_CACHE/version"

    [ "$QUIET" = false ] && echo ""
    [ "$QUIET" = false ] && echo "Pulled: v$VERSION ($FILE_COUNT files) → $CONFIG_CACHE/"

    cd "$GT_ROOT"
    ;;

  diff)
    _ensure_tables

    echo "==========================================="
    echo "  Mesh Config Diff"
    echo "==========================================="
    echo ""

    REMOTE_VER=$(dolt sql -q "SELECT version FROM mesh_config WHERE mesh_id = '$MESH_ID';" -r csv 2>/dev/null | tail -n +2 | head -1)
    REMOTE_HASH=$(dolt sql -q "SELECT config_hash FROM mesh_config WHERE mesh_id = '$MESH_ID';" -r csv 2>/dev/null | tail -n +2 | head -1)
    LOCAL_HASH=""
    [ -f "$CONFIG_CACHE/version" ] && LOCAL_HASH=$(cat "$CONFIG_CACHE/version")

    if [ -z "$REMOTE_HASH" ]; then
      echo "  No remote config published."
      cd "$GT_ROOT"
      exit 0
    fi

    echo "  Remote: v$REMOTE_VER (${REMOTE_HASH:0:16}...)"
    echo "  Local:  ${LOCAL_HASH:0:16}..."
    echo ""

    if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
      echo "  Status: IN SYNC"
    else
      echo "  Status: OUT OF DATE"
      echo ""
      echo "  Run: gt mesh config pull"
    fi

    # Show remote file list
    echo ""
    echo "  Remote files:"
    PATHS=$(dolt sql -q "SELECT CONCAT(path, '|', hash, '|', size_bytes) FROM mesh_config_files WHERE mesh_id = '$MESH_ID' ORDER BY path;" -r csv 2>/dev/null | tail -n +2 | sed 's/^"//;s/"$//')
    while IFS='|' read -r path hash size; do
      [ -z "$path" ] && continue
      # Check if local copy exists and matches
      if [ -f "$CONFIG_CACHE/$path" ]; then
        LOCAL_FILE_HASH=$(_hash_file "$CONFIG_CACHE/$path")
        if [ "$LOCAL_FILE_HASH" = "$hash" ]; then
          marker="="
        else
          marker="~"
        fi
      else
        marker="+"
      fi
      printf "  %s %-40s %6s bytes\n" "$marker" "$path" "$size"
    done <<< "$PATHS"

    echo ""
    echo "  Legend: = in sync  ~ modified  + new"
    echo ""

    cd "$GT_ROOT"
    ;;

  status)
    _ensure_tables

    REMOTE_VER=$(dolt sql -q "SELECT version FROM mesh_config WHERE mesh_id = '$MESH_ID';" -r csv 2>/dev/null | tail -n +2 | head -1)
    REMOTE_HASH=$(dolt sql -q "SELECT config_hash FROM mesh_config WHERE mesh_id = '$MESH_ID';" -r csv 2>/dev/null | tail -n +2 | head -1)
    REMOTE_FILES=$(dolt sql -q "SELECT file_count FROM mesh_config WHERE mesh_id = '$MESH_ID';" -r csv 2>/dev/null | tail -n +2 | head -1)
    REMOTE_BY=$(dolt sql -q "SELECT updated_by FROM mesh_config WHERE mesh_id = '$MESH_ID';" -r csv 2>/dev/null | tail -n +2 | head -1)
    REMOTE_AT=$(dolt sql -q "SELECT CAST(updated_at AS CHAR) FROM mesh_config WHERE mesh_id = '$MESH_ID';" -r csv 2>/dev/null | tail -n +2 | head -1)

    LOCAL_HASH=""
    [ -f "$CONFIG_CACHE/version" ] && LOCAL_HASH=$(cat "$CONFIG_CACHE/version")

    echo "==========================================="
    echo "  Mesh Config Status"
    echo "==========================================="
    echo ""
    echo "  Mesh ID:      $MESH_ID"

    if [ -z "$REMOTE_HASH" ]; then
      echo "  Remote:       (no config published)"
      echo ""
      echo "  To publish:  gt mesh config publish"
    else
      echo "  Remote:       v$REMOTE_VER ($REMOTE_FILES files)"
      echo "  Published by: $REMOTE_BY"
      echo "  Updated:      $REMOTE_AT"
      echo "  Hash:         ${REMOTE_HASH:0:16}..."
      echo ""
      if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
        echo "  Local:        IN SYNC"
      elif [ -z "$LOCAL_HASH" ]; then
        echo "  Local:        NOT PULLED"
        echo "  Run:          gt mesh config pull"
      else
        echo "  Local:        OUT OF DATE"
        echo "  Run:          gt mesh config pull"
      fi
    fi

    echo ""
    echo "  Config source: $CONFIG_SOURCE"
    echo "  Local cache:   $CONFIG_CACHE"
    echo ""

    cd "$GT_ROOT"
    ;;

  *)
    echo "Usage: gt mesh config <publish|pull|diff|status>"
    echo ""
    echo "  publish     Push config to mesh (coordinator only)"
    echo "  pull        Pull latest config from mesh"
    echo "  diff        Compare local vs remote config"
    echo "  status      Show config sync status"
    exit 1
    ;;
esac

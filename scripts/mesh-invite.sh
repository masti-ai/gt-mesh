#!/bin/bash
# GT Mesh — Generate invite tokens with time-limited access
#
# Usage: mesh-invite.sh [--role R] [--rigs R] [--expires D] [--note "text"]

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"

if [ ! -f "$MESH_YAML" ]; then
  echo "[error] Not in a mesh. Run: gt mesh init"
  exit 1
fi

# Defaults
ROLE="write"
RIGS=""
EXPIRES="7d"
NOTE=""

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --role) ROLE="$2"; shift 2 ;;
    --rigs) RIGS="$2"; shift 2 ;;
    --expires) EXPIRES="$2"; shift 2 ;;
    --note) NOTE="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: gt mesh invite [options]"
      echo ""
      echo "Options:"
      echo "  --role <role>       Access level: read, write, admin (default: write)"
      echo "  --rigs <list>       Comma-separated rig names (default: all shared)"
      echo "  --expires <duration> Token lifetime: 4h, 7d, 30d, never (default: 7d)"
      echo "  --note <text>       Optional note about this invite"
      echo ""
      echo "Examples:"
      echo "  gt mesh invite --role read --expires 24h        # 24-hour read access"
      echo "  gt mesh invite --role write --expires 14d       # 2-week sprint token"
      echo "  gt mesh invite --role admin --expires never     # Permanent admin"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Validate role
if [[ "$ROLE" != "read" && "$ROLE" != "write" && "$ROLE" != "admin" ]]; then
  echo "[error] Role must be: read, write, or admin"
  exit 1
fi

# Read identity
GT_ID=$(grep "^  id:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR=$(grep "clone_dir:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"

if [ ! -d "$CLONE_DIR/.dolt" ]; then
  echo "[error] Sync clone not found. Run: gt mesh sync"
  exit 1
fi

# Generate invite code: MESH-XXXX-YYYY (uppercase alphanum)
CODE_PART1=$(head -c 4 /dev/urandom | xxd -p | tr 'a-f' 'A-F' | head -c 4)
CODE_PART2=$(head -c 4 /dev/urandom | xxd -p | tr 'a-f' 'A-F' | head -c 4)
INVITE_CODE="MESH-${CODE_PART1}-${CODE_PART2}"

# Calculate expiry
case "$EXPIRES" in
  never)
    EXPIRES_SQL="NULL"
    EXPIRES_DISPLAY="never (permanent)"
    ;;
  *h)
    HOURS="${EXPIRES%h}"
    EXPIRES_SQL="DATE_ADD(NOW(), INTERVAL $HOURS HOUR)"
    EXPIRES_DISPLAY="$HOURS hours"
    ;;
  *d)
    DAYS="${EXPIRES%d}"
    EXPIRES_SQL="DATE_ADD(NOW(), INTERVAL $DAYS DAY)"
    EXPIRES_DISPLAY="$DAYS days"
    ;;
  *m)
    MINS="${EXPIRES%m}"
    EXPIRES_SQL="DATE_ADD(NOW(), INTERVAL $MINS MINUTE)"
    EXPIRES_DISPLAY="$MINS minutes"
    ;;
  *)
    echo "[error] Invalid expires format. Use: 4h, 7d, 30d, never"
    exit 1
    ;;
esac

# Ensure invites table exists
cd "$CLONE_DIR"
dolt pull 2>/dev/null || true

dolt sql -q "CREATE TABLE IF NOT EXISTS invites (
  code VARCHAR(16) PRIMARY KEY,
  created_by VARCHAR(64) NOT NULL,
  role VARCHAR(32) DEFAULT 'write',
  rigs JSON,
  note VARCHAR(512),
  created_at DATETIME NOT NULL,
  expires_at DATETIME,
  claimed_by VARCHAR(64),
  claimed_at DATETIME,
  status VARCHAR(32) DEFAULT 'active'
);" 2>/dev/null || true

# Build rigs JSON
if [ -n "$RIGS" ]; then
  RIGS_JSON="JSON_ARRAY($(echo "$RIGS" | sed "s/,/','/g" | sed "s/^/'/;s/$/'/" ))"
else
  RIGS_JSON="NULL"
fi

# Insert invite
NOTE_ESC=$(echo "$NOTE" | sed "s/'/''/g")
dolt sql -q "INSERT INTO invites (code, created_by, role, rigs, note, created_at, expires_at, status) VALUES ('$INVITE_CODE', '$GT_ID', '$ROLE', $RIGS_JSON, '$NOTE_ESC', NOW(), $EXPIRES_SQL, 'active');" 2>/dev/null

dolt add . 2>/dev/null || true
dolt commit -m "mesh: invite $INVITE_CODE ($ROLE, expires $EXPIRES)" --allow-empty 2>/dev/null || true
dolt push 2>/dev/null || echo "[warn] Push deferred — invite will sync on next cycle"

cd "$GT_ROOT"

echo ""
echo "==========================================="
echo "  Invite Code: $INVITE_CODE"
echo "==========================================="
echo ""
echo "  Role:    $ROLE"
echo "  Expires: $EXPIRES_DISPLAY"
if [ -n "$RIGS" ]; then
  echo "  Rigs:    $RIGS"
fi
if [ -n "$NOTE" ]; then
  echo "  Note:    $NOTE"
fi
echo ""
echo "  Share this code with your collaborator."
echo "  They run: gt mesh join $INVITE_CODE"
echo ""

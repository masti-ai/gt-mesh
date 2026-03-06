#!/bin/bash
# GT Mesh — Join a mesh with an invite code
#
# Usage: mesh-join.sh <MESH-XXXX-YYYY> [--github <username>] [--name <name>]

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"
DOLTHUB_DB="${DOLTHUB_DB:-deepwork/gt-agent-mail}"
CLONE_DIR="/tmp/mesh-sync-clone"

INVITE_CODE="$1"
shift 2>/dev/null || true

OWNER_GITHUB=""
GT_NAME=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --github) OWNER_GITHUB="$2"; shift 2 ;;
    --name) GT_NAME="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$INVITE_CODE" ]; then
  echo "Usage: gt mesh join <MESH-XXXX-YYYY> [--github <username>] [--name <name>]"
  echo ""
  echo "Join an existing GT Mesh network using an invite code."
  exit 1
fi

# Validate invite code format
if ! echo "$INVITE_CODE" | grep -qE "^MESH-[A-Z0-9]{4}-[A-Z0-9]{4}$"; then
  echo "[error] Invalid invite code format. Expected: MESH-XXXX-YYYY"
  exit 1
fi

echo "==========================================="
echo "  GT Mesh — Joining Network"
echo "==========================================="
echo ""
echo "  Invite code: $INVITE_CODE"
echo ""

# Ensure DoltHub clone exists
echo "[1/5] Connecting to mesh backbone..."
if [ -d "$CLONE_DIR/.dolt" ]; then
  cd "$CLONE_DIR"
  dolt pull 2>/dev/null || true
else
  dolt clone "$DOLTHUB_DB" "$CLONE_DIR" 2>/dev/null || {
    echo "[error] Failed to connect to DoltHub. Check credentials: dolt creds ls"
    exit 1
  }
  cd "$CLONE_DIR"
fi
echo "       Connected"
echo ""

# Validate invite FIRST (before collecting identity)
echo "[2/5] Validating invite..."
INVITE_STATUS=$(dolt sql -q "SELECT status FROM invites WHERE code = '$INVITE_CODE';" -r csv 2>/dev/null | tail -n +2 | head -1)

if [ -z "$INVITE_STATUS" ]; then
  echo "[error] Invite code not found: $INVITE_CODE"
  exit 1
fi

if [ "$INVITE_STATUS" != "active" ]; then
  echo "[error] Invite is no longer active (status: $INVITE_STATUS)"
  exit 1
fi

# Check expiry
EXPIRED=$(dolt sql -q "SELECT CASE WHEN expires_at IS NOT NULL AND expires_at < NOW() THEN 'yes' ELSE 'no' END as expired FROM invites WHERE code = '$INVITE_CODE';" -r csv 2>/dev/null | tail -n +2 | head -1)

if [ "$EXPIRED" = "yes" ]; then
  echo "[error] Invite has expired. Ask the coordinator for a new one."
  dolt sql -q "UPDATE invites SET status = 'expired' WHERE code = '$INVITE_CODE';" 2>/dev/null
  dolt add . 2>/dev/null || true
  dolt commit -m "mesh: expire invite $INVITE_CODE" --allow-empty 2>/dev/null || true
  dolt push 2>/dev/null || true
  exit 1
fi

# Get invite details
INVITE_ROLE=$(dolt sql -q "SELECT role FROM invites WHERE code = '$INVITE_CODE';" -r csv 2>/dev/null | tail -n +2 | head -1)
INVITE_CREATOR=$(dolt sql -q "SELECT created_by FROM invites WHERE code = '$INVITE_CODE';" -r csv 2>/dev/null | tail -n +2 | head -1)
INVITE_EXPIRES=$(dolt sql -q "SELECT COALESCE(CAST(expires_at AS CHAR), 'never') FROM invites WHERE code = '$INVITE_CODE';" -r csv 2>/dev/null | tail -n +2 | head -1)

echo "       Valid invite from: $INVITE_CREATOR"
echo "       Role: $INVITE_ROLE"
echo "       Expires: $INVITE_EXPIRES"
echo ""

# Collect identity (only after invite is validated)
if [ -z "$OWNER_GITHUB" ]; then
  echo "[error] GitHub username is required. Use --github <username>"
  echo "        This is MANDATORY for contributor attribution."
  exit 1
fi

OWNER_NAME=$(git config --global user.name 2>/dev/null || echo "$OWNER_GITHUB")
OWNER_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

if [ -z "$GT_NAME" ]; then
  GT_NAME="gt-$(hostname -s 2>/dev/null || echo 'unknown')"
fi

echo "[3/5] Identity"
echo "       GT Name:  $GT_NAME"
echo "       GitHub:   $OWNER_GITHUB"
echo "       Email:    $OWNER_EMAIL"
echo ""

# Claim the invite
echo "[4/5] Claiming invite..."
dolt sql -q "UPDATE invites SET claimed_by = '$GT_NAME', claimed_at = NOW(), status = 'claimed' WHERE code = '$INVITE_CODE';" 2>/dev/null

# Register as peer
DOLT_PUBKEY=$(dolt creds ls 2>/dev/null | grep "^  " | head -1 | awk '{print $1}' || echo "unknown")

dolt sql -q "REPLACE INTO peers (gt_id, name, owner, role, status, dolt_pubkey, joined_at, last_seen, invited_by, metadata) VALUES ('$GT_NAME', '$GT_NAME', '$OWNER_NAME <$OWNER_EMAIL>', '$INVITE_ROLE', 'active', '$DOLT_PUBKEY', NOW(), NOW(), '$INVITE_CREATOR', JSON_OBJECT('github', '$OWNER_GITHUB', 'invite_code', '$INVITE_CODE'));" 2>/dev/null

dolt add . 2>/dev/null || true
dolt commit -m "mesh: $GT_NAME joined via invite $INVITE_CODE (role: $INVITE_ROLE)" --allow-empty 2>/dev/null || true
dolt push 2>/dev/null || echo "       [warn] Push deferred"
echo "       Claimed and registered"
echo ""

# Create mesh.yaml if it doesn't exist
echo "[5/5] Setting up local config..."
cd "$GT_ROOT"

if [ ! -f "$MESH_YAML" ]; then
  cat > "$MESH_YAML" <<YAML
# GT Mesh Configuration
# Joined via invite: $INVITE_CODE
# Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)

instance:
  id: "$GT_NAME"
  name: "$GT_NAME"
  role: "$INVITE_ROLE"
  owner:
    name: "$OWNER_NAME"
    email: "$OWNER_EMAIL"
    github: "$OWNER_GITHUB"
  invited_by: "$INVITE_CREATOR"
  invite_code: "$INVITE_CODE"
  invite_expires: "$INVITE_EXPIRES"

behavioral_role:
  this_gt: "$([ "$INVITE_ROLE" = "write" ] && echo "worker" || echo "$INVITE_ROLE")"

dolthub:
  org: "deepwork"
  database: "gt-agent-mail"
  sync_interval: "2m"
  clone_dir: "$CLONE_DIR"

daemon:
  enabled: true
  sync_interval: "2m"
  auto_claim:
    enabled: $([ "$INVITE_ROLE" = "write" ] && echo "true" || echo "false")
    max_concurrent: 2
YAML
  echo "       Created mesh.yaml"
else
  echo "       mesh.yaml already exists (preserved)"
fi

echo ""
echo "==========================================="
echo "  Joined the mesh!"
echo "==========================================="
echo ""
echo "  GT ID:      $GT_NAME"
echo "  Role:       $INVITE_ROLE"
echo "  Invited by: $INVITE_CREATOR"
echo "  Expires:    $INVITE_EXPIRES"
echo ""
echo "  Next steps:"
echo "    gt mesh inbox          # Check for work assignments"
echo "    gt mesh status         # See mesh dashboard"
echo "    gt mesh send $INVITE_CREATOR \"Hello\" \"I've joined the mesh!\""
echo ""

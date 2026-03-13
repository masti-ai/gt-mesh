#!/bin/bash
# GT Mesh — One-liner agent onboarding
#
# Sets up a new agent node with everything it needs:
#   1. Dolt (for mesh mail)
#   2. DoltHub sync (mesh backbone)
#   3. Gitea account + API token (work queue)
#   4. Git repos with Gitea remotes (code)
#   5. mesh.yaml config
#   6. Sync cron job
#
# Usage:
#   curl -s <coordinator-url>/onboard.sh | bash -s -- <INVITE-CODE>
#   OR
#   bash mesh-onboard.sh <INVITE-CODE> [options]
#
# Options:
#   --name <name>         Agent name (default: gt-<hostname>)
#   --role <role>         worker|reviewer (default: worker)
#   --gitea <url>         Gitea URL (default: from invite)
#   --workspace <dir>     Where to set up (default: ~/gt)

set -euo pipefail

# ─── Defaults ───
INVITE_CODE="${1:-}"
shift 2>/dev/null || true

GT_NAME=""
GT_ROLE="worker"
GITEA_URL=""
WORKSPACE="${HOME}/gt"
DOLTHUB_DB="deepwork/gt-agent-mail"
CLONE_DIR="/tmp/mesh-sync-clone"

while [[ $# -gt 0 ]]; do
  case $1 in
    --name) GT_NAME="$2"; shift 2 ;;
    --role) GT_ROLE="$2"; shift 2 ;;
    --gitea) GITEA_URL="$2"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$INVITE_CODE" ]; then
  echo "GT Mesh — Agent Onboarding"
  echo ""
  echo "Usage: bash mesh-onboard.sh <INVITE-CODE> [options]"
  echo ""
  echo "Options:"
  echo "  --name <name>       Agent name (default: gt-<hostname>)"
  echo "  --role <role>       worker|reviewer (default: worker)"
  echo "  --gitea <url>       Gitea server URL"
  echo "  --workspace <dir>   Workspace directory (default: ~/gt)"
  echo ""
  echo "Get an invite code from the mesh coordinator."
  exit 1
fi

# Auto-detect name
if [ -z "$GT_NAME" ]; then
  GT_NAME="gt-$(hostname -s 2>/dev/null || echo "node-$$")"
fi

echo "╔══════════════════════════════════════════╗"
echo "║     GT Mesh — Agent Onboarding           ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Agent:  $GT_NAME"
echo "  Role:   $GT_ROLE"
echo "  Invite: $INVITE_CODE"
echo ""

# ─── Step 1: Check/Install Dolt ───
echo "[1/7] Checking Dolt..."
if command -v dolt &>/dev/null; then
  DOLT_VER=$(dolt version | head -1)
  echo "       Found: $DOLT_VER"
else
  echo "       Installing Dolt..."
  curl -sL https://github.com/dolthub/dolt/releases/latest/download/install.sh | bash
  if ! command -v dolt &>/dev/null; then
    echo "[error] Dolt installation failed. Install manually: https://docs.dolthub.com/introduction/installation"
    exit 1
  fi
  echo "       Installed: $(dolt version | head -1)"
fi

# Initialize dolt creds if needed
if ! dolt creds ls &>/dev/null; then
  dolt creds new 2>/dev/null || true
fi
echo ""

# ─── Step 2: Connect to DoltHub mesh backbone ───
echo "[2/7] Connecting to mesh backbone..."
if [ -d "$CLONE_DIR/.dolt" ]; then
  cd "$CLONE_DIR"
  dolt pull 2>/dev/null || {
    echo "       Stale clone, refreshing..."
    rm -rf "$CLONE_DIR"
    dolt clone "$DOLTHUB_DB" "$CLONE_DIR" 2>/dev/null
    cd "$CLONE_DIR"
  }
else
  dolt clone "$DOLTHUB_DB" "$CLONE_DIR" 2>/dev/null || {
    echo "[error] Cannot connect to DoltHub. Check: dolt creds ls"
    exit 1
  }
  cd "$CLONE_DIR"
fi
echo "       Connected to $DOLTHUB_DB"
echo ""

# ─── Step 3: Validate invite ───
echo "[3/7] Validating invite..."
INVITE_ROW=$(dolt sql -q "SELECT status, role, created_by, COALESCE(gitea_url,'') as gitea_url, COALESCE(CAST(expires_at AS CHAR),'never') as expires FROM invites WHERE code = '$INVITE_CODE';" -r csv 2>/dev/null | tail -n +2 | head -1)

if [ -z "$INVITE_ROW" ]; then
  echo "[error] Invite code not found: $INVITE_CODE"
  echo "       Ask the coordinator for a valid invite."
  exit 1
fi

INVITE_STATUS=$(echo "$INVITE_ROW" | cut -d',' -f1)
INVITE_ROLE=$(echo "$INVITE_ROW" | cut -d',' -f2)
INVITE_CREATOR=$(echo "$INVITE_ROW" | cut -d',' -f3)
INVITE_GITEA=$(echo "$INVITE_ROW" | cut -d',' -f4)
INVITE_EXPIRES=$(echo "$INVITE_ROW" | cut -d',' -f5)

if [ "$INVITE_STATUS" != "active" ]; then
  echo "[error] Invite is $INVITE_STATUS. Ask for a new one."
  exit 1
fi

# Use gitea URL from invite if not specified
if [ -z "$GITEA_URL" ] && [ -n "$INVITE_GITEA" ]; then
  GITEA_URL="$INVITE_GITEA"
fi

echo "       Valid! From: $INVITE_CREATOR | Role: $INVITE_ROLE"
echo ""

# ─── Step 4: Create Gitea account ───
echo "[4/7] Setting up Gitea account..."
if [ -z "$GITEA_URL" ]; then
  echo "       [skip] No Gitea URL in invite. Use --gitea <url>"
else
  # The invite includes a one-time setup token
  SETUP_TOKEN=$(dolt sql -q "SELECT COALESCE(setup_token,'') FROM invites WHERE code = '$INVITE_CODE';" -r csv 2>/dev/null | tail -n +2 | head -1)

  if [ -n "$SETUP_TOKEN" ]; then
    # Use the setup token to create account via Gitea API
    GITEA_PASS="mesh-$(head -c 8 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 12)"

    RESULT=$(curl -s -X POST "$GITEA_URL/api/v1/admin/users" \
      -H "Authorization: token $SETUP_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"$GT_NAME\",\"password\":\"$GITEA_PASS\",\"email\":\"$GT_NAME@mesh.local\",\"must_change_password\":false,\"login_name\":\"$GT_NAME\",\"source_id\":0}" 2>/dev/null)

    GITEA_USER=$(echo "$RESULT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('login',''))" 2>/dev/null || echo "")

    if [ -n "$GITEA_USER" ]; then
      # Create API token
      TOKEN_RESULT=$(curl -s -X POST "$GITEA_URL/api/v1/users/$GT_NAME/tokens" \
        -u "$GT_NAME:$GITEA_PASS" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"mesh-token\",\"scopes\":[\"all\"]}" 2>/dev/null)

      GITEA_TOKEN=$(echo "$TOKEN_RESULT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('sha1',''))" 2>/dev/null || echo "")

      # Add to agents team
      curl -s -X PUT "$GITEA_URL/api/v1/teams/2/members/$GT_NAME" \
        -H "Authorization: token $SETUP_TOKEN" -o /dev/null 2>/dev/null

      echo "       Account created: $GT_NAME"
      echo "       Token: ${GITEA_TOKEN:0:8}..."
    else
      echo "       [warn] Account creation failed. May already exist."
      GITEA_TOKEN=""
      GITEA_PASS=""
    fi
  else
    echo "       [warn] No setup token in invite. Ask coordinator for credentials."
    GITEA_TOKEN=""
    GITEA_PASS=""
  fi
fi
echo ""

# ─── Step 5: Clone repos ───
echo "[5/7] Setting up workspace..."
mkdir -p "$WORKSPACE"

# Get repo list from mesh
REPOS=$(dolt sql -q "SELECT COALESCE(repos,'') FROM mesh_config WHERE key = 'repos';" -r csv 2>/dev/null | tail -n +2 | head -1)

if [ -z "$REPOS" ] && [ -n "$GITEA_URL" ]; then
  # Fallback: list repos from Gitea org
  REPOS=$(curl -s "$GITEA_URL/api/v1/orgs/Deepwork-AI/repos" \
    -H "Authorization: token ${GITEA_TOKEN:-$SETUP_TOKEN}" 2>/dev/null | \
    python3 -c "import sys,json;print(','.join(r['name'] for r in json.load(sys.stdin)))" 2>/dev/null || echo "")
fi

if [ -n "$REPOS" ] && [ -n "$GITEA_URL" ]; then
  IFS=',' read -ra REPO_LIST <<< "$REPOS"
  for repo in "${REPO_LIST[@]}"; do
    repo=$(echo "$repo" | tr -d ' ')
    REPO_DIR="$WORKSPACE/$repo"
    if [ -d "$REPO_DIR/.git" ]; then
      echo "       $repo: exists, adding gitea remote"
      cd "$REPO_DIR"
      git remote remove gitea 2>/dev/null || true
      git remote add gitea "$GITEA_URL/Deepwork-AI/$repo.git"
      git fetch gitea 2>/dev/null || true
    else
      echo "       $repo: cloning from Gitea..."
      git clone "$GITEA_URL/Deepwork-AI/$repo.git" "$REPO_DIR" 2>/dev/null || {
        echo "       [warn] Failed to clone $repo"
        continue
      }
    fi
    # Set git user for this repo
    cd "$REPO_DIR"
    git config user.name "$GT_NAME"
    git config user.email "$GT_NAME@mesh.local"
    # Checkout dev branch
    git checkout dev 2>/dev/null || git checkout -b dev 2>/dev/null || true
  done
else
  echo "       [skip] No repos configured or no Gitea URL"
fi
echo ""

# ─── Step 6: Write mesh.yaml ───
echo "[6/7] Writing config..."
MESH_YAML="$WORKSPACE/mesh.yaml"

cat > "$MESH_YAML" <<YAML
# GT Mesh Configuration
# Onboarded via invite: $INVITE_CODE
# Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)

instance:
  id: "$GT_NAME"
  name: "$GT_NAME"
  role: "$INVITE_ROLE"
  invited_by: "$INVITE_CREATOR"

behavioral_role:
  this_gt: "$GT_ROLE"

gitea:
  url: "$GITEA_URL"
  token: "${GITEA_TOKEN:-SET_ME}"
  org: "Deepwork-AI"

dolthub:
  org: "deepwork"
  database: "gt-agent-mail"
  sync_interval: "2m"
  clone_dir: "$CLONE_DIR"

rules:
  branch_format: "gt/{id}/{issue}-{desc}"
  pr_target: "dev"
  commit_format: "conventional"
  require_issue_reference: true

work:
  source: "gitea"
  poll_interval: "2m"
  auto_claim: true
  max_concurrent: 2

communication:
  channel: "dolthub"
  use_for: "chat_only"
  not_for: "work_assignment"
YAML

echo "       Written: $MESH_YAML"
echo ""

# ─── Step 7: Claim invite + register ───
echo "[7/7] Registering on mesh..."
cd "$CLONE_DIR"

dolt sql -q "UPDATE invites SET claimed_by = '$GT_NAME', claimed_at = NOW(), status = 'claimed' WHERE code = '$INVITE_CODE';" 2>/dev/null

DOLT_PUBKEY=$(dolt creds ls 2>/dev/null | grep "^  " | head -1 | awk '{print $1}' || echo "unknown")

dolt sql -q "REPLACE INTO peers (gt_id, name, owner, role, status, dolt_pubkey, joined_at, last_seen, invited_by, metadata) VALUES ('$GT_NAME', '$GT_NAME', '$(whoami)', '$GT_ROLE', 'active', '$DOLT_PUBKEY', NOW(), NOW(), '$INVITE_CREATOR', JSON_OBJECT('invite', '$INVITE_CODE'));" 2>/dev/null

dolt add . 2>/dev/null || true
dolt commit -m "mesh: $GT_NAME onboarded via $INVITE_CODE" --allow-empty 2>/dev/null || true
dolt push 2>/dev/null || echo "       [warn] Push deferred — will sync on next cycle"

# Send hello message
dolt sql -q "INSERT INTO messages (id, from_gt, from_addr, to_gt, to_addr, subject, body, priority, created_at) VALUES ('msg-join-$(date +%s)', '$GT_NAME', 'mayor/', 'gt-local', 'mayor/', '$GT_NAME joined the mesh', 'New agent $GT_NAME (role: $GT_ROLE) onboarded via invite $INVITE_CODE. Ready for work.', 1, NOW());" 2>/dev/null
dolt add . 2>/dev/null && dolt commit -m "mesh: $GT_NAME hello" --allow-empty 2>/dev/null && dolt push 2>/dev/null || true

echo "       Registered as: $GT_NAME"
echo ""

echo "╔══════════════════════════════════════════╗"
echo "║     Onboarding Complete!                  ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Agent:     $GT_NAME"
echo "  Role:      $GT_ROLE"
echo "  Workspace: $WORKSPACE"
echo "  Gitea:     ${GITEA_URL:-not configured}"
echo ""
echo "  Your work loop:"
echo "    1. Poll Gitea for issues assigned to you"
echo "    2. Claim an issue (add 'in-progress' label)"
echo "    3. Branch: gt/$GT_NAME/<issue>-<desc>"
echo "    4. Code, commit, push to Gitea"
echo "    5. Create PR targeting 'dev'"
echo "    6. Wait for review, then pick next issue"
echo ""
echo "  Mesh commands:"
echo "    bash .gt-mesh/scripts/mesh-inbox.sh    # Check messages"
echo "    bash .gt-mesh/scripts/mesh-send.sh gt-local 'subject' 'body'"
echo "    bash .gt-mesh/scripts/mesh-sync.sh     # Force sync"
echo ""
echo "  Need work? Send: mesh-send.sh gt-local 'Need issues' 'Ready for work'"
echo ""

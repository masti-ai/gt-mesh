#!/bin/bash
# setup-mesh-node.sh
# One-command setup for GT Mesh node

set -e

echo "🚀 GT Mesh Node Setup"
echo "====================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
check_prereq() {
    echo -n "Checking $1... "
    if command -v "$1" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC} (not found)"
        return 1
    fi
}

# Check all prerequisites
echo "Checking prerequisites..."
check_prereq git || { echo "Install git first"; exit 1; }
check_prereq gh || { echo "Install GitHub CLI first"; exit 1; }
check_prereq dolt || { echo "Install Dolt first"; exit 1; }

echo ""

# Get user info
echo "📝 Configuration"
echo "----------------"
read -rp "Instance ID (e.g., gt-worker-001): " INSTANCE_ID
read -rp "Your name: " OWNER_NAME
read -rp "Your email: " OWNER_EMAIL
read -rp "GitHub username: " GITHUB_USER

# Create directory
CONFIG_DIR="$HOME/$INSTANCE_ID-config"
echo ""
echo "Creating config at: $CONFIG_DIR"
mkdir -p "$CONFIG_DIR"
cd "$CONFIG_DIR"

# Create mesh.yaml
cat > mesh.yaml << EOF
version: 1

instance:
  id: "$INSTANCE_ID"
  name: "$OWNER_NAME's Gas Town"
  role: "worker"
  owner:
    name: "$OWNER_NAME"
    email: "$OWNER_EMAIL"
    github: "$GITHUB_USER"

dolthub:
  org: "deepwork"
  database: "gt-mesh-mail"
  sync_interval: "2m"

shared_rigs: []

agents:
  master:
    id: "agent-1"
    name: "Agent1"
    role: "orchestrator"
    model: "claude-sonnet"

EOF

echo -e "${GREEN}✓${NC} Created mesh.yaml"

# Create agents directory
mkdir -p agents/agent-1
cat > agents/agent-1/SOUL.md << 'EOF'
# Agent Configuration

## Identity
- Name: Agent1
- Role: Orchestrator

## Responsibilities
- Coordinate work
- Report to $OWNER_NAME
EOF

echo -e "${GREEN}✓${NC} Created agent config"

# Create memory directory
mkdir -p memory
touch memory/MISTAKES.md memory/SHARED_KNOWLEDGE.md

echo -e "${GREEN}✓${NC} Created memory files"

# Create scripts directory
mkdir -p scripts

# Create sync script
cat > scripts/sync.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")/.."
git pull origin main 2>/dev/null || true
echo "Config synced: $(date)"
EOF
chmod +x scripts/sync.sh

echo -e "${GREEN}✓${NC} Created sync script"

# Create check-mail script
cat > scripts/check-mail.sh << 'EOF'
#!/bin/bash
cd /tmp/hq-sync 2>/dev/null || { echo "DoltHub not cloned yet. Run: gt mesh init"; exit 1; }
dolt pull origin main >/dev/null 2>&1
INSTANCE_ID=$(grep "instance.id:" ../mesh.yaml | awk '{print $2}')
dolt sql -q "SELECT from_gt, subject, created_at FROM messages WHERE to_gt = '$INSTANCE_ID' AND read_at IS NULL ORDER BY created_at DESC LIMIT 10;"
EOF
chmod +x scripts/check-mail.sh

echo -e "${GREEN}✓${NC} Created mail checker"

# Git init
git init >/dev/null 2>&1
git add .
git commit -m "Initial GT Mesh config for $INSTANCE_ID" >/dev/null 2>&1

echo ""
echo -e "${GREEN}✅ Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Generate DoltHub credentials: dolt creds new"
echo "2. Share your public key with mesh admin"
echo "3. Run: gt mesh init (from your Gas Town directory)"
echo "4. Start collaborating!"
echo ""
echo "Config location: $CONFIG_DIR"
echo "Edit mesh.yaml to customize further."

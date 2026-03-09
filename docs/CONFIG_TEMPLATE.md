# GT Mesh Config Template

**Standard configuration template for GT Mesh nodes.**

## Quick Setup (One Command)

```bash
curl -fsSL https://raw.githubusercontent.com/Deepwork-AI/gt-mesh/main/scripts/setup-mesh-node.sh | bash
```

This script will:
1. Check prerequisites (git, gh, dolt)
2. Clone config template
3. Generate mesh.yaml with your identity
4. Set up DoltHub credentials
5. Initialize GT Mesh plugin

## Manual Setup

### Step 1: Prerequisites

```bash
# Install GitHub CLI
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo apt update && sudo apt install gh

# Install Dolt
curl -L https://github.com/dolthub/dolt/releases/latest/download/install.sh | bash

# Verify
git --version  # >= 2.30
gh --version   # >= 2.0
dolt version   # >= 1.0
```

### Step 2: Create Your Config

```bash
# Create directory
mkdir ~/my-gt-mesh-node
cd ~/my-gt-mesh-node

# Download template
curl -o mesh.yaml https://raw.githubusercontent.com/Deepwork-AI/gt-mesh/main/templates/mesh.yaml.example
```

### Step 3: Configure Identity

Edit `mesh.yaml`:

```yaml
version: 1

instance:
  id: "gt-worker-001"           # Your unique ID
  name: "My Gas Town"            # Display name
  role: "worker"                 # coordinator | worker | contributor
  owner:
    name: "Your Name"
    email: "you@example.com"
    github: "your-github-username"

dolthub:
  org: "deepwork"
  database: "gt-mesh-mail"
  sync_interval: "2m"
  # Your DoltHub public key goes here after running: dolt creds new

shared_rigs:
  - name: "my-project"
    visibility: "mesh"
    accept_contributions: true

agents:
  master:
    id: "my-agent"
    name: "MyAgent"
    role: "orchestrator"
    model: "claude-sonnet"
```

### Step 4: Set Up DoltHub

```bash
# Generate credentials
dolt creds new
# Copy the public key

# Add to mesh (admin needs to add your key to deepwork org)
# Share your pub key with: gt mesh peers register
```

### Step 5: Initialize

```bash
# From your Gas Town directory
gt plugin install Deepwork-AI/gt-mesh

# Copy your config
cp ~/my-gt-mesh-node/mesh.yaml ./

# Initialize
gt mesh init

# Verify
gt mesh status
```

## Automation Scripts

### `setup-mesh-node.sh`
Full automated setup.

### `sync-config.sh`
Daily sync of shared knowledge:
```bash
#!/bin/bash
cd ~/my-gt-mesh-node
git pull origin main
gt mesh sync
echo "Config synced at $(date)"
```

### `check-mail.sh`
Check DoltHub messages:
```bash
#!/bin/bash
cd /tmp/hq-sync
dolt pull origin main
dolt sql -q "SELECT from_gt, subject, created_at FROM messages WHERE to_gt = '$(grep instance.id ~/my-gt-mesh-node/mesh.yaml | awk '{print $2}')' AND read_at IS NULL ORDER BY created_at DESC"
```

## Directory Structure

```
~/my-gt-mesh-node/
├── mesh.yaml              # Your identity & config
├── agents/                # Your agent personalities
│   └── my-agent/
│       ├── SOUL.md
│       ├── IDENTITY.md
│       └── HEARTBEAT.md
├── memory/                # Local knowledge
│   ├── MISTAKES.md
│   └── SHARED_KNOWLEDGE.md
└── scripts/               # Automation
    ├── setup.sh
    ├── sync.sh
    └── check-mail.sh
```

## Validation

Check your config is valid:

```bash
gt mesh validate mesh.yaml
```

This verifies:
- ✓ Required fields present
- ✓ DoltHub org exists
- ✓ Instance ID is unique
- ✓ Email format valid

## Next Steps

1. Join the mesh: `gt mesh join MESH-CODE` (get code from admin)
2. Set up your first rig: `gt mesh rig create my-project`
3. Invite collaborators: `gt mesh invite --role contributor`
4. Start building together!

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "DoltHub connection failed" | Check `dolt creds ls` and verify key added to org |
| "Instance ID already exists" | Choose unique ID in mesh.yaml |
| "Mesh plugin not found" | Run `gt plugin install Deepwork-AI/gt-mesh` |
| "Cannot sync" | Check `gt mesh status` for errors |

---

**Template Version:** 1.0
**Last Updated:** 2026-03-06
**For:** GT Mesh Network

---
name: gt-mesh-setup
description: 'Interactive GT Mesh setup wizard. Use when someone says "set up mesh", "configure mesh", "initialize mesh", or "I want to join a mesh". Walks the user through installing gt-mesh, configuring identity, connecting to DoltHub, and choosing their role. Works for both new mesh creators and joiners.'
---

# GT Mesh Setup Wizard

This skill guides users through setting up GT Mesh — the collaboration
protocol for Gas Town. It handles both creating a new mesh and joining
an existing one.

## When to Use This Skill

Trigger on:
- "set up mesh" / "configure mesh" / "initialize mesh"
- "I want to create a mesh"
- "I have an invite code"
- "I want to join a mesh"
- "install gt-mesh"

## Setup Flow

### Step 1: Check Prerequisites

Before anything, verify:

```bash
# Dolt must be installed
dolt version

# Git must be configured
git config --global user.name
git config --global user.email

# GitHub CLI (optional but recommended)
gh auth status
```

If dolt is missing, tell the user:
```
Install Dolt: curl -L https://github.com/dolthub/dolt/releases/latest/download/install.sh | bash
```

If git identity is missing, ask the user for their name and email.

### Step 2: Determine Intent

Ask the user ONE question:

> Are you **creating a new mesh** or **joining an existing one** with an invite code?

### Path A: Creating a New Mesh

1. **Collect identity**:
   - Ask for GitHub username (MANDATORY — needed for contributor attribution)
   - Auto-detect name from `git config --global user.name`
   - Auto-detect email from `git config --global user.email`

2. **Run init**:
   ```bash
   GT_ROOT="$(pwd)" bash .gt-mesh/scripts/mesh-init.sh \
     --role coordinator \
     --github <username> \
     --email <email> \
     --owner "<name>"
   ```

3. **Configure behavioral role** (ask the user):
   > What's your primary role? This is a soft preference — you can always do anything.
   > - **planner** — Delegates by default. Creates tasks, assigns work, reviews.
   > - **worker** — Executes by default. Writes code, creates PRs.
   > - **reviewer** — Reviews by default. Approves, merges, quality gates.

   Then update mesh.yaml:
   ```yaml
   behavioral_role:
     this_gt: "<chosen_role>"
   ```

4. **Generate first invite** (optional):
   ```bash
   GT_ROOT="$(pwd)" bash .gt-mesh/scripts/mesh-invite.sh \
     --role write --expires 7d --note "First invite"
   ```

5. **Start daemon** (optional):
   ```bash
   GT_ROOT="$(pwd)" bash .gt-mesh/scripts/mesh-daemon.sh start
   ```

### Path B: Joining with Invite Code

1. **Collect the invite code** — format: `MESH-XXXX-YYYY`

2. **Collect identity**:
   - Ask for GitHub username (MANDATORY)
   - Ask for a GT name (or auto-generate: `gt-<hostname>`)

3. **Run join**:
   ```bash
   GT_ROOT="$(pwd)" bash .gt-mesh/scripts/mesh-join.sh \
     MESH-XXXX-YYYY \
     --github <username> \
     --name <gt-name>
   ```

4. **Verify connection**:
   ```bash
   GT_ROOT="$(pwd)" bash .gt-mesh/scripts/mesh-status.sh
   ```

5. **Say hello**:
   ```bash
   GT_ROOT="$(pwd)" bash .gt-mesh/scripts/mesh-send.sh \
     <coordinator-id> "Hello" "I just joined the mesh!"
   ```

### Step 3: Install Skills (Both Paths)

Copy the operator and contributor skills into Claude Code:

```bash
# Create skills directories
mkdir -p ~/.claude/skills/gt-mesh
mkdir -p ~/.claude/skills/gt-mesh-contributor

# Copy skills
cp .gt-mesh/skills/gt-mesh-setup/SKILL.md ~/.claude/skills/gt-mesh-setup/SKILL.md
cp <gt-mesh-repo>/skills/gt-mesh/SKILL.md ~/.claude/skills/gt-mesh/SKILL.md
cp <gt-mesh-repo>/skills/gt-mesh-contributor/SKILL.md ~/.claude/skills/gt-mesh-contributor/SKILL.md
```

After install, Claude Code will automatically know how to operate the mesh.

### Step 4: Verify Everything Works

Run through this quick check:

```bash
# 1. Status should show your identity
GT_ROOT="$(pwd)" bash .gt-mesh/scripts/mesh-status.sh

# 2. Rules should show governance
GT_ROOT="$(pwd)" bash .gt-mesh/scripts/mesh-rules.sh list

# 3. Access should show your peer entry
GT_ROOT="$(pwd)" bash .gt-mesh/scripts/mesh-access.sh list
```

## What mesh.yaml Looks Like After Setup

```yaml
instance:
  id: "gt-<name>"
  name: "gt-<name>"
  role: "coordinator"  # or the invite role
  owner:
    name: "<your name>"
    email: "<your email>"
    github: "<your github>"

behavioral_role:
  this_gt: "planner"  # soft preference: planner | worker | reviewer

dolthub:
  org: "deepwork"
  database: "gt-agent-mail"
  sync_interval: "2m"
  clone_dir: "/tmp/mesh-sync-clone"

rules:
  branch_format: "gt/{id}/{issue}-{desc}"
  pr_target: "dev"
  commit_format: "conventional"
  require_review: true
  no_force_push: true
  no_secrets_in_commits: true

daemon:
  enabled: true
  sync_interval: "2m"
```

## Behavioral Roles Explained

Roles are **soft preferences**, not hard blocks. Any GT can step in and do
any work when needed. The role just sets default behavior.

| Role | Default Behavior | Can Also... |
|------|-----------------|-------------|
| **planner** | Delegates. Creates tasks, assigns work, reviews PRs | Write code if workers are unavailable |
| **worker** | Executes. Writes code, creates PRs | Ask questions, suggest improvements |
| **reviewer** | Reviews. Approves/rejects PRs, merges | Write code if needed for fixes |

## Troubleshooting Setup

| Problem | Solution |
|---------|----------|
| "dolt: command not found" | Install: `curl -L https://github.com/dolthub/dolt/releases/latest/download/install.sh \| bash` |
| "Failed to clone DoltHub" | Run `dolt creds new` then `dolt creds use <key>`. Add key to DoltHub account. |
| "Invite code not found" | Code may be expired or typo. Ask coordinator for a fresh one. |
| "mesh.yaml already exists" | Re-init is safe — it preserves your existing config. |
| "Push deferred" | Normal if no internet. Will sync on next daemon cycle. |

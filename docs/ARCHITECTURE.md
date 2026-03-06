# GT Config: Federated Collaborative Coding Platform

**Status:** Draft v1
**Date:** 2026-03-06
**Author:** gt-local Mayor
**Epic:** hq-78jj0 (revised)

---

## Vision

GT Config turns Gas Town from a single-user tool into a **multiplayer collaborative
coding platform**. Two or more developers, each running their own Gas Town, can
connect into a mesh network and collaborate through shared AI agents.

**The pitch:** "I invite my friend. They join my workspace. They create beads.
My polecats build the features. We're vibe coding together."

**This is NOT** about running multiple autonomous GTs for one person. It's about
**multiple people** working together, each with their own GT, sharing compute
and context through a federated network.

---

## Core User Flow

```
OWNER (Pratham)                           FRIEND (Alex)
─────────────────                         ──────────────
Has Gas Town running                      Has their own Gas Town
with rigs, polecats, agents

1. gt mesh invite \
     --role contributor \
     --rigs villa_ai_planogram \
     --expires 24h
   → generates config snippet

2. Sends snippet to Alex               → Receives snippet
   (Slack, email, whatever)

                                        3. gt mesh join <snippet>
                                           → auto-configures DoltHub sync
                                           → registers as peer
                                           → can see villa_ai_planogram rig

                                        4. Uses their own GT + API keys to
                                           read the codebase, understand context

                                        5. bd create --rig villa_ai_planogram \
                                             "Add dark mode to dashboard"
                                           → bead created
                                           → mail sent to Owner's Mayor

6. Mayor receives mail:
   "Alex wants: Add dark mode"
   Reviews → accepts

7. gt sling <bead> villa_ai_planogram
   → polecat picks it up
   → work gets done
   → PR created

8. Mail back to Alex:                   → "PR merged, dark mode is live"
   "Feature complete"

                                        9. Access expires after 24h
                                           (or owner revokes with gt mesh revoke)
```

---

## Architecture Overview

```
                    ┌─────────────────────────┐
                    │   DoltHub Mail Server    │
                    │  deepwork/gt-mesh-mail   │
                    │                          │
                    │  messages | peers        │
                    │  channels | access       │
                    │  invites  | findings     │
                    └────────┬────────────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
         ┌────▼────┐   ┌────▼────┐   ┌────▼────┐
         │ GT-local │   │GT-docker│   │ GT-alex │
         │ (owner)  │   │(worker) │   │ (contrib│
         │          │   │         │   │  utor)  │
         │ rigs:    │   │ rigs:   │   │ rigs:   │
         │  vap     │   │  own    │   │  own    │
         │  vaa     │   │  stuff  │   │  stuff  │
         │  gta     │   │         │   │         │
         └──────────┘   └─────────┘   └─────────┘
              ▲              ▲              ▲
         sync 2min      sync 2min      sync 2min
```

**Key principle:** Every GT syncs with ONE central DoltHub database. Not with
each other. This scales linearly — adding a GT = one more sync client. No N^2
connections.

---

## Mail Infrastructure at Scale (20+ GTs)

### The Problem

Point-to-point sync between N GTs = N*(N-1)/2 connections.
- 2 GTs = 1 connection (current state)
- 5 GTs = 10 connections
- 20 GTs = 190 connections (unmanageable)

### The Solution: Hub Model

One shared DoltHub database acts as the mail backbone. All GTs sync to this
single hub. Messages are append-only rows — no merge conflicts.

**For 20 GTs at 2-minute sync intervals:**
- 20 sync clients, each doing pull+push every 2 minutes
- 10 pushes/min + 10 pulls/min to DoltHub (well within rate limits)
- Each sync only transfers NEW rows since last pull (delta sync)
- DoltHub handles concurrent pushes via Dolt's 3-way merge

### Database Schema

```sql
-- The shared DoltHub database: deepwork/gt-mesh-mail

-- All messages in the mesh
CREATE TABLE messages (
    id          VARCHAR(36) PRIMARY KEY,   -- UUID
    from_gt     VARCHAR(64) NOT NULL,      -- sender GT instance ID
    from_addr   VARCHAR(128) NOT NULL,     -- sender address (e.g., "mayor/")
    to_gt       VARCHAR(64),               -- recipient GT (NULL = channel msg)
    to_addr     VARCHAR(128),              -- recipient address
    channel     VARCHAR(128),              -- channel name (NULL = direct msg)
    subject     VARCHAR(512) NOT NULL,
    body        TEXT NOT NULL,
    priority    TINYINT DEFAULT 2,         -- 0=critical, 4=low
    created_at  DATETIME NOT NULL,
    read_at     DATETIME,                  -- set by recipient
    thread_id   VARCHAR(36),               -- for threaded conversations
    metadata    JSON                       -- extensible (attachments, bead refs)
);

-- All GTs in the mesh
CREATE TABLE peers (
    gt_id       VARCHAR(64) PRIMARY KEY,   -- unique instance ID
    name        VARCHAR(128) NOT NULL,     -- human-readable name
    owner       VARCHAR(128) NOT NULL,     -- owner name/email
    role        ENUM('coordinator','worker','contributor') NOT NULL,
    status      ENUM('active','idle','offline','expired') DEFAULT 'active',
    dolt_pubkey VARCHAR(128),              -- DoltHub credential public key
    capabilities JSON,                     -- rig names, agent types, specializations
    joined_at   DATETIME NOT NULL,
    last_seen   DATETIME NOT NULL,         -- updated every sync
    expires_at  DATETIME,                  -- NULL = permanent, else auto-expire
    invited_by  VARCHAR(64),               -- which GT invited this peer
    metadata    JSON                       -- version, platform, etc.
);

-- Communication channels
CREATE TABLE channels (
    id          VARCHAR(128) PRIMARY KEY,  -- channel name (e.g., "#rig-vap")
    name        VARCHAR(256) NOT NULL,     -- display name
    type        ENUM('dm','rig','broadcast','convoy','custom') NOT NULL,
    created_by  VARCHAR(64) NOT NULL,      -- GT that created it
    created_at  DATETIME NOT NULL,
    rig_name    VARCHAR(64),               -- linked rig (for type=rig)
    metadata    JSON
);

-- Channel membership
CREATE TABLE channel_members (
    channel_id  VARCHAR(128) NOT NULL,
    gt_id       VARCHAR(64) NOT NULL,
    role        ENUM('owner','admin','member','readonly') DEFAULT 'member',
    joined_at   DATETIME NOT NULL,
    PRIMARY KEY (channel_id, gt_id)
);

-- Access control: which GT can see which rigs
CREATE TABLE access (
    id          VARCHAR(36) PRIMARY KEY,
    gt_id       VARCHAR(64) NOT NULL,      -- who has access
    rig_name    VARCHAR(64) NOT NULL,      -- to which rig
    role        ENUM('viewer','contributor','reviewer','admin') NOT NULL,
    granted_by  VARCHAR(64) NOT NULL,      -- who granted it
    granted_at  DATETIME NOT NULL,
    expires_at  DATETIME,                  -- NULL = permanent
    revoked_at  DATETIME,                  -- set when revoked
    UNIQUE KEY (gt_id, rig_name)
);

-- Mesh invites
CREATE TABLE invites (
    code        VARCHAR(64) PRIMARY KEY,   -- invite code
    created_by  VARCHAR(64) NOT NULL,      -- owner GT
    role        ENUM('worker','contributor','reviewer') NOT NULL,
    rig_scope   JSON,                      -- which rigs (NULL = all visible)
    expires_at  DATETIME NOT NULL,
    claimed_by  VARCHAR(64),               -- GT that used this invite
    claimed_at  DATETIME,
    metadata    JSON                       -- custom permissions, notes
);

-- Shared findings (knowledge layer — Phase 2+)
CREATE TABLE findings (
    id          VARCHAR(36) PRIMARY KEY,
    source_gt   VARCHAR(64) NOT NULL,
    category    ENUM('pattern','mistake','solution','architecture') NOT NULL,
    title       VARCHAR(512) NOT NULL,
    content     TEXT NOT NULL,
    confidence  TINYINT DEFAULT 3,         -- 1-5 scale
    created_at  DATETIME NOT NULL,
    tags        JSON,
    adopted_count INT DEFAULT 0,           -- denormalized for quick reads
    rejected_count INT DEFAULT 0
);

-- Finding adoption tracking
CREATE TABLE adoptions (
    finding_id  VARCHAR(36) NOT NULL,
    gt_id       VARCHAR(64) NOT NULL,
    adopted     BOOLEAN NOT NULL,
    reason      TEXT,                      -- why accepted/rejected
    adopted_at  DATETIME NOT NULL,
    PRIMARY KEY (finding_id, gt_id)
);
```

### Addressing Model

Messages use a hierarchical addressing scheme:

| Address Format | Meaning | Example |
|---------------|---------|---------|
| `<gt-id>/mayor/` | Specific agent on specific GT | `gt-docker/mayor/` |
| `<gt-id>/` | Any agent on that GT | `gt-local/` |
| `#general` | All GTs in the mesh | broadcast |
| `#rig-<name>` | All GTs with access to that rig | `#rig-villa_ai_planogram` |
| `#convoy-<id>` | Convoy participants | `#convoy-planogram-v2` |
| `@contributors` | All contributors | group alias |
| `@workers` | All workers | group alias |

### Sync Model

```
Every 2 minutes (configurable per GT):

1. PULL from DoltHub
   └─ Get new rows since last sync (messages, peers, invites, etc.)

2. PROCESS incoming
   ├─ New messages addressed to us → deliver to local mail
   ├─ Peer status updates → update local peer cache
   ├─ Invite claims → process if we're the inviter
   └─ Access changes → update local access cache

3. PUSH to DoltHub
   ├─ Outbox messages → messages table
   ├─ Our last_seen → peers table
   ├─ Any invite claims → invites table
   └─ Any new findings → findings table

4. HEALTH CHECK
   ├─ Mark peers with last_seen > 10min as offline
   ├─ Mark peers past expires_at as expired
   └─ Revoke access for expired peers
```

### Conflict Resolution

Messages are append-only (INSERT, never UPDATE for content). The only mutable
fields are:
- `messages.read_at` — only updated by recipient GT (no conflict)
- `peers.last_seen` — only updated by owner GT (no conflict)
- `peers.status` — only updated by owner GT (no conflict)
- `invites.claimed_by` — race condition possible (two GTs claim same invite)
  → Dolt merge picks one winner, loser detects on next pull and gets "already claimed"

No merge conflicts in practice because each GT only writes to its own rows.

---

## GT Config Plugin Architecture

### What is GT Config?

GT Config is a **plugin for existing Gas Town installations**. It adds mesh
networking capabilities to any GT instance.

```
Existing GT installation
├── mayor/
├── rigs/
├── .beads/
├── .dolt-data/
└── gtconfig/              ← THE PLUGIN
    ├── gtconfig.yaml      ← Identity + mesh config
    ├── mesh/
    │   ├── peers.cache    ← Local peer cache
    │   ├── invites/       ← Pending invites
    │   └── sync.log       ← Sync history
    └── scripts/
        ├── sync.sh        ← DoltHub sync cron
        ├── invite.sh      ← Generate invites
        └── join.sh        ← Process invite + join mesh
```

### gtconfig.yaml — The Identity File

```yaml
# GT Config — Mesh Network Identity & Settings
version: 1

# This GT's identity
instance:
  id: "gt-local"                    # Unique across the mesh
  name: "Pratham's Gas Town"        # Human-readable
  role: "coordinator"               # coordinator | worker | contributor
  owner:
    name: "Pratham"
    email: "prathamonchain@gmail.com"
    github: "freebird-ai"

# DoltHub connection (the mesh backbone)
dolthub:
  org: "deepwork"
  database: "gt-mesh-mail"
  credential_pubkey: "bqh2k0mvac4achivnalmcr9t6d9jcohersfk7bf7ip52aobb4v2g"
  sync_interval: "2m"               # How often to sync
  sync_dir: "/tmp/gt-mesh-sync"     # Clone dir (NOT sql-server dir)

# Which rigs are shared on the mesh
shared_rigs:
  - name: "villa_ai_planogram"
    visibility: "invite-only"       # public | invite-only | private
    accept_contributions: true
    auto_accept_from: []            # GT IDs whose beads auto-accept
  - name: "villa_alc_ai"
    visibility: "private"           # Not shared
    accept_contributions: false

# Default permissions for new contributors
defaults:
  contributor_role: "contributor"
  contributor_expiry: "7d"          # Default invite expiry
  auto_accept_beads: false          # Require mayor review by default

# Notification preferences
notifications:
  new_peer: true                    # Alert when someone joins
  new_contribution: true            # Alert when contributor creates bead
  peer_offline: true                # Alert when peer goes offline >10min
```

### gt mesh Commands

```bash
# --- Owner commands ---

gt mesh init                        # Initialize gtconfig plugin
                                    # Creates gtconfig.yaml, sets up DoltHub sync

gt mesh status                      # Show mesh health dashboard
                                    # Lists all peers, their status, last seen

gt mesh invite \                    # Generate invite for a friend
  --role contributor \
  --rigs villa_ai_planogram \
  --expires 24h
# → Outputs a config snippet (base64-encoded YAML blob)
# → Also creates a short invite code for easier sharing

gt mesh revoke <gt-id>              # Revoke a peer's access immediately
gt mesh revoke --invite <code>      # Revoke an unclaimed invite

gt mesh peers                       # List all peers
gt mesh peers --online              # List online peers only

gt mesh access list                 # Show access control table
gt mesh access grant <gt-id> \      # Grant rig access
  --rig villa_ai_planogram \
  --role reviewer

gt mesh access revoke <gt-id> \     # Revoke rig access
  --rig villa_ai_planogram

# --- Contributor commands ---

gt mesh join <snippet-or-code>      # Join a mesh using invite
                                    # Sets up DoltHub sync, registers as peer
                                    # Gets access to invited rigs

gt mesh leave                       # Leave the mesh gracefully
                                    # Deregisters from peers table

gt mesh rigs                        # List rigs you have access to

# --- Common commands ---

gt mesh sync                        # Force immediate sync (don't wait for cron)
gt mesh log                         # Show recent sync activity
gt mesh ping <gt-id>                # Check if a peer is reachable
```

### Invite Snippet Format

When an owner runs `gt mesh invite`, it generates something like:

```yaml
# GT Mesh Invite — paste this into: gt mesh join <file>
# Or use code: MESH-A7K9-XPLN
# Expires: 2026-03-07T11:00:00Z
mesh_invite:
  code: "MESH-A7K9-XPLN"
  mesh:
    dolthub_org: "deepwork"
    dolthub_db: "gt-mesh-mail"
  invited_by: "gt-local"
  role: "contributor"
  rigs:
    - "villa_ai_planogram"
  expires: "2026-03-07T11:00:00Z"
```

The friend can either:
1. Save to a file and run `gt mesh join invite.yaml`
2. Use the short code: `gt mesh join MESH-A7K9-XPLN`

---

## Contributor Bead Flow (The Review Gate)

When a contributor creates a bead on a shared rig, it doesn't go straight to
the polecat queue. It goes through a review gate.

```
Contributor GT                    Owner GT
─────────────                     ────────

bd create --rig vap \
  "Add dark mode"
    │
    ▼
Creates bead locally
with status: proposed
    │
    ▼
Sync pushes to DoltHub ────────► Sync pulls new bead
                                     │
                                     ▼
                                 Mayor gets mail:
                                 "Contribution from gt-alex:
                                  Add dark mode to dashboard"
                                     │
                              ┌──────┴──────┐
                              │             │
                         ACCEPT          REJECT
                              │             │
                              ▼             ▼
                         Status →      Mail back:
                         open          "Rejected: reason"
                              │
                              ▼
                         gt sling → polecat works
                              │
                              ▼
                         PR created
                              │
                              ▼
                         Mail to contributor:
                         "Feature built, PR #42"
```

### Commands for the review gate

```bash
# Owner reviews incoming contributions
gt mesh contributions                    # List pending contributions
gt mesh accept <bead-id>                # Accept → becomes normal bead
gt mesh reject <bead-id> --reason "..." # Reject with explanation
gt mesh accept --from <gt-id> --all     # Accept all from trusted peer
```

---

## Implementation Phases (Revised)

### Phase 0: Foundation (NOW — in progress)
**Goal:** DoltHub mail bridge working between gt-local and gt-docker.

- [x] DoltHub shared DB created (deepwork/gt-agent-mail)
- [x] gt-local sync cron running
- [ ] gt-docker completes their sync setup
- [ ] Verified cross-GT mail delivery

### Phase 1: Mesh Plugin Core
**Goal:** `gt mesh init`, `gt mesh invite`, `gt mesh join` working.

| Task | Description | Owner |
|------|-------------|-------|
| gtconfig.yaml schema | Design the identity + mesh config file | gt-docker proposes, gt-local reviews |
| gt mesh init | Create gtconfig.yaml, set up DoltHub sync | gt-local |
| gt mesh invite | Generate invite snippet with access scope | gt-local |
| gt mesh join | Process invite, register as peer, start sync | gt-docker |
| Peer registry | peers table in DoltHub, auto-health tracking | gt-local |
| Schema migration | Migrate from gt-agent-mail to gt-mesh-mail | gt-local |

### Phase 2: Contribution Flow
**Goal:** Contributors can create beads on shared rigs, owners review and accept.

| Task | Description | Owner |
|------|-------------|-------|
| Remote bead creation | Contributor creates bead, syncs to mesh DB | Both |
| Review gate | Mayor gets mail for incoming contributions | gt-local |
| Accept/reject flow | gt mesh accept/reject commands | gt-local |
| Notification system | Mail notifications for all contribution events | Both |
| Access control | Enforce rig visibility and role permissions | gt-local |

### Phase 3: Multi-Rig Collaboration
**Goal:** Multiple rigs shared, multiple contributors, convoy support.

| Task | Description | Owner |
|------|-------------|-------|
| Multi-rig sharing | Share multiple rigs per invite | gt-local |
| Convoy across GTs | Cross-GT convoy coordination | Both |
| Contributor dashboard | Show contributors their beads, PR status | gt-docker |
| Auto-accept rules | Trusted peers skip review gate | gt-local |

### Phase 4: Knowledge Network
**Goal:** Findings propagate across the mesh. Exponential learning.

| Task | Description | Owner |
|------|-------------|-------|
| Findings table | Schema + write path for GT discoveries | Both |
| Mirror system | Deacon reviews incoming findings | gt-local |
| Adoption tracking | Record accept/reject with reasons | Both |
| Quality signals | Adoption rate as finding quality metric | gt-local |

### Phase 5: Public Release
**Goal:** Anyone can set up GT Config and join/create a mesh.

| Task | Description | Owner |
|------|-------------|-------|
| Bootstrap script | One-command install for new GT + mesh join | gt-docker |
| Documentation | README, quickstart, example configs | Both |
| `gtconfig init` CLI | Interactive scaffold for new config | gt-docker |
| Template configs | Starter configs for common setups | Both |

---

## Scale Considerations (20+ GTs)

### Sync Performance

| GTs | Pushes/min | Pulls/min | DoltHub load | Viable? |
|-----|-----------|-----------|-------------|---------|
| 2   | 1         | 1         | Trivial     | Yes |
| 5   | 2.5       | 2.5       | Light       | Yes |
| 10  | 5         | 5         | Moderate    | Yes |
| 20  | 10        | 10        | Moderate    | Yes |
| 50  | 25        | 25        | Heavy       | Maybe (increase interval to 5min) |
| 100 | 50        | 50        | Too heavy   | Need relay architecture |

### Beyond 50 GTs: Relay Nodes

For very large meshes, introduce relay nodes:

```
                    ┌─────────────────┐
                    │  DoltHub Master  │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
         ┌────▼────┐   ┌────▼────┐   ┌────▼────┐
         │ Relay A  │   │ Relay B  │   │ Relay C  │
         │ (region) │   │ (region) │   │ (region) │
         └────┬────┘   └────┬────┘   └────┬────┘
              │              │              │
         ┌────┼────┐   ┌────┼────┐   ┌────┼────┐
         GT1  GT2  GT3  GT4  GT5  GT6  GT7  GT8  GT9
```

Relay nodes aggregate sync for their region. Each GT syncs with its relay
(local Dolt), relays sync with the master DoltHub. Reduces DoltHub load from
N to R (number of relays).

**Not needed until 50+ GTs.** Keep the simple hub model for now.

### Message Volume Management

As the mesh grows, message volume grows. Strategies:
- **TTL on messages:** Auto-delete messages older than 30 days
- **Channel filtering:** Each GT only pulls messages for its subscribed channels
- **Pagination:** Sync only pulls last N messages on first join, then deltas
- **Archive:** Old messages moved to archive table (queryable but not synced)

### Security at Scale

- **Invite-only by default.** No open mesh join.
- **Expiring access.** Contributors expire after their invite period.
- **Rig-level isolation.** Contributors only see rigs they're invited to.
- **Read-only context.** Contributors read code via their own GT, never get
  direct access to owner's filesystem or agents.
- **Review gate.** All external beads require owner approval.
- **Revocation propagates immediately.** Next sync removes access.
- **Audit log.** All access grants/revokes logged in the mesh DB.

---

## Comparison: Old Plan vs New Plan

| Aspect | Old Plan (Mesh Network) | New Plan (Collab Platform) |
|--------|------------------------|---------------------------|
| **Who** | One person, multiple GTs | Multiple people, each with GT |
| **Why** | Autonomous GT coordination | Human collaboration through agents |
| **Join** | Manual GitHub + DoltHub setup | One invite code, one command |
| **Access** | Permanent, symmetric | Time-limited, asymmetric (owner/contributor) |
| **Work flow** | GT assigns to GT | Human creates bead → owner reviews → polecat executes |
| **Scale model** | N^2 point-to-point | Hub-and-spoke via DoltHub |
| **Knowledge** | Still included (Phase 4) | Deprioritized, but architecture supports it |

---

## Open Questions

1. **DoltHub pricing at scale.** Free tier supports how many pushes/pulls?
   Need to verify limits for 20+ GT mesh.

2. **Bead sync format.** Do contributors create beads locally and sync the
   bead data through the mesh DB? Or do they create a "contribution request"
   that the owner's GT materializes as a bead?

3. **Code context sharing.** How does a contributor read the owner's codebase?
   Options: (a) they have their own clone of the repo, (b) read-only API,
   (c) the invite includes repo access (GitHub collaborator invite).

4. **Real-time vs polling.** 2-minute sync is fine for async work. For
   real-time pairing, we'd need websockets or a different channel.

5. **Multi-owner meshes.** Can a mesh have multiple coordinators? Or is it
   always one owner + N contributors? The schema supports it, but the
   review gate assumes one owner.

---

## Related Documents

- Beads: hq-78jj0 (epic), hq-gtc01 through hq-gtc06 (sub-tasks)
- GitHub: Deepwork-AI/gtconfig (issues #1-#6)
- Memory: /home/pratham2/.claude/projects/-home-pratham2-gt/memory/MEMORY.md
- Worker instructions: /home/pratham2/gt/mayor/multi-gt-worker-instructions.md

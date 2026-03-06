# gtconfig.yaml — Standard Mesh Config Specification v1
#
# Every GT mesh node has a gtconfig.yaml (replaces mesh.yaml).
# This is the single source of truth for a node's identity, behavior,
# connections, and installed packs.
#
# The file is created on `gt mesh init` or `gt mesh join` and updated
# by `gt mesh packs install` and `gt mesh config pull`.

# Schema version (for forward compatibility)
config_version: 1

# --- IDENTITY ---
# Who is this GT node?
instance:
  id: "gt-local"                      # Unique across the mesh (required)
  name: "Pratham's Gas Town"           # Human-readable display name
  role: "coordinator"                  # coordinator | worker | contributor
  owner:
    name: "Pratham"                    # Human name
    email: "pratham@example.com"       # Contact email
    github: "freebird-ai"             # GitHub username (for attribution)
  invited_by: ""                       # GT ID that invited this node (empty if coordinator)
  invite_code: ""                      # Invite code used to join (empty if coordinator)

# --- BEHAVIORAL ROLE ---
# Soft preference — what this GT does by default (not a hard block)
behavioral_role:
  this_gt: "planner"                   # planner | worker | reviewer
  peer_roles:                          # Optional: override roles for known peers
    gt-docker:
      role: "worker"
      specialties: ["backend", "infrastructure"]
      max_concurrent: 3

# --- MESH CONNECTION ---
# How this node connects to the mesh backbone
dolthub:
  org: "deepwork"                      # DoltHub organization
  database: "gt-agent-mail"            # Shared database name
  credential_pubkey: ""                # This node's DoltHub public key
  sync_interval: "2m"                  # Pull/push frequency
  clone_dir: "/tmp/mesh-sync-clone"    # Local clone directory (NOT sql-server dir)

# --- MESH IDENTITY ---
# Which mesh network this node belongs to
mesh:
  id: "deepwork-mesh"                  # Mesh network ID
  config_version: ""                   # Last pulled config version hash

# --- SHARED RIGS ---
# Which rigs are visible to other mesh participants
shared_rigs:
  - name: "villa_ai_planogram"
    visibility: "invite-only"          # public | invite-only | private
    accept_contributions: true
    auto_accept_from: []               # GT IDs whose beads auto-accept
  - name: "villa_alc_ai"
    visibility: "private"
    accept_contributions: false

# --- GOVERNANCE RULES ---
# Inline rules (also synced to DoltHub mesh_rules table)
rules:
  branch_format: "gt/{id}/{issue}-{desc}"
  pr_target: "dev"
  commit_format: "conventional"
  require_issue_reference: true
  max_concurrent_claims: 3
  require_review: true
  no_force_push: true
  no_secrets_in_commits: true

# --- INSTALLED PACKS ---
# Packs installed from the mesh registry
packs:
  # - name: "deepwork-base"
  #   version: "1.0.0"
  #   installed_at: "2026-03-06T15:00:00Z"
  # - name: "frontend-skills"
  #   version: "2.1.0"
  #   installed_at: "2026-03-06T15:10:00Z"

# --- NOTIFICATION PREFERENCES ---
notifications:
  new_peer: true                       # Alert when someone joins the mesh
  new_contribution: true               # Alert when contributor creates bead
  peer_offline: true                   # Alert when peer offline >10min
  pack_updates: true                   # Alert when installed pack has update
  config_updates: true                 # Alert when mesh config changes

# --- DAEMON ---
# Background sync daemon settings
daemon:
  enabled: true
  sync_interval: "2m"
  auto_claim:
    enabled: false
    max_concurrent: 2

# --- FEED ---
# Activity feed preferences
feed:
  delivery: "digest"                   # realtime | digest | off
  digest_interval: "30m"

# --- DEFAULTS FOR NEW CONTRIBUTORS ---
# Only used by coordinators
defaults:
  contributor_role: "contributor"
  contributor_expiry: "7d"
  auto_accept_beads: false

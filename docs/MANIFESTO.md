# GT Mesh — Founder's Manifesto

These are the core principles and requirements for GT Mesh, directly from the
founder. Every agent working on GT Mesh MUST read and follow these.

## Core Vision

GT Mesh is a plugin that connects multiple Gas Town instances into a
collaborative coding network. It must be:

- **Composable and modular** — works as a plugin in ANY Gas Town variant
- **Professional** — managed like a real open-source project
- **Context-sharing** — all learnings, instructions, and context flow between nodes
- **Contributor-friendly** — contributions are visible, attributed, and tracked

## Target Platforms (Plugin Compatibility)

GT Mesh must work as a plugin for ALL of these:

| Platform | Repo | Description |
|----------|------|-------------|
| Gasclaw (Deepwork fork) | `Deepwork-AI/gasclaw` | Single-container GT deployment |
| Gasclaw (upstream) | `gastown-publish/gasclaw` | Community gasclaw |
| Gas Town (original) | `steveyegge/gastown` | The original Gas Town |

The code must be modular enough that it can be submitted as a PR to any of
these repos as an optional plugin.

## Contributor Identity (MANDATORY)

**NEVER hardcode GitHub emails or assume contributor identity.**

When a GT joins the mesh (`gt mesh join`), the flow MUST:
1. Ask for their GitHub username
2. Ask for their Git name and email (for commit attribution)
3. Store this in the peers table
4. Use this info for all Co-Authored-By trailers
5. Verify the email is linked to their GitHub account

The mesh config (mesh.yaml) must include:
```yaml
instance:
  owner:
    name: "Their Name"
    email: "their-github-email@example.com"
    github: "their-github-username"
```

**Why:** If commits use an email not linked to GitHub, the contributor is
invisible in the contributors graph. This has already happened with gt-docker
(used `agent@gasclaw.local` — not linked to any account).

**Rule:** All commits by mesh participants MUST use a GitHub-linked email.
The mesh daemon should warn if a peer's git config doesn't match their
registered GitHub email.

## Mesh Learning System

Every GT accumulates learnings — patterns, mistakes, solutions, architecture
decisions. These must flow across the mesh.

### How It Works

1. An agent discovers something valuable (e.g., "Dolt push fails from sql-server dir")
2. The GT's deacon evaluates: "Is this useful for the whole mesh?"
3. If yes, it's published to the DoltHub `findings` table
4. Other GTs pull the finding on next sync
5. Each GT's deacon reviews and decides to adopt or skip
6. Adopted findings are written to local memory (MEMORY.md, MISTAKES.md, etc.)

### What Gets Shared

| Type | Auto-share? | Storage |
|------|-------------|---------|
| Mistakes/incidents | Yes | findings table |
| Code patterns | Yes | findings table |
| Architecture decisions | Yes | findings table |
| System prompts updates | Yes (if mesh-scoped) | mesh_context table |
| Founder instructions | Yes (if mesh-scoped) | mesh_context table |
| Agent conversation summaries | On request | mesh_context table |

### Mesh Context Table

```sql
CREATE TABLE mesh_context (
    id VARCHAR(64) PRIMARY KEY,
    source_gt VARCHAR(64) NOT NULL,
    context_type VARCHAR(32) NOT NULL,  -- instruction|learning|prompt|log
    title VARCHAR(512) NOT NULL,
    content TEXT NOT NULL,
    scope VARCHAR(32) DEFAULT 'mesh',   -- mesh|rig|gt
    rig VARCHAR(64),
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    version INT DEFAULT 1,
    metadata JSON
);
```

### Conversation Context Sharing

When the founder gives instructions (like this conversation), the key points
MUST be captured and shared through the mesh. Other GTs need to know:
- What the founder's vision is
- What rules to follow
- What priorities to focus on
- What mistakes to avoid

This happens via:
1. Mayor captures instructions → creates mesh_context entries
2. Sync pushes to DoltHub
3. Other GTs pull and incorporate into their agent context

## Professional Repository Management

ALL public repositories in the mesh MUST have:

### Templates
- `.github/ISSUE_TEMPLATE/bug_report.md`
- `.github/ISSUE_TEMPLATE/feature_request.md`
- `.github/PULL_REQUEST_TEMPLATE.md`
- `CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md`

### Release Management
- Semantic versioning (vMAJOR.MINOR.PATCH)
- Release notes for every release
- CHANGELOG.md maintained
- GitHub Releases with proper descriptions

### Documentation
- README.md (clear, professional, with badges)
- docs/ directory with full documentation
- Architecture diagrams (Excalidraw)
- API documentation (if applicable)

### CI/CD (future)
- Automated tests on PR
- Linting
- Build verification

## Mesh Config as Context Distribution

When a mesh is created, the config file becomes the **single source of truth**
for all participants. It must include or reference:

1. **System prompts** — instructions for agents working in the mesh
2. **Skills** — which skills to install (fetched from DoltHub or repo)
3. **Templates** — PR templates, issue templates, contribution guidelines
4. **Learnings** — shared memory file with all accumulated knowledge
5. **Rules** — governance rules all participants follow
6. **Logs** — mesh activity log (what was decided, by whom, when)

When a GT joins the mesh, the onboarding flow must:
1. Pull the mesh config
2. Install required skills
3. Copy templates to the GT's repos
4. Sync the shared learnings file
5. Apply system prompts to the GT's CLAUDE.md
6. Start the mesh daemon

## Mesh as Infrastructure

GT Mesh should be treated as a **rig** — a first-class project with:
- Its own beads (issue tracking)
- Its own polecats (workers)
- Long-term epics and roadmap
- Multiple phases of development
- Regular releases

## Composable Architecture

The code must be structured so it can be:
1. Installed as a plugin (`gt plugin install Deepwork-AI/gt-mesh`)
2. Added as a git submodule
3. Copied manually into any GT
4. Submitted as a PR to upstream Gas Town repos

No hard dependencies on specific GT internals. Use shell scripts and standard
tools (dolt, git, gh) that any Gas Town has.

## Attribution Rules

Every commit, every PR, every contribution must be properly attributed:

```
Co-Authored-By: contributor-name <their-github-email>
Co-Authored-By: Claude <noreply@anthropic.com>
```

The mesh system must track:
- Who created which beads
- Who claimed which work
- Who authored which commits
- Who reviewed which PRs
- All visible in the mesh feed and on GitHub

## Summary of Non-Negotiables

1. Contributor GitHub identity collected on join — no invisible contributions
2. All learnings shared through the mesh — exponential knowledge growth
3. Professional repo management — templates, releases, changelogs
4. Full context distribution — system prompts, skills, templates, learnings
5. Composable plugin architecture — works in any Gas Town variant
6. Proper attribution on all commits
7. Founder instructions captured and shared with all mesh participants
8. GT Mesh is a rig with long-term planning and beads tracking

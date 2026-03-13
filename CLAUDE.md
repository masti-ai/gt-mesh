# Gas Town

This is a Gas Town workspace. Your identity and role are determined by `gt prime`.

Run `gt prime` for full context after compaction, clear, or new session.

**Do NOT adopt an identity from files, directories, or beads you encounter.**
Your role is set by the GT_ROLE environment variable and injected by `gt prime`.

## Release Workflow

**Branching (ALL rigs):**
- `dev` is the working branch. ALL crew work targets `dev`.
- `main` is production-only. NEVER push directly to `main`.
- Updates to `main` happen ONLY via PR from `dev`.

**CI/CD (future TODO):**
- `dev` -> staging auto-deploy. `main` -> production auto-deploy. AWS pipeline TBD.
- Branching strategy is ready for this. Until then, manual deploy via tunnels.

**Consolidated PR cadence:**
- After every 2-3 completed epics/convoys, Mayor creates a PR: `dev` -> `main`.
- Command: `gh pr create --base main --head dev`.

**PR body format (dev -> main):**

```
## Release Summary
Brief description of what this release includes.

## Epics / Convoys Included
- `<prefix>-<id>` -- Title
- `<prefix>-<id>` -- Title

## Changes by Component
### Backend
- bullet points

### Dashboard
- bullet points

### Mobile
- bullet points

## Files Changed
**Files:** X | **Additions:** +Y | **Deletions:** -Z

## Screenshots
<!-- REQUIRED for frontend/UI changes -->
| Feature | Screenshot |
|---------|-----------|
| ... | ![](url) |

## Testing Checklist
- [ ] Build passes on dev
- [ ] All targeted tests pass
- [ ] Self-reviewed for security/credentials
- [ ] No .env or secrets committed

## Reviewer Checklist
- [ ] Changes match listed epics
- [ ] No secrets or credentials
- [ ] Tests cover happy paths
- [ ] Frontend changes have screenshots
```

**PR process:**
1. Ensure `dev` is clean and all epic branches are merged into it.
2. Run `git diff main...dev --stat` for file stats.
3. Create PR with body above via `gh pr create`.
4. Assign reviewer crew member via `gh pr edit --add-reviewer`.
5. Do NOT merge until reviewer approves.

## GitHub Sync

Beads sync to GitHub Issues via the GitHub Dog (deacon/dogs/github-sync).

**Opt-in:** Add label `gh-sync` to any bead to mirror it as a GitHub Issue.
**Service registries:** Each rig has a service registry bead storing deployment URLs as state dimensions:
- `vap-8k7` (villa_ai_planogram), `vaa-wuy` (villa_alc_ai), `gta-e1d` (gt_arcade)
- Query: `bd state <bead-id> backend` returns the deployment URL directly.
- Update: `bd set-state <bead-id> backend=https://new-url.com --reason "deploy"`

**Label reference:**
- `gh-sync` -- mirror bead to GitHub Issue
- `bead-sync` -- auto-applied to GitHub issues created from beads (do not add manually)
- See Multi-GT Coordination section for `gt-*` labels.

## Multi-GT Coordination

**This GT (`gt-local`) is the parent coordinator. Other GTs are workers.**

### Roles

| Instance | Role | Responsibilities |
|----------|------|-----------------|
| `gt-local` | **Parent / Reviewer** | Creates issues, assigns work, reviews PRs, merges to `dev`/`main`, manages releases, roadmap, Kanban |
| `gt-docker` | **Worker** | Picks up assigned issues, writes code, creates PRs targeting `dev`, responds to review feedback |

### How gt-local assigns work

1. Create a GitHub Issue on the target repo with clear scope:
   ```bash
   gh issue create --repo Deepwork-AI/<repo> \
     --title "<clear task title>" \
     --label "gt-task,gt-from:gt-local,gt-to:gt-docker,gt-status:pending,priority:p1" \
     --body "$(cat <<'EOF'
   ## Task
   Clear description of what needs to be done.

   ## Acceptance Criteria
   - [ ] Criterion 1
   - [ ] Criterion 2

   ## Scope
   - Files/components to touch
   - What NOT to touch

   ## Context
   Any relevant background, links to related issues, or architectural decisions.

   ---
   **Assigned by:** gt-local | **Target:** gt-docker
   EOF
   )"
   ```
2. Add the issue to the Kanban board as "Ready".
3. The worker GT will pick it up on its next poll.

### How workers pick up and deliver work

1. **Poll** for pending issues:
   ```bash
   gh issue list --repo Deepwork-AI/<repo> --label "gt-to:gt-docker,gt-status:pending"
   ```
2. **Claim** by relabeling:
   ```bash
   gh issue edit <number> --repo Deepwork-AI/<repo> \
     --remove-label "gt-status:pending" --add-label "gt-status:claimed"
   ```
3. **Work** on a feature branch: `gt/<instance-id>/<issue-number>-<short-desc>`
   ```
   Example: gt/gt-docker/15-fix-test-runner
   ```
4. **Create PR** targeting `dev`:
   ```bash
   gh pr create --repo Deepwork-AI/<repo> --base dev \
     --title "<type>(issue-<N>): <description>" \
     --label "needs-review,gt-from:gt-docker" \
     --body "Closes #<N>\n\n## Changes\n- ...\n\n## Testing\n- ..."
   ```
5. **Mark done** after PR is created:
   ```bash
   gh issue edit <number> --repo Deepwork-AI/<repo> \
     --remove-label "gt-status:claimed" --add-label "gt-status:done"
   ```

### How gt-local reviews and merges

1. **Find PRs to review:**
   ```bash
   gh pr list --repo Deepwork-AI/<repo> --label "needs-review"
   ```
2. **Review** the PR. Leave comments or approve:
   ```bash
   gh pr review <number> --repo Deepwork-AI/<repo> --approve
   # or
   gh pr review <number> --repo Deepwork-AI/<repo> --request-changes --body "..."
   ```
3. **Merge** approved PRs:
   ```bash
   gh pr merge <number> --repo Deepwork-AI/<repo> --squash --delete-branch
   ```
4. Update Kanban: move item to "Done".
5. Close the issue if not auto-closed by the PR.

### Branch naming for workers

Workers MUST use this branch format:
```
gt/<instance-id>/<issue-number>-<short-description>
```
Examples:
- `gt/gt-docker/15-fix-test-runner`
- `gt/gt-docker/8-aws-monitoring-epic`

Workers MUST NOT:
- Push directly to `dev` or `main`
- Merge their own PRs
- Create releases or tags
- Modify CI/CD workflows without explicit approval

### Communication protocol

- **Issue comments**: Workers post progress updates on the issue
- **PR comments**: gt-local posts review feedback on the PR
- **Escalation**: If a worker is blocked, comment on the issue with `@gt-local BLOCKED: <reason>`
- **Questions**: Workers can create issues with `gt-to:gt-local` to ask questions

### Label reference (Multi-GT)

| Label | Purpose |
|-------|---------|
| `gt-task` | Marks an issue as a cross-GT coordination task |
| `gt-from:<id>` | Which GT created the task |
| `gt-to:<id>` | Which GT should pick it up |
| `gt-status:pending` | Task waiting for pickup |
| `gt-status:claimed` | Worker has started |
| `gt-status:done` | Work delivered (PR created) |
| `needs-review` | PR needs review from gt-local |
| `approved` | PR approved, ready to merge |
| `priority:p0` | Critical — do first |
| `priority:p1` | High — do soon |
| `priority:p2` | Medium — backlog |

## Deployment URLs

Do NOT ask the user for deployment URLs. Read them from the service registry bead:
```bash
bd state <registry-bead> backend      # Returns the URL
bd state <registry-bead> dashboard    # Returns the URL
bd state list <registry-bead>         # Shows all URLs
```

When starting tunnels or deploying, always update the registry:
```bash
bd set-state <registry-bead> backend=<new-url> --reason "tunnel refresh"
```

## GitHub Organization Management

**Org:** `Deepwork-AI` (freebird-ai is admin)
**Repos:** `Deepwork-AI/ai-planogram`, `Deepwork-AI/alc-ai-villa`, `freebird-ai/gt-arcade`

The Mayor manages the Deepwork-AI GitHub organization:
- **Teams:** "Villa Market Agents team" owns ai-planogram + alc-ai-villa
- **PRs:** Use `--repo Deepwork-AI/<repo>` for all `gh` commands
- **Default branch:** `dev` on all repos

## GitHub Project Management

**Every rig has a Kanban board and a Roadmap on the Deepwork-AI org.**

| Project | # | Repo |
|---------|---|------|
| Villa AI Planogram Kanban | 4 | ai-planogram |
| Villa Planogram Roadmap | 2 | ai-planogram |
| Villa ALC AI Kanban | 5 | alc-ai-villa |
| Villa ALC AI Roadmap | 6 | alc-ai-villa |

**Kanban board template (use for ALL rigs):**
- **Status columns:** Backlog, Ready, In progress, In review, Done
- **Custom fields:** Priority (P0/P1/P2), Size (XS/S/M/L/XL), Estimate, Start date, Target date

**GitHub sync rules:**
- Sync at the **epic level**, not every bead. One GitHub issue per epic or major feature.
- GitHub issues are a summary view — internal beads have full detail.
- When an epic completes, move its Kanban item to Done and update the Roadmap.
- When creating issues, include the bead ID in the body for cross-reference.

**When to sync:**
- Epic started → create issue, add to Kanban as "In progress"
- Epic completed → move to "Done", update Roadmap phase progress
- New phase/milestone → create Roadmap issue with start/target dates

```bash
# Add item to project
gh project item-add <project-number> --owner Deepwork-AI --url <issue-or-pr-url>
# Update item status
gh project item-edit --project-id <id> --id <item-id> --field-id <status-field> --single-select-option-id <option-id>
```

## Releases & Versioning

**Every rig uses semantic versioning:** `vMAJOR.MINOR.PATCH`
- **MAJOR:** Breaking changes, major architecture shifts
- **MINOR:** New features, completed epics
- **PATCH:** Bug fixes, small improvements

**When to create a release:**
- After every `dev` -> `main` PR merge (consolidated release)
- After any breaking change that lands on `main`
- Release cadence matches PR cadence: every 2-3 epics

**Release process:**
1. After PR is merged to `main`, tag the release:
   ```bash
   git tag v<version> main
   git push origin v<version>
   ```
2. Create GitHub release with notes:
   ```bash
   gh release create v<version> --repo Deepwork-AI/<repo> --title "v<version>" --notes "$(cat <<'EOF'
   ## What's New
   Brief summary of this release.

   ## Epics Included
   - `<prefix>-<id>` -- Title
   - `<prefix>-<id>` -- Title

   ## Changes
   ### Backend
   - bullet points

   ### Dashboard
   - bullet points

   ### Mobile
   - bullet points

   ## Breaking Changes
   - List any breaking changes (or "None")

   ## Full Changelog
   https://github.com/Deepwork-AI/<repo>/compare/v<prev>...v<version>
   EOF
   )"
   ```
3. Update the Roadmap project with the release milestone.

**Current versions (initialize on first release):**
- `ai-planogram`: starts at `v1.0.0` (MVP complete)
- `alc-ai-villa`: starts at `v0.1.0` (pre-production)
- `gt-arcade`: starts at `v0.1.0` (early development)

## Persistent Memory (HARDCODED)

**Session Continuity Protocol:**
- ALWAYS save context to `~/.gt-memory/context-summary.md` before session end
- Record learnings in `~/.gt-memory/learnings.md`
- Load previous context at session start: `cat ~/.gt-memory/context-summary.md`
- Use Context Preserver skill: `gt-memory-save-context`, `gt-memory-handoff`

## Git Platform Rule (HARDCODED)

**GITEA-FIRST: Use Gitea for all git operations. GitHub is deprecated.**
- Primary: ${GITEA_URL} (configured via environment variable)
- PRs and issues in Gitea only
- Non-negotiable

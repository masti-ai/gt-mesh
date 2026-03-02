# Commit Message Convention

## Format

`<type>(<bead-id>): <description>`

Conventional Commits with bead ID as scope. Enforced by `.githooks/commit-msg`.

## Types

| Type | When to Use |
|------|-------------|
| feat | New feature or capability |
| fix | Bug fix |
| refactor | Code restructuring (no behavior change) |
| chore | Maintenance, config, dependencies |
| test | Adding or updating tests |
| docs | Documentation only |

## Examples

- `feat(vap-123): add JWT auth to photo upload endpoint`
- `fix(vap-456): handle null shelf_id in planogram query`
- `test(vap-123): add unit tests for auth middleware`
- `docs(vap-789): update API endpoint documentation`

## Multi-Bead Work

Use primary bead ID in scope. Reference others in commit body:

```
feat(vap-123): add photo upload with auth

Also addresses vap-124 (upload service) and vap-125 (validation).
```

## Merge and Revert Commits

Merge commits (`Merge branch ...`) and revert commits (`Revert ...`) are
automatically allowed by the hook without bead ID requirement.

# Branch Naming Convention

## Format

`<polecat-name>-<type>-<slug>`

## Components

| Component | Source | Example |
|-----------|--------|---------|
| polecat-name | Polecat identity | `aalu-bomb` |
| type | Bead type mapping | `feat` |
| slug | Bead title, kebab-case, max 5 words | `add-auth-endpoint` |

## Type Mapping

| Bead Type | Branch Type |
|-----------|-------------|
| feature | feat |
| bug | fix |
| task (refactor) | refactor |
| task (other) | chore |
| test | test |
| docs | docs |

## Examples

- `aalu-bomb-feat-add-auth-endpoint`
- `anar-fix-upload-crash`
- `mayor-chore-cleanup-stale-branches`

## Rules

1. All lowercase, kebab-case only
2. No slashes (breaks some CI tools)
3. Max total length: 63 characters (git branch limit for some remotes)
4. Slug derived from bead title — first 5 meaningful words

# Conventions — Deepwork-AI Mesh

## Config Files

- `gtconfig.yaml` — Node identity, mesh connection, installed packs
- `pack.yaml` — Pack manifest (in each pack directory)
- `.mesh-config/` — Local cache of mesh config pulled from DoltHub
- `.mesh-packs/` — Locally installed packs

## Naming

- GT instance IDs: lowercase, hyphenated (gt-local, gt-docker, gt-alex)
- Pack names: lowercase, hyphenated (deepwork-base, frontend-skills)
- Skill names: lowercase, hyphenated (gt-mesh-setup, excalidraw-diagram-generator)
- Role names: lowercase single word (planner, worker, reviewer)

## DoltHub Tables

| Table | Purpose |
|-------|---------|
| messages | Mesh mail between GTs |
| peers | Registered mesh nodes |
| mesh_rules | Governance rules |
| mesh_config | Config distribution manifest |
| mesh_config_files | Config file contents |
| mesh_packs | Pack registry |
| mesh_pack_files | Pack file contents |
| shared_beads | Cross-GT work items |
| claims | Bead claim tracking |
| shared_skills | Individual skill registry |
| activity_log | Auto-sync activity feed |
| invites | Mesh invite codes |

## Versioning

- Packs use semver: MAJOR.MINOR.PATCH
- Config version: integer, incremented on each publish
- gtconfig.yaml: config_version field for forward compatibility

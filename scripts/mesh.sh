#!/bin/bash
# GT Mesh — Main dispatcher
# Routes `gt mesh <subcommand>` to the correct script
#
# Usage: mesh.sh <subcommand> [args...]

set -e

MESH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="$MESH_DIR/scripts"
GT_ROOT="${GT_ROOT:-$(cd "$MESH_DIR/.." && pwd)}"
MESH_YAML="$GT_ROOT/mesh.yaml"

export GT_ROOT MESH_DIR MESH_YAML

cmd="${1:-help}"
shift 2>/dev/null || true

case "$cmd" in
  init)
    bash "$SCRIPTS_DIR/mesh-init.sh" "$@"
    ;;
  status)
    bash "$SCRIPTS_DIR/mesh-status.sh" "$@"
    ;;
  send)
    bash "$SCRIPTS_DIR/mesh-send.sh" "$@"
    ;;
  inbox)
    bash "$SCRIPTS_DIR/mesh-inbox.sh" "$@"
    ;;
  invite)
    bash "$SCRIPTS_DIR/mesh-invite.sh" "$@"
    ;;
  join)
    bash "$SCRIPTS_DIR/mesh-join.sh" "$@"
    ;;
  peers)
    bash "$SCRIPTS_DIR/mesh-status.sh" --peers "$@"
    ;;
  feed)
    bash "$SCRIPTS_DIR/mesh-feed.sh" "$@"
    ;;
  sync)
    bash "$SCRIPTS_DIR/mesh-sync.sh" "$@"
    ;;
  daemon)
    bash "$SCRIPTS_DIR/mesh-daemon.sh" "$@"
    ;;
  access)
    bash "$SCRIPTS_DIR/mesh-access.sh" "$@"
    ;;
  rules)
    bash "$SCRIPTS_DIR/mesh-rules.sh" "$@"
    ;;
  help|--help|-h)
    echo "GT Mesh — Collaborative coding for Gas Town"
    echo ""
    echo "Usage: gt mesh <command> [options]"
    echo ""
    echo "Commands:"
    echo "  init          Initialize this GT as a mesh node"
    echo "  status        Show mesh status and dashboard"
    echo "  send          Send a message to another GT"
    echo "  inbox         Check incoming mesh messages"
    echo "  invite        Generate an invite code"
    echo "  join          Join a mesh with an invite code"
    echo "  peers         List connected peers"
    echo "  feed          View mesh activity feed"
    echo "  sync          Force sync with DoltHub"
    echo "  daemon        Start/stop/status of mesh daemon"
    echo "  access        Manage access control"
    echo "  rules         View/set mesh rules"
    echo "  help          Show this help"
    echo ""
    echo "Config: $MESH_YAML"
    echo "Plugin: $MESH_DIR"
    ;;
  *)
    echo "Unknown command: $cmd"
    echo "Run 'gt mesh help' for usage."
    exit 1
    ;;
esac

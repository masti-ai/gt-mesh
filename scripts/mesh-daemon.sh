#!/bin/bash
# GT Mesh — Daemon management (background sync)
#
# Usage: mesh-daemon.sh start | stop | status | restart

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"
PIDFILE="/tmp/gt-mesh-daemon.pid"
LOGFILE="/tmp/gt-mesh-daemon.log"

if [ ! -f "$MESH_YAML" ]; then
  echo "[error] Not in a mesh. Run: gt mesh init"
  exit 1
fi

SUBCMD="${1:-status}"
MESH_DIR="$(cd "$(dirname "$0")/.." && pwd)"

case "$SUBCMD" in
  start)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "[warn] Daemon already running (PID $(cat "$PIDFILE"))"
      exit 0
    fi

    echo "[daemon] Starting mesh daemon..."

    # Background sync loop
    (
      while true; do
        GT_ROOT="$GT_ROOT" MESH_YAML="$MESH_YAML" bash "$MESH_DIR/scripts/mesh-sync.sh" >> "$LOGFILE" 2>&1
        sleep 120  # 2 minutes
      done
    ) &

    DAEMON_PID=$!
    echo "$DAEMON_PID" > "$PIDFILE"
    echo "[daemon] Started (PID $DAEMON_PID)"
    echo "[daemon] Log: $LOGFILE"
    ;;

  stop)
    if [ -f "$PIDFILE" ]; then
      PID=$(cat "$PIDFILE")
      if kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null
        # Also kill child processes
        pkill -P "$PID" 2>/dev/null
        rm -f "$PIDFILE"
        echo "[daemon] Stopped (was PID $PID)"
      else
        rm -f "$PIDFILE"
        echo "[daemon] Not running (stale PID file removed)"
      fi
    else
      echo "[daemon] Not running"
    fi
    ;;

  status)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      PID=$(cat "$PIDFILE")
      echo "[daemon] Running (PID $PID)"
      echo "[daemon] Log: $LOGFILE"
      if [ -f "$LOGFILE" ]; then
        echo "[daemon] Last sync:"
        tail -3 "$LOGFILE" 2>/dev/null | sed 's/^/         /'
      fi
    else
      echo "[daemon] Not running"
      [ -f "$PIDFILE" ] && rm -f "$PIDFILE"
    fi
    ;;

  restart)
    "$0" stop
    sleep 1
    "$0" start
    ;;

  *)
    echo "Usage: gt mesh daemon <start|stop|status|restart>"
    exit 1
    ;;
esac

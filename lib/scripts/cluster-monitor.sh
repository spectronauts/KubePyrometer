#!/usr/bin/env bash
#
# Lightweight cluster resource monitor using kubectl top + events.
#
# Standalone:  bash cluster-monitor.sh [--interval 10] [--output file.log]
# Embedded:    Called by run.sh with env vars MONITOR_INTERVAL and MONITOR_OUTPUT.
#
set -uo pipefail

INTERVAL="${MONITOR_INTERVAL:-${1:-10}}"
OUTPUT="${MONITOR_OUTPUT:-}"
NAMESPACES_PATTERN="kb-stress|kb-probe"

# ---------------------------------------------------------------------------
# Arg parsing (standalone mode)
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval) INTERVAL="$2"; shift 2 ;;
    --output)   OUTPUT="$2";   shift 2 ;;
    --help|-h)
      echo "Usage: cluster-monitor.sh [--interval SECONDS] [--output FILE]"
      echo "  --interval  Seconds between snapshots (default: 10)"
      echo "  --output    Write to file instead of stdout"
      exit 0 ;;
    *) shift ;;
  esac
done

# ---------------------------------------------------------------------------
# Output handling
# ---------------------------------------------------------------------------
if [ -n "$OUTPUT" ]; then
  exec >> "$OUTPUT" 2>&1
fi

# ---------------------------------------------------------------------------
# Detect metrics-server
# ---------------------------------------------------------------------------
HAS_METRICS=true
if ! kubectl top nodes --request-timeout=5s >/dev/null 2>&1; then
  HAS_METRICS=false
  echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) === WARNING: metrics-server not available, skipping kubectl top ==="
  echo ""
fi

# ---------------------------------------------------------------------------
# Clean shutdown on SIGTERM/SIGINT
# ---------------------------------------------------------------------------
RUNNING=true
trap 'RUNNING=false' TERM INT

echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) === cluster-monitor started (interval=${INTERVAL}s, metrics=${HAS_METRICS}) ==="
echo ""

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
while $RUNNING; do
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  if $HAS_METRICS; then
    echo "=== ${TS} === kubectl top nodes ==="
    kubectl top nodes --request-timeout=5s 2>/dev/null || echo "(unavailable)"
    echo ""

    for ns in $(kubectl get ns --no-headers -o custom-columns=':metadata.name' 2>/dev/null | grep -E "^(${NAMESPACES_PATTERN})" || true); do
      echo "=== ${TS} === kubectl top pods -n ${ns} ==="
      kubectl top pods -n "$ns" --request-timeout=5s 2>/dev/null || echo "(no pods or metrics unavailable)"
      echo ""
    done
  fi

  echo "=== ${TS} === recent events (kb namespaces) ==="
  for ns in $(kubectl get ns --no-headers -o custom-columns=':metadata.name' 2>/dev/null | grep -E "^(${NAMESPACES_PATTERN})" || true); do
    local_events=$(kubectl get events -n "$ns" --sort-by='.lastTimestamp' --no-headers 2>/dev/null | tail -5)
    if [ -n "$local_events" ]; then
      echo "--- ${ns} ---"
      echo "$local_events"
    fi
  done
  echo ""

  echo "=== ${TS} === node conditions ==="
  kubectl get nodes -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[?(@.status=="True")].type' --no-headers 2>/dev/null || echo "(unavailable)"
  echo ""
  echo "────────────────────────────────────────"
  echo ""

  sleep "$INTERVAL" &
  wait $! 2>/dev/null || true
done

echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) === cluster-monitor stopped ==="

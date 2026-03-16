#!/usr/bin/env bash
set -euo pipefail

RUN_DIR="${1:?Usage: bundle-run.sh <run-dir>}"

if [ ! -d "$RUN_DIR" ]; then
  echo "ERROR: $RUN_DIR is not a directory"
  exit 1
fi

RUN_NAME="$(basename "$RUN_DIR")"
TMPROOT="$(mktemp -d)"
BUNDLE_DIR="$TMPROOT/kubepyrometer-${RUN_NAME}"
mkdir -p "$BUNDLE_DIR"

trap 'rm -rf "$TMPROOT"' EXIT

for f in summary.csv probe-stats.csv phases.jsonl probe.jsonl \
         modes.env modes.json image-map.txt kb-version.txt \
         cluster-fingerprint.txt cluster-monitor.log \
         failures.log safety-plan.txt; do
  [ -f "$RUN_DIR/$f" ] && cp "$RUN_DIR/$f" "$BUNDLE_DIR/"
done

# Phase logs
for f in "$RUN_DIR"/phase-*.log; do
  [ -f "$f" ] && cp "$f" "$BUNDLE_DIR/"
done

OUTFILE="${RUN_DIR}/kubepyrometer-${RUN_NAME}.tar.gz"
tar -czf "$OUTFILE" -C "$TMPROOT" "kubepyrometer-${RUN_NAME}"
echo "Bundle created: $OUTFILE"
echo "Contents:"
tar -tzf "$OUTFILE" | sed 's/^/  /'

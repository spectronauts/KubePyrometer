#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${KUBEPYROMETER_HOME:-}" ]; then
  V0_DIR="$KUBEPYROMETER_HOME"
else
  V0_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
TAR_FILE="${1:-$V0_DIR/images/harness-images.tar}"

if [ ! -f "$TAR_FILE" ]; then
  echo "ERROR: image archive not found: $TAR_FILE"
  echo "Run scripts/save-images.sh to create it."
  exit 1
fi

CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

if [[ "$CONTEXT" == kind-* ]]; then
  CLUSTER_NAME="${CONTEXT#kind-}"
  echo ">>> Loading images into Kind cluster: $CLUSTER_NAME"
  NODE="${CLUSTER_NAME}-control-plane"
  if docker exec -i "$NODE" ctr --namespace=k8s.io images import - < "$TAR_FILE" 2>/dev/null; then
    echo ">>> Images loaded via ctr import"
  elif kind load image-archive "$TAR_FILE" --name "$CLUSTER_NAME" 2>/dev/null; then
    echo ">>> Images loaded via kind load"
  else
    echo "WARN: Kind image load failed; pods will attempt registry pull"
  fi
elif command -v k3d &>/dev/null && k3d cluster list 2>/dev/null | grep -q .; then
  echo ">>> Loading images into k3d cluster"
  k3d image import "$TAR_FILE"
else
  echo ">>> Loading images via docker load"
  docker load < "$TAR_FILE"
  echo "NOTE: For remote clusters (EKS/GKE/AKS), images must be in a"
  echo "reachable registry. Use -r to redirect images to your registry."
fi

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
V0_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$V0_DIR/images"
TAR_FILE="$OUT_DIR/harness-images.tar"

BUSYBOX_TAG="1.36.1"
KUBECTL_TAG="latest"

mkdir -p "$OUT_DIR"

echo ">>> Pulling bitnami/kubectl:$KUBECTL_TAG"
docker pull "bitnami/kubectl:$KUBECTL_TAG"

echo ">>> Pulling busybox:$BUSYBOX_TAG"
docker pull "busybox:$BUSYBOX_TAG"

echo ">>> Saving images to $TAR_FILE"
docker save "busybox:$BUSYBOX_TAG" "bitnami/kubectl:$KUBECTL_TAG" -o "$TAR_FILE"

SIZE=$(du -h "$TAR_FILE" | cut -f1)
echo ">>> Done: $SIZE  $TAR_FILE"
echo ">>> Bundled: busybox:$BUSYBOX_TAG  bitnami/kubectl:$KUBECTL_TAG"

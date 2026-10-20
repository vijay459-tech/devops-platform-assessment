#!/usr/bin/env bash
# Scan a locally available image and the repo config with Trivy.
# Used identically by CI and by developers so local evidence == CI evidence.
#
# Usage: scripts/scan-image.sh <image-ref>
# Exit non-zero on unfixed-ignored HIGH/CRITICAL findings not in .trivyignore.
set -euo pipefail

IMAGE="${1:?usage: scan-image.sh <image-ref>}"
TRIVY_IMAGE="${TRIVY_IMAGE:-ghcr.io/aquasecurity/trivy:0.57.1}"  # pin by digest in production
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/reports"

run_trivy() {
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$ROOT":/work:ro \
    -w /work \
    "$TRIVY_IMAGE" "$@"
}

echo "== Trivy image scan: $IMAGE =="
run_trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 \
  --ignorefile /work/.trivyignore "$IMAGE" | tee "$ROOT/reports/trivy-image.txt"

echo "== Trivy config + secret scan: repo =="
run_trivy fs --scanners misconfig,secret --severity HIGH,CRITICAL --exit-code 1 \
  --ignorefile /work/.trivyignore /work | tee "$ROOT/reports/trivy-config.txt"

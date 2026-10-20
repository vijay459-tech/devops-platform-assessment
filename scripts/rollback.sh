#!/usr/bin/env bash
# EMERGENCY traffic shift to a known-good Cloud Run revision (seconds, not a pipeline run).
# The governed path is the "Rollback" workflow (re-deploys a previous image digest through
# plan -> approval -> apply). Use this script only to stop the bleeding first; then reconcile
# Terraform (re-run the Rollback workflow for the same digest) so state matches reality.
#
# Usage:
#   scripts/rollback.sh list    <project> <region> <service>
#   scripts/rollback.sh shift   <project> <region> <service> <revision>   # 100% to <revision>
#   scripts/rollback.sh canary  <project> <region> <service> <revision> <percent>
#   scripts/rollback.sh restore <project> <region> <service>              # 100% back to latest
set -euo pipefail

cmd="${1:?command: list|shift|canary|restore}"; project="${2:?project}"; region="${3:?region}"; service="${4:?service}"

case "$cmd" in
  list)
    gcloud run revisions list --project "$project" --region "$region" --service "$service" \
      --format="table(metadata.name,status.conditions[0].status:label=READY,metadata.creationTimestamp,spec.containers[0].image)"
    ;;
  shift)
    rev="${5:?revision}"
    gcloud run services update-traffic "$service" --project "$project" --region "$region" --to-revisions "${rev}=100"
    ;;
  canary)
    rev="${5:?revision}"; pct="${6:?percent}"
    gcloud run services update-traffic "$service" --project "$project" --region "$region" --to-revisions "${rev}=${pct}"
    ;;
  restore)
    gcloud run services update-traffic "$service" --project "$project" --region "$region" --to-latest
    ;;
  *) echo "unknown command: $cmd" >&2; exit 64 ;;
esac

echo "Current traffic split:"
gcloud run services describe "$service" --project "$project" --region "$region" \
  --format="value(status.traffic)"

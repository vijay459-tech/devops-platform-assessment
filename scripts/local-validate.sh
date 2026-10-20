#!/usr/bin/env bash
# Runs the same checks as CI, locally, and records the output in docs/evidence/local-validation.log.
# A step whose tool is not installed is reported as SKIP (never as PASS).
# Prerequisites: python3.11+, and optionally terraform>=1.7, docker. See README.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
LOG="docs/evidence/local-validation.log"; mkdir -p docs/evidence reports
{ echo "# local validation $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(uname -sm)"; } > "$LOG"
pass=0; fail=0; skip=0; results=()

have() { command -v "$1" >/dev/null 2>&1; }
run() {  # run <name> <cmd...>
  local name="$1"; shift
  { echo; echo "=== $name ==="; echo "\$ $*"; } >> "$LOG"
  if "$@" >> "$LOG" 2>&1; then results+=("PASS  $name"); pass=$((pass+1)); else results+=("FAIL  $name"); fail=$((fail+1)); fi
}
skipstep() { results+=("SKIP  $1 ($2 not installed)"); skip=$((skip+1)); echo "=== SKIP $1: $2 not installed ===" >> "$LOG"; }

run "app unit tests"            bash -c 'cd app && python3 -m unittest discover -s tests -t . -v'
run "pipeline script tests"     python3 -m unittest discover -s tests -v
run "workflow policy check"     python3 scripts/validate_workflows.py
run "action pinning report"     python3 scripts/check_action_pins.py
if have ruff; then run "ruff lint" ruff check app scripts tests
else skipstep "ruff lint" ruff; fi

if have terraform; then
  run "terraform fmt"           terraform fmt -check -recursive -diff terraform
  for d in terraform/modules/cloud_run_service terraform/service; do
    run "terraform init+validate $d" bash -c "terraform -chdir=$d init -backend=false -input=false && terraform -chdir=$d validate"
  done
  run "terraform test"          terraform -chdir=terraform/modules/cloud_run_service test -verbose
else skipstep "terraform fmt/validate/test" terraform; fi

if have docker; then
  IMG="service:local"
  run "docker build"            docker build --build-arg GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo local)" -t "$IMG" .
  run "image runs non-root"     bash -c "u=\$(docker inspect --format '{{.Config.User}}' $IMG); echo user=\$u; [[ -n \$u && \$u != 0 && \$u != root ]]"
  run "container smoke test"    bash -c "docker rm -f svc-local >/dev/null 2>&1; docker run -d --name svc-local -p 8080:8080 $IMG >/dev/null \
      && for i in \$(seq 1 20); do curl -fsS localhost:8080/health && break; sleep 1; done \
      && curl -fsS localhost:8080/ready && curl -fsS localhost:8080/version \
      && docker stop --time 10 svc-local >/dev/null && [[ \$(docker inspect --format '{{.State.ExitCode}}' svc-local) == 0 ]]; rc=\$?; docker rm -f svc-local >/dev/null 2>&1; exit \$rc"
  run "trivy image + config"    scripts/scan-image.sh "$IMG"
else skipstep "docker build / smoke / trivy" docker; fi

echo; echo "---- summary ----"; printf '%s\n' "${results[@]}" | tee -a "$LOG"
echo "PASS=$pass FAIL=$fail SKIP=$skip (details: $LOG)" | tee -a "$LOG"
[[ $fail -eq 0 ]]

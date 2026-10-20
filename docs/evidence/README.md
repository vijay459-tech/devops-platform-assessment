# Validation evidence

Everything here is output of commands that were actually run. Files marked **NOT RUN** exist so the gap is visible rather than hidden.
Regenerate the full set on a machine with Docker and Terraform: `scripts/local-validate.sh` (writes `local-validation.log`).

| Evidence | Status | File |
|---|---|---|
| App unit tests (6) | **Run** | `local-validation.log` |
| Live process smoke test (`/health`, `/ready`, `/version`, 404, clean SIGTERM exit 0) | **Run** (host process, not container) | `process-smoke.txt` |
| Pipeline script tests incl. negative cases (26) | **Run** | `local-validation.log` |
| Workflow security/release-control policy check | **Run** | `local-validation.log` |
| Action pinning report | **Run** (reports 22 non-SHA refs; enforcement off) | `local-validation.log` |
| `terraform fmt` / `validate` / `test` | **NOT RUN** (Terraform unavailable in authoring sandbox) | `terraform.md` in this folder |
| `docker build`, container smoke test, non-root check | **NOT RUN** | `docker.md` |
| Trivy image/config scan | **NOT RUN** | `trivy.md` |
| `ruff` lint | **NOT RUN** | - |
| GitHub Actions execution (PR + main) | **NOT RUN** | - |

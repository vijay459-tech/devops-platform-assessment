# Cloud Run delivery pattern: Docker, Terraform, GitHub Actions, reliability

A small, production-shaped delivery pattern for a stateless HTTP service on Google Cloud Run: container build and scan,
reusable Terraform, a CI/CD pipeline with release-integrity controls, an incident runbook, and a two-region HA design.

> **Read this first: what is validated and what is not.** See [`docs/evidence/README.md`](docs/evidence/README.md).
> App tests, a live-process smoke test, the pipeline-script tests and the workflow policy checks were run.
> `terraform fmt/validate/test`, `docker build`, Trivy, `ruff` and real GitHub Actions runs were **not** executed
> before handoff; run `scripts/local-validate.sh` and commit the output. Disclosure, trade-offs and unfinished work:
> [`docs/disclosure.md`](docs/disclosure.md).

## Requirement map

| # | Requirement | Where |
|---|---|---|
| 1 | Containerize and validate | `Dockerfile`, `.dockerignore`, `scripts/scan-image.sh`, `.trivyignore`, `scripts/local-validate.sh` |
| 2 | Reusable Terraform | `terraform/modules/cloud_run_service` (+ `tests/`), `terraform/service`, `terraform/env/`, [`docs/terraform.md`](docs/terraform.md) |
| 3 | GitHub Actions | `.github/workflows/{ci,release,deploy,rollback}.yml`, [`docs/pipeline.md`](docs/pipeline.md) |
| 4 | Production failure | [`docs/incident-response.md`](docs/incident-response.md) |
| 5 | HA / load balancing design | [`docs/architecture-ha.md`](docs/architecture-ha.md) (**design only**) |
| - | Optional kind/minikube extension | not attempted |

## Layout

```
app/                  service (stdlib Python): /health /ready /version + tests
Dockerfile            multi-stage, distroless, non-root (65532), tests run in the build stage
terraform/            module + thin root + env/{dev,prod}.{tfvars,backend.hcl}
.github/workflows/    ci (PR + gate) | release (build once -> dev -> prod) | deploy (plan/approve/apply) | rollback
scripts/              scan-image.sh, local-validate.sh, rollback.sh, check_destructive_plan.py,
                      validate_workflows.py, check_action_pins.py
tests/                tests for the pipeline scripts (incl. negative cases)
docs/                 terraform, pipeline, incident-response, architecture-ha, disclosure, evidence/
```

## Prerequisites

Python 3.11+ (required); Docker (build, scan); Terraform >= 1.7 (module tests use `mock_provider`); optional `gcloud` only for a real deployment.
No cloud account, credentials or spend are needed for any validation below.

## Setup and validation

```bash
python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements-dev.txt

scripts/local-validate.sh          # everything below, in one go; SKIPs what isn't installed; log in docs/evidence/
```

Individually:

```bash
# 1. App
(cd app && python3 -m unittest discover -s tests -t . -v)
ruff check app scripts tests

# 2. Container: build, verify health, non-root, clean shutdown, scan
docker build -t service:local .
docker run -d --name svc -p 8080:8080 service:local
curl -fsS localhost:8080/health && curl -fsS localhost:8080/ready && curl -fsS localhost:8080/version
docker inspect --format '{{.Config.User}}' service:local          # 65532:65532
docker stop svc && docker rm svc
scripts/scan-image.sh service:local                               # Trivy: HIGH/CRITICAL fixable findings fail

# 3. Terraform (no credentials, no backend)
terraform fmt -check -recursive terraform
terraform -chdir=terraform/modules/cloud_run_service init -backend=false && terraform -chdir=terraform/modules/cloud_run_service validate
terraform -chdir=terraform/service init -backend=false && terraform -chdir=terraform/service validate
terraform -chdir=terraform/modules/cloud_run_service test -verbose
git add terraform/*/.terraform.lock.hcl terraform/modules/*/.terraform.lock.hcl   # commit the provider lock files

# 4. Pipeline controls
python3 -m unittest discover -s tests -v                          # script tests incl. negative cases
python3 scripts/validate_workflows.py                             # permissions, OIDC, concurrency, plan/apply split ...
python3 scripts/check_action_pins.py                              # supply-chain pin report
```

Troubleshooting the image: the runtime is `gcr.io/distroless/python3-debian12:nonroot` (Python 3.11) with an explicit
`/usr/bin/python3` entrypoint. If a build argument or tag has moved, override `PYTHON_BUILD_IMAGE` / `RUNTIME_IMAGE`; keep minor versions aligned.

## Pipeline behavior

- **Pull request** (`ci.yml`, read-only token, no cloud access): lint, service tests, `terraform fmt/validate/test`,
  image build (not pushed) + smoke test + non-root check, Trivy image/config/secret scan, workflow policy checks.
- **Merge to `main`** (`release.yml`): CI gate -> **build once**, scan the exact image, push, resolve the **digest** -> deploy dev -> promote the **same digest** to prod.
- **Each deploy** (`deploy.yml`): plan with a read-only identity -> destructive-change gate -> reviewed plan retained and checksummed ->
  **approval** (GitHub environment) -> apply that saved plan under a per-environment **concurrency lock** -> verify the live revision runs the intended digest.
- **Keyless auth:** OIDC + Workload Identity Federation placeholders; no service-account keys.
- **Dry run by default:** without the repo variable `ENABLE_GCP=true` the workflow builds, scans and records a manifest, and the deploy job reports what it would do.
  Setup for a real run: [`docs/pipeline.md`](docs/pipeline.md).

## Rollback

1. Emergency traffic shift (seconds): `scripts/rollback.sh shift <project> <region> <service> <revision>`, then `DEPLOY_FREEZE=true`.
2. Governed: Actions -> **Rollback** -> environment + previous `image@sha256:...` + reason; same plan/approval/apply path.
Find targets in `release-manifest-*` / `deployment-evidence-*` artifacts or `scripts/rollback.sh list ...`. Details and the Terraform-drift hazard: `docs/pipeline.md`.

## Cleanup

Local: `docker rm -f svc; docker rmi service:local; rm -rf .venv reports/* terraform/**/.terraform`.
Cloud (only if you deployed): `terraform destroy` per environment (dev: `deletion_protection=false`; prod must be
unprotected by a reviewed change first, deliberately), then delete the Artifact Registry repo, state buckets, WIF pool/provider and pipeline service accounts.

## Known limitations

See `docs/disclosure.md` ("Unfinished") and the limits sections of `docs/pipeline.md` and `docs/architecture-ha.md`.

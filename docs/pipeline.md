# CI/CD pipeline

```mermaid
flowchart LR
  PR[Pull request] --> CI
  subgraph CI [ci.yml - read-only, no cloud access]
    A[lint + unit tests] --- T[terraform fmt/validate/test] --- C[docker build, smoke, Trivy] --- P[policy checks]
  end
  M[Merge to main] --> CI2[ci.yml again as gate]
  CI2 --> B[build ONCE, scan, push, record digest]
  B -->|image@sha256| D1[deploy dev]
  D1 -->|same digest| D2[deploy prod]
  subgraph deploy.yml
    PL[plan - read-only identity] --> AP[approval: GitHub environment] --> APL[apply saved plan - apply identity]
  end
  D1 --- deploy.yml
  D2 --- deploy.yml
  RB[Rollback workflow] -->|previous digest| deploy.yml
```

## Triggers and permissions

| Workflow | Trigger | Token permissions | Cloud access |
|---|---|---|---|
| `ci.yml` | `pull_request` to `main`; `workflow_call` | `contents: read` | none |
| `release.yml` | `push` to `main` | top-level `contents: read`; `build` and deploy jobs add `id-token: write` | build: push SA only |
| `deploy.yml` | `workflow_call` only | top-level `contents: read`; plan/apply add `id-token: write` | plan SA, apply SA |
| `rollback.yml` | `workflow_dispatch` | as deploy | via deploy.yml |

- No `pull_request_target`; PRs from forks never get cloud access or secrets. `id-token: write` is granted only
  to jobs that authenticate, and it never implies repository write access.
- `actions/checkout` uses `persist-credentials: false`; untrusted values (`inputs.*`) reach shell only via `env:`, never
  interpolated into `run:` (prevents script injection). `scripts/validate_workflows.py` enforces these rules in CI.

## Build once, promote the same artifact

`release.yml` builds the image once per commit, scans **that exact image**, pushes it, and resolves its
**registry digest**. Both environments deploy `image@sha256:...`; Terraform rejects non-digest references, so
a tag can't be moved underneath a deploy. The manifest (`release-manifest-<sha>`: commit, tag, digest,
run URL, time) is retained 400 days as the source for rollback targets. `deployment-evidence-*` records which
revision runs which digest. Provenance attestation (e.g. `actions/attest-build-provenance`) and Binary
Authorization are the natural next step (not implemented).

## Plan, approval, apply

1. **plan** (environment `<env>-plan`, plan SA, read-only + state lock): `terraform plan -out`, text and JSON
   renderings, destructive-change gate, SHA-256 of the plan, upload as artifact (90 days).
2. **apply** (environment `<env>`): GitHub holds the job until the environment's reviewers approve. Then it
   re-downloads the plan, verifies the SHA-256 matches, authenticates as the apply SA, and runs
   `terraform apply tfplan` (never a fresh plan). It then asserts the live revision's image equals the intended digest.
3. **Concurrency:** `terraform-apply-<env>` with `cancel-in-progress: false`: two applies to one environment never overlap, and a running apply is never cancelled.
   `release.yml` also serialises whole releases. A *pending* (not running) older apply is superseded by a newer one,
   which is acceptable because the newer plan is built from newer code.

## Keyless GCP auth (OIDC + Workload Identity Federation)

No service-account keys exist anywhere (`validate_workflows.py` fails on `credentials_json`). One-time setup (admin, outside this repo):

```bash
# Pool + provider trusting only this repository (attribute condition is the primary guard)
gcloud iam workload-identity-pools create github --project="$PROJECT" --location=global
gcloud iam workload-identity-pools providers create-oidc github-oidc --project="$PROJECT" \
  --location=global --workload-identity-pool=github \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner_id=assertion.repository_owner_id" \
  --attribute-condition="assertion.repository == 'OWNER/REPO' && assertion.repository_owner_id == 'OWNER_ID'"

# Bind each service account to the *specific* token subject allowed to use it
P="principal://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github/subject"
gcloud iam service-accounts add-iam-policy-binding "$PUSH_SA"       --role=roles/iam.workloadIdentityUser --member="$P/repo:OWNER/REPO:ref:refs/heads/main"
gcloud iam service-accounts add-iam-policy-binding "$PROD_PLAN_SA"  --role=roles/iam.workloadIdentityUser --member="$P/repo:OWNER/REPO:environment:prod-plan"
gcloud iam service-accounts add-iam-policy-binding "$PROD_APPLY_SA" --role=roles/iam.workloadIdentityUser --member="$P/repo:OWNER/REPO:environment:prod"
```

The prod apply SA can only be impersonated by a job running in the `prod` environment, i.e. one that
passed its protection rules. A compromised PR or feature branch cannot reach it.

**GitHub settings required** (placeholders in the workflows reference these):

| Where | Name | Value |
|---|---|---|
| Repo variable | `ENABLE_GCP` | `true` to activate push/plan/apply; unset = dry run |
| Repo variables | `GCP_REGION`, `GCP_ARTIFACT_PROJECT`, `GAR_REPOSITORY`, `SERVICE_NAME` | image location |
| Repo variable | `GCP_WIF_PROVIDER`, `GCP_PUSH_SA` | `projects/NUMBER/locations/global/workloadIdentityPools/github/providers/github-oidc`, SA email |
| Repo variables | `ACTION_PIN_ENFORCE`, `DEPLOY_FREEZE` | `true` to enforce SHA pinning / stop prod promotions |
| Environments | `dev-plan`, `dev`, `prod-plan`, `prod` | env variables `GCP_WIF_PROVIDER`, `GCP_PLAN_SA` (plan envs) or `GCP_APPLY_SA` (apply envs) |
| Environment `prod` | protection | required reviewers, **prevent self-review**, deployment branches = `main` only, optional wait timer |
| Branch `main` | protection | PRs required, status checks (CI jobs) required, CODEOWNERS review |

## Supply-chain choices

- **Actions:** the policy is full-commit-SHA pins for every external action (tags are mutable). The workflows in this
  repo currently use **version tags marked `# PIN`** because SHAs can only be resolved online and I would not guess
  them. `scripts/check_action_pins.py` reports every non-SHA reference (22 today) and, once `ACTION_PIN_ENFORCE=true`, fails CI on any.
  Before enabling `ENABLE_GCP`, run a pinning tool (e.g. `pinact run`) and let Dependabot (configured for `github-actions`) keep the SHAs current.
  Also restrict allowed actions in org/repo settings to GitHub-owned, `hashicorp/*` and `google-github-actions/*`.
- **Fewer third-party actions:** build/scan/push use `docker`, `gcloud`, and the pinned Trivy container
  (`ghcr.io/aquasecurity/trivy:0.57.1`, to be digest-pinned) rather than wrapper actions.
- **Base images** are build args so CI can pass digest-pinned refs; Dependabot (`docker`) proposes updates.
- **Image gating:** HIGH/CRITICAL fixable vulnerabilities fail the build; accepted exceptions live in `.trivyignore`
  with reason/owner/expiry, mirrored in `docs/evidence/trivy.md`.

## Rollback paths

1. **Emergency (seconds):** `scripts/rollback.sh shift <project> <region> <service> <revision>` moves 100% of traffic
   to a known-good revision (or `canary ... <percent>`). Then set `DEPLOY_FREEZE=true` so the next merge can't re-promote the bad build.
   *Hazard:* Terraform declares "latest revision gets 100%", so the next apply would undo a manual shift. Reconcile promptly with path 2.
2. **Governed:** run the **Rollback** workflow with the previous digest (from a `release-manifest-*`
   or `deployment-evidence-*` artifact, or `rollback.sh list`). It deploys that digest as a new revision through the same
   plan, approval and apply path, under the same lock. Terraform state then matches reality.
3. **Forward-fix** through the normal pipeline when the defect is understood and the fix is small.

## Not implemented / limits (be explicit)

- The workflows have not been executed on GitHub in this submission; YAML structure and control rules are checked
  by `validate_workflows.py` and its tests, which is not the same as a real run. Expect small first-run fixes.
- Post-deploy verification confirms the revision is Ready and runs the intended digest; it does not run an
  SLO-gated canary (see the improvement proposed in `docs/incident-response.md`).

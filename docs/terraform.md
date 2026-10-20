# Terraform design

## Structure

```
terraform/
  modules/cloud_run_service/   # the reusable implementation (+ tests/)
  service/                     # thin root: calls the module, owns provider + backend
  env/dev.tfvars  dev.backend.hcl     # per-environment inputs and state location
  env/prod.tfvars prod.backend.hcl
```

One implementation, two sets of inputs. `dev` and `prod` differ only in `env/*.tfvars` and
`env/*.backend.hcl`; nothing is copied. The pipeline always derives both from the same
`environment` value (`-var-file=../env/$ENV.tfvars` and `-backend-config=../env/$ENV.backend.hcl`).

**Trade-off:** a single root with per-env tfvars gives the strongest "same code, promoted" guarantee, but
a human can pair the wrong tfvars and backend. Mitigations: the pipeline derives both from one input;
dev and prod live in **separate GCP projects with separate state buckets and separate CI identities**, so a
mismatched pairing fails authentication rather than touching the wrong environment. The alternative
(a root directory per environment) trades that risk for ~40 lines of duplication per environment.

## Module interface

| Input | Default | Notes |
|---|---|---|
| `project_id`, `region`, `environment`, `service_name` | required | validated; no IDs hardcoded |
| `image` | required | **must be `...-docker.pkg.dev/...@sha256:<64 hex>`**; tags are rejected |
| `cpu`, `memory` | `1`, `512Mi` | |
| `timeout_seconds`, `max_concurrency` | `30`, `80` | range-validated |
| `min_instances`, `max_instances` | `0`, `3` | `min>0` trades cost for cold-start latency |
| `ingress` | `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` | see decision below |
| `invoker_members` | `[]` | `allUsers`/`allAuthenticatedUsers` rejected by validation |
| `env_vars` | `{}` | non-secret only |
| `secret_env` | `{}` | `{ENV_NAME = {secret, version}}` references only |
| `deletion_protection` | `true` | |

Outputs: `service_name`, `service_url`, `latest_ready_revision`, `runtime_service_account_email`,
`deployed_image`, `ingress` (root also exports `project_id`, `region` for the pipeline's evidence step).

Versions: `required_version >= 1.7.0, < 2.0.0` (1.7 is needed for `mock_provider`); provider
`hashicorp/google >= 6.30.0, < 7.0.0`. **Commit `.terraform.lock.hcl`** (created by the first
`terraform init`) so provider hashes are pinned; it could not be generated offline when this was authored.

## Ingress and authentication decision

- **Authentication is always on.** Nothing in this repo grants `allUsers`. Access is `roles/run.invoker`
  for named identities only; the default is *nobody*.
- **prod:** `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER`. The `*.run.app` URL is not reachable from the
  internet; the only public path is an external Application Load Balancer. Until that LB exists, prod is
  deliberately unreachable externally (fail closed).
- **dev:** `INGRESS_TRAFFIC_ALL` with IAM auth, so developers can test with
  `curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" $URL` and no LB is needed.
- **When a load balancer is introduced**, direct access stays controlled by three layers: (1) the ingress
  setting above blocks the run.app URL for internet callers; (2) IAM still requires an identity, and the LB's
  identity (or the client's ID token, which the LB passes through) is added to `invoker_members` by a
  reviewed PR; (3) Cloud Armor on the backend service filters at the edge. Hardening to consider:
  disabling the default run.app URL entirely (provider support should be confirmed for the pinned version).
- **Known tension:** a browser-facing public API behind the LB cannot present a Google ID token, so it
  needs unauthenticated invocation at the IAM layer, with ingress restricted to the LB and Cloud Armor in
  front. This module refuses that on purpose; making a service public should be a separate, reviewed module
  change, not a tfvars edit.

## IAM: minimum required

**Runtime service account** (created by the module, one per service+environment; the default compute SA is
never used):

| Grant | Scope | Why |
|---|---|---|
| `roles/secretmanager.secretAccessor` | each *referenced* secret only | read injected secrets |
| *(nothing else)* | | Cloud Run writes stdout logs on the service's behalf; add roles only when the app calls a GCP API |

**Pipeline identities** (separate service accounts, keyless via WIF; setup in `docs/pipeline.md`):

| Identity | Needs | Notes |
|---|---|---|
| push SA | `roles/artifactregistry.writer` on the one repository | impersonable only from `main` |
| plan SA (per env) | read on managed resources (`roles/run.viewer`, secret/IAM get), object access on the state bucket for locking | cannot modify infrastructure |
| apply SA (per env) | `roles/run.developer`-level rights on the service, `roles/iam.serviceAccountUser` **on the runtime SA only**, SA create/delete scoped by IAM condition to the `-run` name pattern, `roles/secretmanager.secretAccessor` admin on the referenced secrets (or `secretmanager.secrets.setIamPolicy` via a narrow custom role), state bucket access | impersonable only by jobs that passed that environment's protection rules |

Trade-off: because this module creates the runtime SA and secret bindings, the apply identity needs some
IAM-writing power. A stricter layout moves SA creation and secret IAM into a separate, more tightly
controlled "bootstrap" stack and lets the module accept an existing SA email. Not done here (time-box).

## Secrets

Only **references** exist in code, tfvars and workflows: `secret_env` carries a Secret Manager secret id
and a version; Cloud Run resolves the value at runtime. Secret *values* are created out-of-band
(`gcloud secrets versions add`) and therefore never enter Terraform state or plan artifacts.
Prefer a pinned version (`"3"`) in prod so a rotation is a reviewed deploy rather than a silent behavior change;
`"latest"` is allowed for dev convenience. Note a secret mounted as an env var is only read at instance start.

## State strategy (intended; buckets are not created here)

- **Remote state in GCS**, one bucket **per environment, in that environment's project**, with object
  versioning on, uniform bucket-level access, public access prevention, and optionally CMEK. Prefix per stack
  (`cloud-run/demo-api`).
- **Locking:** the GCS backend locks natively (lock object written next to the state). CI uses
  `-lock-timeout` so a concurrent run waits instead of failing, and the workflow's per-environment
  `concurrency` group ensures applies don't even attempt to overlap.
- **Environment separation:** separate projects, buckets, WIF providers/service accounts and GitHub
  environments. The plan identity can read and lock; only the approval-gated apply identity can change things.
- **Access to state:** state is sensitive even without secret values (resource IDs, IAM). Bucket access is limited to the
  pipeline identities and a small break-glass group; versioning enables recovery from a bad write.
- **Bootstrap:** the state buckets, WIF pool and pipeline service accounts are created once by an admin
  out-of-band (or a separate bootstrap stack) because they must exist before this stack can run.

## Destructive-change review

1. `terraform plan -out=tfplan` runs under the read-only plan identity; `plan.json` is produced.
2. `scripts/check_destructive_plan.py` fails the job if any resource would be **deleted or replaced**
   (replace = delete+create), unless the run was explicitly started with `allow_destructive=true`.
3. The Cloud Run service has `deletion_protection = true` in prod, so Terraform itself refuses to destroy it.
4. The approver sees the plan text and change summary in the run summary; the exact reviewed binary plan is
   retained as an artifact, its SHA-256 is verified before apply, and apply uses *that* plan
   (a stale plan fails instead of applying something unreviewed).
5. Recommended repo settings: CODEOWNERS on `terraform/` and `.github/workflows/`, required reviews, branch protection on `main`.

## Testing

`terraform test` (module, mocked `google` provider, no credentials): secure defaults (ingress, no invoker,
deletion protection, dedicated SA), naming/labels, sizing/scaling/timeout/concurrency mapping, digest-pinned
image, invoker grants only when named, secret references with scoped IAM and de-duplication, plus negative tests
that reject tags, public invokers, unknown environments, over-long names and bad ingress values.
Mocked plans prove configuration logic, not that GCP will accept it; that needs a real `apply` in a sandbox project.

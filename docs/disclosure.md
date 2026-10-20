# Disclosure

> **Complete the `[FILL IN]` items before submitting. They must be true statements about *your* work.**

## Time spent

[FILL IN: actual hours, by area. The assessment asks you to stop at 3 hours and document what is unfinished.]

## Material use of AI-assisted tooling

This repository was drafted with substantial assistance from **Claude (Anthropic)**: application code, Dockerfile, Terraform module and tests,
GitHub Actions workflows, policy scripts and all documentation were generated in a single AI-assisted session.
Candidate review: [FILL IN: what you read, ran, changed or rejected. You must be able to explain and modify every file.]

What was verified by running it (in the AI's sandbox, which had Python only): the application unit tests, a live-process smoke test
including SIGTERM drain, the pipeline-script unit tests (26, including negative cases) and the workflow policy checks.
What was **not** executed anywhere before handoff: `terraform fmt/validate/test`, `docker build`, Trivy, `ruff`, and any GitHub Actions run.
See `docs/evidence/README.md`. [FILL IN: which of these you subsequently ran, and the real output / any fixes you had to make.]

## Assumptions

- Stateless service; Python standard library only; no database.
- Artifact Registry as the registry; digest-pinned deploys; Cloud Run v2 service resource; `hashicorp/google` 6.x; Terraform 1.7+.
- Two GCP projects (dev/prod) with separate state buckets and CI identities; GitHub environments `dev-plan`, `dev`, `prod-plan`, `prod`.
- No live GCP deployment; workflows run in "dry run" unless `ENABLE_GCP=true` and the GCP-side setup in `docs/pipeline.md` exists.

## Key trade-offs

1. Single Terraform root + per-env tfvars/backends (no duplication, strongest promotion story) vs. wrong-pairing risk; mitigated with separate projects/identities.
2. Module creates the runtime SA and secret bindings (self-contained) vs. giving the apply identity IAM-writing power; a bootstrap stack would be stricter.
3. Distroless runtime (small, no shell) vs. harder interactive debugging; build stage runs tests so a failing test fails the image build.
4. Digest-only image input (immutability, rollback by digest) vs. less human-readable than tags; a `sha-<commit>` tag is still pushed for humans.
5. Plan and apply as separate jobs with a verified, retained plan (strong evidence) vs. extra complexity and stale-plan failures (intentional).
6. Prod ingress is fail-closed (unreachable until an LB exists) vs. immediate usability.

## Unfinished / not done

- Action references use version tags marked `# PIN`; SHAs must be resolved online and enforced (`ACTION_PIN_ENFORCE=true`). 22 references are unpinned today.
- `.terraform.lock.hcl` not committed (needs a networked `terraform init`).
- No real GCP deployment, WIF pool, state buckets, or GitHub environments were created.
- Two-region design is conceptual only (see `docs/architecture-ha.md` for exact repository gaps). No Cloud Run readiness probe is configured for service health.
- Optional kind/minikube resilience extension not attempted.
- No SLO-gated canary; no provenance attestation / Binary Authorization.

## One failure encountered and how it was diagnosed (for the walkthrough)

[FILL IN with a **real** failure from your own validation run. For example: a `terraform validate`/`test` error, a Docker build or distroless
entrypoint issue, a Trivy finding, or a workflow YAML error, and how you diagnosed it. Do not describe a failure you did not experience.]

Disclosure

Time spent

Approximately 3–4 hours, including implementation, validation, troubleshooting, security remediation, and final verification.



Validation performed

Application unit tests: 6 passed.

Pipeline and policy tests: 26 passed.

Ruff lint validation: passed.

Docker image build: passed.

Container smoke test: passed.

Non-root container validation: passed.

Terraform validation and tests: 13 passed, 0 failed.

Trivy image scan: 0 HIGH and 0 CRITICAL findings after remediation.

Final GitHub Actions Release workflow: passed.

No live GCP deployment was performed. The deployment workflow remained in dry-run mode.



Issues encountered

During the first GitHub Actions run, scripts/scan-image.sh failed with exit code 126 because the executable permission was not preserved.



I corrected the Git file mode from 100644 to 100755 and reran the pipeline.



Once Trivy executed successfully, it identified 43 HIGH and 0 CRITICAL findings in the original Debian 12 runtime image. I did not suppress those findings.



An initial attempt to update the distroless image used an invalid image tag, which was caught during the next CI run.



I then aligned the build and runtime images on Python 3.13 and Debian 13.



The final GitHub Actions Release workflow passed. Terraform completed with 13 tests passed and 0 failed, and Trivy reported 0 HIGH and 0 CRITICAL findings.



Key design decisions

Stateless Python service with minimal runtime dependencies.

Multi-stage Docker build.

Distroless non-root runtime container.

Immutable image digests for deployment and rollback.

Reusable Terraform module for Cloud Run.

Separate Terraform plan and apply stages.

Security scanning blocks HIGH and CRITICAL fixable vulnerabilities.

GCP authentication is designed around Workload Identity Federation rather than long-lived service-account keys.

Live cloud deployment is intentionally not required for this submission.

Not implemented

Live GCP deployment.

Workload Identity Federation infrastructure.

Remote Terraform state infrastructure.

Production GitHub environments.

Deployment of the proposed multi-region architecture.

Optional kind/minikube extension.

SLO-based canary rollout.

Binary Authorization and provenance attestation.

GitHub Actions references currently use version tags rather than immutable commit-SHA pins. I would address this before using the workflow for a production deployment.



Walkthrough example

The container security issue is the main troubleshooting example from the assessment.



The initial problem was a Linux file-permission failure that prevented the security scan from executing. After correcting the permission, Trivy exposed actual vulnerabilities in the container base image.



Rather than weakening the security gate, I updated the runtime strategy and validated the change through the same CI pipeline.



The final result was a successful Release workflow with 0 HIGH and 0 CRITICAL image findings.

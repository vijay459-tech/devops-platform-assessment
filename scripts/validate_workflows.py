#!/usr/bin/env python3
"""Policy checks over .github/workflows/*.yml.

These make the pipeline's security/release controls *testable* without GitHub
or GCP: the checks run locally and in CI, and have their own unit tests.
Exits non-zero if any rule fails.
"""

from __future__ import annotations

import pathlib
import re
import sys

import yaml

WORKFLOW_DIR = pathlib.Path(__file__).resolve().parent.parent / ".github" / "workflows"
FORBIDDEN_STRINGS = ("credentials_json", "GOOGLE_CREDENTIALS", "service_account_key", "private_key")
# Attacker-influenced contexts must not be interpolated straight into shell.
INJECTABLE = re.compile(r"\$\{\{\s*(github\.event\.|github\.head_ref|inputs\.)")


def triggers(doc: dict) -> dict:
    # PyYAML (YAML 1.1) parses the bare key `on` as boolean True.
    return doc.get("on", doc.get(True, {})) or {}


def check_workflow(name: str, doc: dict, raw: str) -> list[str]:
    errors: list[str] = []
    jobs = doc.get("jobs", {})

    def err(msg: str) -> None:
        errors.append(f"{name}: {msg}")

    top_perms = doc.get("permissions")
    if top_perms is None:
        err("missing explicit top-level `permissions`")
    elif isinstance(top_perms, str):
        err(f"top-level permissions must be a read-only mapping, got string {top_perms!r}")
    else:
        for scope, level in top_perms.items():
            if level == "write":
                err(f"top-level permission {scope}: write (grant write per job, not workflow-wide)")

    if "pull_request_target" in triggers(doc):
        err("uses pull_request_target (runs untrusted PR code with secrets)")

    for bad in FORBIDDEN_STRINGS:
        if bad in raw:
            err(f"contains forbidden long-lived credential reference: {bad}")

    for job_id, job in jobs.items():
        steps = job.get("steps", [])
        for step in steps:
            uses = str(step.get("uses", ""))
            run = str(step.get("run", ""))
            if INJECTABLE.search(run):
                err(f"job {job_id}: untrusted context interpolated into `run:`; pass via env: instead")
            if uses.startswith("actions/checkout") and step.get("with", {}).get("persist-credentials") is not False:
                err(f"job {job_id}: actions/checkout without persist-credentials: false")
            if uses.startswith("google-github-actions/auth"):
                with_ = step.get("with", {})
                perms = job.get("permissions", {}) or {}
                if "workload_identity_provider" not in with_:
                    err(f"job {job_id}: GCP auth without workload_identity_provider (OIDC/WIF)")
                if perms.get("id-token") != "write":
                    err(f"job {job_id}: GCP auth requires job-level `id-token: write`")
    return errors


def check_deploy_controls(docs: dict[str, dict]) -> list[str]:
    """Cross-cutting release controls on the reusable deploy workflow."""
    errors: list[str] = []
    deploy = docs.get("deploy.yml")
    if deploy is None:
        return ["deploy.yml: missing"]
    jobs = deploy.get("jobs", {})
    if "plan" not in jobs or "apply" not in jobs:
        errors.append("deploy.yml: plan and apply must be separate jobs")
        return errors
    apply = jobs["apply"]
    if "plan" not in _as_list(apply.get("needs")):
        errors.append("deploy.yml: apply must `needs: plan` (applies the reviewed plan)")
    if not apply.get("environment"):
        errors.append("deploy.yml: apply job must target a GitHub environment (approval boundary)")
    conc = apply.get("concurrency")
    if not isinstance(conc, dict) or conc.get("cancel-in-progress") is not False:
        errors.append("deploy.yml: apply needs `concurrency` with cancel-in-progress: false")
    elif "inputs.environment" not in str(conc.get("group", "")):
        errors.append("deploy.yml: apply concurrency group must be per-environment")
    plan_text = str(jobs["plan"])
    if "upload-artifact" not in plan_text:
        errors.append("deploy.yml: plan job must retain the plan as an artifact")
    apply_text = str(apply)
    if "terraform apply" not in apply_text or "tfplan" not in apply_text:
        errors.append("deploy.yml: apply must apply the saved tfplan, not re-plan")
    return errors


def _as_list(value: object) -> list:
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def load_all(directory: pathlib.Path) -> tuple[dict[str, dict], dict[str, str]]:
    docs, raws = {}, {}
    for path in sorted(directory.glob("*.yml")):
        raws[path.name] = path.read_text(encoding="utf-8")
        docs[path.name] = yaml.safe_load(raws[path.name])
    return docs, raws


def main() -> int:
    docs, raws = load_all(WORKFLOW_DIR)
    if not docs:
        print("no workflows found", file=sys.stderr)
        return 1
    errors: list[str] = []
    for name, doc in docs.items():
        errors += check_workflow(name, doc, raws[name])
    errors += check_deploy_controls(docs)
    for name in docs:
        status = "FAIL" if any(e.startswith(name) for e in errors) else "ok"
        print(f"[{status}] {name}")
    for e in errors:
        print(f"  - {e}")
    print(f"\n{len(docs)} workflow(s) checked, {len(errors)} violation(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())

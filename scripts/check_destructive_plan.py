#!/usr/bin/env python3
"""Fail a release when a Terraform plan would delete or replace resources.

Reads the JSON from `terraform show -json tfplan`. Any resource whose planned
actions include "delete" (a pure delete, or a replace, which is delete+create)
is reported. The check exits 2 unless ALLOW_DESTRUCTIVE=true, which only a
reviewer-approved workflow_dispatch should set.

Output is Markdown so the workflow can append it to $GITHUB_STEP_SUMMARY.
"""

from __future__ import annotations

import json
import os
import sys


def classify(actions: list[str]) -> str:
    if "delete" in actions and "create" in actions:
        return "replace"
    if "delete" in actions:
        return "delete"
    if actions == ["create"]:
        return "create"
    if actions == ["update"]:
        return "update"
    return "no-op"


def summarize(plan: dict) -> dict:
    counts: dict[str, int] = {"create": 0, "update": 0, "delete": 0, "replace": 0, "no-op": 0}
    destructive: list[dict] = []
    for rc in plan.get("resource_changes", []):
        kind = classify(rc.get("change", {}).get("actions", []))
        counts[kind] += 1
        if kind in ("delete", "replace"):
            destructive.append({"address": rc["address"], "type": rc["type"], "action": kind})
    return {"counts": counts, "destructive": destructive}


def render(result: dict, allowed: bool) -> str:
    c = result["counts"]
    lines = [
        "### Terraform plan change summary",
        "",
        f"create: **{c['create']}** | update: **{c['update']}** | "
        f"delete: **{c['delete']}** | replace: **{c['replace']}** | no-op: {c['no-op']}",
        "",
    ]
    if result["destructive"]:
        verdict = "ALLOWED by ALLOW_DESTRUCTIVE=true" if allowed else "BLOCKED"
        lines += [f"**Destructive changes detected - {verdict}**", "", "| Resource | Action |", "|---|---|"]
        lines += [f"| `{d['address']}` | {d['action']} |" for d in result["destructive"]]
    else:
        lines.append("No destructive changes.")
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: check_destructive_plan.py <plan.json>", file=sys.stderr)
        return 64
    with open(argv[1], encoding="utf-8") as fh:
        plan = json.load(fh)
    allowed = os.environ.get("ALLOW_DESTRUCTIVE", "").lower() == "true"
    result = summarize(plan)
    print(render(result, allowed))
    if result["destructive"] and not allowed:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

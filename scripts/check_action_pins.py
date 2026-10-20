#!/usr/bin/env python3
"""Report how every `uses:` reference in workflows is pinned.

Supply-chain policy: third-party actions should be pinned to a full 40-char
commit SHA (tags are mutable). This script reports status and, when
ACTION_PIN_ENFORCE=true (or --strict), fails on any non-SHA external reference.
It is report-only by default because SHAs must be resolved online (see
docs/pipeline.md, "Pinning actions").
"""

from __future__ import annotations

import os
import pathlib
import re
import sys

USES = re.compile(r"^\s*-?\s*uses:\s*([^\s#]+)")
SHA = re.compile(r"^[0-9a-f]{40}$")
WORKFLOWS = pathlib.Path(__file__).resolve().parent.parent / ".github" / "workflows"


def classify(ref: str) -> str:
    if ref.startswith("./"):
        return "local"
    if ref.startswith("docker://"):
        return "docker" if "@sha256:" in ref else "unpinned"
    _, _, version = ref.partition("@")
    return "sha" if SHA.match(version) else "tag"


def scan(directory: pathlib.Path) -> list[tuple[str, int, str, str]]:
    rows = []
    for path in sorted(directory.glob("*.yml")):
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            m = USES.match(line)
            if m:
                rows.append((path.name, n, m.group(1), classify(m.group(1))))
    return rows


def main(argv: list[str]) -> int:
    strict = "--strict" in argv or os.environ.get("ACTION_PIN_ENFORCE", "").lower() == "true"
    rows = scan(WORKFLOWS)
    loose = [r for r in rows if r[3] in ("tag", "unpinned")]
    for name, line, ref, kind in rows:
        print(f"{kind:9} {name}:{line} {ref}")
        if kind in ("tag", "unpinned"):
            level = "error" if strict else "warning"
            print(f"::{level} file=.github/workflows/{name},line={line}::{ref} is not pinned to a commit SHA")
    print(f"\n{len(rows)} reference(s); {len(loose)} not SHA-pinned; enforcement={'ON' if strict else 'off (report only)'}")
    return 1 if (strict and loose) else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

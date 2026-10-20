import os
import pathlib
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "scripts"))

import check_destructive_plan as cdp  # noqa: E402


def plan(*changes: tuple[str, list[str]]) -> dict:
    return {
        "resource_changes": [
            {"address": f"google_x.{name}", "type": "google_x", "change": {"actions": actions}}
            for name, actions in changes
        ]
    }


class ClassifyTest(unittest.TestCase):
    def test_actions(self) -> None:
        self.assertEqual(cdp.classify(["create"]), "create")
        self.assertEqual(cdp.classify(["update"]), "update")
        self.assertEqual(cdp.classify(["delete"]), "delete")
        self.assertEqual(cdp.classify(["delete", "create"]), "replace")
        self.assertEqual(cdp.classify(["create", "delete"]), "replace")
        self.assertEqual(cdp.classify(["no-op"]), "no-op")


class SummarizeTest(unittest.TestCase):
    def test_safe_plan_has_no_destructive_entries(self) -> None:
        result = cdp.summarize(plan(("a", ["create"]), ("b", ["update"]), ("c", ["no-op"])))
        self.assertEqual(result["destructive"], [])
        self.assertEqual(result["counts"]["create"], 1)

    def test_replace_and_delete_are_flagged(self) -> None:
        result = cdp.summarize(plan(("svc", ["delete", "create"]), ("sa", ["delete"]), ("ok", ["update"])))
        self.assertEqual({d["address"]: d["action"] for d in result["destructive"]},
                         {"google_x.svc": "replace", "google_x.sa": "delete"})


class MainTest(unittest.TestCase):
    def run_main(self, p: dict, allow: str | None) -> int:
        import json
        import tempfile

        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
            json.dump(p, fh)
        env = {"ALLOW_DESTRUCTIVE": allow} if allow is not None else {}
        with mock.patch.dict(os.environ, env, clear=False):
            if allow is None:
                os.environ.pop("ALLOW_DESTRUCTIVE", None)
            with mock.patch("builtins.print"):
                return cdp.main(["x", fh.name])

    def test_blocks_destructive_by_default(self) -> None:
        self.assertEqual(self.run_main(plan(("svc", ["delete", "create"])), None), 2)

    def test_blocks_when_flag_is_not_exactly_true(self) -> None:
        self.assertEqual(self.run_main(plan(("svc", ["delete"])), "false"), 2)

    def test_allows_destructive_with_explicit_flag(self) -> None:
        self.assertEqual(self.run_main(plan(("svc", ["delete"])), "true"), 0)

    def test_passes_safe_plan(self) -> None:
        self.assertEqual(self.run_main(plan(("svc", ["update"])), None), 0)


if __name__ == "__main__":
    unittest.main()

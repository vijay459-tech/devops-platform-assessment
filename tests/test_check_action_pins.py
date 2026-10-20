import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "scripts"))

import check_action_pins as cap  # noqa: E402


class ClassifyTest(unittest.TestCase):
    def test_classification(self) -> None:
        self.assertEqual(cap.classify("./.github/workflows/x.yml"), "local")
        self.assertEqual(cap.classify("actions/checkout@v4"), "tag")
        self.assertEqual(cap.classify("actions/checkout@" + "a" * 40), "sha")
        self.assertEqual(cap.classify("actions/checkout@" + "a" * 39), "tag")
        self.assertEqual(cap.classify("docker://alpine:3"), "unpinned")
        self.assertEqual(cap.classify("docker://alpine@sha256:" + "b" * 64), "docker")


if __name__ == "__main__":
    unittest.main()

import json
import os
import threading
import unittest
import urllib.error
import urllib.request
from unittest import mock

from service import server


class ServerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.state = server.State()
        self.state.ready.set()
        self.httpd = server.make_server("127.0.0.1", 0, self.state)
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self) -> None:
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(timeout=5)

    def get(self, path: str) -> tuple[int, dict, dict]:
        url = f"http://127.0.0.1:{self.port}{path}"
        try:
            with urllib.request.urlopen(url, timeout=5) as resp:  # noqa: S310
                return resp.status, json.load(resp), dict(resp.headers)
        except urllib.error.HTTPError as err:
            return err.code, json.load(err), dict(err.headers)

    def test_health_is_ok(self) -> None:
        status, body, headers = self.get("/health")
        self.assertEqual(status, 200)
        self.assertEqual(body, {"status": "ok"})
        self.assertEqual(headers["Cache-Control"], "no-store")

    def test_ready_reflects_draining_state(self) -> None:
        status, _, _ = self.get("/ready")
        self.assertEqual(status, 200)
        self.state.ready.clear()
        status, body, _ = self.get("/ready")
        self.assertEqual(status, 503)
        self.assertEqual(body["status"], "draining")

    def test_health_stays_ok_while_draining(self) -> None:
        self.state.ready.clear()
        status, _, _ = self.get("/health")
        self.assertEqual(status, 200)

    def test_version_uses_build_metadata(self) -> None:
        env = {"APP_VERSION": "1.2.3", "GIT_SHA": "abc123", "BUILD_TIME": "2026-10-19T00:00:00Z"}
        with mock.patch.dict(os.environ, env):
            status, body, _ = self.get("/version")
        self.assertEqual(status, 200)
        self.assertEqual(body, {"version": "1.2.3", "commit": "abc123", "build_time": "2026-10-19T00:00:00Z"})

    def test_unknown_path_is_404(self) -> None:
        status, _, _ = self.get("/nope")
        self.assertEqual(status, 404)

    def test_query_string_is_ignored_for_routing(self) -> None:
        status, _, _ = self.get("/health?x=1")
        self.assertEqual(status, 200)


if __name__ == "__main__":
    unittest.main()

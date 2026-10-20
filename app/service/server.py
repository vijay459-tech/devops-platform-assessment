"""HTTP service exposing /health, /ready and /version.

Design notes
- Standard library only: no third-party dependencies to patch or scan.
- /health is liveness (process is up). /ready is readiness (safe to receive
  traffic) and flips to 503 on SIGTERM so Cloud Run / a load balancer can stop
  routing before the process exits.
- Logs are single-line JSON on stdout, which Cloud Logging parses natively
  (``severity`` and ``message`` are recognised fields).
- No secret is ever read or logged here. Secrets, if any, arrive as environment
  variables injected by Cloud Run from Secret Manager.
"""

from __future__ import annotations

import json
import logging
import os
import signal
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = logging.getLogger("service")


class JsonFormatter(logging.Formatter):
    """Format log records as one JSON object per line for Cloud Logging."""

    def format(self, record: logging.LogRecord) -> str:
        return json.dumps(
            {
                "severity": record.levelname,
                "message": record.getMessage(),
                "logger": record.name,
            }
        )


class State:
    """Process readiness. Cleared when the process begins draining."""

    def __init__(self) -> None:
        self.ready = threading.Event()


def build_info() -> dict[str, str]:
    """Build metadata baked into the image via build args / env."""
    return {
        "version": os.environ.get("APP_VERSION", "0.0.0-dev"),
        "commit": os.environ.get("GIT_SHA", "unknown"),
        "build_time": os.environ.get("BUILD_TIME", "unknown"),
    }


def make_handler(state: State) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "service"
        sys_version = ""

        def _send_json(self, status: int, body: dict[str, str]) -> None:
            payload = json.dumps(body).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            self.wfile.write(payload)

        def do_GET(self) -> None:  # noqa: N802 - stdlib naming
            path = self.path.split("?", 1)[0]
            if path == "/health":
                self._send_json(200, {"status": "ok"})
            elif path == "/ready":
                if state.ready.is_set():
                    self._send_json(200, {"status": "ready"})
                else:
                    self._send_json(503, {"status": "draining"})
            elif path == "/version":
                self._send_json(200, build_info())
            else:
                self._send_json(404, {"error": "not found"})

        def log_message(self, fmt: str, *args: object) -> None:
            LOG.info("%s %s", self.address_string(), fmt % args)

    return Handler


def make_server(host: str, port: int, state: State) -> ThreadingHTTPServer:
    return ThreadingHTTPServer((host, port), make_handler(state))


def run() -> int:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    logging.basicConfig(level=logging.INFO, handlers=[handler])

    port = int(os.environ.get("PORT", "8080"))
    state = State()
    # 0.0.0.0 is required inside a container; exposure is controlled by the
    # platform (Cloud Run ingress / IAM), not by the bind address.
    server = make_server("0.0.0.0", port, state)  # noqa: S104

    def _drain(signum: int, _frame: object) -> None:
        LOG.info("signal %s received; draining", signum)
        state.ready.clear()
        # shutdown() blocks until serve_forever() returns, so call it off-thread.
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, _drain)
    signal.signal(signal.SIGINT, _drain)

    state.ready.set()
    LOG.info("listening on port %d", port)
    try:
        server.serve_forever()
    finally:
        server.server_close()
        LOG.info("stopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(run())

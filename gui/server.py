"""A one-page GUI for the guard. Runs on the presenter's laptop, standard library only.

    scripts/gui.sh            live: signs each request with your AWS credentials (via curl --aws-sigv4)
    scripts/gui.sh --mock     no AWS, no model: canned answers, and the page says MOCK in big letters

The browser can't sign SigV4 requests, so this server does: it reads the API URL from
Terraform outputs, gets short-lived credentials from `aws configure export-credentials`,
and forwards each message with the same curl call scripts/demo.sh uses.
Listens on 127.0.0.1 only.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PAGE = (Path(__file__).parent / "index.html").read_bytes()
MAX_CHARS = 4000


def run(cmd: list[str], stdin: str | None = None, timeout: float = 40) -> str:
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True, timeout=timeout, check=True).stdout


def tf_cmd() -> str:
    import shutil
    return shutil.which("tofu") or shutil.which("terraform") or "terraform"

def tf_output(name: str) -> str:
    return run([tf_cmd(), f"-chdir={ROOT / 'terraform'}", "output", "-raw", name], timeout=30).strip()


class Live:
    mode = "live"

    def __init__(self) -> None:
        self.api_url = tf_output("api_url")
        self.region = tf_output("region")
        self.queue_url = tf_output("review_queue_url")
        self._creds: dict | None = None
        self._creds_at = 0.0

    def creds(self) -> dict:
        # Refresh every 10 minutes; SSO/assumed-role credentials expire.
        if self._creds is None or time.time() - self._creds_at > 600:
            self._creds = json.loads(run(["aws", "configure", "export-credentials", "--format", "process"]))
            self._creds_at = time.time()
        return self._creds

    def send(self, message: str) -> tuple[int, dict]:
        c = self.creds()
        # Secrets go to curl on stdin (a config file), never on its command line.
        cfg = [f'user = "{c["AccessKeyId"]}:{c["SecretAccessKey"]}"']
        if c.get("SessionToken"):
            cfg.append(f'header = "x-amz-security-token: {c["SessionToken"]}"')
        out = run(
            ["curl", "-sS", "--max-time", "35", "--config", "-",
             "--aws-sigv4", f"aws:amz:{self.region}:execute-api",
             "-H", "content-type: application/json",
             "--data-binary", json.dumps({"message": message}),
             "-w", "\n%{http_code}", self.api_url],
            stdin="\n".join(cfg) + "\n",
        )
        body, _, code = out.rpartition("\n")
        try:
            parsed = json.loads(body) if body.strip() else {}
        except ValueError:
            parsed = {"error": "non-JSON response", "detail": body[:300]}
        return int(code or 0), parsed

    def queue_depth(self) -> int | None:
        try:
            out = run(["aws", "sqs", "get-queue-attributes", "--region", self.region, "--queue-url", self.queue_url,
                       "--attribute-names", "ApproximateNumberOfMessages",
                       "--query", "Attributes.ApproximateNumberOfMessages", "--output", "text"], timeout=15)
            return int(out.strip())
        except Exception:
            return None


class Mock:
    """Canned answers for rehearsing the page without AWS. Clearly labelled in the UI."""

    mode = "mock"

    def __init__(self) -> None:
        self.depth = 0

    def send(self, message: str) -> tuple[int, dict]:
        m = message.lower()
        pii = 0.97 if re.search(r"\d{3}-\d{3}-\d{4}|\d{4}[- ]\d{4}|@", m) else 0.66 if any(w in m for w in ("landlord", "husband", "wife", "whose")) else 0.03
        angry = 0.93 if any(w in m for w in ("third time", "!!", "cancel", "ridiculous")) else 0.04
        tech = any(w in m for w in ("error", "login", "crash", "bug", "down"))
        dept = {"billing": 0.05, "technical": 0.9, "other": 0.05} if tech else {"billing": 0.91, "technical": 0.06, "other": 0.03}
        business = 0.04
        p_redact = round(pii * (1 - business), 3)
        answers = {"pii": {"type": "noul", "p": pii}, "business": {"type": "noul", "p": business},
                   "dept": {"type": "choice", "probabilities": dept}}
        winner = max(dept, key=dept.get)
        gates = {
            "redact": {"value": None if 0.5 < p_redact < 0.7 else p_redact >= 0.6, "p": p_redact,
                       "outcome": "escalate" if 0.5 < p_redact < 0.7 else "decided",
                       "rule": {"op": "and", "tau": 0.6, "band": 0.1}},
            "route": {"value": winner, "p": dept[winner], "outcome": "decided", "confidence": 0.71,
                      "rule": {"op": "argmax", "tau": 0.5, "band": 0.1, "min_confidence": 0.35}},
        }
        if "angry" in m or angry > 0.5:
            answers["angry"] = {"type": "noul", "p": angry}
            gates["angry_to_human"] = {"value": angry >= 0.7, "p": angry, "outcome": "decided",
                                       "rule": {"op": "threshold", "tau": 0.7, "band": 0.1}}
        reasons = [g for g, v in gates.items() if v["outcome"] != "decided"]
        if gates.get("angry_to_human", {}).get("value") is True:
            reasons.append("angry_to_human")
        if reasons:
            self.depth += 1
            return 202, {"status": "human_review", "request_id": "mock", "review_id": f"mock-{self.depth}",
                         "summary": "MOCK summary: the customer needs help, and the guard was not sure enough to act alone.",
                         "summary_error": None, "reasons": reasons, "answers": answers, "gates": gates, "latency_ms": 180}
        text = message
        masks: dict = {}
        if gates["redact"]["value"]:
            for name, pat in (("EMAIL", r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+"), ("PHONE", r"\b\d{3}[ .-]\d{3}[ .-]\d{4}\b"),
                              ("ACCOUNT", r"\b\d{4}[- ]\d{4}[- ]?\d*\b")):
                text, n = re.subn(pat, f"[{name}]", text)
                if n:
                    masks[name] = n
        return 200, {"status": "routed", "department": winner, "redacted": bool(gates["redact"]["value"]),
                     "message": text, "masks": masks, "request_id": "mock", "answers": answers, "gates": gates,
                     "latency_ms": 180}

    def queue_depth(self) -> int:
        return self.depth


def make_handler(backend):
    class Handler(BaseHTTPRequestHandler):
        def _json(self, status: int, obj: dict) -> None:
            data = json.dumps(obj).encode()
            self.send_response(status)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self) -> None:
            if self.path in ("/", "/index.html"):
                self.send_response(200)
                self.send_header("content-type", "text/html; charset=utf-8")
                self.send_header("content-length", str(len(PAGE)))
                self.end_headers()
                self.wfile.write(PAGE)
            elif self.path == "/api/info":
                self._json(200, {"mode": backend.mode, "queue": backend.queue_depth()})
            else:
                self._json(404, {"error": "not found"})

        def do_POST(self) -> None:
            if self.path != "/api/send":
                return self._json(404, {"error": "not found"})
            try:
                req = json.loads(self.rfile.read(int(self.headers.get("content-length", 0))) or b"{}")
                message = str(req.get("message", ""))[:MAX_CHARS]
                t0 = time.monotonic()
                status, body = backend.send(message)
                ms = round((time.monotonic() - t0) * 1000)
                self._json(200, {"http": status, "ms": ms, "body": body, "mode": backend.mode})
            except subprocess.CalledProcessError as e:
                self._json(200, {"http": 0, "ms": 0, "body": {"error": "local_command_failed",
                                 "detail": (e.stderr or str(e))[:400]}, "mode": backend.mode})
            except Exception as e:
                self._json(200, {"http": 0, "ms": 0, "body": {"error": type(e).__name__, "detail": str(e)[:400]},
                                 "mode": backend.mode})

        def log_message(self, fmt: str, *args) -> None:  # keep the terminal quiet on stage
            pass

    return Handler


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mock", action="store_true", help="canned answers, no AWS (the page is labelled MOCK)")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--no-browser", action="store_true")
    args = ap.parse_args()
    try:
        backend = Mock() if args.mock else Live()
    except Exception as e:
        sys.exit(f"Could not read Terraform outputs or AWS config ({e}). Deploy first, or run with --mock.")
    url = f"http://127.0.0.1:{args.port}/"
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(backend))
    print(f"{'MOCK' if args.mock else 'LIVE'} guard GUI on {url}  (Ctrl-C to stop)")
    if not args.no_browser:
        webbrowser.open(url)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

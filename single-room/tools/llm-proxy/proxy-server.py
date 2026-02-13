import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib import request, error


MODEL = os.getenv("OPENAI_MODEL", "gpt-5.2-codex")
API_KEY = os.getenv("OPENAI_API_KEY", "")
BASE_URL = os.getenv("OPENAI_BASE_URL", "https://api.openai.com")
API_PATH = os.getenv("OPENAI_API_PATH", "/v1/responses")
PORT = int(os.getenv("LLM_PROXY_PORT", "8787"))
TIMEOUT = int(os.getenv("LLM_PROXY_TIMEOUT", "60"))
MAX_BODY = int(os.getenv("LLM_PROXY_MAX_BODY", "500000"))
RETURN_RAW = os.getenv("LLM_PROXY_RETURN_RAW", "0") == "1"


SYSTEM_PROMPT = """You are a Godot diagnostics assistant.
Analyze the payload and return:
1) Primary root-cause hypotheses (top 3)
2) The single best next diagnostic to run
3) Concrete fixes with file paths and rationale
Keep it short, bullet-based, and action-first.
"""

SYSTEM_PROMPT_CHAT = """You are a Godot editor assistant running inside the Godot Editor.
Rules:
- Suggestions only. Never claim to have edited files.
- If proposing temporary parameter overrides, output a single JSON block with key "overrides".
- Keep responses short and actionable.
"""


def _extract_text(resp):
    if not isinstance(resp, dict):
        return ""
    if "output_text" in resp and isinstance(resp["output_text"], str):
        return resp["output_text"]
    output = resp.get("output")
    if isinstance(output, list):
        parts = []
        for item in output:
            if not isinstance(item, dict):
                continue
            if isinstance(item.get("output_text"), str):
                parts.append(item.get("output_text", ""))
            content = item.get("content")
            if isinstance(content, list):
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    block_type = block.get("type")
                    text = block.get("text")
                    if block_type in ("output_text", "text") and isinstance(text, str):
                        parts.append(text)
            elif isinstance(content, str):
                parts.append(content)
        parts = [p for p in parts if isinstance(p, str) and p.strip()]
        if parts:
            return "\n".join(parts)
    if "choices" in resp and resp["choices"]:
        choice = resp["choices"][0]
        msg = choice.get("message", {}) if isinstance(choice, dict) else {}
        content = msg.get("content", "") if isinstance(msg, dict) else ""
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            parts = []
            for item in content:
                if isinstance(item, dict) and item.get("type") == "text":
                    parts.append(item.get("text", ""))
            return "\n".join([p for p in parts if p])
    if isinstance(resp.get("response"), str):
        return resp.get("response")
    return ""


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload):
        data = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path != "/health":
            self._send(404, {"error": "not_found"})
            return
        self._send(200, {
            "status": "ok",
            "model": MODEL,
            "has_key": bool(API_KEY),
        })

    def do_POST(self):
        if self.path not in ("/analyze", "/chat"):
            self._send(404, {"error": "not_found"})
            return
        if not API_KEY:
            self._send(400, {"error": "OPENAI_API_KEY not set"})
            return

        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > MAX_BODY:
            self._send(400, {"error": "invalid_content_length"})
            return

        body = self.rfile.read(length)
        try:
            data = json.loads(body.decode("utf-8"))
        except json.JSONDecodeError:
            self._send(400, {"error": "invalid_json"})
            return

        if self.path == "/chat":
            system_prompt = SYSTEM_PROMPT_CHAT
        else:
            system_prompt = SYSTEM_PROMPT

        messages = data.get("messages")
        if isinstance(messages, list) and messages:
            req_messages = [{"role": "system", "content": system_prompt}] + messages
        else:
            payload = data.get("payload", data)
            user_content = json.dumps(payload, indent=2)
            req_messages = [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_content},
            ]

        req_payload = {
            "model": MODEL,
            "input": req_messages,
        }

        url = BASE_URL.rstrip("/") + API_PATH
        req = request.Request(
            url,
            data=json.dumps(req_payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {API_KEY}",
                "Content-Type": "application/json",
            },
            method="POST",
        )

        try:
            with request.urlopen(req, timeout=TIMEOUT) as resp:
                resp_body = resp.read().decode("utf-8")
                resp_json = json.loads(resp_body)
        except error.HTTPError as exc:
            err_body = exc.read().decode("utf-8") if exc.fp else ""
            self._send(exc.code, {"error": "upstream_http_error", "detail": err_body})
            return
        except Exception as exc:
            self._send(500, {"error": "upstream_error", "detail": str(exc)})
            return

        analysis = _extract_text(resp_json)
        out = {"analysis": analysis}
        if RETURN_RAW:
            out["raw"] = resp_json
        self._send(200, out)


def main():
    server = HTTPServer(("127.0.0.1", PORT), Handler)
    print(f"[LLM Proxy] Listening on http://127.0.0.1:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""websearch-proxy.py — an OpenAI-compatible proxy that gives ninfer-serve web search.

Chat UIs and agents send plain chat turns with no tools, so a question about
current events reaches the model with no way to look anything up: it answers
from training data and invents recent-sounding facts. Tools have to be offered
and executed by the client, and most clients do not.

This proxy sits between the client and ninfer-serve. It injects web_search and
scrape_url tools, runs the tool loop against a self-hosted Firecrawl, and
returns (or streams) the grounded answer in OpenAI format. Small talk passes
through untouched, since the model simply does not call a tool.

Point the client at http://<host>:8899/v1 instead of :8080/v1.

Structure follows ziworkslab/dgx-spark-deepseek-v4-flash's ds4-proxy.py, adapted
for ninfer-serve: the upstream carries an API key, the proxy authenticates its
own callers, and the model's reasoning_content is kept out of the answer.

Standard library only.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = os.environ.get("UPSTREAM", "http://127.0.0.1:8080/v1")
UPSTREAM_API_KEY = os.environ.get("UPSTREAM_API_KEY", "welcome")
FIRECRAWL_URL = os.environ.get("FIRECRAWL_URL", "http://127.0.0.1:3002")
MODEL = os.environ.get("MODEL", "qwen3.8-27b")
PROXY_HOST = os.environ.get("PROXY_HOST", "0.0.0.0")
PROXY_PORT = int(os.environ.get("PROXY_PORT", "8899"))
PROXY_API_KEY = os.environ.get("PROXY_API_KEY", "welcome")
TIMEOUT = int(os.environ.get("TIMEOUT", "600"))
PER_RESULT_CHARS = int(os.environ.get("PER_RESULT_CHARS", "1500"))
MAX_ROUNDS = int(os.environ.get("MAX_ROUNDS", "3"))
MAX_TOKENS = int(os.environ.get("MAX_TOKENS", "3000"))
TODAY = os.environ.get("TODAY") or time.strftime("%Y-%m-%d")
SHOW_PROGRESS = os.environ.get("SHOW_PROGRESS", "1") not in ("0", "false", "no")

SYSTEM_PROMPT = (
    f"Today's date is {TODAY}. You can call the web_search and scrape_url tools. "
    "For anything your training data cannot answer accurately — current events, news, "
    "prices, release versions, or any claim about the present — call web_search and "
    "answer from what it returns. Never present a guess as current information. "
    "web_search already returns each result's title, URL and an excerpt of its text, "
    "which is usually enough: do not re-fetch those URLs with scrape_url. Call "
    "web_search once or twice, then write the answer. Use scrape_url only when one "
    "specific page genuinely needs a deeper read, and at most once or twice. Cite the "
    "source URLs you used. Answer directly, without searching, when the question does "
    "not need it. Reply in the language the user wrote in."
)


def _post(url, payload, timeout, headers=None):
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return json.load(response)


def web_search(query, limit=8):
    """Search the web. Firecrawl returns each hit already scraped to markdown."""
    payload = {"query": query, "limit": min(int(limit), 20),
               "scrapeOptions": {"formats": ["markdown"]}}
    data = _post(FIRECRAWL_URL + "/v1/search", payload, TIMEOUT)
    results = []
    for hit in (data.get("data") or []):
        markdown = (hit.get("markdown") or "").strip()
        results.append({"title": hit.get("title"), "url": hit.get("url"),
                        "content": markdown[:PER_RESULT_CHARS]})
    if not results:
        return {"error": "the search returned nothing", "query": query}
    return results


def scrape_url(url):
    data = _post(FIRECRAWL_URL + "/v1/scrape", {"url": url, "formats": ["markdown"]}, TIMEOUT)
    markdown = ((data.get("data") or {}).get("markdown") or "")
    return {"url": url, "content": markdown[:PER_RESULT_CHARS * 3]}


TOOLS = [
    {"type": "function", "function": {
        "name": "web_search",
        "description": "Search the web and return each result's title, URL and a text "
                       "excerpt. Use for current information and fact checking.",
        "parameters": {"type": "object", "properties": {
            "query": {"type": "string"},
            "limit": {"type": "integer", "description": "number of results, at most 20"}},
            "required": ["query"]}}},
    {"type": "function", "function": {
        "name": "scrape_url",
        "description": "Fetch one page as markdown. For a deeper read of a specific "
                       "result; use sparingly.",
        "parameters": {"type": "object", "properties": {
            "url": {"type": "string"}}, "required": ["url"]}}},
]
DISPATCH = {"web_search": web_search, "scrape_url": scrape_url}


def upstream_stream(messages, max_tokens, temperature):
    """Call ninfer-serve with streaming and yield each parsed chunk."""
    body = {"model": MODEL, "messages": messages, "tools": TOOLS,
            "tool_choice": "auto", "max_tokens": max_tokens or MAX_TOKENS, "stream": True}
    if temperature is not None:
        body["temperature"] = temperature
    headers = {"Content-Type": "application/json"}
    if UPSTREAM_API_KEY:
        headers["Authorization"] = "Bearer " + UPSTREAM_API_KEY
    req = urllib.request.Request(UPSTREAM + "/chat/completions",
                                 data=json.dumps(body).encode(), headers=headers)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as response:
        for raw in response:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            try:
                yield json.loads(data)
            except json.JSONDecodeError:
                continue


def agent_events(messages, max_tokens, temperature, progress=False):
    """Run the tool loop, yielding the answer text as it arrives.

    A turn that asks for tools is executed here and not forwarded; the model's
    reasoning_content is dropped, so only answer text reaches the client.

    With progress set, each search is announced as a line of answer text. A
    search turn produces no visible tokens for tens of seconds otherwise, which
    reads as a hung UI; non-streaming callers leave it off so the announcement
    stays out of the returned answer.
    """
    msgs = [{"role": "system", "content": SYSTEM_PROMPT}] + list(messages)
    for _ in range(MAX_ROUNDS):
        pending = {}  # index -> {id, name, arguments}
        sent_text = False
        for chunk in upstream_stream(msgs, max_tokens, temperature):
            delta = (chunk.get("choices") or [{}])[0].get("delta") or {}
            content = delta.get("content")
            if content:
                sent_text = True
                yield content
            for call_delta in (delta.get("tool_calls") or []):
                slot = pending.setdefault(call_delta.get("index", 0),
                                          {"id": "", "name": "", "arguments": ""})
                if call_delta.get("id"):
                    slot["id"] = call_delta["id"]
                function = call_delta.get("function") or {}
                if function.get("name"):
                    slot["name"] = function["name"]
                if function.get("arguments"):
                    slot["arguments"] += function["arguments"]

        if not pending:
            return  # the turn was the answer

        if sent_text:
            yield "\n\n"
        calls = [(slot["id"] or f"call_{index}", slot["name"], slot["arguments"])
                 for index, slot in sorted(pending.items())]
        msgs.append({"role": "assistant", "content": None, "tool_calls": [
            {"id": call_id, "type": "function",
             "function": {"name": name, "arguments": arguments}}
            for call_id, name, arguments in calls]})
        for call_id, name, argument_text in calls:
            try:
                arguments = json.loads(argument_text or "{}")
            except json.JSONDecodeError:
                arguments = {}
            print(f"[proxy] {name}({arguments})", file=sys.stderr, flush=True)
            if progress:
                detail = arguments.get("query") or arguments.get("url") or ""
                yield f"_{name}: {detail}_\n\n"
            try:
                result = (DISPATCH[name](**arguments) if name in DISPATCH
                          else {"error": f"unknown tool {name}"})
            except Exception as error:  # a failed tool is the model's problem to route around
                result = {"error": str(error)}
            msgs.append({"role": "tool", "tool_call_id": call_id,
                         "content": json.dumps(result, ensure_ascii=False)})

    yield "(Reached the search iteration limit. Please try again.)"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _json(self, code, obj):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _authorized(self):
        if not PROXY_API_KEY:
            return True
        presented = (self.headers.get("Authorization", "").removeprefix("Bearer ").strip()
                     or self.headers.get("x-api-key", "").strip())
        return presented == PROXY_API_KEY

    def do_GET(self):
        path = self.path.rstrip("/")
        if path in ("", "/health"):
            self._json(200, {"status": "ok", "model": MODEL, "upstream": UPSTREAM,
                             "firecrawl": FIRECRAWL_URL})
        elif not self._authorized():
            self._json(401, {"error": {"message": "invalid api key", "type": "invalid_request_error"}})
        elif path == "/v1/models":
            self._json(200, {"object": "list", "data": [
                {"id": MODEL, "object": "model", "created": int(time.time()),
                 "owned_by": "ninfer-websearch-proxy"}]})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        if not self._authorized():
            self._json(401, {"error": {"message": "invalid api key", "type": "invalid_request_error"}})
            return
        if self.path.rstrip("/") != "/v1/chat/completions":
            self._json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            request = json.loads(self.rfile.read(length) or b"{}")
        except Exception as error:
            self._json(400, {"error": f"bad request: {error}"})
            return

        messages = request.get("messages", [])
        max_tokens = request.get("max_tokens")
        temperature = request.get("temperature")
        completion_id = "chatcmpl-websearch"

        if not request.get("stream", False):
            try:
                answer = "".join(agent_events(messages, max_tokens, temperature))
            except Exception as error:
                self._json(502, {"error": {"message": f"proxy error: {error}",
                                           "type": "upstream_error"}})
                return
            self._json(200, {
                "id": completion_id, "object": "chat.completion",
                "created": int(time.time()), "model": MODEL,
                "choices": [{"index": 0, "finish_reason": "stop",
                             "message": {"role": "assistant", "content": answer}}]})
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        base = {"id": completion_id, "object": "chat.completion.chunk",
                "created": int(time.time()), "model": MODEL}

        def send(obj):
            try:
                self.wfile.write(f"data: {json.dumps(obj)}\n\n".encode())
                self.wfile.flush()
                return True
            except (BrokenPipeError, ConnectionResetError):
                return False

        send({**base, "choices": [{"index": 0, "delta": {"role": "assistant"},
                                   "finish_reason": None}]})
        try:
            for piece in agent_events(messages, max_tokens, temperature, progress=SHOW_PROGRESS):
                if not piece:
                    continue
                if not send({**base, "choices": [{"index": 0, "delta": {"content": piece},
                                                  "finish_reason": None}]}):
                    return  # client hung up
        except Exception as error:
            send({**base, "choices": [{"index": 0,
                                       "delta": {"content": f"\n\n(proxy error: {error})"},
                                       "finish_reason": None}]})
        send({**base, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]})
        try:
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == "__main__":
    print(f"websearch-proxy listening on http://{PROXY_HOST}:{PROXY_PORT}/v1 "
          f"(upstream={UPSTREAM}, firecrawl={FIRECRAWL_URL}, model={MODEL}, "
          f"today={TODAY}, max_rounds={MAX_ROUNDS}, "
          f"auth={'api key' if PROXY_API_KEY else 'disabled'})", file=sys.stderr)
    ThreadingHTTPServer((PROXY_HOST, PROXY_PORT), Handler).serve_forever()

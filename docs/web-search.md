# Web search

NInfer serves a model, not a search engine, and chat UIs send plain chat turns
with no tools attached. Ask a bare `ninfer-serve` about anything current and the
model has nothing to look at: it answers from training data and produces
confident, often wrongly dated, invented facts.

`scripts/websearch-proxy.py` closes that gap. It is an OpenAI-compatible server
that sits between the client and `ninfer-serve`, injects `web_search` and
`scrape_url` tools, runs the tool loop against a self-hosted
[Firecrawl](https://github.com/firecrawl/firecrawl), and returns a grounded
answer with source URLs. Questions that do not need a search are passed through:
the model simply does not call a tool.

The design follows
[ziworkslab/dgx-spark-deepseek-v4-flash](https://github.com/ziworkslab/dgx-spark-deepseek-v4-flash),
adapted to this fork: the upstream carries an API key, the proxy authenticates
its own callers with the same default key, and the model's `reasoning_content`
is kept out of the answer.

```
client ──► websearch-proxy :8899 ──► ninfer-serve :8080   (model, tool calls)
                    └──────────────► Firecrawl   :3002   (search + page text)
```

## Setup

Requires Docker with `docker compose` v2, usable without `sudo`
(`sudo usermod -aG docker "$USER"`, then log in again). The build needs about
6 GB of disk for images and no GPU, so it can run while a model is served.

```bash
./scripts/setup-firecrawl.sh     # clone into ./firecrawl, write .env, build images
```

## Run

Three processes, in this order:

```bash
./scripts/run-qwen38-c1.sh          # the model            :8080
./scripts/firecrawl-start.sh        # search backend       :3002
./scripts/run-websearch-proxy.sh    # search-enabled API   :8899
```

Then point the client at **`http://<host>:8899/v1`** instead of `:8080/v1`, with
model `qwen3.8-27b` and the API key (`welcome` unless changed). Everything else
about the OpenAI API stays the same, streaming included.

```bash
curl -s http://127.0.0.1:8899/v1/chat/completions \
  -H 'Content-Type: application/json' -H 'Authorization: Bearer welcome' \
  -d '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"What are the most recent Ubuntu LTS releases? Cite sources."}]}'
```

Stop Firecrawl with `./scripts/firecrawl-stop.sh` (`--down` also removes the
containers); the proxy stops with Ctrl+C.

## Measured behaviour

Qwen3.8-27B on one RTX 3090, `run-qwen38-c1.sh` upstream:

| Request | Result |
|---|---|
| "RTX 3090's VRAM and memory bandwidth, with sources" | 2 searches, correct 24 GB / 936 GB/s, real source URLs, 34 s |
| "Latest Ubuntu releases, in three lines" (streaming) | 2 searches, correct 26.04 LTS / 23 April 2026, TTFT 2.3 s, 39 s total |
| "2+2?" | no search, 1.3 s |

A search costs roughly 9 s per Firecrawl call plus the model's own prefill and
decode. Streaming announces each search as a line of text (`_web_search: ..._`)
because a search turn otherwise emits nothing for half a minute and reads as a
hung UI; set `SHOW_PROGRESS=0` to suppress it. Non-streaming replies never carry
those lines.

## Configuration

The launcher takes the same `NINFER_HOST` / `NINFER_PORT` / `NINFER_API_KEY`
defaults as the model launchers, so the proxy listens on `0.0.0.0:8899` and
requires the key `welcome`. Additional environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `PROXY_PORT` | `8899` | proxy listen port |
| `UPSTREAM` | `http://127.0.0.1:8080/v1` | the `ninfer-serve` to call |
| `UPSTREAM_API_KEY` | `NINFER_API_KEY` | key sent upstream |
| `FIRECRAWL_URL` | `http://127.0.0.1:3002` | Firecrawl endpoint |
| `MODEL` | `qwen3.8-27b` | model id advertised and requested |
| `MAX_ROUNDS` | `3` | tool-loop iterations before giving up |
| `PER_RESULT_CHARS` | `1500` | characters of each result passed to the model |
| `MAX_TOKENS` | `3000` | output cap when the client sends none |
| `MIN_ANSWER_TOKENS` | `1024` | floor applied to the client's `max_tokens` |
| `WAIT_SECONDS` | `90` | how long the launcher waits for its dependencies |
| `SHOW_PROGRESS` | `1` | announce each search while streaming |

Firecrawl itself is configured by `scripts/firecrawl.env`, copied to
`firecrawl/.env` with random secrets on first setup. It runs `/search` through
DuckDuckGo, which needs no API key; set `SEARXNG_ENDPOINT` there to use a
self-hosted [SearXNG](https://github.com/searxng/searxng) instead. Firecrawl's
own AI features point at this host's `ninfer-serve`, so no text is sent to a
third-party model API. Idle footprint is about 3.4 GB of system RAM across five
containers.

## Troubleshooting

**`error: no Firecrawl at http://127.0.0.1:3002`** — its API needs about 15 s
after the container starts, so a proxy launched in the next breath finds nothing
there. The launcher now waits up to `WAIT_SECONDS` for both dependencies and
prints `waiting for Firecrawl ...` while it does. If it still times out, check
the containers:

```bash
docker ps --format '{{.Names}}\t{{.Status}}'
(cd firecrawl && docker compose logs --tail=50 api)
```

**`Address already in use`** — an earlier proxy is still running.
`pkill -f websearch-proxy.py`, or set `PROXY_PORT`.

**An empty answer, or "no answer after several searches"** — the model spends
output budget on reasoning and on the tool-call turn before it writes anything,
so a small `max_tokens` can end the turn first. `MIN_ANSWER_TOKENS` raises the
cap to leave room, and when the model keeps searching past `MAX_ROUNDS` the
proxy asks once more with no tools offered, forcing an answer from the results
already gathered.

## Privacy

Inference stays on this machine, but **search reaches the public internet**:
Firecrawl sends the model's query to DuckDuckGo and fetches the result pages
from their origin servers, from this host's IP address. Only the query and the
page fetches leave the machine — the conversation itself does not — but a query
the model composes may quote the user's wording. Self-hosting SearXNG changes
which engines are contacted, not the fact that they are.

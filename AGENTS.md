# AGENTS.md

This file provides guidance to AI when working with code in this repository.

## What Is This

ZeroGravity is a MITM proxy that intercepts Google Antigravity's Language Server (LS) binary traffic and relays it as OpenAI / Anthropic / Gemini-compatible API endpoints. It runs as a Docker container on `localhost:8741`.

## Quick Start (Docker on macOS)

Prerequisites: Docker Desktop, Antigravity.app installed and logged in, sqlite3 (pre-installed on macOS).

```bash
# 1. Build and start
docker compose up -d --build

# 2. Inject OAuth token from Antigravity
TOKEN=$(sqlite3 "$HOME/Library/Application Support/Antigravity/User/globalStorage/state.vscdb" \
  "SELECT json_extract(value, '$.apiKey') FROM ItemTable WHERE key = 'antigravityAuthStatus';")
curl -X POST http://localhost:8741/v1/token -H "Content-Type: application/json" -d "{\"token\":\"$TOKEN\"}"

# 3. Verify
curl -s http://localhost:8741/health
```

## Connecting AI Tools

The proxy exposes OpenAI, Anthropic, and Gemini-compatible APIs on `http://localhost:8741`.

### Claude Code

```bash
ANTHROPIC_BASE_URL=http://localhost:8741 ANTHROPIC_API_KEY=dummy claude
```

### OpenAI-compatible tools (Cursor, Cline, aider, Continue, etc.)

```
Base URL:  http://localhost:8741/v1
API Key:   anything
Model:     gemini-3-flash / gemini-3-pro / opus-4.6 / sonnet-4.6
```

### curl

```bash
# Anthropic Messages API
curl http://localhost:8741/v1/messages \
  -H "Content-Type: application/json" -H "x-api-key: dummy" -H "anthropic-version: 2023-06-01" \
  -d '{"model":"gemini-3-flash","max_tokens":100,"messages":[{"role":"user","content":"hi"}]}'

# OpenAI Chat Completions API
curl http://localhost:8741/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gemini-3-flash","messages":[{"role":"user","content":"hi"}]}'
```

## Models

| ID | Notes |
|----|-------|
| `opus-4.6` | Claude Opus 4.6 (Thinking), default |
| `sonnet-4.6` | Claude Sonnet 4.6 (Thinking) |
| `opus-4.5` | Claude Opus 4.5 (Thinking) |
| `gemini-3-pro` / `gemini-3-pro-high` | Gemini 3 Pro (High) |
| `gemini-3-pro-low` | Gemini 3 Pro (Low) |
| `gemini-3-flash` | Gemini 3 Flash, recommended for dev/testing |

## Token Management

OAuth tokens expire after ~1 hour. On macOS Docker, `state.vscdb` has the access token but NOT the refresh token (stored in macOS Keychain, inaccessible from Docker). The `docker-compose.yml` intentionally omits `ZEROGRAVITY_TOKEN` to avoid stale env vars.

```bash
# Re-inject token (run when token expires)
TOKEN=$(sqlite3 "$HOME/Library/Application Support/Antigravity/User/globalStorage/state.vscdb" \
  "SELECT json_extract(value, '$.apiKey') FROM ItemTable WHERE key = 'antigravityAuthStatus';")
curl -X POST http://localhost:8741/v1/token -H "Content-Type: application/json" -d "{\"token\":\"$TOKEN\"}"
```

When the token expires: open Antigravity app briefly (refreshes `state.vscdb`), then re-run the above.

When switching Google accounts: log in via Antigravity app, then `docker compose restart` + re-inject token.

## Architecture

```
Client ──OpenAI/Anthropic/Gemini API──> Proxy :8741
  Proxy ──gRPC (dummy prompt)──> Standalone LS binary
    LS ──HTTPS :443──> MITM :8742
      MITM ──modified request (real prompt + tools)──> Google API
      Google ──SSE response──> MITM ──parsed events──> Proxy ──> Client
```

**Key components:**
- **Proxy** (port 8741): HTTP server exposing OpenAI Chat Completions, OpenAI Responses, Anthropic Messages, and Gemini v1beta APIs
- **MITM** (port 8742): TLS-intercepting proxy that modifies LS requests before they reach Google
- **Extension Server stub**: Fake extension server that feeds the LS auth tokens and settings
- **LS binary**: Google's closed-source Go binary extracted from the Antigravity app

## Dockerfile

Three stages:
1. `ls-extractor`: Downloads Antigravity tarball from Google CDN, extracts the LS binary (pinned version `1.16.5-6703236727046144`)
2. `downloader`: Extracts proxy binaries from the official Docker image (GitHub Release arm64 binaries segfault — see Gotchas)
3. Runtime: Debian trixie-slim with UID-isolated `zerogravity-ls` system user

Do NOT `docker run ghcr.io/nikketryhard/zerogravity:latest` directly — its LS binary is a 0-byte placeholder. Always `docker compose build` locally.

## Running Modes

- `--headless` (default in Docker): Standalone LS binary, no Antigravity app needed
- `--classic`: Attaches to a running Antigravity instance
- `--no-mitm`: Proxy only, no MITM interception

## Native Setup (non-Docker)

```bash
# Linux (requires: curl, jq, sudo, iptables; dpkg-deb only if Antigravity not installed)
./scripts/setup-linux.sh && zg start

# macOS (requires: Antigravity.app installed)
./scripts/setup-macos.sh && zg start

# Windows (run as Administrator)
powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1
```

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `ZEROGRAVITY_TOKEN` | OAuth token (`ya29.xxx`) — avoid in docker-compose, use `POST /v1/token` instead |
| `ZEROGRAVITY_LS_PATH` | Custom path to the LS binary |
| `RUST_LOG` | Log level (default: `info` in Docker) |

## Gotchas

- OAuth tokens expire after ~1 hour. On macOS Docker, there is no auto-refresh — use `POST /v1/token` to inject fresh tokens (see Token Management)
- Tool calls are unstable and may hang
- Both `setup-macos.sh` and `setup-windows.ps1` currently download Linux binaries (bug: should download platform-specific binaries)
- Antigravity version pins: Dockerfile pins `AG_VERSION=1.16.5-6703236727046144`, Linux setup pins `ANTIGRAVITY_VERSION=1.16.5-1770081357`. Updating may break compatibility.
- macOS LS binary filename is `language_server_macos_arm` (Antigravity 1.16.5), not `language_server_darwin_arm64` as some docs state
- GitHub Release arm64 binaries (`zerogravity-linux-arm64`) segfault (exit code 139) due to obfuscation. The Dockerfile extracts working binaries from the official Docker image instead.

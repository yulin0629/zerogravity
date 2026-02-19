# AGENTS.md

This file provides guidance to AI when working with code in this repository.

## Repository Context

This is the **public distribution repo** for ZeroGravity. The Rust source code (`src/`, `Cargo.toml`, `Cargo.lock`) and internal documentation (`docs/`) live in a **separate private repo** and are gitignored here. This repo contains release infrastructure: Dockerfile, setup scripts, docker-compose, README, and issue templates.

ZeroGravity is a MITM proxy that intercepts Google Antigravity's Language Server (LS) binary traffic and relays it as OpenAI / Anthropic / Gemini-compatible API endpoints. It impersonates the real Electron webview using BoringSSL TLS fingerprinting (Chrome JA3/JA4 + H2 signatures).

## Architecture

```
Client ──OpenAI/Anthropic/Gemini API──> Proxy :8741
  Proxy ──gRPC (dummy prompt)──> Standalone LS binary
    LS ──HTTPS :443──> MITM :8742
      MITM ──modified request (real prompt + tools)──> Google API
      Google ──SSE response──> MITM ──parsed events──> Proxy ──> Client
```

**Request lifecycle:** Client sends an API request to the Proxy. Proxy converts it to a dummy prompt and tells the LS to make a gRPC call. The MITM intercepts the LS's outbound HTTPS traffic (via iptables UID-scoped redirect on Linux, or HTTPS_PROXY on macOS/Windows), swaps in the real prompt/tools/images/generation params, re-encrypts with Chrome-matching TLS, and forwards to Google. The SSE response is parsed for text, thinking tokens, tool calls, and usage, then streamed back to the client.

**Key components:**
- **Proxy** (port 8741): HTTP server exposing OpenAI Chat Completions, OpenAI Responses, Anthropic Messages, and Gemini v1beta APIs
- **MITM** (port 8742): TLS-intercepting proxy that modifies LS requests before they reach Google
- **Extension Server stub**: Fake extension server that feeds the LS auth tokens and settings, making it believe it's inside a real Antigravity window
- **LS binary**: Google's closed-source Go binary extracted from the Antigravity app

**Running modes** (from bug report template):
- `--headless` (default): No running Antigravity app needed
- `--classic`: Attached to a running Antigravity instance
- `--no-mitm`: Proxy only, no MITM interception

## Build & Run

Source code is not in this repo. The development workflow for this repo focuses on Docker images, setup scripts, and documentation.

### Docker

```bash
# Build image (multi-stage: extracts LS binary from Antigravity tarball + proxy from official image)
docker compose build

# Start container (token injected separately — see Token Management)
docker compose up -d

# NOTE: official image has 0-byte LS binary — build locally with `docker compose build` instead
```

The Dockerfile has three stages:
1. `ls-extractor`: Downloads Antigravity tarball from Google CDN, extracts the LS binary (pinned version `1.16.5-6703236727046144`)
2. `downloader`: Extracts proxy binaries from the official Docker image (GitHub Release arm64 binaries segfault — see Gotchas)
3. Runtime: Debian trixie-slim with UID-isolated `zerogravity-ls` system user

### Setup Scripts

```bash
# Linux (requires: curl, jq, sudo, iptables; dpkg-deb only if Antigravity not installed)
./scripts/setup-linux.sh    # Finds/downloads LS binary, creates system user + sudoers rule, downloads proxy binary

# macOS (requires: Antigravity.app installed)
./scripts/setup-macos.sh    # Creates config dirs, downloads binary

# Windows (run as Administrator)
powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1
```

### Daemon Management (`zg` CLI)

```bash
zg start                # Start proxy daemon
zg stop                 # Stop daemon
zg restart              # Restart without rebuild
zg rebuild              # Build from source + restart (dev only, needs private repo)
zg update               # Download latest binary from GitHub Releases
zg status               # Service status + quota + usage
zg test "hello"         # Quick test (gemini-3-flash)
zg health               # Health check
zg logs [-follow] [N]   # View logs
zg trace [ls|dir|errors] # Debug traces
```

### Testing a Running Instance

```bash
# Health check
curl -s http://localhost:8741/health | jq .

# Chat completions (OpenAI-compatible)
curl http://localhost:8741/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gemini-3-flash","messages":[{"role":"user","content":"hi"}]}'

# List models
curl http://localhost:8741/v1/models
```

## Build Toolchain (Private Repo)

When working with the Rust source (in the private repo), these configs apply:

- **`.cargo/config.toml`**: Uses `sccache` as rustc wrapper, `mold` linker via `clang` on Linux x86_64, 8 parallel jobs
- **`.config/nextest.toml`**: Test runner uses `cargo-nextest`, 8 threads, 30s slow timeout, no retries

## Token Management

Token sources (checked in order): `ZEROGRAVITY_TOKEN` env var, `~/.config/zerogravity/token` file, runtime `POST /v1/token`.

**Docker on macOS**: `state.vscdb` contains the access token but NOT the refresh token (stored in macOS Keychain via Electron safeStorage, inaccessible from Docker). The token freezes at container start and expires after ~1 hour. Solution: inject fresh tokens at runtime via `POST /v1/token`. The `docker-compose.yml` intentionally omits `ZEROGRAVITY_TOKEN` to avoid stale env vars.

```bash
# Extract token from Antigravity's state.vscdb and inject into running proxy
TOKEN=$(sqlite3 "$HOME/Library/Application Support/Antigravity/User/globalStorage/state.vscdb" \
  "SELECT json_extract(value, '$.apiKey') FROM ItemTable WHERE key = 'antigravityAuthStatus';")
curl -X POST http://localhost:8741/v1/token -H "Content-Type: application/json" -d "{\"token\":\"$TOKEN\"}"
```

When the token expires: open Antigravity app briefly (refreshes `state.vscdb`), then re-run the above.

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `ZEROGRAVITY_TOKEN` | OAuth token (`ya29.xxx`) — avoid in docker-compose, use `POST /v1/token` instead |
| `ZEROGRAVITY_LS_PATH` | Custom path to the LS binary |
| `RUST_LOG` | Log level (default: `info` in Docker) |

## Models

| ID | Notes |
|----|-------|
| `opus-4.6` | Claude Opus 4.6 (Thinking), default |
| `sonnet-4.6` | Claude Sonnet 4.6 (Thinking) |
| `opus-4.5` | Claude Opus 4.5 (Thinking) |
| `gemini-3-pro` / `gemini-3-pro-high` | Gemini 3 Pro (High) |
| `gemini-3-pro-low` | Gemini 3 Pro (Low) |
| `gemini-3-flash` | Gemini 3 Flash, recommended for dev/testing |

## Platform Differences

- **Linux**: Full UID-scoped iptables redirect. LS binary can be auto-downloaded from Google's apt repo. System user `zerogravity-ls` for isolation.
- **macOS**: No iptables; uses headless/HTTPS_PROXY mode. Requires Antigravity.app installed (LS binary at `/Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/language_server_darwin_arm64`).
- **Windows**: Similar to macOS. LS binary at `%LOCALAPPDATA%\Programs\Antigravity\resources\app\extensions\antigravity\bin\language_server_windows_x64.exe`.
- **Docker**: Bundles everything. Debian trixie-slim base (required for GLIBC 2.39+). Supports amd64 and arm64.

## Gotchas

- OAuth tokens expire after ~1 hour. On macOS Docker, there is no auto-refresh — use `POST /v1/token` to inject fresh tokens (see Token Management)
- Tool calls are unstable and may hang
- Both `setup-macos.sh` and `setup-windows.ps1` currently download Linux binaries (bug: should download platform-specific binaries)
- Antigravity pins are important: Dockerfile pins `AG_VERSION=1.16.5-6703236727046144`, Linux setup pins `ANTIGRAVITY_VERSION=1.16.5-1770081357`. Updating these may break compatibility if Google changes the LS protocol.
- macOS LS binary filename is `language_server_macos_arm` (Antigravity 1.16.5), but `setup-macos.sh` and some docs reference `language_server_darwin_arm64`. Verify the actual filename in `/Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/` if things don't work.
- Docker on macOS now works with the custom Dockerfile in this repo (v1.1.5). See `docs/macos-docker-setup.md` for setup. The official Docker image (`ghcr.io/nikketryhard/zerogravity:latest`) contains a working proxy binary on trixie base, but its LS binary is a 0-byte placeholder — our Dockerfile's Stage 1 downloads the real LS binary from Google CDN. Do NOT `docker run` the official image directly without building locally first.
- GitHub Release arm64 binaries (`zerogravity-linux-arm64`) segfault (exit code 139) due to obfuscation. The Dockerfile extracts working binaries from the official Docker image instead.

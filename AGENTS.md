# AGENTS.md

This file provides guidance to AI agents working with this repository.

## What Is This

ZeroGravity is a local MITM proxy that makes AI tool requests look like real Antigravity traffic to Google. It exposes OpenAI, Anthropic, and Gemini-compatible API endpoints on `localhost:8741`.

## Quick Reference

**Docs:** [README](README.md) | [API Reference](docs/api.md) | [Docker Guide](docs/docker.md) | [`zg` CLI](docs/zg.md)

## Setup (Docker)

**First-time on a new machine:**
```bash
# 1. Install zg CLI (not managed by chezmoi, must install manually)
curl -fsSL https://github.com/NikkeTryHard/zerogravity/releases/latest/download/zg-macos-arm64 \
  -o ~/.local/bin/zg && chmod +x ~/.local/bin/zg

# 2. Extract refresh token from Antigravity -> accounts.json
zg extract

# 3. Start proxy
zg-start
curl http://localhost:8741/health  # Verify
```

**Subsequent starts:**
```bash
zg-start
```

## Connecting Clients

**Claude Code:**
```bash
ANTHROPIC_BASE_URL=http://localhost:8741 ANTHROPIC_API_KEY=dummy claude
```

**OpenAI-compatible** (Cursor, Cline, aider, etc.):
```
Base URL:  http://localhost:8741/v1
API Key:   anything
```

**Gemini-native** (OpenCode @ai-sdk/google -- recommended, zero-translation):
```
Base URL:  http://localhost:8741/v1beta
API Key:   anything
```

**Anthropic-native** (OpenCode @ai-sdk/anthropic):
```
Base URL:  http://localhost:8741/v1
API Key:   anything
```

## Models

See [README Models table](README.md#models) for the canonical list.

Current models: `opus-4.6` (default), `sonnet-4.6`, `gemini-3-flash` (dev recommended), `gemini-3.1-pro`, `gemini-3.1-pro-low`, `gemini-3-pro-image`.

## Common `zg` Commands

| Command | Description |
|---------|-------------|
| `zg extract` | Extract refresh token from Antigravity |
| `zg docker-init` | Generate docker-compose.yml |
| `zg accounts` | List stored accounts |
| `zg status` | Version, quota, usage |
| `zg test "hi"` | Quick test request |
| `zg smoke` | Full endpoint smoke test |
| `zg logs` | View recent logs |
| `zg update` | Update zg binary |

## Token Management

Tokens are managed automatically via refresh tokens in `accounts.json`. No manual injection needed. Multi-account rotation is automatic when quota is exhausted.

To add accounts: sign into another Google account in Antigravity, quit & relaunch, then `zg extract` again.

## Environment Variables

See [Docker Guide](docs/docker.md) for the full list. Key ones:

| Variable | Purpose |
|----------|---------|
| `ZEROGRAVITY_ACCOUNTS` | Inline accounts (email:refresh_token, comma-separated) |
| `ZEROGRAVITY_API_KEY` | Protect proxy access |
| `ZEROGRAVITY_MODEL_ALIASES` | Custom model name mappings |
| `RUST_LOG` | Log level (default: info) |

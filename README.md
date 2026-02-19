> [!IMPORTANT]
> **Source code has moved to a private repository** for long-term sustainability.
> Binaries, Docker images, and releases will continue to be published here.
>
> **Want access to the source?**
> - 📬 [Open a Discussion](https://github.com/NikkeTryHard/zerogravity/discussions) on this repo
> - 💬 [Join our Telegram](https://t.me/ZeroGravityProxy) and DM me
>
> Read-only access is granted on request.

<p align="center">
  <img src="https://img.shields.io/badge/platform-linux%20%7C%20macos%20%7C%20windows-555?style=flat-square" alt="Platform" />
  <img src="https://img.shields.io/badge/license-MIT-333?style=flat-square" alt="License" />
  <img src="https://img.shields.io/badge/API-OpenAI%20%7C%20Anthropic%20%7C%20Gemini-666?style=flat-square" alt="API" />
</p>

<h1 align="center">ZeroGravity</h1>

<p align="center">
  <img src="assets/logo.png" alt="ZeroGravity" width="200" />
</p>

<p align="center">
  OpenAI, Anthropic, and Gemini-compatible proxy for Google's Antigravity.
</p>

> **Early stage.** Ran this on OpenCode with an Ultra account for 3 days straight, stress testing the whole time. No issues so far.
>
> This software is developed on Linux. I aim to support every OS as best as possible, so if there is any issue please open an issue and I will be happy to assist.
>
> Star the repo so more people can find it while it still works. Issues and PRs are welcome.

---

## Models

| Name                | Label                      | Notes               |
| ------------------- | -------------------------- | ------------------- |
| `opus-4.6`          | Claude Opus 4.6 (Thinking) | Default model       |
| `opus-4.5`          | Claude Opus 4.5 (Thinking) | —                   |
| `gemini-3-pro`      | Gemini 3 Pro (High)        | Default Pro tier    |
| `gemini-3-pro-high` | Gemini 3 Pro (High)        | Alias               |
| `gemini-3-pro-low`  | Gemini 3 Pro (Low)         | —                   |
| `gemini-3-flash`    | Gemini 3 Flash             | Recommended for dev |

## Quick Start

```bash
# Headless mode (no running Antigravity app needed)
RUST_LOG=info ./zerogravity --headless

# Or use the daemon manager
zg start
```

## Authentication

The proxy needs an OAuth token:

1. **Env var**: `ZEROGRAVITY_TOKEN=ya29.xxx`
2. **Token file**: `~/.config/zerogravity/token`
3. **Runtime**: `curl -X POST http://localhost:8741/v1/token -d '\''{ "token": "ya29.xxx" }'\''`

<details>
<summary>How to get the token</summary>

1. Open Antigravity → **Help** > **Toggle Developer Tools**
2. Go to the **Network** tab
3. Send any prompt
4. Find a request to `generativelanguage.googleapis.com`
5. Look for the `Authorization: Bearer ya29.xxx` header
6. Copy the token (starts with `ya29.`)

> **Note:** OAuth tokens expire after ~1 hour. If Antigravity is installed on the same machine, auto-refresh works automatically.

</details>

## Setup

### Download Binary

```bash
# x86_64
curl -fsSL https://github.com/NikkeTryHard/zerogravity/releases/latest/download/zerogravity-linux-x86_64 -o zerogravity
chmod +x zerogravity

# ARM64
curl -fsSL https://github.com/NikkeTryHard/zerogravity/releases/latest/download/zerogravity-linux-arm64 -o zerogravity
chmod +x zerogravity
```

### Linux

```bash
./scripts/setup-linux.sh
zg start
```

### macOS

```bash
./scripts/setup-macos.sh
zg start
```

### Windows

```powershell
# Run as Administrator
powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1
.\zerogravity.exe
```

### Docker

```bash
docker run -d --name zerogravity \
  -p 8741:8741 -p 8742:8742 \
  -e ZEROGRAVITY_TOKEN=ya29.xxx \
  ghcr.io/nikketryhard/zerogravity:latest
```

Or with docker-compose:

```bash
echo "ZEROGRAVITY_TOKEN=ya29.xxx" > .env
docker compose up -d
```

> **Note:** The Docker image bundles the LS binary so no Antigravity installation is needed.

## Endpoints

| Method     | Path                              | Description                           |
| ---------- | --------------------------------- | ------------------------------------- |
| `POST`     | `/v1/responses`                   | Responses API (sync + streaming)      |
| `POST`     | `/v1/chat/completions`            | Chat Completions API (OpenAI compat)  |
| `POST`     | `/v1/messages`                    | Messages API (Anthropic compat)       |
| `POST`     | `/v1beta/models/{model}:{action}` | Official Gemini v1beta routes         |
| `GET`      | `/v1/models`                      | List available models                 |
| `POST`     | `/v1/token`                       | Set OAuth token at runtime            |
| `GET`      | `/v1/usage`                       | Token usage stats                     |
| `GET`      | `/v1/quota`                       | Quota and rate limits                 |
| `GET`      | `/health`                         | Health check                          |

## `zg` Commands

| Command              | Description                                 |
| -------------------- | ------------------------------------------- |
| `zg start`           | Start the proxy daemon                      |
| `zg stop`            | Stop the proxy daemon                       |
| `zg restart`         | Stop + start                                |
| `zg update`          | Download latest binary from GitHub Releases |
| `zg status`          | Service status + quota + usage              |
| `zg logs [N]`        | Show last N lines (default 30)              |
| `zg test [msg]`      | Quick test request (gemini-3-flash)         |
| `zg health`          | Health check                                |

## License

[MIT](LICENSE)

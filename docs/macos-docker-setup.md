# macOS Docker Setup — Research Notes

> Findings from setting up and debugging ZeroGravity via Docker on macOS arm64 (Feb 2026).
> Source code reference: [yulin0629/zerogravity](https://github.com/yulin0629/zerogravity) (old fork with full Rust source)

## Status: Working (v1.1.5)

Docker on macOS arm64 works with the **custom Dockerfile** in this repo. The key is using proxy binaries from the official Docker image (`ghcr.io/nikketryhard/zerogravity`) combined with a Debian trixie-slim base (GLIBC 2.39+).

The official pre-built Docker image (`ghcr.io/nikketryhard/zerogravity:latest`) has a working proxy binary on a trixie base, but its **LS binary is a 0-byte placeholder** — running it directly fails with `Permission denied`. Our Dockerfile downloads the real LS binary from Google CDN in Stage 1.

### Verified (2026-02-19)

| Test | Result |
|------|--------|
| `GET /health` | `{"status":"ok"}` |
| `GET /v1/models` | 7 models listed |
| `POST /v1/chat/completions` (gemini-3-flash) | MITM intercept + response OK |

## Quick Start (macOS arm64)

```bash
# 1. Build & run
docker compose up -d --build

# 2. Inject token from Antigravity's state.vscdb
TOKEN=$(sqlite3 "$HOME/Library/Application Support/Antigravity/User/globalStorage/state.vscdb" \
  "SELECT json_extract(value, '$.apiKey') FROM ItemTable WHERE key = 'antigravityAuthStatus';")
curl -X POST http://localhost:8741/v1/token \
  -H "Content-Type: application/json" -d "{\"token\":\"$TOKEN\"}"

# 3. Test
curl -s http://localhost:8741/health
curl -s http://localhost:8741/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gemini-3-flash","messages":[{"role":"user","content":"hi"}]}'
```

## macOS-Specific Paths

| Item | Path |
|------|------|
| Antigravity config | `~/Library/Application Support/Antigravity/` |
| state.vscdb (token DB) | `~/Library/Application Support/Antigravity/User/globalStorage/state.vscdb` |
| LS binary (ARM) | `/Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm` |

The actual LS binary filename on macOS is `language_server_macos_arm`, not `language_server_darwin_arm64` as stated in some documentation and in the Rust source code (`platform.rs:112-118`).

## Token Management

`state.vscdb` contains only the access token (`apiKey`), NOT the refresh token. The refresh token is stored in macOS Keychain (Electron safeStorage), which Docker cannot access. This means:

- Access tokens expire after ~1 hour
- No auto-refresh inside the Docker container
- Tokens must be injected at runtime via `POST /v1/token`

```bash
# Extract and inject token
TOKEN=$(sqlite3 "$HOME/Library/Application Support/Antigravity/User/globalStorage/state.vscdb" \
  "SELECT json_extract(value, '$.apiKey') FROM ItemTable WHERE key = 'antigravityAuthStatus';")
curl -X POST http://localhost:8741/v1/token \
  -H "Content-Type: application/json" -d "{\"token\":\"$TOKEN\"}"
```

**When the token expires**: open Antigravity app briefly (it refreshes `state.vscdb`), then re-run the extract+inject command above.

**Why `docker-compose.yml` omits `ZEROGRAVITY_TOKEN`**: env vars freeze at container start. A token passed via env becomes stale after ~1 hour with no way to update it without restarting the container. Runtime injection via `POST /v1/token` avoids this.

## Dockerfile Design

Our Dockerfile uses 3 stages:

1. **ls-extractor**: Downloads Antigravity tarball from Google CDN, extracts LS binary
2. **downloader**: Extracts proxy binaries from the official Docker image (NOT from GitHub Releases — the Release arm64 binaries segfault due to obfuscation)
3. **Runtime**: Debian trixie-slim (GLIBC 2.39+) with gcc, iptables, sudo

### Why not use GitHub Release binaries?

`zerogravity-linux-arm64` from GitHub Releases (v1.1.5) crashes with SIGSEGV (exit code 139). The binary from the official Docker image works fine on the same base. This is likely related to the obfuscation applied to release binaries (`readelf` reports section header errors, `ldd` crashes with SIGBUS).

### Why not use the official Docker image directly?

The official `:latest` image contains a working proxy binary on trixie, but its LS binary (`language_server_linux_x64`) is a 0-byte placeholder. Running `docker run ghcr.io/nikketryhard/zerogravity:latest` directly fails with `Permission denied` when trying to spawn the empty LS binary. Our Dockerfile's Stage 1 downloads the real LS binary from Google CDN.

## Headless MITM Interception Mechanism

From source code analysis (`spawn.rs:216-295`). Docker uses headless mode which does **NOT** rely on iptables:

```
1. Modifies LS endpoint URL -> daily-cloudcode-pa.googleapis.com:8742
2. LD_PRELOAD dns_redirect.so hooks getaddrinfo() -> 127.0.0.1
3. Combined: LS connects to 127.0.0.1:8742 (the MITM proxy)
4. MITM intercepts the TLS connection via SNI
```

- `HTTPS_PROXY` is set but the LS's `CodeAssistClient` has `Proxy:nil` hardcoded (`spawn.rs:218`), so it's ignored.
- `dns_redirect.c:8-9` states the LS uses CGO (BoringCrypto), so `getaddrinfo()` goes through glibc and LD_PRELOAD works.

---

<details>
<summary>Historical: v1.1.3 MITM failure analysis</summary>

On v1.1.3, Docker on macOS reported `mitm_matched: false` for all requests, causing 500 errors. Reference: [GitHub Issue #15](https://github.com/NikkeTryHard/zerogravity/issues/15) (CLOSED as COMPLETED in v1.1.5-beta.2).

The original Dockerfile was missing `iptables` and the proxy binary was from GitHub Releases (which segfaults on arm64). After fixing both issues and upgrading to v1.1.5, everything works.

### Debugging commands (for future issues)

```bash
docker exec <container> ldd /usr/local/bin/language_server_linux_x64
docker exec <container> ls -la /tmp/zerogravity-standalone/dns-redirect.so
docker exec <container> cat /tmp/zerogravity-standalone/dns-redirect.log
docker exec <container> cat /tmp/zerogravity-standalone/ls-debug.log
```

</details>

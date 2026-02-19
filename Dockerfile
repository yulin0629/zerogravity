ARG ZG_IMAGE=ghcr.io/nikketryhard/zerogravity:latest

# ── Stage 1: Extract LS binary from Antigravity tarball ──
FROM debian:trixie-slim AS ls-extractor

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Download from Google's CDN — auto-detect architecture
# Pin to known-good version to prevent breakage from Google updates
ARG AG_VERSION=1.16.5-6703236727046144
WORKDIR /extract
RUN ARCH=$(dpkg --print-architecture) \
    && case "$ARCH" in \
    amd64) CDN_ARCH="linux-x64";  LS_NAME="language_server_linux_x64" ;; \
    arm64) CDN_ARCH="linux-arm";   LS_NAME="language_server_linux_arm" ;; \
    *)     echo "Unsupported arch: $ARCH" && exit 1 ;; \
    esac \
    && curl -fsSL "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${AG_VERSION}/${CDN_ARCH}/Antigravity.tar.gz" \
    | tar xz --strip-components=1 \
    && cp "resources/app/extensions/antigravity/bin/${LS_NAME}" /ls_binary \
    && chmod +x /ls_binary \
    && rm -rf /extract

# ── Stage 2: Extract proxy binary from official Docker image ──
# GitHub Release binaries segfault on arm64 (obfuscation issue?), so we
# extract from the working official Docker image instead.
FROM ${ZG_IMAGE} AS downloader

# ── Stage 3: Runtime ──
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    gcc \
    libc6-dev \
    iptables \
    sudo \
    procps \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Create system user for UID isolation
RUN useradd --system --no-create-home --shell /usr/sbin/nologin zerogravity-ls \
    && echo "root ALL=(zerogravity-ls) NOPASSWD: ALL" > /etc/sudoers.d/zerogravity \
    && chmod 0440 /etc/sudoers.d/zerogravity

# Copy binaries
COPY --from=downloader /usr/local/bin/zerogravity /usr/local/bin/zerogravity
COPY --from=downloader /usr/local/bin/zg /usr/local/bin/zg
COPY --from=ls-extractor /ls_binary /usr/local/bin/language_server_linux_x64

# Setup directories
RUN mkdir -p /root/.config/zerogravity \
    && mkdir -p /tmp/zerogravity-standalone \
    && chmod 1777 /tmp/zerogravity-standalone

EXPOSE 8741 8742

ENV RUST_LOG=info
ENV ZEROGRAVITY_TOKEN=""
ENV ZEROGRAVITY_LS_PATH="/usr/local/bin/language_server_linux_x64"

ENTRYPOINT ["zerogravity"]
CMD ["--headless", "--host", "0.0.0.0"]

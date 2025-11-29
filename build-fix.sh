#!/bin/bash
# Build a patched Jellyfin Docker image with the collections loading fix
# This builds the entire Jellyfin from source with the fix applied

set -e

IMAGE_NAME="jellyfin-fixed:10.11.3"

echo "=============================================="
echo "Building Jellyfin with Collections Loading Fix"
echo "=============================================="

# Create the Dockerfile for building
cat > Dockerfile.build << 'DOCKERFILE'
# Multi-stage build for Jellyfin with collections fix
FROM mcr.microsoft.com/dotnet/sdk:9.0-bookworm-slim AS builder

WORKDIR /repo
COPY . .

# Restore and build
RUN dotnet restore Jellyfin.Server/Jellyfin.Server.csproj \
        --disable-parallel \
    && dotnet publish Jellyfin.Server/Jellyfin.Server.csproj \
        --configuration Release \
        --output="/jellyfin" \
        --no-restore \
        -p:DebugSymbols=false \
        -p:DebugType=none

# Final runtime image
FROM debian:bookworm-slim

# Install dependencies
RUN apt-get update \
    && apt-get install --no-install-recommends --no-install-suggests -y \
        ca-certificates \
        gnupg \
        curl \
        apt-transport-https \
    && curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key | gpg --dearmor -o /usr/share/keyrings/jellyfin.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/jellyfin.gpg] https://repo.jellyfin.org/debian bookworm main" > /etc/apt/sources.list.d/jellyfin.list \
    && apt-get update \
    && apt-get install --no-install-recommends --no-install-suggests -y \
        jellyfin-ffmpeg7 \
        openssl \
        locales \
        libfontconfig1 \
        libfreetype6 \
    && apt-get remove -y gnupg apt-transport-https \
    && apt-get clean autoclean -y \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && locale-gen

ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=0 \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en

# Copy jellyfin from builder
COPY --from=builder /jellyfin /jellyfin

EXPOSE 8096
VOLUME /config /cache
ENTRYPOINT ["/jellyfin/jellyfin", \
    "--datadir", "/config", \
    "--cachedir", "/cache", \
    "--ffmpeg", "/usr/lib/jellyfin-ffmpeg/ffmpeg"]
DOCKERFILE

echo "Building Docker image: $IMAGE_NAME"
echo "This may take 5-10 minutes..."
echo ""

docker build -f Dockerfile.build -t "$IMAGE_NAME" .

# Cleanup
rm -f Dockerfile.build

echo ""
echo "=============================================="
echo "Build complete!"
echo "=============================================="
echo ""
echo "The patched image is available as: $IMAGE_NAME"
echo ""
echo "To deploy on your server, you can:"
echo ""
echo "1. Stop current jellyfin:"
echo "   systemctl stop jellyfin"
echo ""
echo "2. Update /etc/systemd/system/jellyfin.service to use the new image:"
echo "   Change the image from 'jellyfin/jellyfin:latest' to '$IMAGE_NAME'"
echo ""
echo "3. Start jellyfin:"
echo "   systemctl daemon-reload && systemctl start jellyfin"
echo ""

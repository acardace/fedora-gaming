#!/bin/bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-ghcr.io/acardace/fedora-gaming}"
BUILD_MINIMAL="${BUILD_MINIMAL:-true}"
BUILD_LATEST="${BUILD_LATEST:-true}"

# Build minimal image
if [[ "${BUILD_MINIMAL}" == "true" ]]; then
    echo "Building minimal image: ${IMAGE_NAME}:minimal"
    podman build \
        -f Containerfile.minimal \
        -t "${IMAGE_NAME}:minimal" \
        .
    echo "✓ Minimal image built successfully: ${IMAGE_NAME}:minimal"
    podman push "${IMAGE_NAME}:minimal"
fi

# Build full image based on minimal
if [[ "${BUILD_LATEST}" == "true" ]]; then
    echo "Building full image: ${IMAGE_NAME}:latest"
    podman build \
        -f Containerfile \
        -t "${IMAGE_NAME}:latest" \
        .
    echo "✓ Full image built successfully: ${IMAGE_NAME}:latest"
fi

echo ""
echo "Images built:"
podman images "${IMAGE_NAME}"

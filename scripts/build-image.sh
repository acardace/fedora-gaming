#!/bin/bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-ghcr.io/acardace/fedora-gaming}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "Building bootc image: ${IMAGE_NAME}:${IMAGE_TAG}"

podman build \
    -f Containerfile \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    .

echo "✓ Image built successfully: ${IMAGE_NAME}:${IMAGE_TAG}"
podman images "${IMAGE_NAME}:${IMAGE_TAG}"

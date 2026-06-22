#!/bin/bash
set -euo pipefail

REGISTRY="${REGISTRY:-registry.canederli.org}"
IMAGE_NAME="${IMAGE_NAME:-fedora-gaming}"
BUILD_BASE="${BUILD_BASE:-true}"
BUILD_NVIDIA="${BUILD_NVIDIA:-true}"

# Build base image (GPU-agnostic)
if [[ "${BUILD_BASE}" == "true" ]]; then
    echo "Building base image: ${REGISTRY}/${IMAGE_NAME}:base"
    podman build \
        -f Containerfile \
        -t "${REGISTRY}/${IMAGE_NAME}:base" \
        .
    echo "✓ Base image built successfully: ${REGISTRY}/${IMAGE_NAME}:base"
fi

# Build NVIDIA image on top of the base
if [[ "${BUILD_NVIDIA}" == "true" ]]; then
    echo "Building nvidia image: ${REGISTRY}/${IMAGE_NAME}-nvidia:latest"
    podman build \
        -f Containerfile.nvidia \
        --build-arg BASE_IMAGE="${REGISTRY}/${IMAGE_NAME}:base" \
        -t "${REGISTRY}/${IMAGE_NAME}-nvidia:latest" \
        .
    echo "✓ Nvidia image built successfully: ${REGISTRY}/${IMAGE_NAME}-nvidia:latest"
fi

echo ""
echo "Images built:"
podman images "${REGISTRY}/${IMAGE_NAME}"
podman images "${REGISTRY}/${IMAGE_NAME}-nvidia"

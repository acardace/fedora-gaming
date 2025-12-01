#!/bin/bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-ghcr.io/acardace/fedora-gaming}"
IMAGE_TAG="${IMAGE_TAG:-minimal}"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"
CONFIG_FILE="${CONFIG_FILE:-./config.toml}"

# Convert to absolute paths for podman volume mounts
OUTPUT_DIR="$(realpath -m "${OUTPUT_DIR}")"
CONFIG_FILE="$(realpath "${CONFIG_FILE}")"

mkdir -p "${OUTPUT_DIR}"

echo "Creating qcow2 disk image from: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "Using config: ${CONFIG_FILE}"
echo "Output directory: ${OUTPUT_DIR}"

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Error: Config file not found: ${CONFIG_FILE}"
    exit 1
fi

# Check if image exists in rootless storage
if ! podman image exists "${IMAGE_NAME}:${IMAGE_TAG}"; then
    echo "Error: Image ${IMAGE_NAME}:${IMAGE_TAG} not found in rootless storage"
    exit 1
fi

# Get image SHA from rootless storage
ROOTLESS_SHA=$(podman image inspect "${IMAGE_NAME}:${IMAGE_TAG}" --format '{{.Id}}' 2>/dev/null)

# Get image SHA from rootful storage (if exists)
ROOTFUL_SHA=$(sudo podman image inspect "${IMAGE_NAME}:${IMAGE_TAG}" --format '{{.Id}}' 2>/dev/null || echo "")

# Only copy if SHAs don't match
if [[ "${ROOTLESS_SHA}" != "${ROOTFUL_SHA}" ]]; then
    echo "Image SHA mismatch, copying to rootful storage..."
    podman save "${IMAGE_NAME}:${IMAGE_TAG}" | sudo podman load
    echo "✓ Image copied to rootful storage"
else
    echo "✓ Image already up to date in rootful storage"
fi

sudo podman run \
    --rm \
    -it \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v "${OUTPUT_DIR}":/output \
    -v "${CONFIG_FILE}":/config.toml:ro \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type qcow2 \
    --rootfs ext4 \
    --config /config.toml \
    "${IMAGE_NAME}:${IMAGE_TAG}"

echo "✓ Disk image created in: ${OUTPUT_DIR}"
ls -lh "${OUTPUT_DIR}"

#!/bin/bash
set -euo pipefail

VM_NAME="${VM_NAME:-fedora-gaming-test}"
VCPUS="${VCPUS:-4}"
MEMORY="${MEMORY:-8192}"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"
SKIP_BUILD="${SKIP_BUILD:-false}"

# Convert to absolute path
OUTPUT_DIR="$(realpath -m "${OUTPUT_DIR}")"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
QCOW2_PATH="${OUTPUT_DIR}/qcow2/disk.qcow2"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Create a qcow2 image and start it in a libvirt VM for testing.

Options:
    --skip-build    Skip building the image, use existing qcow2
    --name NAME     VM name (default: fedora-gaming-test)
    --vcpus N       Number of vCPUs (default: 4)
    --memory MB     Memory in MB (default: 8192)
    --help          Show this help message

Environment variables:
    IMAGE_NAME      Container image name (default: localhost/fedora-gaming)
    IMAGE_TAG       Container image tag (default: latest)
    OUTPUT_DIR      Output directory (default: ./output)
    CONFIG_FILE     Config file path (default: ./config.toml)
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --name)
            VM_NAME="$2"
            shift 2
            ;;
        --vcpus)
            VCPUS="$2"
            shift 2
            ;;
        --memory)
            MEMORY="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Build the qcow2 image if not skipping
if [[ "${SKIP_BUILD}" != "true" ]]; then
    echo "Building qcow2 image..."
    "${SCRIPT_DIR}/create-disk-image.sh"
else
    echo "Skipping build, using existing image..."
fi

# Verify qcow2 exists
if [[ ! -f "${QCOW2_PATH}" ]]; then
    echo "Error: qcow2 image not found at: ${QCOW2_PATH}"
    exit 1
fi

echo "Using qcow2 image: ${QCOW2_PATH}"

# Check if VM already exists and remove it
if sudo virsh dominfo "${VM_NAME}" &>/dev/null; then
    echo "VM '${VM_NAME}' already exists, removing..."
    sudo virsh destroy "${VM_NAME}" 2>/dev/null || true
    sudo virsh undefine "${VM_NAME}" --nvram 2>/dev/null || true
fi

# Create a copy of the qcow2 for the VM (so we don't modify the original)
VM_DISK="${OUTPUT_DIR}/${VM_NAME}.qcow2"
echo "Creating VM disk copy: ${VM_DISK}"
cp "${QCOW2_PATH}" "${VM_DISK}"

# Create and start the VM
echo "Creating VM: ${VM_NAME}"
sudo virt-install \
    --name "${VM_NAME}" \
    --vcpus "${VCPUS}" \
    --memory "${MEMORY}" \
    --disk "path=${VM_DISK},format=qcow2" \
    --import \
    --os-variant fedora-unknown \
    --network network=default \
    --graphics spice \
    --video virtio \
    --boot uefi \
    --tpm none \
    --noautoconsole

echo ""
echo "VM '${VM_NAME}' created and started!"
echo ""
echo "Useful commands:"
echo "  View console:     sudo virsh console ${VM_NAME}"
echo "  Open GUI:         virt-viewer ${VM_NAME}"
echo "  Stop VM:          sudo virsh shutdown ${VM_NAME}"
echo "  Force stop:       sudo virsh destroy ${VM_NAME}"
echo "  Delete VM:        sudo virsh undefine ${VM_NAME} --nvram"
echo "  List VMs:         sudo virsh list --all"

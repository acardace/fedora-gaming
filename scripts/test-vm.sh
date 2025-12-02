#!/bin/bash
set -euo pipefail

VM_NAME="${VM_NAME:-fedora-gaming-test}"
VCPUS="${VCPUS:-4}"
MEMORY="${MEMORY:-8192}"
DISK_SIZE="${DISK_SIZE:-50}"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"
SKIP_BUILD="${SKIP_BUILD:-false}"

# Convert to absolute path
OUTPUT_DIR="$(realpath -m "${OUTPUT_DIR}")"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
ISO_PATH="${OUTPUT_DIR}/bootiso/install.iso"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Create an ISO and start a libvirt VM to test the installation.

Options:
    --skip-build    Skip building the ISO, use existing one
    --name NAME     VM name (default: fedora-gaming-test)
    --vcpus N       Number of vCPUs (default: 4)
    --memory MB     Memory in MB (default: 8192)
    --disk-size GB  Disk size in GB (default: 50)
    --help          Show this help message

Environment variables:
    IMAGE_NAME      Container image name (default: ghcr.io/acardace/fedora-gaming)
    IMAGE_TAG       Container image tag (default: minimal)
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
        --disk-size)
            DISK_SIZE="$2"
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

# Build the ISO if not skipping
if [[ "${SKIP_BUILD}" != "true" ]]; then
    echo "Building ISO..."
    "${SCRIPT_DIR}/create-iso.sh"
else
    echo "Skipping build, using existing ISO..."
fi

# Verify ISO exists
if [[ ! -f "${ISO_PATH}" ]]; then
    echo "Error: ISO not found at: ${ISO_PATH}"
    exit 1
fi

echo "Using ISO: ${ISO_PATH}"

# Check if VM already exists and remove it
if sudo virsh dominfo "${VM_NAME}" &>/dev/null; then
    echo "VM '${VM_NAME}' already exists, removing..."
    sudo virsh destroy "${VM_NAME}" 2>/dev/null || true
    sudo virsh undefine "${VM_NAME}" --nvram 2>/dev/null || true
fi

# Create a blank qcow2 disk for the VM
VM_DISK="${OUTPUT_DIR}/${VM_NAME}.qcow2"
echo "Creating blank ${DISK_SIZE}GB disk: ${VM_DISK}"
qemu-img create -f qcow2 "${VM_DISK}" "${DISK_SIZE}G"

# Create and start the VM
echo "Creating VM: ${VM_NAME}"
sudo virt-install \
    --name "${VM_NAME}" \
    --vcpus "${VCPUS}" \
    --memory "${MEMORY}" \
    --disk "path=${VM_DISK},format=qcow2" \
    --cdrom "${ISO_PATH}" \
    --os-variant fedora-unknown \
    --network network=default \
    --graphics spice \
    --video virtio \
    --boot uefi \
    --tpm none \
    --noautoconsole

echo ""
echo "VM '${VM_NAME}' created and started!"
echo "The installer should be running - use virt-viewer to interact with it."
echo ""
echo "Useful commands:"
echo "  Open GUI:         virt-viewer ${VM_NAME}"
echo "  View console:     sudo virsh console ${VM_NAME}"
echo "  Stop VM:          sudo virsh shutdown ${VM_NAME}"
echo "  Force stop:       sudo virsh destroy ${VM_NAME}"
echo "  Delete VM:        sudo virsh undefine ${VM_NAME} --nvram"
echo "  List VMs:         sudo virsh list --all"

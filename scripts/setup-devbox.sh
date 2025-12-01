#!/bin/bash
set -euo pipefail

# Setup development distrobox with tools excluded from the main bootc image
# This creates a containerized development environment with Go, Rust, and Google Cloud CLI

DISTROBOX_NAME="dev"
DISTROBOX_IMAGE="fedora:43"
RECREATE=false

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="${SCRIPT_DIR}/distrobox-packages.txt"
EXPORTS_FILE="${SCRIPT_DIR}/distrobox-exports.txt"

# Function to read config file (ignoring comments and empty lines)
read_config_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "Error: Config file not found: $file" >&2
        exit 1
    fi
    grep -v '^\s*#' "$file" | grep -v '^\s*$' | sed 's/^\s*//' | sed 's/\s*$//'
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --recreate)
            RECREATE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--recreate]"
            echo
            echo "Options:"
            echo "  --recreate    Force recreation of the distrobox (clean slate)"
            echo "  -h, --help    Show this help message"
            echo
            echo "Default behavior: Updates existing distrobox or creates new one if needed"
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

echo "Setting up development distrobox: ${DISTROBOX_NAME}"
echo "Using image: ${DISTROBOX_IMAGE}"
echo

# Check if distrobox command exists
if ! command -v distrobox &> /dev/null; then
    echo "Error: distrobox is not installed"
    exit 1
fi

# Check if the distrobox already exists
DISTROBOX_EXISTS=false
if distrobox list | grep -q "^${DISTROBOX_NAME} "; then
    DISTROBOX_EXISTS=true
fi

# Handle recreation or smart update
if $DISTROBOX_EXISTS; then
    if $RECREATE; then
        echo "Distrobox '${DISTROBOX_NAME}' exists. Recreating..."
        distrobox rm -f "${DISTROBOX_NAME}"
        DISTROBOX_EXISTS=false
    else
        echo "Distrobox '${DISTROBOX_NAME}' already exists. Updating packages..."
    fi
fi

# Create the distrobox if it doesn't exist
if ! $DISTROBOX_EXISTS; then
    echo "Creating distrobox '${DISTROBOX_NAME}'..."
    distrobox create \
        --name "${DISTROBOX_NAME}" \
        --image "${DISTROBOX_IMAGE}" \
        --yes
    echo
fi

echo "Installing/updating development packages in distrobox..."

# Read packages from config file
PACKAGES=$(read_config_file "$PACKAGES_FILE" | tr '\n' ' ')
echo "Packages to install: $PACKAGES"
echo

# Install packages inside the distrobox
distrobox enter "${DISTROBOX_NAME}" -- bash -c "
set -euo pipefail

echo 'Adding Google Cloud CLI repository...'
sudo tee /etc/yum.repos.d/google-cloud-sdk.repo > /dev/null << EOF
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

echo 'Installing packages...'
sudo dnf install -y $PACKAGES

echo 'Development packages installed successfully!'
"

echo
echo "Exporting commands to host..."

# Export binaries to the host (exports are idempotent)
while IFS= read -r binary; do
    echo "Exporting: $binary"
    distrobox enter "${DISTROBOX_NAME}" -- distrobox-export --bin "$binary" --export-path ~/.local/bin 2>/dev/null || true
done < <(read_config_file "$EXPORTS_FILE")

echo
echo "✓ Development distrobox setup complete!"
echo
echo "Usage:"
echo "  - Enter the distrobox:    distrobox enter ${DISTROBOX_NAME}"
echo "  - Run Go from host:       go version"
echo "  - Run Rust from host:     cargo --version"
echo "  - Run gcloud from host:   gcloud --version"
echo "  - List exported apps:     ls ~/.local/bin/"
echo
echo "Configuration:"
echo "  - Packages:               ${PACKAGES_FILE}"
echo "  - Exports:                ${EXPORTS_FILE}"
echo
echo "Exported commands are available in your PATH (~/.local/bin)"
echo
echo "Tip: Run this script again to update packages, or use --recreate for a fresh start"

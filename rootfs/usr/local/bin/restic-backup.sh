#!/bin/bash
set -euo pipefail

# Restic backup script for bootc system
# Backs up mutable partitions to Google Drive via rclone

# Trap to ensure cleanup on exit/interruption
trap 'echo "Backup interrupted at $(date)" >&2' EXIT TERM INT

RESTIC_REPO="rclone:gdrive:laptop-backup"
BACKUP_PATHS="/home /etc /var /opt"
EXCLUDE_PATTERNS=(
    "/var/home/acardace/.local/share/containers"
    "/var/lib/containers"
    "/var/cache"
    "/var/tmp"
    "/var/log"
    "**/.cache"
    "**/Cache"
    "**/cache"
)

# Source environment variables (RESTIC_PASSWORD)
if [ -f /etc/restic/env ]; then
    source /etc/restic/env
else
    echo "ERROR: /etc/restic/env not found. Please create it with RESTIC_PASSWORD set."
    exit 1
fi

# Check if rclone is configured
if ! rclone listremotes | grep -q "gdrive:"; then
    echo "ERROR: rclone gdrive remote not configured. Run: rclone config"
    exit 1
fi

# Remove stale locks from previous interrupted backups
restic -r "$RESTIC_REPO" unlock 2>/dev/null || true

# Initialize repository if it doesn't exist
if ! restic -r "$RESTIC_REPO" snapshots &>/dev/null; then
    echo "Initializing restic repository..."
    restic -r "$RESTIC_REPO" init
fi

# Build exclude arguments
EXCLUDE_ARGS=()
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    EXCLUDE_ARGS+=(--exclude "$pattern")
done

# Perform backup
echo "Starting backup to $RESTIC_REPO..."
restic -r "$RESTIC_REPO" backup $BACKUP_PATHS "${EXCLUDE_ARGS[@]}" \
    -vv \
    --tag "automated" \
    --tag "$(hostname)"

# Cleanup old backups
echo "Cleaning up old backups..."
restic -r "$RESTIC_REPO" forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 12 \
    --prune

echo "Backup completed successfully at $(date)"

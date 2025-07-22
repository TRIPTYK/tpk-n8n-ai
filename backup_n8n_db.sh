#!/bin/bash

# Set script to exit on error
set -e

# Get the directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables from .env file
if [ -f "$SCRIPT_DIR/.env" ]; then
  echo "Loading environment variables from .env file..."
  source "$SCRIPT_DIR/.env"
else
  echo "Error: .env file not found in $SCRIPT_DIR"
  exit 1
fi

# Set default backup directory and filename
BACKUP_DIR="$SCRIPT_DIR/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/n8n_backup_$TIMESTAMP.sql"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

echo "Starting PostgreSQL backup of n8n database..."
echo "Using database: $POSTGRES_DB"
echo "Using username: $POSTGRES_USER"
echo "Backup will be saved to: $BACKUP_FILE"

# Get the container name or ID
POSTGRES_CONTAINER=$(docker ps --filter name=postgres --format "{{.Names}}" | head -n 1)

if [ -z "$POSTGRES_CONTAINER" ]; then
  echo "Error: PostgreSQL container not found!"
  exit 1
fi

echo "Using PostgreSQL container: $POSTGRES_CONTAINER"

# Perform the backup using docker exec and pg_dump
docker exec -i $POSTGRES_CONTAINER pg_dump \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  -F p > "$BACKUP_FILE"

# Check if backup was successful
if [ $? -eq 0 ]; then
  echo "Backup completed successfully!"
  echo "Backup saved to: $BACKUP_FILE"
  
  # Create a compressed version
  gzip -c "$BACKUP_FILE" > "$BACKUP_FILE.gz"
  echo "Compressed backup saved to: $BACKUP_FILE.gz"
else
  echo "Error: Backup failed!"
  exit 1
fi

echo "Done!"

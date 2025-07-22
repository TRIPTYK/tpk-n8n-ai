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

# Check if a backup file was provided as an argument
if [ -z "$1" ]; then
  echo "Error: No backup file specified!"
  echo "Usage: $0 <backup_file>"
  echo "Example: $0 backups/n8n_backup_20250722_110000.sql"
  exit 1
fi

BACKUP_FILE="$1"

# Check if the backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
  # Check if it's a relative path
  if [ ! -f "$SCRIPT_DIR/$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
  else
    BACKUP_FILE="$SCRIPT_DIR/$BACKUP_FILE"
  fi
fi

# If the file ends with .gz, decompress it first
if [[ "$BACKUP_FILE" == *.gz ]]; then
  echo "Decompressing backup file..."
  TEMP_FILE="${BACKUP_FILE%.gz}"
  gunzip -c "$BACKUP_FILE" > "$TEMP_FILE"
  BACKUP_FILE="$TEMP_FILE"
  echo "Decompressed to: $BACKUP_FILE"
fi

echo "Starting PostgreSQL restore of n8n database..."
echo "Using database: $POSTGRES_DB"
echo "Using username: $POSTGRES_USER"
echo "Restoring from: $BACKUP_FILE"

# Confirm with the user before proceeding
read -p "This will overwrite the current database. Are you sure you want to continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Restore canceled."
  exit 1
fi

# Get the container name or ID
POSTGRES_CONTAINER=$(docker ps --filter name=postgres --format "{{.Names}}" | head -n 1)

if [ -z "$POSTGRES_CONTAINER" ]; then
  echo "Error: PostgreSQL container not found!"
  exit 1
fi

echo "Using PostgreSQL container: $POSTGRES_CONTAINER"

# First, stop the n8n container to prevent connection issues
echo "Stopping n8n container to prevent connection issues..."
docker-compose stop n8n

# Create a clean database by dropping and recreating it
echo "Recreating a clean database..."
docker exec -i $POSTGRES_CONTAINER psql -U "$POSTGRES_USER" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$POSTGRES_DB';"
docker exec -i $POSTGRES_CONTAINER psql -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};"
docker exec -i $POSTGRES_CONTAINER psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE ${POSTGRES_DB};"

# Perform the restore using docker exec and psql
echo "Restoring database..."
cat "$BACKUP_FILE" | docker exec -i $POSTGRES_CONTAINER psql \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB"

# Restart the n8n container
echo "Restarting n8n container..."
docker-compose start n8n

# Check if restore was successful
if [ $? -eq 0 ]; then
  echo "Restore completed successfully!"
else
  echo "Error: Restore failed!"
  exit 1
fi

# Clean up temporary file if we decompressed
if [[ "$BACKUP_FILE" != "$1" && "$1" == *.gz ]]; then
  echo "Cleaning up temporary file..."
  rm "$BACKUP_FILE"
fi

echo "Done!"

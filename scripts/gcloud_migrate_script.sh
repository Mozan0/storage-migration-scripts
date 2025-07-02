#!/bin/bash

set -euo pipefail

# === jq check and install ===
if ! command -v jq &> /dev/null; then
  echo "jq not found, installing..."

  OS="$(uname -s)"
  ARCH="$(uname -m)"

  if [ "$OS" = "Linux" ]; then
    if [ "$ARCH" = "x86_64" ]; then
      JQ_URL="https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"
    else
      echo "Unsupported architecture for jq on Linux: $ARCH"
      exit 1
    fi
  elif [ "$OS" = "Darwin" ]; then
    if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "arm64" ]; then
      JQ_URL="https://github.com/stedolan/jq/releases/download/jq-1.6/jq-osx-amd64"
    else
      echo "Unsupported architecture for jq on macOS: $ARCH"
      exit 1
    fi
  else
    echo "Unsupported OS: $OS"
    exit 1
  fi

  DEST="/usr/local/bin/jq"
  if [ -w /usr/local/bin ]; then
    curl -L -o "$DEST" "$JQ_URL"
    chmod +x "$DEST"
  else
    DEST="/tmp/jq"
    curl -L -o "$DEST" "$JQ_URL"
    chmod +x "$DEST"
    export PATH="/tmp:$PATH"
    echo "jq installed to /tmp and added to PATH"
  fi

  if ! command -v jq &> /dev/null; then
    echo "Failed to install jq"
    exit 1
  fi

  echo "jq installed successfully"
fi

API_URL=""
API_KEY=""
BUCKET_NAME=""
GCS_FOLDER=""

print_usage() {
  echo "Usage: $0 --api-url=URL --apikey=KEY --bucket=BUCKET_NAME [--gcs-folder=prefix]"
  exit 1
}

for ARG in "$@"; do
  case $ARG in
    --api-url=*) API_URL="${ARG#*=}" ;;
    --apikey=*) API_KEY="${ARG#*=}" ;;
    --bucket=*) BUCKET_NAME="${ARG#*=}" ;;
    --gcs-folder=*) GCS_FOLDER="${ARG#*=}" ;;
    *) echo "Unknown option: $ARG"; print_usage ;;
  esac
done

if [[ -z "$API_URL" || -z "$API_KEY" || -z "$BUCKET_NAME" ]]; then
  echo "Missing required arguments."
  print_usage
fi

OBJECTS_JSON=$(curl -sSL -H "apikey: $API_KEY" "$API_URL/storage?limit=10000")
TOTAL_OBJECTS=$(echo "$OBJECTS_JSON" | jq '. | length')

echo "Found $TOTAL_OBJECTS objects."

for (( i=0; i < TOTAL_OBJECTS; i++ )); do
  obj=$(echo "$OBJECTS_JSON" | jq -c ".[$i]")
  ID=$(echo "$obj" | jq -r '._id')
  NAME=$(echo "$obj" | jq -r '.name')

  OLD_NAME="$ID"
  NEW_NAME="$NAME"

  if [[ -n "$GCS_FOLDER" ]]; then
    OLD_NAME="${GCS_FOLDER}/${OLD_NAME}"
    NEW_NAME="${GCS_FOLDER}/${NEW_NAME}"
  fi

  echo "[$((i+1))/$TOTAL_OBJECTS] Copying gs://$BUCKET_NAME/$OLD_NAME to gs://$BUCKET_NAME/$NEW_NAME"
  if gcloud storage objects copy "gs://$BUCKET_NAME/$OLD_NAME" "gs://$BUCKET_NAME/$NEW_NAME"; then
    echo "Copy successful, deleting old object..."
    if gcloud storage objects delete "gs://$BUCKET_NAME/$OLD_NAME"; then
      echo "Deleted gs://$BUCKET_NAME/$OLD_NAME"
    else
      echo "Warning: failed to delete old object gs://$BUCKET_NAME/$OLD_NAME"
    fi
  else
    echo "Error: failed to copy gs://$BUCKET_NAME/$OLD_NAME, skipping deletion"
  fi
done

echo "Migration completed."

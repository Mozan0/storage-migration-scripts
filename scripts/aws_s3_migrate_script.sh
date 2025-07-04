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
CONCURRENCY=""

print_usage() {
  echo "Usage: $0 --api-url=URL --apikey=KEY --bucket=BUCKET_NAME --concurrency=N"
  exit 1
}

# Parse args
for ARG in "$@"; do
  case $ARG in
    --api-url=*) API_URL="${ARG#*=}" ;;
    --apikey=*) API_KEY="${ARG#*=}" ;;
    --bucket=*) BUCKET_NAME="${ARG#*=}" ;;
    --concurrency=*) CONCURRENCY="${ARG#*=}" ;;
    *) echo "Unknown option: $ARG"; print_usage ;;
  esac
done

if [[ -z "$API_URL" || -z "$API_KEY" || -z "$BUCKET_NAME" || -z "$CONCURRENCY" ]]; then
  echo "Missing required arguments."
  print_usage
fi

SKIP=0
LIMIT=$CONCURRENCY

while true; do
  echo "Fetching objects from $SKIP to $((SKIP + LIMIT - 1))..."

  OBJECTS=$(curl -sSL -H "Authorization: apikey $API_KEY" "$API_URL/storage?limit=$LIMIT&skip=$SKIP")

  COUNT=$(echo "$OBJECTS" | jq length)
  if [[ "$COUNT" == "0" ]]; then
    echo "No more objects to process."
    break
  fi

  for i in $(seq 0 $((COUNT - 1))); do
    (
      OBJECT=$(echo "$OBJECTS" | jq ".[$i]")
      [[ "$OBJECT" == "null" ]] && continue
      ID=$(echo "$OBJECT" | jq -r '._id')
      NAME=$(echo "$OBJECT" | jq -r '.name')

      OLD_NAME="$ID"
      NEW_NAME="$NAME"

      if aws s3 cp "s3://$BUCKET_NAME/$OLD_NAME" "s3://$BUCKET_NAME/$NEW_NAME"; then
        echo "Moved s3://$BUCKET_NAME/$OLD_NAME to s3://$BUCKET_NAME/$NEW_NAME"
        echo "removing old object s3://$BUCKET_NAME/$OLD_NAME"
        if ! aws s3 rm "s3://$BUCKET_NAME/$OLD_NAME"; then
          echo "Warning: failed to delete old object s3://$BUCKET_NAME/$OLD_NAME"
        fi
      else
        echo "Error: failed to copy s3://$BUCKET_NAME/$OLD_NAME, skipping deletion"
      fi

    ) &

    while (( $(jobs -r -p | wc -l) >= CONCURRENCY )); do
      sleep 1
    done
  done

  wait
  SKIP=$((SKIP + COUNT))
done

echo "Migration completed."

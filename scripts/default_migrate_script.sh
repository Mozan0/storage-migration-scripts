#!/bin/bash

# Check and install jq if missing
if ! command -v jq &>/dev/null; then
  echo "jq not found. Installing..."

  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if command -v apt-get &>/dev/null; then
      sudo apt-get update && sudo apt-get install -y jq
    elif command -v yum &>/dev/null; then
      sudo yum install -y jq
    else
      echo "Unsupported Linux package manager. Please install jq manually."
      exit 1
    fi

  elif [[ "$OSTYPE" == "darwin"* ]]; then
    if command -v brew &>/dev/null; then
      brew install jq
    else
      echo "Homebrew not found. Please install Homebrew or jq manually: https://stedolan.github.io/jq/download/"
      exit 1
    fi

  else
    echo "Unsupported OS. Please install jq manually: https://stedolan.github.io/jq/download/"
    exit 1
  fi
else
  echo "jq found."
fi

# Parse CLI arguments
for arg in "$@"; do
  case $arg in
    --api-url=*)
      API_URL="${arg#*=}"
      shift
      ;;
    --apikey=*)
      API_KEY="${arg#*=}"
      shift
      ;;
    --concurrency=*)
      CONCURRENCY="${arg#*=}"
      shift
      ;;
    --folder-name=*)
      FOLDER_NAME="${arg#*=}"
      shift
      ;;
    *)
      echo "Unknown argument: $arg"
      exit 1
      ;;
  esac
done

if [[ -z "$API_URL" || -z "$API_KEY" || -z "$CONCURRENCY" || -z "$FOLDER_NAME" ]]; then
  echo "Usage: $0 --api-url=URL --apikey=KEY --concurrency=N --folder-name=FOLDER"
  exit 1
fi

SKIP=0
LIMIT=$CONCURRENCY

while true; do
  echo "Fetching objects from $SKIP to $((SKIP + LIMIT - 1))..."
  OBJECTS=$(curl -s -H "Authorization: apikey $API_KEY" "$API_URL/storage?limit=$LIMIT&skip=$SKIP")

  count=$(echo "$OBJECTS" | jq length)
  if [[ "$count" == "0" ]]; then
    echo "No more objects to process."
    break
  fi

  for i in $(seq 0 $((count - 1))); do
    OBJECT=$(echo "$OBJECTS" | jq -r ".[$i]")
    [[ "$OBJECT" == "null" ]] && continue

    ID=$(echo "$OBJECT" | jq -r "._id")
    NAME=$(echo "$OBJECT" | jq -r ".name")

    OLD_PATH="${FOLDER_NAME}/${ID}.storageobj"
    NEW_PATH="${FOLDER_NAME}/${NAME}.storageobj"

    if [[ -f "$OLD_PATH" ]]; then
      echo "Renaming $OLD_PATH to $NEW_PATH"
      mv "$OLD_PATH" "$NEW_PATH"
    else
      echo "Skipping: $OLD_PATH not found"
    fi
  done
  SKIP=$((SKIP + count))
done

echo "Migration completed."

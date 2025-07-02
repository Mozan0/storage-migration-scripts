# Storage Migration Script

This script migrates file storage naming from `_id`-based to `name`-based naming.

## Usage

```bash
./scripts/migratescript.sh \
  --api-url="http://localhost:4300" \
  --apikey="real_apikey" \
  --concurrency=10 \
  --folder-name="/private/tmp/storage"

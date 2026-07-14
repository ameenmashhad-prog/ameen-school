#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <NEXT_FORMS_V3_URL>"
  echo "Example: $0 https://next-forms-v3.vercel.app"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_URL="${1%/}"
TEMPLATE_FILE="$ROOT_DIR/family-registration-v3-hard-switch.template.html"
LEGACY_FILE="$ROOT_DIR/family-registration.html"
PUBLIC_LEGACY_FILE="$ROOT_DIR/family-registration-legacy.html"
BACKUP_DIR="$ROOT_DIR/migration_backups"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="$BACKUP_DIR/family-registration.${TIMESTAMP}.legacy.html"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "Template not found: $TEMPLATE_FILE"
  exit 2
fi

if [[ ! -f "$LEGACY_FILE" ]]; then
  echo "Legacy file not found: $LEGACY_FILE"
  exit 3
fi

mkdir -p "$BACKUP_DIR"
cp "$LEGACY_FILE" "$BACKUP_FILE"
cp "$LEGACY_FILE" "$PUBLIC_LEGACY_FILE"

python3 - <<PY
from pathlib import Path
root = Path(r"$ROOT_DIR")
template = (root / 'family-registration-v3-hard-switch.template.html').read_text(encoding='utf-8')
output = template.replace('__NEXT_FORMS_V3_URL__', r'$TARGET_URL')
(root / 'family-registration.html').write_text(output, encoding='utf-8')
PY

echo "Hard switch applied successfully."
echo "Legacy backup saved to: $BACKUP_FILE"
echo "Public legacy copy saved to: $PUBLIC_LEGACY_FILE"
echo "family-registration.html now redirects to: $TARGET_URL/ar/forms/family-registration-v3"

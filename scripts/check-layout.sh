#!/usr/bin/env bash
# Run from repo root before committing.
# Verifies that the api-service app directory has the structure
# expected by the new Dockerfile and main.py.

set -euo pipefail

APP_DIR="app/api-service"
STATIC_DIR="$APP_DIR/static"

echo "== Checking $APP_DIR layout =="

for f in main.py Dockerfile requirements.txt; do
  if [ -f "$APP_DIR/$f" ]; then
    echo "  [OK]   $APP_DIR/$f"
  else
    echo "  [MISS] $APP_DIR/$f"
  fi
done

echo ""
echo "== Checking $STATIC_DIR (frontend assets) =="

# List of all required static files
FILES_TO_CHECK=(
  "ecommerce-storefront.html"
  "ecommerce-ops-center.html"
  "catalog.json"
  "theme.css"
  "storefront.css"
  "ops.css"
)

mkdir -p "$STATIC_DIR"

for f in "${FILES_TO_CHECK[@]}"; do
  if [ -f "$STATIC_DIR/$f" ]; then
    echo "  [OK]   $STATIC_DIR/$f"
  else
    echo "  [MISS] $STATIC_DIR/$f  <-- copy this in before building the image"
  fi
done

echo ""
echo "== Expected final tree =="
echo "$APP_DIR/"
echo "├── Dockerfile"
echo "├── main.py"
echo "├── requirements.txt"
echo "├── pytest.ini"
echo "├── tests/"
echo "└── static/"
echo "    ├── ecommerce-storefront.html  (served at /)"
echo "    ├── ecommerce-ops-center.html  (served at /ops)"
echo "    ├── catalog.json               (served at /api/products)"
echo "    ├── theme.css                  (shared tokens)"
echo "    ├── storefront.css             (storefront specific)"
echo "    └── ops.css                    (ops center specific)"
echo ""
echo "If any [MISS] lines appear above, copy the corresponding files into"
echo "$STATIC_DIR/ before running 'docker build'."
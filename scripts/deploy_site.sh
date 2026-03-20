#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_DIR="${SITE_DIR:-$ROOT_DIR/site}"
STAGING_DIR="${STAGING_DIR:-}"
PAGES_ENV="${PAGES_ENV:-prod}"
PAGES_SERVICE="${PAGES_SERVICE:-cloudflare-pages}"
PAGES_PROJECT_NAME="${PAGES_PROJECT_NAME:-overwatchr}"
PAGES_CUSTOM_DOMAIN="${PAGES_CUSTOM_DOMAIN:-overwatchr.dev}"
PAGES_ZONE_NAME="${PAGES_ZONE_NAME:-overwatchr.dev}"
PAGES_BRANCH="${PAGES_BRANCH:-main}"
PAGES_PRODUCTION_BRANCH="${PAGES_PRODUCTION_BRANCH:-main}"
APPROVE="${APPROVE:-1}"

if [[ ! -f "$SITE_DIR/index.html" ]]; then
  echo "error: expected static site at $SITE_DIR" >&2
  exit 1
fi

cleanup() {
  if [[ -n "${TEMP_STAGE_DIR:-}" && -d "$TEMP_STAGE_DIR" ]]; then
    rm -rf "$TEMP_STAGE_DIR"
  fi
}
trap cleanup EXIT

if [[ -z "$STAGING_DIR" ]]; then
  TEMP_STAGE_DIR="$(mktemp -d /tmp/overwatchr-pages.XXXXXX)"
  STAGING_DIR="$TEMP_STAGE_DIR"
fi

mkdir -p "$STAGING_DIR"
chmod 777 "$STAGING_DIR"
cp -R "$SITE_DIR"/. "$STAGING_DIR"/
mkdir -p "$STAGING_DIR/.wrangler/tmp"
chmod 777 "$STAGING_DIR/.wrangler" "$STAGING_DIR/.wrangler/tmp"

cmd=(
  privateinfractl pages
  --pages-env "$PAGES_ENV"
  --pages-service "$PAGES_SERVICE"
)

if [[ "$APPROVE" == "1" ]]; then
  cmd+=(--approve)
fi

cmd+=(
  --
  ensure-deploy "$STAGING_DIR"
  --project-name "$PAGES_PROJECT_NAME"
  --custom-domain "$PAGES_CUSTOM_DOMAIN"
  --zone-name "$PAGES_ZONE_NAME"
  --production-branch "$PAGES_PRODUCTION_BRANCH"
  --branch "$PAGES_BRANCH"
)

echo "+ ${cmd[*]}"
(
  cd "$STAGING_DIR"
  "${cmd[@]}"
)

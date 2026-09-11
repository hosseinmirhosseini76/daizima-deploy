#!/usr/bin/env bash
# Daizima Storefront — automatic release version bump (SemVer).
#
# Usage (from anywhere):
#   ./deploy/versioning/bump-frontend.sh
#   ./deploy/versioning/bump-frontend.sh --dry-run
#   ./deploy/versioning/bump-frontend.sh --patch --yes
#
# Reads git history since last v* tag, inspects status, updates:
#   - daizima-frontend-new/VERSION
#   - daizima-frontend-new/apps/storefront/package.json (version)
#   - daizima-frontend-new/.env.example (NUXT_PUBLIC_APP_VERSION=)
#   - daizima-frontend-new/apps/storefront/app/app.vue (const APP_VERSION)

set -euo pipefail

VERSIONING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$VERSIONING_DIR/lib.sh"

APP_LABEL="Daizima Storefront"
APP_SLUG="storefront"
APP_DIR="${MONOREPO_ROOT}/daizima-frontend-new"
GIT_PATHSPEC="apps/storefront VERSION .env.example"
VERSION_JSON_FILE="apps/storefront/package.json"
ENV_VERSION_KEY="NUXT_PUBLIC_APP_VERSION"
APP_VERSION_CONST_FILE="apps/storefront/app/app.vue"

run_bump_workflow "$@"

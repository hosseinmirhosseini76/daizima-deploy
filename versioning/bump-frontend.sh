#!/usr/bin/env bash
# Daizima Frontend — automatic release version bump (SemVer).
#
# Usage (from anywhere):
#   ./deploy/versioning/bump-frontend.sh
#   ./deploy/versioning/bump-frontend.sh --dry-run
#   ./deploy/versioning/bump-frontend.sh --patch --yes
#
# Reads git history since last v* tag, inspects status, updates:
#   - daizima-frontend/VERSION
#   - daizima-frontend/package.json (version)
#   - daizima-frontend/.env.example (NUXT_PUBLIC_APP_VERSION=)
#   - daizima-frontend/app/app.vue (const APP_VERSION)

set -euo pipefail

VERSIONING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$VERSIONING_DIR/lib.sh"

APP_LABEL="Daizima Frontend"
APP_SLUG="frontend"
APP_DIR="${MONOREPO_ROOT}/daizima-frontend"
VERSION_JSON_FILE="package.json"
ENV_VERSION_KEY="NUXT_PUBLIC_APP_VERSION"
APP_VERSION_CONST_FILE="app/app.vue"

run_bump_workflow "$@"

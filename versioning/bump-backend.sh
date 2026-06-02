#!/usr/bin/env bash
# Daizima Backend — automatic release version bump (SemVer).
#
# Usage (from anywhere):
#   ./deploy/versioning/bump-backend.sh
#   ./deploy/versioning/bump-backend.sh --dry-run
#   ./deploy/versioning/bump-backend.sh --minor --yes
#
# Reads git history since last v* tag, inspects status, updates:
#   - daizima-backend/VERSION
#   - daizima-backend/composer.json (version)
#   - daizima-backend/.env.example (APP_VERSION=)

set -euo pipefail

VERSIONING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$VERSIONING_DIR/lib.sh"

APP_LABEL="Daizima Backend"
APP_SLUG="backend"
APP_DIR="${MONOREPO_ROOT}/daizima-backend"
VERSION_JSON_FILE="composer.json"
ENV_VERSION_KEY="APP_VERSION"

run_bump_workflow "$@"

#!/usr/bin/env bash
# Shared helpers for Daizima release versioning (SemVer).
# Sourced by bump-backend.sh and bump-frontend.sh — do not run directly.

set -euo pipefail

VERSIONING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "$VERSIONING_DIR/.." && pwd)"
MONOREPO_ROOT="$(cd "$DEPLOY_ROOT/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[version]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[version]${NC} $*"; }
log_error() { echo -e "${RED}[version]${NC} $*" >&2; }
log_step()  { echo -e "${CYAN}[version]${NC} $*"; }

# Resolve APP_DIR to a stable absolute path (Git Bash / MSYS: /d/... avoids \b escapes in Node)
normalize_app_dir() {
  if [ -d "$APP_DIR" ]; then
    APP_DIR="$(cd "$APP_DIR" && pwd)"
  fi
}

# --- SemVer ---

semver_parse() {
  local v="${1#v}"
  if [[ ! "$v" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-([0-9A-Za-z.-]+))?(\+([0-9A-Za-z.-]+))?$ ]]; then
    log_error "Invalid SemVer: $1"
    return 1
  fi
  SEMVER_MAJOR="${BASH_REMATCH[1]}"
  SEMVER_MINOR="${BASH_REMATCH[2]}"
  SEMVER_PATCH="${BASH_REMATCH[3]}"
}

semver_bump() {
  local current="$1" level="$2"
  semver_parse "$current"
  case "$level" in
    major) SEMVER_MAJOR=$((SEMVER_MAJOR + 1)); SEMVER_MINOR=0; SEMVER_PATCH=0 ;;
    minor) SEMVER_MINOR=$((SEMVER_MINOR + 1)); SEMVER_PATCH=0 ;;
    patch) SEMVER_PATCH=$((SEMVER_PATCH + 1)) ;;
    *) log_error "Unknown bump level: $level"; return 1 ;;
  esac
  echo "${SEMVER_MAJOR}.${SEMVER_MINOR}.${SEMVER_PATCH}"
}

# --- Git ---

git_require_repo() {
  git -C "$APP_DIR" rev-parse --git-dir >/dev/null 2>&1 || {
    log_error "Not a git repository: $APP_DIR"
    exit 1
  }
}

git_status_report() {
  local porcelain
  porcelain="$(git -C "$APP_DIR" status --porcelain 2>/dev/null || true)"
  if [ -z "$porcelain" ]; then
    log_info "Git working tree: clean"
    GIT_DIRTY=false
    return 0
  fi
  GIT_DIRTY=true
  local staged unstaged untracked
  staged=$(echo "$porcelain" | grep -c '^[MARCD]' || true)
  unstaged=$(echo "$porcelain" | grep -c '^ [MARCD]' || true)
  untracked=$(echo "$porcelain" | grep -c '^??' || true)
  log_warn "Git working tree: dirty (staged≈$staged, unstaged≈$unstaged, untracked≈$untracked)"
  echo "$porcelain" | head -20
  local total
  total=$(echo "$porcelain" | wc -l | tr -d ' ')
  if [ "$total" -gt 20 ]; then
    log_warn "... and $((total - 20)) more files"
  fi
}

git_last_release_tag() {
  # Latest vX.Y.Z tag reachable from HEAD
  git -C "$APP_DIR" tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname 2>/dev/null | head -1
}

git_range_for_analysis() {
  LAST_TAG="$(git_last_release_tag)"
  if [ -n "$LAST_TAG" ]; then
    GIT_RANGE="${LAST_TAG}..HEAD"
    log_step "Changes since tag: $LAST_TAG"
  else
    GIT_RANGE="HEAD"
    log_warn "No v* tag found — analyzing entire branch history"
  fi
}

# Returns suggested level: major | minor | patch | none
analyze_bump_level() {
  local level="patch"
  local has_changes=false
  local commit_count=0

  if [ -n "${LAST_TAG:-}" ]; then
    if ! git -C "$APP_DIR" rev-parse "$LAST_TAG" >/dev/null 2>&1; then
      GIT_RANGE="HEAD"
    elif [ -z "$(git -C "$APP_DIR" log "$GIT_RANGE" --oneline 2>/dev/null)" ]; then
      echo "none"
      return 0
    fi
  fi

  local commits
  commits="$(git -C "$APP_DIR" log "$GIT_RANGE" --pretty=format:%s 2>/dev/null || true)"
  if [ -n "$commits" ]; then
    has_changes=true
    commit_count=$(echo "$commits" | grep -c . || echo 0)
  fi

  local diff_files
  if [ -n "${LAST_TAG:-}" ] && git -C "$APP_DIR" rev-parse "$LAST_TAG" >/dev/null 2>&1; then
    diff_files="$(git -C "$APP_DIR" diff --name-only "$LAST_TAG..HEAD" 2>/dev/null || true)"
  else
    diff_files="$(git -C "$APP_DIR" diff --name-only HEAD 2>/dev/null || true)"
  fi

  if [ -z "$commits" ] && [ -z "$diff_files" ] && [ "$GIT_DIRTY" != true ]; then
    echo "none"
    return 0
  fi

  # --- MAJOR signals ---
  if echo "$commits" | grep -qiE '(^|[[:space:]])BREAKING[[:space:]]CHANGE|BREAKING:'; then
    echo "major"
    return 0
  fi
  if echo "$commits" | grep -qE '^[a-zA-Z]+(\([^)]+\))?!:'; then
    echo "major"
    return 0
  fi
  local diff_range="HEAD"
  if [ -n "${LAST_TAG:-}" ] && git -C "$APP_DIR" rev-parse "$LAST_TAG" >/dev/null 2>&1; then
    diff_range="${LAST_TAG}..HEAD"
  fi

  if [ -n "$diff_files" ]; then
    if echo "$diff_files" | grep -qE 'database/migrations/.*\.php$'; then
      local migration_bodies
      migration_bodies="$(git -C "$APP_DIR" diff "$diff_range" -- 'database/migrations' 2>/dev/null || true)"
      if echo "$migration_bodies" | grep -qE 'dropTable|dropColumn|dropForeign|renameColumn'; then
        echo "major"
        return 0
      fi
    fi
    if echo "$diff_files" | grep -qE '^(\.env\.example|config/)' && echo "$commits" | grep -qiE 'breaking|major'; then
      echo "major"
      return 0
    fi
  fi

  # --- MINOR signals ---
  if echo "$commits" | grep -qE '^feat(\([^)]+\))?:'; then
    echo "minor"
    return 0
  fi
  if [ -n "$diff_files" ]; then
    if echo "$diff_files" | grep -qE '^database/migrations/[0-9]+.*\.php$'; then
      echo "minor"
      return 0
    fi
    # New significant modules (backend / frontend heuristics)
    if echo "$diff_files" | grep -qE '^app/(Http/Controllers|Services)/.*\.php$'; then
      local new_controllers
      new_controllers=$(echo "$diff_files" | while read -r f; do
        [ -n "${LAST_TAG:-}" ] && git -C "$APP_DIR" cat-file -e "${LAST_TAG}:$f" 2>/dev/null && continue
        echo "$f"
      done)
      if [ -n "$new_controllers" ]; then
        echo "minor"
        return 0
      fi
    fi
    if echo "$diff_files" | grep -qE '^app/pages/[^/]+/index\.vue$|^app/pages/[^/]+\.vue$'; then
      echo "minor"
      return 0
    fi
    local file_count
    file_count=$(echo "$diff_files" | grep -c . || echo 0)
    if [ "$file_count" -ge 20 ]; then
      echo "minor"
      return 0
    fi
  fi
  if [ "$commit_count" -ge 8 ] && [ "$has_changes" = true ]; then
    echo "minor"
    return 0
  fi

  # --- PATCH (fixes, chores, docs, small tweaks) ---
  if echo "$commits" | grep -qE '^(fix|hotfix|perf|refactor|docs|style|test|chore|build|ci)(\([^)]+\))?:'; then
    echo "patch"
    return 0
  fi

  if [ "$GIT_DIRTY" = true ] || [ -n "$diff_files" ] || [ -n "$commits" ]; then
    echo "patch"
    return 0
  fi

  echo "none"
}

read_version_from_files() {
  local v=""
  if [ -f "$APP_DIR/VERSION" ]; then
    v="$(tr -d ' \r\n' < "$APP_DIR/VERSION")"
  fi
  if [ -z "$v" ] && [ -n "$VERSION_JSON_FILE" ] && [ -f "$APP_DIR/$VERSION_JSON_FILE" ]; then
    if command -v php >/dev/null 2>&1; then
      v="$(APP_DIR="$APP_DIR" VERSION_JSON_FILE="$VERSION_JSON_FILE" php -r '
        $path = getenv("APP_DIR") . DIRECTORY_SEPARATOR . getenv("VERSION_JSON_FILE");
        $p = json_decode(file_get_contents($path), true);
        echo $p["version"] ?? "";
      ' 2>/dev/null || true)"
    elif command -v node >/dev/null 2>&1; then
      v="$(APP_DIR="$APP_DIR" VERSION_JSON_FILE="$VERSION_JSON_FILE" node -e "
        const fs = require('fs');
        const path = require('path');
        const file = path.join(process.env.APP_DIR, process.env.VERSION_JSON_FILE);
        const p = JSON.parse(fs.readFileSync(file, 'utf8'));
        console.log(p.version || '');
      " 2>/dev/null || true)"
    fi
  fi
  if [ -z "$v" ]; then
    v="0.1.0"
    log_warn "No version in files — starting from $v"
  fi
  echo "$v"
}

write_version_files() {
  local new_version="$1"
  echo "$new_version" > "$APP_DIR/VERSION"

  if [ -n "$VERSION_JSON_FILE" ] && [ -f "$APP_DIR/$VERSION_JSON_FILE" ]; then
    if command -v php >/dev/null 2>&1; then
      APP_DIR="$APP_DIR" VERSION_JSON_FILE="$VERSION_JSON_FILE" NEW_VERSION="$new_version" php -r '
        $path = getenv("APP_DIR") . DIRECTORY_SEPARATOR . getenv("VERSION_JSON_FILE");
        $data = json_decode(file_get_contents($path), true) ?: [];
        $data["version"] = getenv("NEW_VERSION");
        file_put_contents($path, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);
      '
    elif command -v node >/dev/null 2>&1; then
      APP_DIR="$APP_DIR" VERSION_JSON_FILE="$VERSION_JSON_FILE" NEW_VERSION="$new_version" node -e "
        const fs = require('fs');
        const path = require('path');
        const file = path.join(process.env.APP_DIR, process.env.VERSION_JSON_FILE);
        const data = JSON.parse(fs.readFileSync(file, 'utf8'));
        data.version = process.env.NEW_VERSION;
        fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
      "
    else
      log_error "Need php or node to update $VERSION_JSON_FILE"
      exit 1
    fi
  fi

  # Optional env example sync
  if [ -f "$APP_DIR/.env.example" ] && [ -n "$ENV_VERSION_KEY" ]; then
    if grep -q "^${ENV_VERSION_KEY}=" "$APP_DIR/.env.example" 2>/dev/null; then
      sed -i.bak "s/^${ENV_VERSION_KEY}=.*/${ENV_VERSION_KEY}=${new_version}/" "$APP_DIR/.env.example"
      rm -f "$APP_DIR/.env.example.bak"
    else
      echo "${ENV_VERSION_KEY}=${new_version}" >> "$APP_DIR/.env.example"
    fi
  fi
}

create_annotated_tag() {
  local tag="v${NEW_VERSION}"
  local msg="Release ${APP_LABEL} v${NEW_VERSION}"
  if [ -n "${LAST_TAG:-}" ]; then
    msg="${msg}

${APP_LABEL} release since ${LAST_TAG}."
  fi
  git -C "$APP_DIR" tag -a "$tag" -m "$msg"
  log_info "Created tag: $tag"
}

print_summary() {
  echo ""
  log_info "=== ${APP_LABEL} — Release version summary ==="
  echo "  App path:     $APP_DIR"
  echo "  Previous:     $CURRENT_VERSION"
  echo "  New version:  $NEW_VERSION"
  echo "  Bump level:   $BUMP_LEVEL (suggested: $SUGGESTED_LEVEL)"
  [ -n "${LAST_TAG:-}" ] && echo "  Since tag:    $LAST_TAG"
  echo ""
  if [ "$DRY_RUN" = true ]; then
    log_warn "Dry run — no files or tags were changed."
  else
    log_info "Updated: VERSION, $VERSION_JSON_FILE"
    [ "$CREATE_TAG" = true ] && log_info "Git tag: v${NEW_VERSION}"
    echo ""
    log_step "Suggested commit:"
    echo "  git add VERSION $VERSION_JSON_FILE .env.example"
    echo "  git commit -m \"chore(${APP_SLUG}): release v${NEW_VERSION}\""
    if [ "$CREATE_TAG" = true ]; then
      echo "  git push && git push origin v${NEW_VERSION}"
    fi
  fi
}

parse_bump_args() {
  DRY_RUN=false
  CREATE_TAG=true
  ALLOW_DIRTY=false
  FORCE_LEVEL=""
  AUTO_YES=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN=true ;;
      --no-tag) CREATE_TAG=false ;;
      --allow-dirty) ALLOW_DIRTY=true ;;
      --yes|-y) AUTO_YES=true ;;
      --major) FORCE_LEVEL=major ;;
      --minor) FORCE_LEVEL=minor ;;
      --patch) FORCE_LEVEL=patch ;;
      -h|--help) SHOW_HELP=true ;;
      *) log_error "Unknown option: $1"; exit 1 ;;
    esac
    shift
  done
}

run_bump_workflow() {
  parse_bump_args "$@"

  if [ "${SHOW_HELP:-false}" = true ]; then
    cat <<EOF
Usage: $0 [options]

Analyzes git status and commits since the last v* tag, suggests SemVer bump,
updates VERSION + manifest ($VERSION_JSON_FILE), optionally creates git tag.

Options:
  --dry-run       Show analysis only, do not write files or tags
  --no-tag        Update version files without creating a git tag
  --allow-dirty   Allow bump with uncommitted changes (tag still requires clean tree)
  --yes, -y       Skip confirmation prompt
  --major         Force MAJOR bump
  --minor         Force MINOR bump
  --patch         Force PATCH bump
  -h, --help      This help

SemVer rules (automatic):
  MAJOR  BREAKING commits, feat!/fix!, destructive migrations
  MINOR  feat:, new migrations, new pages/controllers, large diffs (20+ files)
  PATCH  fix:, chore:, docs:, small changes
EOF
    exit 0
  fi

  normalize_app_dir
  git_require_repo
  GIT_DIRTY=false
  git_status_report

  if [ "$GIT_DIRTY" = true ] && [ "$ALLOW_DIRTY" != true ] && [ "$DRY_RUN" != true ]; then
    log_error "Working tree is dirty. Commit/stash first, or pass --allow-dirty"
    exit 1
  fi

  CURRENT_VERSION="$(read_version_from_files)"
  semver_parse "$CURRENT_VERSION" || semver_parse "0.1.0"
  CURRENT_VERSION="${SEMVER_MAJOR}.${SEMVER_MINOR}.${SEMVER_PATCH}"

  git_range_for_analysis
  SUGGESTED_LEVEL="$(analyze_bump_level)"

  if [ "$SUGGESTED_LEVEL" = "none" ] && [ "$GIT_DIRTY" != true ]; then
    log_info "No changes since last release — version stays at $CURRENT_VERSION"
    exit 0
  fi

  if [ -n "$FORCE_LEVEL" ]; then
    BUMP_LEVEL="$FORCE_LEVEL"
    log_step "Forced bump: $BUMP_LEVEL"
  else
    BUMP_LEVEL="$SUGGESTED_LEVEL"
    [ "$BUMP_LEVEL" = "none" ] && BUMP_LEVEL="patch"
    log_step "Suggested bump from git analysis: $BUMP_LEVEL"
  fi

  NEW_VERSION="$(semver_bump "$CURRENT_VERSION" "$BUMP_LEVEL")"

  if [ "$AUTO_YES" != true ] && [ "$DRY_RUN" != true ]; then
    echo ""
    read -r -p "Apply ${CURRENT_VERSION} → ${NEW_VERSION} (${BUMP_LEVEL})? [y/N] " confirm
    case "$confirm" in
      y|Y|yes|YES) ;;
      *) log_warn "Cancelled."; exit 0 ;;
    esac
  fi

  if [ "$DRY_RUN" = true ]; then
    print_summary
    exit 0
  fi

  write_version_files "$NEW_VERSION"

  if [ "$CREATE_TAG" = true ]; then
    if [ "$GIT_DIRTY" = true ]; then
      log_warn "Skipping git tag (dirty tree). Commit first, then: git tag -a v${NEW_VERSION}"
    else
      if git -C "$APP_DIR" rev-parse "v${NEW_VERSION}" >/dev/null 2>&1; then
        log_error "Tag v${NEW_VERSION} already exists"
        exit 1
      fi
      create_annotated_tag
    fi
  fi

  print_summary
}

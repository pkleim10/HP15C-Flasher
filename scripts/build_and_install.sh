#!/bin/bash
# Build HP 15C Flasher and install it to /Applications.
#
# Default: Release build, auto-bumps CURRENT_PROJECT_VERSION in the Xcode project.
# Does not create a DMG — use scripts/package_dmg.sh for a release.
#
# Flags:
#   --debug            Build Debug configuration instead of Release.
#   --no-bump          Skip the build-number bump (useful for quick retries).
#   --no-install       Build only; don't copy to /Applications.

set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=version.sh
source "${ROOT}/scripts/version.sh"

CONFIG="Release"
BUMP=1
INSTALL=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) CONFIG="Debug"; shift ;;
    --no-bump) BUMP=0; shift ;;
    --no-install) INSTALL=0; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [[ $BUMP -eq 1 ]]; then
  CURRENT_BUILD="$(read_build)"
  NEW_BUILD="$(bump_build)"
  echo "Bumped build: ${CURRENT_BUILD} -> ${NEW_BUILD}"
else
  NEW_BUILD="$(read_build)"
  echo "Build (no bump): ${NEW_BUILD}"
fi

MARKETING="$(read_marketing)"
echo "Version: ${MARKETING} (${NEW_BUILD}) [${CONFIG}]"

mkdir -p "$DERIVED"
exclude_derived_data_from_spotlight

SIGN_ARGS=()
if [[ "$CONFIG" == "Release" ]]; then
  IDENTITY="$(detect_identity || true)"
  if [[ -n "$IDENTITY" ]]; then
    TEAM_ID="$(printf '%s\n' "$IDENTITY" | sed -n 's/.*(\([^)]*\)).*/\1/p')"
    echo "Signing identity: ${IDENTITY}"
    SIGN_ARGS=(
      CODE_SIGN_IDENTITY="$IDENTITY"
      CODE_SIGN_STYLE=Manual
      CODE_SIGNING_ALLOWED=YES
    )
    if [[ -n "$TEAM_ID" ]]; then
      SIGN_ARGS+=(DEVELOPMENT_TEAM="$TEAM_ID")
    fi
  else
    echo "warning: no Developer ID; ad-hoc signing this Release build" >&2
    SIGN_ARGS=(
      CODE_SIGN_IDENTITY=-
      CODE_SIGN_STYLE=Automatic
      CODE_SIGNING_ALLOWED=YES
    )
  fi
fi

BUILD_LOG=$(mktemp -t hp15c-build.XXXXXX)
trap 'rm -f "$BUILD_LOG"' EXIT

echo "Building (${CONFIG})... (log: ${BUILD_LOG})"
set +e
if [[ ${#SIGN_ARGS[@]} -gt 0 ]]; then
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    "${SIGN_ARGS[@]}" \
    build >"$BUILD_LOG" 2>&1
else
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    build >"$BUILD_LOG" 2>&1
fi
BUILD_STATUS=$?
set -e

if [[ $BUILD_STATUS -ne 0 ]]; then
  echo "BUILD FAILED (exit ${BUILD_STATUS}). Last 40 lines:" >&2
  tail -40 "$BUILD_LOG" >&2
  exit $BUILD_STATUS
fi

APP_PATH="$(built_app_path "$CONFIG")"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at expected path: $APP_PATH" >&2
  exit 1
fi

echo "Built: ${APP_PATH}"

if [[ $INSTALL -eq 1 ]]; then
  install_to_applications "$APP_PATH"
fi

announce "$MARKETING" "$NEW_BUILD" "$CONFIG"

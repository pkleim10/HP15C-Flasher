#!/bin/bash
# Build a Developer ID–signed, notarized, stapled DMG for machiilabs.com.
#
# This is the release path. Day-to-day builds use scripts/build_and_install.sh
# (no DMG).
#
# Prerequisites:
#   - Developer ID Application identity in the keychain
#   - notarytool keychain profile (default: SkagwayNotary, same Developer ID team)
#       xcrun notarytool store-credentials "SkagwayNotary" \
#         --apple-id "…" --team-id "99DA5P7M35" --password "app-specific-password"
#
# Flags:
#   --no-bump          Skip the build-number bump
#   --skip-notarize    Build + sign DMG only (no notarytool / stapler)
#   --no-install       Don't copy the app to /Applications
#   --notary-profile NAME   Keychain profile (default: notarytool-profile)

set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=version.sh
source "${ROOT}/scripts/version.sh"

BUMP=1
NOTARIZE=1
INSTALL=1
NOTARY_PROFILE="${NOTARYTOOL_PROFILE:-SkagwayNotary}"
ENTITLEMENTS="${ROOT}/App/HP15CFlasher.entitlements"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-bump) BUMP=0; shift ;;
    --skip-notarize) NOTARIZE=0; shift ;;
    --no-install) INSTALL=0; shift ;;
    --notary-profile)
      NOTARY_PROFILE="${2:?--notary-profile requires a name}"
      shift 2
      ;;
    *)
      echo "Unknown flag: $1" >&2
      exit 1
      ;;
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
echo "Packaging ${APP_NAME} ${MARKETING} (${NEW_BUILD})"

IDENTITY="$(detect_identity || true)"
if [[ -z "$IDENTITY" ]]; then
  echo "No Developer ID Application identity found. Create one in Xcode → Settings → Accounts → Manage Certificates." >&2
  exit 1
fi
TEAM_ID="$(printf '%s\n' "$IDENTITY" | sed -n 's/.*(\([^)]*\)).*/\1/p')"
echo "Signing identity: ${IDENTITY}"

DIST_DIR="${ROOT}/dist"
STAGE_DIR="$(mktemp -d /private/tmp/hp15c-flasher.XXXXXX)"
VERSIONED_DMG="${DIST_DIR}/15CEFlasher-${MARKETING}-${NEW_BUILD}.dmg"
BUILD_LOG=$(mktemp -t hp15c-package.XXXXXX)

cleanup() {
  rm -f "$BUILD_LOG"
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

mkdir -p "$DIST_DIR" "$DERIVED"
exclude_derived_data_from_spotlight

echo "Building Release (universal, Developer ID + hardened runtime)... (log: ${BUILD_LOG})"
set +e
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=YES \
  ${TEAM_ID:+DEVELOPMENT_TEAM="$TEAM_ID"} \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  build >"$BUILD_LOG" 2>&1
BUILD_STATUS=$?
set -e

if [[ $BUILD_STATUS -ne 0 ]]; then
  echo "BUILD FAILED (exit ${BUILD_STATUS}). Last 60 lines:" >&2
  tail -60 "$BUILD_LOG" >&2
  exit $BUILD_STATUS
fi

APP_PATH="$(built_app_path Release)"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at expected path: $APP_PATH" >&2
  exit 1
fi

echo "Signing ${FULL_PRODUCT_NAME}…"
xattr -cr "$APP_PATH"
codesign --force --deep --timestamp --options runtime \
  --sign "$IDENTITY" \
  --entitlements "$ENTITLEMENTS" \
  "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

mkdir -p "$STAGE_DIR"
ditto "$APP_PATH" "${STAGE_DIR}/${FULL_PRODUCT_NAME}"
ln -s /Applications "${STAGE_DIR}/Applications"

if [[ $INSTALL -eq 1 ]]; then
  install_to_applications "$APP_PATH"
fi

echo "Creating DMG…"
rm -f "$VERSIONED_DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$VERSIONED_DMG"

echo "Signing DMG…"
codesign --force --timestamp --sign "$IDENTITY" "$VERSIONED_DMG"

if [[ $NOTARIZE -eq 1 ]]; then
  echo "Submitting to Apple notary service (profile: ${NOTARY_PROFILE})…"
  xcrun notarytool submit "$VERSIONED_DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  echo "Stapling notarization ticket…"
  xcrun stapler staple "$VERSIONED_DMG"
  xcrun stapler validate "$VERSIONED_DMG"
else
  echo "Skipping notarization (--skip-notarize)."
fi

shasum -a 256 "$VERSIONED_DMG" | tee "${VERSIONED_DMG}.sha256"

announce "$MARKETING" "$NEW_BUILD" "Release"
echo "  ${VERSIONED_DMG}"
if [[ $NOTARIZE -eq 1 ]]; then
  echo "  Notarized + stapled (Gatekeeper-ready)."
else
  echo "  Signed DMG only — run without --skip-notarize for public distribution."
fi

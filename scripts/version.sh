#!/bin/bash
# Shared version helpers for 15CE Flasher (sourced, not executed).

PBXPROJ="${ROOT}/HP15CFlasher.xcodeproj/project.pbxproj"
APP_NAME="15CE Flasher"
FULL_PRODUCT_NAME="${APP_NAME}.app"
BUNDLE_ID="com.machiilabs.HP15CFlasher"
SCHEME="HP15CFlasher"
PROJECT="HP15CFlasher.xcodeproj"
DERIVED="${ROOT}/build/DerivedData"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

bundle_id_of() {
  defaults read "${1}/Contents/Info" CFBundleIdentifier 2>/dev/null || true
}

exclude_derived_data_from_spotlight() {
  mkdir -p "$DERIVED"
  touch "${ROOT}/build/.metadata_never_index" "${DERIVED}/.metadata_never_index"
}

is_our_extra_app() {
  local app=$1 dest=$2
  local id base
  [[ "$app" == "$dest" ]] && return 1
  base=$(basename "$app")
  [[ "$base" == "${FULL_PRODUCT_NAME}.pre-update."* ]] && return 0
  case "$app" in
    "${DERIVED}"/*/"${FULL_PRODUCT_NAME}") return 0 ;;
    */DerivedData/HP15CFlasher-*/Build/Products/*/"${FULL_PRODUCT_NAME}") return 0 ;;
  esac
  id="$(bundle_id_of "$app")"
  [[ "$id" == "$BUNDLE_ID" ]]
}

# Extra copies of THIS app (DerivedData / numbered /Applications copies) become
# extra Launcher icons. Only delete bundles we can prove are ours.
forget_non_canonical_apps() {
  local dest=$1
  local keep=${2:-}
  local app tmp

  exclude_derived_data_from_spotlight

  tmp=$(mktemp)
  {
    mdfind "kMDItemCFBundleIdentifier == '${BUNDLE_ID}'" 2>/dev/null || true
    if [[ -x "$LSREGISTER" ]]; then
      "$LSREGISTER" -dump 2>/dev/null | awk -v id="$BUNDLE_ID" '
        BEGIN { RS="--------------------------------------------------------------------------------" }
        index($0, id) {
          n = split($0, lines, "\n")
          for (i = 1; i <= n; i++) {
            if (lines[i] ~ /^path:/) {
              p = lines[i]
              sub(/^path:[ \t]+/, "", p)
              sub(/[ \t]+\([^)]+\)[ \t]*$/, "", p)
              print p
            }
          }
        }
      '
    fi
    printf '%s\n' \
      "${DERIVED}/Build/Products/Debug/${FULL_PRODUCT_NAME}" \
      "${DERIVED}/Build/Products/Release/${FULL_PRODUCT_NAME}"
    for dir in /Applications "${HOME}/Applications"; do
      [[ -d "$dir" ]] || continue
      find "$dir" -maxdepth 1 \( -name "${FULL_PRODUCT_NAME}" -o -name "${FULL_PRODUCT_NAME} *.app" -o -name "${FULL_PRODUCT_NAME}.pre-update.*" \) -print 2>/dev/null || true
    done
  } | awk 'NF && $0 !~ /^\/$/' | sort -u >"$tmp"

  while IFS= read -r app; do
    [[ -z "$app" || "$app" == "$dest" || "$app" == "$keep" ]] && continue
    if [[ -d "$app" ]] && is_our_extra_app "$app" "$dest"; then
      echo "Removing extra copy: ${app}"
      if [[ "$app" =~ (/.*/DerivedData/HP15CFlasher-[^/]+) ]]; then
        touch "${BASH_REMATCH[1]}/.metadata_never_index" 2>/dev/null || true
      fi
      if [[ -x "$LSREGISTER" ]]; then
        "$LSREGISTER" -u "$app" >/dev/null 2>&1 || true
      fi
      rm -rf "$app" || true
    elif [[ -x "$LSREGISTER" ]] && is_our_extra_app "$app" "$dest"; then
      "$LSREGISTER" -u "$app" >/dev/null 2>&1 || true
    fi
  done <"$tmp"
  rm -f "$tmp"

  if [[ -x "$LSREGISTER" && -d "$dest" ]]; then
    "$LSREGISTER" -f "$dest" >/dev/null 2>&1 || true
  fi
}

read_marketing() {
  awk '/MARKETING_VERSION = / { gsub(/[";]/, "", $3); print $3; exit }' "$PBXPROJ"
}

read_build() {
  awk '/CURRENT_PROJECT_VERSION = / { gsub(/;/, "", $3); print $3; exit }' "$PBXPROJ"
}

bump_build() {
  local current new
  current="$(read_build)"
  if [[ -z "$current" || ! "$current" =~ ^[0-9]+$ ]]; then
    echo "Could not find CURRENT_PROJECT_VERSION in $PBXPROJ" >&2
    exit 1
  fi
  new=$((current + 1))
  sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\1${new};/" "$PBXPROJ"
  echo "$new"
}

announce() {
  local marketing=$1 build=$2 config=$3
  echo ""
  echo "✓ ${APP_NAME} ${marketing} (${build}) [${config}]"
}

built_app_path() {
  local config=$1
  local settings products
  settings=$(xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$config" \
    -derivedDataPath "$DERIVED" \
    -showBuildSettings 2>/dev/null)
  products=$(printf '%s\n' "$settings" | awk -F' = ' '/ BUILT_PRODUCTS_DIR / { print $2; exit }')
  printf '%s/%s\n' "$products" "$FULL_PRODUCT_NAME"
}

install_to_applications() {
  local app_path=$1
  local dest="/Applications/${FULL_PRODUCT_NAME}"
  local install_ok=0 aside

  if [[ -d "$dest" ]]; then
    if touch "${dest}/Contents/.hp15c_install_probe" 2>/dev/null; then
      rm -f "${dest}/Contents/.hp15c_install_probe"
      if rsync -a --delete "${app_path}/" "${dest}/"; then
        install_ok=1
      fi
    fi
  else
    ditto "$app_path" "$dest"
    install_ok=1
  fi

  if [[ $install_ok -eq 0 ]]; then
    aside="${dest}.pre-update.$$"
    rm -rf "$aside"
    echo "In-place update blocked (likely TCC macl on the existing app) — replacing via rename…"
    mv "$dest" "$aside"
    ditto "$app_path" "$dest"
    rm -rf "$aside"
  fi

  echo "Installed: ${dest}"

  forget_non_canonical_apps "$dest"
  mdimport "$dest" >/dev/null 2>&1 || true
}

detect_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$CODESIGN_IDENTITY"
    return
  fi
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }'
}

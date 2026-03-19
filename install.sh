#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Overwatchr.app"
REPO_SLUG="${REPO_SLUG:-atiti/overwatchr}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
INSTALL_APP="${INSTALL_APP:-1}"
INSTALL_HOOKS="${INSTALL_HOOKS:-0}"
HOOK_SCOPE="${HOOK_SCOPE:-user}"
VERSION="${VERSION:-latest}"

SCRIPT_PATH="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""
if [[ -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
fi

choose_prefix() {
  if [[ -n "${PREFIX:-}" ]]; then
    printf '%s\n' "$PREFIX"
    return
  fi

  if [[ -d /usr/local/bin && -w /usr/local/bin ]] || { [[ ! -e /usr/local/bin ]] && mkdir -p /usr/local/bin 2>/dev/null; }; then
    printf '%s\n' "/usr/local/bin"
  else
    printf '%s\n' "$HOME/.local/bin"
  fi
}

choose_app_destination() {
  if [[ -n "${APP_DESTINATION:-}" ]]; then
    printf '%s\n' "$APP_DESTINATION"
    return
  fi

  if [[ -d /Applications && -w /Applications ]] || { [[ ! -e /Applications ]] && mkdir -p /Applications 2>/dev/null; }; then
    printf '%s\n' "/Applications"
  else
    printf '%s\n' "$HOME/Applications"
  fi
}

PREFIX="$(choose_prefix)"
APP_DESTINATION="$(choose_app_destination)"

ensure_directory() {
  mkdir -p "$1"
}

note_path_if_needed() {
  case ":$PATH:" in
    *":$PREFIX:"*) ;;
    *)
      echo
      echo "Add $PREFIX to your PATH to use the overwatchr CLI everywhere."
      ;;
  esac
}

install_hooks_if_requested() {
  if [[ "$INSTALL_HOOKS" != "1" ]]; then
    return
  fi

  echo
  echo "Installing user-facing hook integrations ($HOOK_SCOPE)..."
  "$PREFIX/overwatchr" hooks install all --scope "$HOOK_SCOPE"
}

install_cli_binary() {
  local source_binary="$1"
  ensure_directory "$PREFIX"
  install -m 755 "$source_binary" "$PREFIX/overwatchr"
  echo "CLI ready at $PREFIX/overwatchr"
}

install_app_bundle() {
  local source_bundle="$1"
  ensure_directory "$APP_DESTINATION"
  rm -rf "$APP_DESTINATION/$APP_NAME"
  ditto "$source_bundle" "$APP_DESTINATION/$APP_NAME"
  echo "Menu bar app ready at $APP_DESTINATION/$APP_NAME"
}

release_api_url() {
  if [[ "$VERSION" == "latest" ]]; then
    printf 'https://api.github.com/repos/%s/releases/latest\n' "$REPO_SLUG"
  else
    printf 'https://api.github.com/repos/%s/releases/tags/v%s\n' "$REPO_SLUG" "$VERSION"
  fi
}

fetch_release_asset_url() {
  local suffix="$1"
  local release_json
  release_json="$(curl -fsSL "$(release_api_url)")"

  /usr/bin/python3 - "$suffix" <<'PY' <<<"$release_json"
import json
import sys

suffix = sys.argv[1]
release = json.load(sys.stdin)
for asset in release.get("assets", []):
    name = asset.get("name", "")
    if name.endswith(suffix):
        print(asset["browser_download_url"])
        raise SystemExit(0)

raise SystemExit(f"Could not find release asset ending with {suffix}")
PY
}

install_from_release() {
  local temp_dir
  temp_dir="$(mktemp -d /tmp/overwatchr-install.XXXXXX)"
  trap 'rm -rf "$temp_dir"' EXIT

  local cli_url
  cli_url="$(fetch_release_asset_url "-macos-cli.zip")"

  echo "Downloading latest overwatchr CLI release..."
  curl -fsSL "$cli_url" -o "$temp_dir/cli.zip"
  ditto -x -k "$temp_dir/cli.zip" "$temp_dir/cli"
  install_cli_binary "$temp_dir/cli/release/overwatchr"

  if [[ "$INSTALL_APP" == "1" ]]; then
    local app_url
    app_url="$(fetch_release_asset_url "-macos-app.zip")"
    echo "Downloading latest overwatchr app release..."
    curl -fsSL "$app_url" -o "$temp_dir/app.zip"
    ditto -x -k "$temp_dir/app.zip" "$temp_dir/app"
    install_app_bundle "$temp_dir/app/$APP_NAME"
  fi
}

install_from_source() {
  local root_dir="$1"
  local dist_dir="${DIST_DIR:-$root_dir/dist}"

  echo "Building overwatchr ($BUILD_CONFIGURATION)..."
  swift build -c "$BUILD_CONFIGURATION" --package-path "$root_dir"

  install_cli_binary "$root_dir/.build/$BUILD_CONFIGURATION/overwatchr"

  if [[ "$INSTALL_APP" == "1" ]]; then
    BUILD_CONFIGURATION="$BUILD_CONFIGURATION" CREATE_ARCHIVE=0 DIST_DIR="$dist_dir" "$root_dir/scripts/build_app_bundle.sh"
    install_app_bundle "$dist_dir/$APP_NAME"
  fi
}

if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/Package.swift" && -d "$SCRIPT_DIR/scripts" ]]; then
  install_from_source "$SCRIPT_DIR"
else
  install_from_release
fi

note_path_if_needed
install_hooks_if_requested
echo
echo "Done. Your terminal agents now have a lookout."
echo "Next:"
echo "  1. Launch Overwatchr.app"
echo "  2. Grant Accessibility access"
if [[ "$INSTALL_HOOKS" != "1" ]]; then
  echo "  3. Run: overwatchr hooks install all --scope user"
fi

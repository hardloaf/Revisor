#!/usr/bin/env bash
set -euo pipefail

PREFIX="${1:-$HOME/Library/Application Scripts/com.apple.mail}"
TARGET="${2:-FilterSecurityCamera}"
GIT_VERSION="${3:-unknown}"

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_SCRIPT="$REPO_DIR/FilterSecurityCamera.applescript"
WORKER_SCRIPT="$REPO_DIR/FilterSecurityCameraWorker.sh"
BINARY="$REPO_DIR/$TARGET"
BUNDLE_DIR="$PREFIX/Revisor.scptd"
RES_DIR="$BUNDLE_DIR/Contents/Resources"
SCRIPTS_DIR="$RES_DIR/Scripts"

mkdir -p "$(dirname "$BUNDLE_DIR")"

if command -v osacompile >/dev/null 2>&1; then
  tmpdir=$(mktemp -d)
  echo "Compiling $SRC_SCRIPT into $tmpdir/Revisor.scptd"
  osacompile -o "$tmpdir/Revisor.scptd" "$SRC_SCRIPT"
  rm -rf "$BUNDLE_DIR"
  mv "$tmpdir/Revisor.scptd" "$BUNDLE_DIR"
  # Normalize location
  if [ -f "$BUNDLE_DIR/Contents/Resources/main.scpt" ]; then
    mkdir -p "$SCRIPTS_DIR"
    mv "$BUNDLE_DIR/Contents/Resources/main.scpt" "$SCRIPTS_DIR/main.scpt"
  fi
else
  echo "osacompile not found; assembling bundle manually in $PREFIX"
  mkdir -p "$SCRIPTS_DIR"
  cp "$SRC_SCRIPT" "$SCRIPTS_DIR/main.scpt"
  mkdir -p "$RES_DIR"
  rm -rf "$BUNDLE_DIR"
  mkdir -p "$BUNDLE_DIR/Contents/Resources"
fi

# Copy binary and worker script into Resources
if [ -f "$BINARY" ]; then
  install -m 755 "$BINARY" "$RES_DIR/$TARGET"
else
  echo "Warning: binary $BINARY not found; build first"
fi

if [ -f "$WORKER_SCRIPT" ]; then
  install -m 755 "$WORKER_SCRIPT" "$RES_DIR/$(basename "$WORKER_SCRIPT")"
fi

# Ensure Info.plist exists
PLIST="$BUNDLE_DIR/Contents/Info.plist"
if [ ! -f "$PLIST" ]; then
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<INFOPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.andrey.revisor</string>
  <key>CFBundleName</key>
  <string>Revisor</string>
  <key>CFBundleVersion</key>
  <string>$GIT_VERSION</string>
  <key>CFBundleShortVersionString</key>
  <string>$GIT_VERSION</string>
</dict>
</plist>
INFOPLIST
fi

# If PlistBuddy is available, set version fields
if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $GIT_VERSION" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $GIT_VERSION" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $GIT_VERSION" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $GIT_VERSION" "$PLIST"
fi

echo "Installed bundle to $BUNDLE_DIR"

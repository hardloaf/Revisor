# Compiler settings
SWIFTC = swiftc
# -O enables compiler optimizations for speed
FLAGS = -O -whole-module-optimization

# File names
TARGET = FilterSecurityCamera
SRC = classify_image.swift
VERSION_FILE = Version.swift

# Install path (user's Application Scripts directory for Mail). Quoted when used to handle spaces.
PREFIX := $(HOME)/Library/Application Scripts/com.apple.mail

# Extract the Git version (e.g., v1.0-4-g9a8b7c or just the short hash if no tags exist)
# If the directory isn't a git repo, it defaults to "unknown"
GIT_VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "unknown")

.PHONY: all build clean install uninstall

all: build

# Generate a temporary Swift file containing the Git version string
$(VERSION_FILE):
@echo "Injecting version: $(GIT_VERSION)"
@echo 'let appVersion = "$(GIT_VERSION)"' > $(VERSION_FILE)

# Compile the main script and the temporary version file together
build: $(VERSION_FILE)
$(SWIFTC) $(FLAGS) $(SRC) $(VERSION_FILE) -o $(TARGET)
@rm -f $(VERSION_FILE) # Clean up the temp file immediately after building

clean:
rm -f $(TARGET) $(VERSION_FILE)

# Install builds the binary and produces a proper Revisor.scptd script bundle
# using osacompile -o when available. The compiled bundle is installed into the
# Mail Application Scripts directory and includes the compiled main script under
# Contents/Resources/Scripts/main.scpt and other helper resources in Contents/Resources.
install: build
@echo "Installing Revisor.scptd bundle to $(PREFIX)"
@mkdir -p "$(PREFIX)"
# If osacompile is available, compile the AppleScript source into a .scptd bundle
if command -v osacompile >/dev/null 2>&1; then \
tempdir=$$(mktemp -d); \
echo "Compiling FilterSecurityCamera.applescript into $$tempdir/Revisor.scptd"; \
osacompile -o "$$tempdir/Revisor.scptd" "FilterSecurityCamera.applescript" || { echo "osacompile failed"; rm -rf "$$tempdir"; exit 1; }; \
# Remove any previous install and move the compiled bundle into place
rm -rf "$(PREFIX)/Revisor.scptd"; \
mv "$$tempdir/Revisor.scptd" "$(PREFIX)/Revisor.scptd"; \
# Normalize script location: some osacompile versions place the compiled script
# at Contents/Resources/main.scpt; ensure it's under Resources/Scripts/main.scpt
if [ -f "$(PREFIX)/Revisor.scptd/Contents/Resources/main.scpt" ]; then \
mkdir -p "$(PREFIX)/Revisor.scptd/Contents/Resources/Scripts"; \
mv "$(PREFIX)/Revisor.scptd/Contents/Resources/main.scpt" "$(PREFIX)/Revisor.scptd/Contents/Resources/Scripts/main.scpt"; \
fi; \
# Copy the compiled binary and worker into the bundle Resources
install -m 755 "$(TARGET)" "$(PREFIX)/Revisor.scptd/Contents/Resources/FilterSecurityCamera"; \
if [ -f "FilterSecurityCameraWorker.sh" ]; then \
install -m 755 "FilterSecurityCameraWorker.sh" "$(PREFIX)/Revisor.scptd/Contents/Resources/FilterSecurityCameraWorker.sh"; \
fi; \
# Ensure Info.plist has version keys set; prefer PlistBuddy if available
plist="$(PREFIX)/Revisor.scptd/Contents/Info.plist"; \
if [ -f "$$plist" ]; then \
if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then \
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $(GIT_VERSION)" "$$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(GIT_VERSION)" "$$plist"; \
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $(GIT_VERSION)" "$$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(GIT_VERSION)" "$$plist"; \
else \
echo "PlistBuddy not found; writing minimal Info.plist (may overwrite keys)"; \
cat > "$$plist" <<EOFpl
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>CFBundleIdentifier</key>
<string>com.andrey.revisor</string>
<key>CFBundleName</key>
<string>Revisor</string>
<key>CFBundleVersion</key>
<string>$(GIT_VERSION)</string>
<key>CFBundleShortVersionString</key>
<string>$(GIT_VERSION)</string>
</dict>
</plist>
EOFpl
; \
fi; \
else \
# Create minimal Info.plist
mkdir -p "$(PREFIX)/Revisor.scptd/Contents"; \
cat > "$(PREFIX)/Revisor.scptd/Contents/Info.plist" <<EOFpl
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>CFBundleIdentifier</key>
<string>com.andrey.revisor</string>
<key>CFBundleName</key>
<string>Revisor</string>
<key>CFBundleVersion</key>
<string>$(GIT_VERSION)</string>
<key>CFBundleShortVersionString</key>
<string>$(GIT_VERSION)</string>
</dict>
</plist>
EOFpl
; \
fi; \
rm -rf "$$tempdir"; \
else \
# Fallback: assemble bundle manually (no compiled script)
echo "osacompile not found; assembling bundle manually in $(PREFIX)"; \
mkdir -p "$(PREFIX)/Revisor.scptd/Contents/Resources/Scripts"; \
install -m 644 "FilterSecurityCamera.applescript" "$(PREFIX)/Revisor.scptd/Contents/Resources/Scripts/main.scpt"; \
install -m 755 "$(TARGET)" "$(PREFIX)/Revisor.scptd/Contents/Resources/FilterSecurityCamera"; \
if [ -f "FilterSecurityCameraWorker.sh" ]; then install -m 755 "FilterSecurityCameraWorker.sh" "$(PREFIX)/Revisor.scptd/Contents/Resources/FilterSecurityCameraWorker.sh"; fi; \
cat > "$(PREFIX)/Revisor.scptd/Contents/Info.plist" <<EOFpl
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>CFBundleIdentifier</key>
<string>com.andrey.revisor</string>
<key>CFBundleName</key>
<string>Revisor</string>
<key>CFBundleVersion</key>
<string>$(GIT_VERSION)</string>
<key>CFBundleShortVersionString</key>
<string>$(GIT_VERSION)</string>
</dict>
</plist>
EOFpl
; \
fi

uninstall:
rm -rf "$(PREFIX)/Revisor.scptd"

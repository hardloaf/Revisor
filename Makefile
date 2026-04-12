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
tmpdir=$$(mktemp -d); \
echo "Compiling FilterSecurityCamera.applescript into $$tmpdir/Revisor.scptd"; \
osacompile -o "$$tmpdir/Revisor.scptd" "FilterSecurityCamera.applescript" || { echo "osacompile failed"; rm -rf "$$tmpdir"; exit 1; }; \
# Replace any existing installation
rm -rf "$(PREFIX)/Revisor.scptd"; \
mv "$$tmpdir/Revisor.scptd" "$(PREFIX)/Revisor.scptd"; \
# Ensure compiled script is under Resources/Scripts/main.scpt
if [ -f "$(PREFIX)/Revisor.scptd/Contents/Resources/main.scpt" ]; then \
mkdir -p "$(PREFIX)/Revisor.scptd/Contents/Resources/Scripts"; \
mv "$(PREFIX)/Revisor.scptd/Contents/Resources/main.scpt" "$(PREFIX)/Revisor.scptd/Contents/Resources/Scripts/main.scpt"; \
fi; \
# Copy the compiled binary and worker into the bundle Resources
install -m 755 "$(TARGET)" "$(PREFIX)/Revisor.scptd/Contents/Resources/FilterSecurityCamera"; \
if [ -f "FilterSecurityCameraWorker.sh" ]; then \
install -m 755 "FilterSecurityCameraWorker.sh" "$(PREFIX)/Revisor.scptd/Contents/Resources/FilterSecurityCameraWorker.sh"; \
fi; \
# If a repo-provided Info.plist exists, copy it
if [ -f "Revisor.scptd/Contents/Info.plist" ]; then \
install -m 644 "Revisor.scptd/Contents/Info.plist" "$(PREFIX)/Revisor.scptd/Contents/Info.plist"; \
fi; \
# Set version keys in Info.plist if possible
if [ -f "$(PREFIX)/Revisor.scptd/Contents/Info.plist" ] && command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then \
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(GIT_VERSION)" "$(PREFIX)/Revisor.scptd/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $(GIT_VERSION)" "$(PREFIX)/Revisor.scptd/Contents/Info.plist"; \
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(GIT_VERSION)" "$(PREFIX)/Revisor.scptd/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $(GIT_VERSION)" "$(PREFIX)/Revisor.scptd/Contents/Info.plist"; \
fi; \
rm -rf "$$tmpdir"; \
else \
# Fallback: assemble bundle manually (no compiled script)
echo "osacompile not found; assembling bundle manually in $(PREFIX)"; \
mkdir -p "$(PREFIX)/Revisor.scptd/Contents/Resources/Scripts"; \
install -m 644 "FilterSecurityCamera.applescript" "$(PREFIX)/Revisor.scptd/Contents/Resources/Scripts/main.scpt"; \
install -m 755 "$(TARGET)" "$(PREFIX)/Revisor.scptd/Contents/Resources/FilterSecurityCamera"; \
if [ -f "FilterSecurityCameraWorker.sh" ]; then install -m 755 "FilterSecurityCameraWorker.sh" "$(PREFIX)/Revisor.scptd/Contents/Resources/FilterSecurityCameraWorker.sh"; fi; \
if [ -f "Revisor.scptd/Contents/Info.plist" ]; then install -m 644 "Revisor.scptd/Contents/Info.plist" "$(PREFIX)/Revisor.scptd/Contents/Info.plist"; else \
mkdir -p "$(PREFIX)/Revisor.scptd/Contents"; \
cat > "$(PREFIX)/Revisor.scptd/Contents/Info.plist" <<INFOPLIST; \
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
INFOPLIST
fi; \
fi

uninstall:
rm -rf "$(PREFIX)/Revisor.scptd"

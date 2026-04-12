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

# Install builds the binary and assembles a script bundle (Revisor.scptd)
# in the user's Mail Application Scripts directory. The bundle's Resources
# folder contains the binary, helper scripts and compiled AppleScript.
install: build
@echo "Installing Revisor.scptd bundle to $(PREFIX)"
# Create the bundle structure (Scripts folder will contain the compiled main script)
mkdir -p "$(PREFIX)/Revisor.scptd/Contents/Resources/Scripts"
# Copy the compiled tool into the bundle Resources
install -m 755 "$(TARGET)" "$(PREFIX)/Revisor.scptd/Contents/Resources/FilterSecurityCamera"
# Copy the worker script
if [ -f "FilterSecurityCameraWorker.sh" ]; then \
install -m 755 "FilterSecurityCameraWorker.sh" "$(PREFIX)/Revisor.scptd/Contents/Resources/FilterSecurityCameraWorker.sh"; \
fi
# Compile the AppleScript source into the bundle Scripts/main.scpt (compiled)
if [ -f "FilterSecurityCamera.applescript" ]; then \
if command -v osacompile >/dev/null 2>&1; then \
osacompile -o "$(PREFIX)/Revisor.scptd/Contents/Resources/Scripts/main.scpt" "FilterSecurityCamera.applescript"; \
else \
echo "Warning: osacompile not found; copying source as main.scpt (uncompiled)"; \
install -m 644 "FilterSecurityCamera.applescript" "$(PREFIX)/Revisor.scptd/Contents/Resources/Scripts/main.scpt"; \
fi \
fi
# Generate Info.plist with version information so the bundle includes the Git version
@mkdir -p "$(PREFIX)/Revisor.scptd/Contents"
@cat > "$(PREFIX)/Revisor.scptd/Contents/Info.plist" <<EOF
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

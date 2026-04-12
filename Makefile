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

# Install builds the binary and assembles a script-bundle (Revisor.scptd) in the user's
# Mail Application Scripts directory. The bundle's Resources folder contains the binary
# and helper scripts so the AppleScript can locate them via `path to resource`.
install: build
	@echo "Installing Revisor.scptd bundle to $(PREFIX)"
	# Create the bundle structure
	mkdir -p "$(PREFIX)/Revisor.scptd/Contents/Resources"
	# Copy the compiled tool into the bundle Resources
	install -m 755 "$(TARGET)" "$(PREFIX)/Revisor.scptd/Contents/Resources/FilterSecurityCamera"
	# Copy the worker script
	if [ -f "FilterSecurityCameraWorker.sh" ]; then \
		install -m 755 "FilterSecurityCameraWorker.sh" "$(PREFIX)/Revisor.scptd/Contents/Resources/FilterSecurityCameraWorker.sh"; \
	fi
	# Copy the AppleScript (main script) into the bundle Resources
	if [ -f "FilterSecurityCamera.scpt" ]; then \
		install -m 644 "FilterSecurityCamera.scpt" "$(PREFIX)/Revisor.scptd/Contents/Resources/FilterSecurityCamera.scpt"; \
	fi
	# Install Info.plist if present in the repo; otherwise create an empty placeholder
	if [ -f "Revisor.scptd/Contents/Info.plist" ]; then \
		install -m 644 "Revisor.scptd/Contents/Info.plist" "$(PREFIX)/Revisor.scptd/Contents/Info.plist"; \
	else \
		install -m 644 /dev/null "$(PREFIX)/Revisor.scptd/Contents/Info.plist"; \
	fi

uninstall:
	# Remove the entire bundle
	rm -rf "$(PREFIX)/Revisor.scptd"

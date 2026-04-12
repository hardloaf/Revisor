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

# Install copies the built tools and companion scripts into the user's
# Mail Application Scripts directory so they can be used by Mail rules.
# Uses 'install' to ensure the correct mode is set and files are owned by
# the current user.
install: build
	@echo "Installing to $(PREFIX)"
	mkdir -p "$(PREFIX)"
	# Install main binary
	install -m 755 "$(TARGET)" "$(PREFIX)/FilterSecurityCamera"
	# Install worker script if present
	if [ -f "FilterSecurityCameraWorker.sh" ]; then \
		install -m 755 "FilterSecurityCameraWorker.sh" "$(PREFIX)/FilterSecurityCameraWorker.sh"; \
	fi
	# Install AppleScript bundle if present
	if [ -f "FilterSecurityCamera.scpt" ]; then \
		install -m 644 "FilterSecurityCamera.scpt" "$(PREFIX)/FilterSecurityCamera.scpt"; \
	fi

uninstall:
	rm -f "$(PREFIX)/FilterSecurityCamera"
	rm -f "$(PREFIX)/FilterSecurityCameraWorker.sh"
	rm -f "$(PREFIX)/FilterSecurityCamera.scpt"

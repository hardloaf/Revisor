# Compiler settings
SWIFTC = swiftc
# -O enables compiler optimizations for speed
FLAGS = -O -whole-module-optimization

# File names
TARGET = classify_image
SRC = classify_image.swift
VERSION_FILE = Version.swift

# Install path
PREFIX = /usr/local/bin

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

install: build
	mkdir -p $(PREFIX)
	cp $(TARGET) $(PREFIX)/$(TARGET)

uninstall:
	rm -f $(PREFIX)/$(TARGET)
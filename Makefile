# Earshot — build helpers.
#
# All Xcode output goes to the local build/ directory (gitignored), so nothing
# leaks into ~/Library/Developer/Xcode/DerivedData.

PROJECT      := Earshot.xcodeproj
SCHEME       := Earshot
DERIVED_DATA := build
CONFIG_DEBUG := Debug
CONFIG_REL   := Release
APP          := $(DERIVED_DATA)/Build/Products/$(CONFIG_REL)/Earshot.app

XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA)

.PHONY: all build test release install clean

all: build

## Debug build.
build:
	$(XCODEBUILD) -configuration $(CONFIG_DEBUG) build

## Run the unit tests.
test:
	$(XCODEBUILD) -destination 'platform=macOS' test

## Release build.
release:
	$(XCODEBUILD) -configuration $(CONFIG_REL) build

## Release build, then copy Earshot.app into /Applications.
install: release
	rm -rf "/Applications/Earshot.app"
	cp -R "$(APP)" /Applications/
	@echo "Installed Earshot to /Applications/Earshot.app"

## Remove the local build directory and Xcode's project caches.
clean:
	rm -rf $(DERIVED_DATA)
	-$(XCODEBUILD) clean

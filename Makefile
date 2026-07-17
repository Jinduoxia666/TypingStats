APP_NAME    := TypingStats
CONFIG      := release
BUILD_DIR   := .build
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
BIN_PATH    := $(BUILD_DIR)/$(CONFIG)/$(APP_NAME)
STAGING     := $(BUILD_DIR)/dmg-staging

# Keep the human-facing version stable, while every packaging invocation gets
# a sortable, unique build version. The same values are embedded in the app and
# included in the DMG name so old packages can coexist and be identified.
APP_VERSION     ?= $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
BUILD_VERSION   ?= $(shell date +%Y%m%d.%H%M%S)
APP_VERSION     := $(APP_VERSION)
BUILD_VERSION   := $(BUILD_VERSION)
PACKAGE_VERSION := $(APP_VERSION)-$(BUILD_VERSION)
DMG_PATH        := $(BUILD_DIR)/$(APP_NAME)-$(PACKAGE_VERSION).dmg

# Stable signing identity so the Accessibility (TCC) grant survives rebuilds.
# Falls back to ad-hoc (-) if the cert isn't present on this machine.
SIGN_ID     := Apple Development: REDACTED (ZR56Z9UGC3)

.PHONY: all build app run dmg test clean reset-perm

all: app

build:
	swift build -c $(CONFIG)

app: build
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(BIN_PATH)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(APP_VERSION)" "$(APP_BUNDLE)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_VERSION)" "$(APP_BUNDLE)/Contents/Info.plist"
	@cp Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	@codesign --force --deep --sign "$(SIGN_ID)" --entitlements Resources/TypingStats.entitlements "$(APP_BUNDLE)" 2>/dev/null \
		|| codesign --force --deep --sign - --entitlements Resources/TypingStats.entitlements "$(APP_BUNDLE)" 2>/dev/null \
		|| codesign --force --deep --sign - "$(APP_BUNDLE)"
	@echo "Built: $(APP_BUNDLE) ($(PACKAGE_VERSION))"

run: app
	@pkill -x $(APP_NAME) 2>/dev/null || true
	open "$(APP_BUNDLE)"

# Package the .app into a versioned drag-to-install .dmg. Versioned artifacts
# are intentionally not deleted, so each release remains distinguishable.
dmg: app
	@rm -rf "$(STAGING)"
	@mkdir -p "$(STAGING)"
	@cp -R "$(APP_BUNDLE)" "$(STAGING)/"
	@ln -s /Applications "$(STAGING)/Applications"
	@hdiutil create -volname "$(APP_NAME) $(PACKAGE_VERSION)" -srcfolder "$(STAGING)" -ov -format UDZO "$(DMG_PATH)" >/dev/null
	@rm -rf "$(STAGING)"
	@echo "Built: $(DMG_PATH)"

test:
	swift test

clean:
	swift package clean
	rm -rf "$(APP_BUNDLE)"

# Wipe the macOS Accessibility permission record for this bundle id.
# Useful during dev when ad-hoc signature changes invalidate the permission.
reset-perm:
	tccutil reset Accessibility com.jinduoxia.TypingStats

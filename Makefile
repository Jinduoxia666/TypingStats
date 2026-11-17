APP_NAME    := TypingStats
CONFIG      := release
BUILD_DIR   := .build
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
BIN_PATH    := $(BUILD_DIR)/$(CONFIG)/$(APP_NAME)
STAGING     := $(BUILD_DIR)/dmg-staging
WIDGET_BUILD := $(BUILD_DIR)/widget
WIDGET_BUNDLE := $(WIDGET_BUILD)/Build/Products/Release/CalculatorWidget.appex

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
# Set it in the untracked signing.local.mk (`SIGN_ID := Apple Development: …`)
# or the environment; defaults to ad-hoc (-), which is also the fallback when
# the cert isn't present on this machine.
-include signing.local.mk
SIGN_ID     ?= -

.PHONY: all build widget app run dmg test clean reset-perm

all: app

build:
	swift build -c $(CONFIG)

widget:
	xcodegen generate
	xcodebuild -project TypingStats.xcodeproj -scheme CalculatorWidget -configuration Release -destination 'platform=macOS' -derivedDataPath "$(WIDGET_BUILD)" -skipPackageUpdates CODE_SIGNING_ALLOWED=NO MARKETING_VERSION="$(APP_VERSION)" CURRENT_PROJECT_VERSION="$(BUILD_VERSION)" build

app: build widget
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(BIN_PATH)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(APP_VERSION)" "$(APP_BUNDLE)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_VERSION)" "$(APP_BUNDLE)/Contents/Info.plist"
	@cp Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	@mkdir -p "$(APP_BUNDLE)/Contents/PlugIns"
	@cp -R "$(WIDGET_BUNDLE)" "$(APP_BUNDLE)/Contents/PlugIns/"
	@codesign --force --sign "$(SIGN_ID)" --entitlements Resources/CalculatorWidget.entitlements "$(APP_BUNDLE)/Contents/PlugIns/CalculatorWidget.appex" \
		|| codesign --force --sign - --entitlements Resources/CalculatorWidget.entitlements "$(APP_BUNDLE)/Contents/PlugIns/CalculatorWidget.appex"
	@codesign --force --sign "$(SIGN_ID)" --entitlements Resources/TypingStats.entitlements "$(APP_BUNDLE)" \
		|| codesign --force --sign - --entitlements Resources/TypingStats.entitlements "$(APP_BUNDLE)"
	@codesign --verify --deep --strict "$(APP_BUNDLE)"
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

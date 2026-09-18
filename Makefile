# Liquid Desktop — builds a signed, universal .app and a DMG with the Command
# Line Tools alone. swiftc is called directly (no SwiftPM, no Xcode project),
# and the Metal shaders compile at runtime, so no Xcode install is needed.

APP_NAME   := Liquid Desktop
EXECUTABLE := LiquidDesktop
BUNDLE_ID  := app.liquiddesktop.mac
BUILD_DIR  := .build/release
DIST_DIR   := .dist
APP        := $(DIST_DIR)/$(APP_NAME).app
CONTENTS   := $(APP)/Contents
VERSION    := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG        := $(DIST_DIR)/Liquid Desktop.dmg

SOURCES    := $(wildcard Sources/LiquidDesktop/*.swift) $(wildcard Sources/LiquidDesktop/*/*.swift)
FRAMEWORKS := AppKit SwiftUI Metal QuartzCore ScreenCaptureKit CoreMedia CoreVideo IOKit Carbon ServiceManagement
FLAGS      := -O -swift-version 5 $(addprefix -framework ,$(FRAMEWORKS))
MIN_MACOS  := 14.0

# Stable local identity keeps the Screen Recording grant across rebuilds.
# For distribution set CODESIGN_IDENTITY="Developer ID Application: …".
SIGNING_CERT_NAME := Liquid Desktop Local Signing
CODESIGN_IDENTITY ?= $(shell security find-certificate -c "$(SIGNING_CERT_NAME)" \
    >/dev/null 2>&1 && echo "$(SIGNING_CERT_NAME)" || echo "-")

PREVIEW_SOURCES := $(wildcard Sources/LiquidDesktop/Simulation/*.swift) \
                   Sources/LiquidDesktop/Render/LiquidShaders.swift \
                   Sources/LiquidDesktop/Render/LiquidRenderer.swift \
                   Sources/LiquidDesktop/Model/LiquidTheme.swift \
                   Sources/LiquidDesktop/Model/LidMapping.swift \
                   Tools/Shared/MockDesktop.swift

.PHONY: all build bundle sign install run uninstall dmg notarize icon preview promo \
        certificate remove-certificate reset-permission clean

all: bundle sign

build:
	@mkdir -p $(BUILD_DIR)
	@swiftc $(FLAGS) -target arm64-apple-macos$(MIN_MACOS) $(SOURCES) -o $(BUILD_DIR)/$(EXECUTABLE)-arm64
	@swiftc $(FLAGS) -target x86_64-apple-macos$(MIN_MACOS) $(SOURCES) -o $(BUILD_DIR)/$(EXECUTABLE)-x86_64
	@lipo -create $(BUILD_DIR)/$(EXECUTABLE)-arm64 $(BUILD_DIR)/$(EXECUTABLE)-x86_64 -output $(BUILD_DIR)/$(EXECUTABLE)
	@echo "Built    $(BUILD_DIR)/$(EXECUTABLE) (arm64 + x86_64)"

bundle: build icon
	@rm -rf "$(APP)"
	@mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	@cp $(BUILD_DIR)/$(EXECUTABLE) "$(CONTENTS)/MacOS/$(EXECUTABLE)"
	@cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	@cp Resources/AppIcon.icns "$(CONTENTS)/Resources/AppIcon.icns"
	@cp Resources/Acknowledgements.txt "$(CONTENTS)/Resources/Acknowledgements.txt"
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@echo "Bundled  $(APP)"

TIMESTAMP := $(if $(findstring Developer ID,$(CODESIGN_IDENTITY)),--timestamp,--timestamp=none)

sign:
	@codesign --force --options runtime $(TIMESTAMP) \
		--entitlements Resources/LiquidDesktop.entitlements \
		--sign "$(CODESIGN_IDENTITY)" "$(APP)"
	@echo "Signed   with: $(CODESIGN_IDENTITY)"

install: all
	@pkill -x $(EXECUTABLE) 2>/dev/null || true
	@rm -rf "/Applications/$(APP_NAME).app"
	@cp -R "$(APP)" /Applications/
	@echo "Installed /Applications/$(APP_NAME).app"

run: install
	@open "/Applications/$(APP_NAME).app"

uninstall:
	@pkill -x $(EXECUTABLE) 2>/dev/null || true
	@rm -rf "/Applications/$(APP_NAME).app"

dmg: all
	@CODESIGN_IDENTITY="$(CODESIGN_IDENTITY)" Scripts/make-dmg.sh "$(APP)" "$(DMG)" "$(APP_NAME)"

# Needs a Developer ID identity (CODESIGN_IDENTITY) and a notarytool keychain
# profile: xcrun notarytool store-credentials liquiddesktop --apple-id … --team-id …
notarize: dmg
	@Scripts/notarize.sh "$(DMG)"

icon: Resources/AppIcon.icns

Resources/AppIcon.icns: Tools/IconRender/main.swift
	@mkdir -p $(BUILD_DIR) $(DIST_DIR)/AppIcon.iconset
	@swiftc -O -framework AppKit Tools/IconRender/main.swift -o $(BUILD_DIR)/IconRender
	@$(BUILD_DIR)/IconRender $(DIST_DIR)/icon-1024.png
	@for size in 16 32 128 256 512; do \
		sips -z $$size $$size $(DIST_DIR)/icon-1024.png --out $(DIST_DIR)/AppIcon.iconset/icon_$${size}x$${size}.png >/dev/null; \
		double=$$((size * 2)); \
		sips -z $$double $$double $(DIST_DIR)/icon-1024.png --out $(DIST_DIR)/AppIcon.iconset/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	@iconutil -c icns $(DIST_DIR)/AppIcon.iconset -o Resources/AppIcon.icns
	@echo "Wrote    Resources/AppIcon.icns"

# Offscreen render of a scripted lid performance over a mock desktop.
# THEME=clear|lagoon|mercury|lava|all, SIZE="1512 982", SECONDS=10
THEME   ?= clear
SIZE    ?= 1512 982
SECONDS ?= 10
preview:
	@mkdir -p $(BUILD_DIR) $(DIST_DIR)/preview
	@swiftc $(FLAGS) -target arm64-apple-macos$(MIN_MACOS) -framework ImageIO $(PREVIEW_SOURCES) Tools/LiquidPreview/main.swift -o $(BUILD_DIR)/LiquidPreview
	@$(BUILD_DIR)/LiquidPreview $(DIST_DIR)/preview $(THEME) $(SIZE) $(SECONDS)

# Marketing video: 3D MacBook mock-up with live liquid. Writes the 9:16 Reel
# and a landscape loop for the website into .dist/promo.
promo:
	@mkdir -p $(BUILD_DIR) $(DIST_DIR)/promo
	@swiftc $(FLAGS) -target arm64-apple-macos$(MIN_MACOS) $(PREVIEW_SOURCES) Tools/PromoRender/*.swift -o $(BUILD_DIR)/PromoRender
	@$(BUILD_DIR)/PromoRender $(DIST_DIR)/promo $(DIST_DIR)/icon-1024.png

certificate:
	@Scripts/make-signing-certificate.sh

remove-certificate:
	@Scripts/make-signing-certificate.sh --remove

reset-permission:
	@tccutil reset ScreenCapture $(BUNDLE_ID) || true

clean:
	@rm -rf .build $(DIST_DIR)

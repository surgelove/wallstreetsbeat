# ── LOVE2D BUILD TOOLS ──
# Targets:
#   make love      — Package the game into a .love file
#   make run       — Run locally with LÖVE
#   make ios       — Build for iOS simulator (SDK 26.5, runs on iOS 27)
#   make ios-device — Build for iOS device (needs signing)
#   make ios-setup — Check iOS build dependencies
#   make apk       — Build Android APK (requires love-android)
#   make ios-clean  — Remove iOS build artifacts

APP_NAME = wallstreetsbeat
LOVE_FILE = $(APP_NAME).love

# Find the love binary
LOVE := $(shell which love 2>/dev/null || which love2 2>/dev/null || echo "")

# ──────────────────────────
# Files to exclude from build
# ──────────────────────────
EXCLUDE = Makefile .DS_Store .gitkeep

.PHONY: love run apk clean ios ios-device ios-setup ios-clean

# ── Package .love file ──
love:
	@echo "📦 Creating $(LOVE_FILE)..."
	@cd . && zip -r "$(LOVE_FILE)" \
		*.lua *.json *.png *.jpg *.ttf *.wav *.m4a \
		memes/ sounds/ music/ data/ characters/presidents/ characters/ controls/ fonts/ sprites/ \
		-x $(EXCLUDE)
	@echo "✅ Done: $(LOVE_FILE) ($(shell stat -f%z "$(LOVE_FILE)" 2>/dev/null || stat -c%s "$(LOVE_FILE)" 2>/dev/null) bytes)"

# ── Run locally ──
run: love
	@if [ -z "$(LOVE)" ]; then \
		echo "❌ LÖVE not found. Install via: brew install love"; \
		exit 1; \
	fi
	@echo "🎮 Launching $(APP_NAME)..."
	@"$(LOVE)" "$(LOVE_FILE)"

# ── Build Android APK (requires love-android project) ──
apk:
	@echo "📱 Building Android APK..."
	@echo ""
	@echo "   This requires the love-android project."
	@echo "   See: https://github.com/love2d/love-android"
	@echo ""
	@echo "   Quick steps:"
	@echo ""
	@echo "   1. First create the .love file:  make love"
	@echo "   2. Clone love-android:"
	@echo "      git clone https://github.com/love2d/love-android.git"
	@echo "   3. Copy your .love file in:"
	@echo "      cp $(LOVE_FILE) love-android/app/src/main/assets/game.love"
	@echo "   4. Build with Gradle:"
	@echo "      cd love-android && ./gradlew assembleRelease"
	@echo "   5. Find your APK at:"
	@echo "      love-android/app/build/outputs/apk/release/"
	@echo ""

# ── iOS Build ──
#   make ios        — simulator build (SDK 26.5, works on iOS 27 devices)
#   make ios-device — device build (requires signing, SDK 26.5)
#   SDK 27 beta is NOT used because SDL2 lacks UIScene lifecycle support
#   (see Technote TN3187). Apps built with 26.5 SDK run fine on iOS 27.
IOS_PROJECT = ios/love-source/platform/xcode/love.xcodeproj
IOS_SDK_SIM = iphonesimulator26.5
IOS_SDK_DEV = iphoneos26.5
IOS_BUILD_DIR = $(CURDIR)/ios/build
IOS_PRODUCT = $(IOS_BUILD_DIR)/Debug-iphonesimulator/STONKS.app
IOS_PRODUCT_DEV = $(IOS_BUILD_DIR)/Debug-iphoneos/STONKS.app
# Use regular Xcode (not beta) — SDL2 is incompatible with SDK 27
XCODE_DEV = /Applications/Xcode.app/Contents/Developer

ios: love
	@echo "📱 Building STONKS for iOS simulator (SDK 26.5)..."
	@mkdir -p "$(IOS_BUILD_DIR)"
	cp "$(LOVE_FILE)" "ios/love-source/platform/xcode/ios/game.love"
	DEVELOPER_DIR="$(XCODE_DEV)" \
	xcodebuild -project "$(IOS_PROJECT)" \
		-target love-ios \
		-sdk "$(IOS_SDK_SIM)" \
		CONFIGURATION_BUILD_DIR="$(IOS_BUILD_DIR)/Debug-iphonesimulator" \
		CODE_SIGNING_ALLOWED=NO \
		ASSETCATALOG_COMPILER_APPICON_NAME="" \
		SYMROOT="$(IOS_BUILD_DIR)"
	cp "$(LOVE_FILE)" "$(IOS_PRODUCT)/game.love"
	@echo "✅ iOS simulator build done: $(IOS_PRODUCT)"

ios-device: love
	@echo "📱 Building STONKS for iOS device (SDK 26.5)..."
	@mkdir -p "$(IOS_BUILD_DIR)"
	cp "$(LOVE_FILE)" "ios/love-source/platform/xcode/ios/game.love"
	DEVELOPER_DIR="$(XCODE_DEV)" \
	xcodebuild -project "$(IOS_PROJECT)" \
		-target love-ios \
		-sdk "$(IOS_SDK_DEV)" \
		-configuration Debug \
		CONFIGURATION_BUILD_DIR="$(IOS_BUILD_DIR)/Debug-iphoneos" \
		ASSETCATALOG_COMPILER_APPICON_NAME="" \
		SYMROOT="$(IOS_BUILD_DIR)"
	cp "$(LOVE_FILE)" "$(IOS_PRODUCT_DEV)/game.love"
	@echo "✅ iOS device build done: $(IOS_PRODUCT_DEV)"

ios-setup:
	@echo "📱 Checking iOS build dependencies..."
	@if [ ! -d "ios/love-source" ]; then \
		echo "❌ LÖVE source not found at ios/love-source/"; \
		echo "   Download LÖVE 11.5 source and place it there."; \
		exit 1; \
	fi
	@if [ ! -f "ios/love-source/platform/xcode/ios/libraries/SDL2.xcframework/Info.plist" ]; then \
		echo "⚠️  iOS libraries (xcframeworks) may be missing."; \
		echo "   They should be in ios/love-source/platform/xcode/ios/libraries/"; \
	fi
	@echo "✅ iOS project is set up at $(IOS_PROJECT)"

# ── Clean ──
clean:
	rm -f "$(LOVE_FILE)"
	@echo "🧹 Cleaned up."

ios-clean:
	rm -rf "$(IOS_BUILD_DIR)"
	@echo "🧹 iOS build artifacts cleaned."

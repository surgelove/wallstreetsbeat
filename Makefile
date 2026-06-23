# ── LOVE2D BUILD TOOLS ──
# Targets:
#   make love     — Package the game into a .love file
#   make run      — Run locally with LÖVE
#   make ios      — Build for iOS 27 simulator (Xcode-beta.app or Xcode.app)
#   make ios-setup — Check iOS build dependencies
#   make apk      — Build Android APK (requires love-android)
#   make ios-clean — Remove iOS build artifacts

APP_NAME = wallstreetsbeat
LOVE_FILE = $(APP_NAME).love

# Find the love binary
LOVE := $(shell which love 2>/dev/null || which love2 2>/dev/null || echo "")

# ──────────────────────────
# Files to exclude from build
# ──────────────────────────
EXCLUDE = Makefile .DS_Store .gitkeep

.PHONY: love run apk clean

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

# ── iOS Build (simulator) ──
IOS_PROJECT = ios/love-source/platform/xcode/love.xcodeproj
IOS_SDK = iphonesimulator27.0
IOS_BUILD_DIR = $(CURDIR)/ios/build
IOS_PRODUCT = $(IOS_BUILD_DIR)/Debug-iphonesimulator/STONKS.app
XCODE_BETA = /Applications/Xcode-beta.app
XCODE_BETA_DEV = $(XCODE_BETA)/Contents/Developer

ios: love
	@echo "📱 Building STONKS for iOS simulator..."
	@mkdir -p "$(IOS_BUILD_DIR)"
	cp "$(LOVE_FILE)" "ios/love-source/platform/xcode/ios/game.love"
	if [ -d "$(XCODE_BETA)" ]; then \
		echo "   Using Xcode beta: $(XCODE_BETA)"; \
		DEVELOPER_DIR="$(XCODE_BETA_DEV)" \
		xcodebuild -project "$(IOS_PROJECT)" \
			-target love-ios \
			-sdk "$(IOS_SDK)" \
			CONFIGURATION_BUILD_DIR="$(IOS_BUILD_DIR)/Debug-iphonesimulator" \
			CODE_SIGNING_ALLOWED=NO \
			ASSETCATALOG_COMPILER_APPICON_NAME="" \
			SYMROOT="$(IOS_BUILD_DIR)"; \
	else \
		xcodebuild -project "$(IOS_PROJECT)" \
			-target love-ios \
			-sdk "$(IOS_SDK)" \
			CONFIGURATION_BUILD_DIR="$(IOS_BUILD_DIR)/Debug-iphonesimulator" \
			CODE_SIGNING_ALLOWED=NO \
			ASSETCATALOG_COMPILER_APPICON_NAME="" \
			SYMROOT="$(IOS_BUILD_DIR)"; \
	fi
	cp "$(LOVE_FILE)" "$(IOS_PRODUCT)/game.love"
	@echo "✅ iOS build done: $(IOS_PRODUCT)"

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

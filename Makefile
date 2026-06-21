# ── LOVE2D BUILD TOOLS ──
# Targets:
#   make love     — Package the game into a .love file
#   make apk     — Build a standalone Android APK (requires love-android)
#   make run     — Run locally with LÖVE

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

# ── Clean ──
clean:
	rm -f "$(LOVE_FILE)"
	@echo "🧹 Cleaned up."

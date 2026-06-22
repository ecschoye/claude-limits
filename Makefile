APP     := ClaudeLimits
BUNDLE  := build/$(APP).app
BIN     := $(BUNDLE)/Contents/MacOS/$(APP)
SRCS    := $(wildcard Sources/*.swift)
TARGET  := arm64-apple-macosx14.0
FRAMEWORKS := -framework SwiftUI -framework AppKit -framework ServiceManagement -framework Security -framework UserNotifications

# Stable self-signed identity if it exists (so keychain "Always Allow" persists across rebuilds),
# else ad-hoc. Create the identity once: see `make codesign-help`.
SIGN := $(shell security find-identity -p codesigning 2>/dev/null | grep -q "ClaudeLimits Dev" && echo "ClaudeLimits Dev" || echo "-")

.PHONY: build run test clean install

build: $(BIN)

$(BIN): $(SRCS) Info.plist
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	swiftc -O -target $(TARGET) $(FRAMEWORKS) $(SRCS) -o $(BIN)
	@cp Info.plist $(BUNDLE)/Contents/Info.plist
	@[ -d Resources ] && cp -R Resources/. $(BUNDLE)/Contents/Resources/ || true
	@codesign --force --sign "$(SIGN)" $(BUNDLE)
	@echo "built $(BUNDLE) (signed: $(SIGN))"

run: build
	open $(BUNDLE)

# Pure-logic self-test: each provider's parser + countdown. No SwiftUI, no network.
TEST_SRCS := Sources/Shared.swift Sources/KeychainStore.swift Sources/ClaudeProvider.swift \
             Sources/CodexProvider.swift Sources/OpenRouterProvider.swift
test:
	@mkdir -p build
	swiftc -target $(TARGET) -framework Security $(TEST_SRCS) Tests/main.swift -o build/selftest
	./build/selftest

install: build
	@rm -rf /Applications/$(APP).app
	cp -R $(BUNDLE) /Applications/
	@echo "installed to /Applications/$(APP).app"

clean:
	rm -rf build

# One-time: create a stable self-signed code-signing identity so the keychain
# "Always Allow" survives rebuilds (no more repeated password prompts).
codesign-help:
	@echo "One-time setup to stop repeated keychain prompts on each build:"
	@echo "  1. Open Keychain Access."
	@echo "  2. Menu: Keychain Access > Certificate Assistant > Create a Certificate."
	@echo "  3. Name: ClaudeLimits Dev"
	@echo "     Identity Type: Self Signed Root"
	@echo "     Certificate Type: Code Signing"
	@echo "     Click Create, then Done."
	@echo "  4. make build   (now signs as 'ClaudeLimits Dev')."
	@echo "  5. On next launch, click 'Always Allow' on the keychain prompt ONCE."
	@echo "Current signing identity: $(SIGN)"

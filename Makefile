APP     := ClaudeLimits
BUNDLE  := build/$(APP).app
BIN     := $(BUNDLE)/Contents/MacOS/$(APP)
SRCS    := $(wildcard Sources/*.swift)
TARGET  := arm64-apple-macosx14.0
FRAMEWORKS := -framework SwiftUI -framework AppKit -framework ServiceManagement -framework Security

.PHONY: build run test clean install

build: $(BIN)

$(BIN): $(SRCS) Info.plist
	@mkdir -p $(BUNDLE)/Contents/MacOS
	swiftc -O -target $(TARGET) $(FRAMEWORKS) $(SRCS) -o $(BIN)
	@cp Info.plist $(BUNDLE)/Contents/Info.plist
	@codesign --force --sign - $(BUNDLE)
	@echo "built $(BUNDLE)"

run: build
	open $(BUNDLE)

# Pure-logic self-test: parse + countdown formatting. No SwiftUI, no network.
test:
	@mkdir -p build
	swiftc -target $(TARGET) Sources/Usage.swift Tests/main.swift -o build/selftest
	./build/selftest

install: build
	@rm -rf /Applications/$(APP).app
	cp -R $(BUNDLE) /Applications/
	@echo "installed to /Applications/$(APP).app"

clean:
	rm -rf build

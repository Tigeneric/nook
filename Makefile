# The Xcode packaging layer on top of SPM. The dev loop for libraries and
# tests stays on `swift build` / `swift test`; xcodebuild is only here for the
# .app bundle.

# Signing team. Empty on purpose: a fresh clone then builds ad-hoc-signed,
# which is all a locally built app needs and asks for no Apple account. With
# your own: `DEVELOPMENT_TEAM=XXXXXXXXXX make install`.
DEVELOPMENT_TEAM ?=
export DEVELOPMENT_TEAM

# No team, no certificate: sign ad-hoc. arm64 binaries have to carry some
# signature to run at all, and `-` is the one that needs nothing.
ifeq ($(strip $(DEVELOPMENT_TEAM)),)
SIGNING = CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- PROVISIONING_PROFILE_SPECIFIER=
else
SIGNING =
endif

PROJECT = Nook.xcodeproj
CONFIG  = Debug
DERIVED = .build/xcode
APP     = $(DERIVED)/Build/Products/$(CONFIG)/Nook.app

.PHONY: build test test-xcode generate app install run clean icon

build:
	swift build

test:
	swift test

# The same tests through the Xcode project — what ⌘U runs. Worth a check
# after touching project.yml: the test targets are defined there a second
# time, and the two definitions can drift.
test-xcode: generate
	xcodebuild test -project $(PROJECT) -scheme NookApp \
		-destination 'platform=macOS' -derivedDataPath $(DERIVED)

generate:
	xcodegen generate

app: generate
	xcodebuild -project $(PROJECT) -scheme NookApp -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) $(SIGNING) build

install: app
	rm -rf /Applications/Nook.app
	cp -R $(APP) /Applications/
	@echo "Installed /Applications/Nook.app"

run: install
	open /Applications/Nook.app

# Re-render the app icon's sizes after editing tools/AppIcon.svg.
icon:
	swift tools/render-icon.swift tools/AppIcon.svg Sources/Nook/Assets.xcassets/AppIcon.appiconset

clean:
	rm -rf $(DERIVED) $(PROJECT) .build

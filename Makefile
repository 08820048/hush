# Hush build tasks. Requires Xcode (set DEVELOPER_DIR if Xcode is not the active developer dir,
# e.g. DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer make app).

APP_BUILD := .build/xcode
APP := $(APP_BUILD)/Build/Products/Debug/Hush.app

.PHONY: test cli project app run snapshots icon release site deploy-site clean

test:            ## Run HushCore tests
	swift test --package-path Core

cli:             ## Build the release CLI to .build/release/hush
	swift build -c release --product hush

project:         ## Generate App/Hush.xcodeproj (needs xcodegen)
	cd App && xcodegen generate

app: project     ## Build Hush.app (Debug)
	xcodebuild -project App/Hush.xcodeproj -scheme Hush -configuration Debug -derivedDataPath $(APP_BUILD) build

run: app         ## Build and launch the app
	open $(APP)

snapshots: app   ## Render UI snapshots offscreen (Debug only) and print their folder
	$(APP)/Contents/MacOS/Hush --render-snapshots

icon:            ## Re-render the app icon (needs Pillow)
	python3 scripts/render_app_icon.py App/Hush/Assets.xcassets/AppIcon.appiconset

release:         ## Build release zips into dist/ (signs and notarizes when DEVELOPER_ID is set)
	scripts/release.sh

site:            ## Build the website into website/dist
	python3 website/build.py

deploy-site: site ## Deploy the website to Cloudflare Pages (needs wrangler login)
	wrangler pages deploy website/dist --project-name hush-website --branch main

clean:
	rm -rf .build dist website/dist App/Hush.xcodeproj

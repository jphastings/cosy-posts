# chaos.awaits.us

Private community platform for sharing videos, photos, audio, and text.

## Components

- **`api/`** — Go API server with TUS resumable uploads, photo processing (jpegli), and 11ty-compatible post generation
- **`app/`** — SwiftUI iOS app with offline-first upload queue and share sheet extension

## Setup

After cloning, enable the repo's git hooks:

```sh
git config core.hooksPath .githooks
```

This sets up a pre-push hook that runs contract tests before each push.

## Tasks

### run-api

Build and run the API service for testing purposes.

```sh
cd api && \
go run . --config ~/.cosyposts/config.yaml
```

### run-mac-app

Build and run the macOS app for testing purposes. On first run, open the project in Xcode to register the device and create provisioning profiles.

```sh
cd app && \
xcodegen generate && \
xcodebuild -project CosyPostsAdmin.xcodeproj -scheme CosyPostsAdmin -destination 'platform=macOS' -allowProvisioningUpdates build && \
open ~/Library/Developer/Xcode/DerivedData/CosyPostsAdmin-*/Build/Products/Debug/CosyPostsAdmin.app
```

### run-ios-app

Build and run the iOS app on the iOS Simulator for testing purposes.

```sh
cd app && \
xcodegen generate && \
xcodebuild -project CosyPostsAdmin.xcodeproj -scheme CosyPostsAdmin -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build && \
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null

xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/CosyPostsAdmin-*/Build/Products/Debug-iphonesimulator/CosyPostsAdmin.app && \
xcrun simctl launch booted me.byjp.cosyposts.app && \
open -a Simulator
```

### test-contracts

Run consumer (Swift) then provider (Go) contract tests. Requires the pact FFI library (`go install github.com/pact-foundation/pact-go/v2@v2.4.2 && sudo "$(go env GOPATH)/bin/pact-go" install`).

```sh
cd app && \
xcodegen generate && \
PACT_OUTPUT_DIR="$(cd ../contracts && pwd)" \
xcodebuild -project CosyPostsAdmin.xcodeproj -scheme ContractTests \
  -destination 'platform=macOS' -only-testing:ContractTests \
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO test && \
cd ../api && \
go test -tags pact -run TestPactProvider -count=1 -v ./...
```

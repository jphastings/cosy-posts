# chaos.awaits.us

Private community platform for sharing videos, photos, audio, and text.

## Components

- **`api/`** — Go API server with TUS resumable uploads, photo processing (jpegli), and 11ty-compatible post generation
- **`app/`** — SwiftUI iOS app with offline-first upload queue and share sheet extension

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

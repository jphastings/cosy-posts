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

### test-api

Run Go unit tests with coverage summary.

```sh
cd api && \
go test -count=1 -coverprofile=coverage.out -covermode=atomic ./... && \
echo && go tool cover -func=coverage.out | tail -1 && \
rm -f coverage.out
```

### test-app

Run Swift unit tests with coverage summary.

```sh
cd app && \
xcodegen generate && \
rm -rf TestResults.xcresult && \
xcodebuild \
  -project CosyPostsAdmin.xcodeproj \
  -scheme UploadTests \
  -destination 'platform=macOS' \
  -only-testing:UploadTests \
  -enableCodeCoverage YES \
  -resultBundlePath TestResults.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  test && \
echo && xcrun xccov view --report --only-targets TestResults.xcresult && \
rm -rf TestResults.xcresult
```

### test

Run all tests with coverage.

```sh
xc test-api && xc test-app
```

### bump

Run all tests then create a new semver tag. COMPONENT is `api` or `app`. BUMP is `major`, `minor`, or `patch` (defaults to `patch`).

Inputs: COMPONENT, BUMP
Environment: BUMP=patch

Requires: test, test-contracts

```sh
set -euo pipefail

if [ "$COMPONENT" != "api" ] && [ "$COMPONENT" != "app" ]; then
  echo "Error: COMPONENT must be 'api' or 'app'" >&2; exit 1
fi
if [ "$BUMP" != "major" ] && [ "$BUMP" != "minor" ] && [ "$BUMP" != "patch" ]; then
  echo "Error: BUMP must be 'major', 'minor', or 'patch'" >&2; exit 1
fi

if [ "$COMPONENT" = "app" ]; then
  PREFIX="app/v"
  LATEST=$(git tag --list 'app/v*' | sed 's|^app/v||' | sort -V | tail -1)
else
  PREFIX="v"
  LATEST=$(git tag --list 'v*' | grep -v '/' | sed 's|^v||' | sort -V | tail -1)
fi
LATEST="${LATEST:-0.0.0}"

IFS='.' read -r MAJOR MINOR PATCH_NUM <<< "$LATEST"
case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH_NUM=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH_NUM=0 ;;
  patch) PATCH_NUM=$((PATCH_NUM + 1)) ;;
esac
NEW_TAG="${PREFIX}${MAJOR}.${MINOR}.${PATCH_NUM}"

git tag "$NEW_TAG"
echo "Tagged $NEW_TAG (was v$LATEST). Run 'git push origin $NEW_TAG' to publish."
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

# Maperick — development commands

# Default: list available commands
default:
    @just --list

# Build the Rust binary in release mode
build:
    cargo build --release

# Install maperick to ~/.cargo/bin (adds to PATH) and download GeoIP DB
install:
    cargo install --path .
    @echo ""
    @echo "Downloading GeoIP database (if not already present)..."
    @maperick --db-path > /dev/null 2>&1 || true
    @maperick --db-path 2>/dev/null && echo "GeoIP DB location: $(maperick --db-path 2>/dev/null)" || true
    @echo ""
    @echo "maperick installed! Run 'maperick -e' to start."

# Run maperick with enhanced graphics (auto-downloads DB if needed)
run:
    cargo run -- -e

# Run maperick with a specific database path
run-with-db path:
    cargo run -- -e -p {{path}}

# Show where the GeoIP database is stored
db-path:
    cargo run -- --db-path

# Run tests
test:
    cargo test

# Run clippy lints
lint:
    cargo clippy -- -D warnings

# Format code
fmt:
    cargo fmt

# Build macOS .app and create a DMG (requires create-dmg: brew install create-dmg)
dmg:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Building Maperick.app (Release)..."
    xcodebuild build \
        -project mac_app/Maperick/Maperick.xcodeproj \
        -scheme Maperick \
        -configuration Release \
        -derivedDataPath build_mac \
        -quiet
    APP_PATH="build_mac/Build/Products/Release/Maperick.app"
    if [ ! -d "$APP_PATH" ]; then
        echo "ERROR: Maperick.app not found at $APP_PATH"
        exit 1
    fi
    echo "Creating DMG..."
    rm -f Maperick.dmg
    create-dmg \
        --volname "Maperick" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "Maperick.app" 175 185 \
        --app-drop-link 425 185 \
        "Maperick.dmg" \
        "$APP_PATH"
    echo "✓ Maperick.dmg created ($(du -h Maperick.dmg | cut -f1))"

# Upload Maperick.dmg to the latest GitHub release (requires gh CLI)
upload-dmg:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f Maperick.dmg ]; then
        echo "ERROR: Maperick.dmg not found. Run 'just dmg' first."
        exit 1
    fi
    TAG=$(gh release list --limit 1 --json tagName -q '.[0].tagName')
    echo "Uploading Maperick.dmg to release $TAG..."
    gh release upload "$TAG" Maperick.dmg --clobber
    echo "✓ Uploaded to release $TAG"

# Build DMG and upload to latest GitHub release
release-dmg: dmg upload-dmg

# Serve GitHub Pages locally (requires Python 3)
pages:
    @echo "Serving docs/ at http://localhost:8000"
    cd docs && python3 -m http.server 8000

# Serve GitHub Pages on a custom port
pages-port port="8080":
    @echo "Serving docs/ at http://localhost:{{port}}"
    cd docs && python3 -m http.server {{port}}

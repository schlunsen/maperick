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

# Serve GitHub Pages locally (requires Python 3)
pages:
    @echo "Serving docs/ at http://localhost:8000"
    cd docs && python3 -m http.server 8000

# Serve GitHub Pages on a custom port
pages-port port="8080":
    @echo "Serving docs/ at http://localhost:{{port}}"
    cd docs && python3 -m http.server {{port}}

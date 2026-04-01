# Maperick — development commands

# Default: list available commands
default:
    @just --list

# Build the Rust binary in release mode
build:
    cargo build --release

# Run maperick with enhanced graphics
run path="mmdbs/GeoLite2-City.mmdb":
    cargo run -- -e -p {{path}}

# Serve GitHub Pages locally (requires Python 3)
pages:
    @echo "Serving docs/ at http://localhost:8000"
    cd docs && python3 -m http.server 8000

# Serve GitHub Pages on a custom port
pages-port port="8080":
    @echo "Serving docs/ at http://localhost:{{port}}"
    cd docs && python3 -m http.server {{port}}

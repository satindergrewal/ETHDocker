#!/bin/bash
# Manual update script for ETH Docker stack
# Usage: ./update.sh [geth_version geth_commit] [lighthouse_version]
#
# Examples:
#   ./update.sh                          # Rebuilds all local images with current versions
#   ./update.sh --geth 1.17.4 abc12345   # Update Geth to specific version
#   ./update.sh --lighthouse 8.2.0       # Update Lighthouse to specific version

set -euo pipefail

COMPOSE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$COMPOSE_DIR"

echo "=== ETH Docker Stack Updater ==="
echo ""

# Show current state
echo "Current containers:"
docker compose ps
echo ""

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --geth)
            NEW_GETH_VERSION="$2"
            NEW_GETH_COMMIT="$3"
            echo "Updating Geth to version ${NEW_GETH_VERSION} (${NEW_GETH_COMMIT})..."
            sed -i.bak "s/^ARG GETH_VERSION=.*/ARG GETH_VERSION=${NEW_GETH_VERSION}/" geth/Dockerfile
            sed -i.bak "s/^ARG GETH_COMMIT=.*/ARG GETH_COMMIT=${NEW_GETH_COMMIT}/" geth/Dockerfile
            rm -f geth/Dockerfile.bak
            echo "NOTE: Update SHA256 checksums in geth/Dockerfile for the new version!"
            echo ""
            shift 3
            ;;
        --lighthouse)
            NEW_LH_VERSION="$2"
            echo "Updating Lighthouse to version ${NEW_LH_VERSION}..."
            sed -i.bak "s/^ARG LIGHTHOUSE_VERSION=.*/ARG LIGHTHOUSE_VERSION=${NEW_LH_VERSION}/" lighthouse/Dockerfile
            rm -f lighthouse/Dockerfile.bak
            echo "NOTE: Update SHA256 checksums in lighthouse/Dockerfile for the new version!"
            echo ""
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--geth VERSION COMMIT] [--lighthouse VERSION]"
            exit 1
            ;;
    esac
done

# Rebuild local images and recreate all containers
echo "Rebuilding local images (Geth, Lighthouse, Tor) and recreating containers..."
echo "(Chain data is preserved — no re-sync)"
echo ""
docker compose build --no-cache
docker compose up -d --remove-orphans
echo ""

# Show running status
echo "=== Stack Status ==="
docker compose ps
echo ""

echo "Update complete. Monitor logs with:"
echo "  ./eth.sh logs"

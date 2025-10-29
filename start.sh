#!/bin/bash
# VibeDeploy startup script
# Works on macOS and Linux (including WSL2)

set -e

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🚀 Starting VibeDeploy..."
echo ""

# Detect OS
OS="unknown"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    echo "📍 Detected: Linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="mac"
    echo "📍 Detected: macOS"
fi
echo ""

# Check Docker
echo "Checking Docker..."
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ ERROR: Docker Desktop is not running!${NC}"
    echo "Please start Docker Desktop first."
    exit 1
fi
echo -e "${GREEN}✅ Docker Desktop is running${NC}"
echo ""

sleep 1

# Check if cloudflared tunnel is running
if ! pgrep -f "cloudflared tunnel" > /dev/null; then
    echo "Starting Cloudflare Tunnel..."
    nohup cloudflared tunnel run vibe-deploy > /tmp/cloudflared.log 2>&1 &
    sleep 2
    if pgrep -f "cloudflared tunnel" > /dev/null; then
        echo -e "${GREEN}✅ Tunnel started${NC}"
    else
        echo -e "${RED}❌ Failed to start Cloudflare Tunnel${NC}"
        echo "Check /tmp/cloudflared.log for errors"
        exit 1
    fi
else
    echo -e "${GREEN}✅ Tunnel already running${NC}"
fi
echo ""

# Start Docker services
echo "Starting Docker services..."
cd "$SCRIPT_DIR"
docker compose up -d

sleep 2
echo -e "${GREEN}✅ Docker services started${NC}"
echo ""

# Show status
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ VibeDeploy is running!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Running Services:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo -e "${YELLOW}🌐 URLs:${NC}"
echo "  - Webhook endpoint: https://deploy.tomtom.fyi/webhook"
echo ""

echo -e "${YELLOW}🔧 Logs:${NC}"
echo "  - Caddy: docker logs -f caddy"
echo "  - Webhook: docker logs -f vibe-deploy-webhook"
echo "  - Tunnel: tail -f /tmp/cloudflared.log"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

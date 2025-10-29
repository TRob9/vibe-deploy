#!/bin/bash
# VibeDeploy Startup Script (Caddy Edition)
# Simpler, more explicit configuration - no Docker label magic!

set -e

DEPLOYMENTS_DIR="$HOME/Projects/vibe-deploy/deployments"
DOMAIN="tomtom.fyi"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🚀 Starting VibeDeploy (Caddy Edition)..."
echo ""

# 0. Check Docker
echo "Checking Docker..."
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ ERROR: Docker Desktop is not running!${NC}"
    echo "Please start Docker Desktop first."
    exit 1
fi
echo -e "${GREEN}✅ Docker Desktop is running${NC}"
echo ""

sleep 2

# 1. Start Cloudflare Tunnel
echo "Starting Cloudflare Tunnel..."
if pgrep -f "cloudflared tunnel" > /dev/null; then
    echo -e "${GREEN}✅ Cloudflare Tunnel already running${NC}"
else
    nohup cloudflared tunnel run vibe-deploy > /tmp/cloudflared.log 2>&1 &
    sleep 2
    if pgrep -f "cloudflared tunnel" > /dev/null; then
        echo -e "${GREEN}✅ Cloudflare Tunnel started${NC}"
    else
        echo -e "${RED}❌ Failed to start Cloudflare Tunnel${NC}"
        exit 1
    fi
fi
echo ""

# 2. Start Docker Compose (Caddy + Webhook)
echo "Starting Caddy and Webhook service..."
cd ~/Projects/vibe-deploy
docker compose up -d
sleep 3
echo -e "${GREEN}✅ Caddy and Webhook service started${NC}"
echo ""

# 3. Deploy sites from deployments folder
echo "Deploying sites..."
echo ""

DEPLOYED_SITES=()

if [ ! -d "$DEPLOYMENTS_DIR" ]; then
    echo -e "${RED}❌ Deployments directory not found${NC}"
    exit 1
fi

for PROJECT_DIR in "$DEPLOYMENTS_DIR"/*/ ; do
    if [ ! -d "$PROJECT_DIR" ]; then
        continue
    fi

    PROJECT_NAME=$(basename "$PROJECT_DIR")

    if [[ "$PROJECT_NAME" == .* ]]; then
        continue
    fi

    echo -e "${BLUE}📦 Deploying: $PROJECT_NAME${NC}"

    # Detect app type
    APP_TYPE="static"
    IMAGE_NAME="nginx:alpine"
    PORT="80"

    if [ -f "$PROJECT_DIR/go.mod" ]; then
        APP_TYPE="go"
        IMAGE_NAME="vibe-deploy-$PROJECT_NAME:latest"
        PORT="8080"
    elif [ -f "$PROJECT_DIR/package.json" ]; then
        APP_TYPE="node"
        IMAGE_NAME="vibe-deploy-$PROJECT_NAME:latest"
        PORT="3000"
    elif [ -f "$PROJECT_DIR/requirements.txt" ]; then
        APP_TYPE="python"
        IMAGE_NAME="vibe-deploy-$PROJECT_NAME:latest"
        PORT="8000"
    fi

    # Stop existing container
    docker stop "$PROJECT_NAME" 2>/dev/null || true
    docker rm "$PROJECT_NAME" 2>/dev/null || true

    # Deploy based on app type
    if [ "$APP_TYPE" = "static" ]; then
        # Static site: NO LABELS! Just network name.
        docker run -d \
            --name "$PROJECT_NAME" \
            --network vibe-deploy_web \
            -v "$PROJECT_DIR:/usr/share/nginx/html:ro" \
            nginx:alpine > /dev/null

        echo -e "${GREEN}   ✅ Deployed as static site${NC}"
    else
        # Dynamic app
        echo "   🔨 Building..."

        if [ ! -f "$PROJECT_DIR/Dockerfile" ]; then
            echo "   ⚠️  No Dockerfile, creating one..."
            # Create temporary Dockerfile logic here if needed
        fi

        docker build -t "$IMAGE_NAME" "$PROJECT_DIR" > /dev/null 2>&1

        if [ $? -ne 0 ]; then
            echo -e "${RED}   ❌ Build failed${NC}"
            continue
        fi

        docker run -d \
            --name "$PROJECT_NAME" \
            --network vibe-deploy_web \
            "$IMAGE_NAME" > /dev/null

        echo -e "${GREEN}   ✅ Deployed as $APP_TYPE app${NC}"
    fi

    # Add to sites.yaml if not exists
    SITES_YAML="$HOME/Projects/vibe-deploy/sites.yaml"
    HOSTNAME="$PROJECT_NAME.$DOMAIN"

    if ! grep -q "$HOSTNAME" "$SITES_YAML" 2>/dev/null; then
        cat >> "$SITES_YAML" <<EOF

  $HOSTNAME:
    container: $PROJECT_NAME
    port: $PORT
    type: $APP_TYPE
EOF
        echo -e "${YELLOW}   + Added to sites.yaml${NC}"
    fi

    DEPLOYED_SITES+=("$PROJECT_NAME")
    echo ""
done

# 4. Generate Caddyfile and reload
echo "Updating Caddy configuration..."
bash ~/Projects/vibe-deploy/generate-caddy-config.sh
echo ""

# Show status
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ VibeDeploy (Caddy Edition) is operational!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Running Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
echo ""

if [ ${#DEPLOYED_SITES[@]} -gt 0 ]; then
    echo -e "${YELLOW}📍 Deployed Sites:${NC}"
    for site in "${DEPLOYED_SITES[@]}"; do
        echo -e "   ${GREEN}✓${NC} $site → https://$site.$DOMAIN"
    done
    echo ""
fi

echo -e "${YELLOW}🔧 System:${NC}"
echo -e "   ${GREEN}✓${NC} Webhook → https://deploy.$DOMAIN/webhook"
echo -e "   ${GREEN}✓${NC} Routing → Explicit Caddyfile (no Docker labels!)"
echo ""

echo -e "${YELLOW}🌐 Cloudflare Tunnel:${NC}"
if pgrep -f "cloudflared tunnel" > /dev/null; then
    echo -e "   ${GREEN}✓${NC} Running (PID: $(pgrep -f 'cloudflared tunnel'))"
else
    echo -e "   ${RED}✗${NC} Not running"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "All services ready! 🎉"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

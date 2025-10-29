#!/bin/bash
# VibeDeploy Site Archival Script
# Stops container, removes it, and moves site to ~/Projects for archival

set -e

DEPLOYMENTS_DIR="$HOME/Projects/vibe-deploy/deployments"
ARCHIVE_DIR="$HOME/Projects"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}    VibeDeploy Site Archival Tool${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Get list of deployed sites
cd "$DEPLOYMENTS_DIR"
SITES=($(ls -d */ 2>/dev/null | sed 's#/##'))

if [ ${#SITES[@]} -eq 0 ]; then
    echo -e "${RED}No deployed sites found in $DEPLOYMENTS_DIR${NC}"
    exit 1
fi

# Display sites
echo -e "${YELLOW}Deployed Sites:${NC}"
echo ""
for i in "${!SITES[@]}"; do
    SITE="${SITES[$i]}"
    # Check if container is running
    if docker ps -q -f name="^${SITE}$" > /dev/null 2>&1; then
        STATUS="${GREEN}[RUNNING]${NC}"
    elif docker ps -aq -f name="^${SITE}$" > /dev/null 2>&1; then
        STATUS="${YELLOW}[STOPPED]${NC}"
    else
        STATUS="${RED}[NO CONTAINER]${NC}"
    fi
    echo -e "  $((i+1)). ${BLUE}${SITE}${NC} ${STATUS}"
done

echo ""
echo -e "${YELLOW}Select a site to archive (or 0 to cancel):${NC}"
read -p "> " SELECTION

# Validate input
if ! [[ "$SELECTION" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Invalid selection. Must be a number.${NC}"
    exit 1
fi

if [ "$SELECTION" -eq 0 ]; then
    echo -e "${YELLOW}Cancelled.${NC}"
    exit 0
fi

if [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt ${#SITES[@]} ]; then
    echo -e "${RED}Invalid selection. Must be between 1 and ${#SITES[@]}.${NC}"
    exit 1
fi

SITE="${SITES[$((SELECTION-1))]}"

echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}You selected: ${BLUE}${SITE}${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo ""
echo "This will:"
echo "  1. Stop and remove the Docker container"
echo "  2. Move the site from deployments/ to ~/Projects/"
echo "  3. Optionally remove the GitHub webhook"
echo ""
echo -e "${RED}WARNING: The site will go offline immediately!${NC}"
echo ""
read -p "Continue? (y/N): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cancelled.${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Starting archival process...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Step 1: Stop container
echo -e "${YELLOW}[1/4]${NC} Stopping container..."
if docker stop "$SITE" > /dev/null 2>&1; then
    echo -e "${GREEN}   ✓ Container stopped${NC}"
else
    echo -e "${YELLOW}   ⚠ Container was not running${NC}"
fi

# Step 2: Remove container
echo -e "${YELLOW}[2/4]${NC} Removing container..."
if docker rm "$SITE" > /dev/null 2>&1; then
    echo -e "${GREEN}   ✓ Container removed${NC}"
else
    echo -e "${YELLOW}   ⚠ Container did not exist${NC}"
fi

# Step 3: Move directory
echo -e "${YELLOW}[3/4]${NC} Moving site to ~/Projects/..."
DESTINATION="$ARCHIVE_DIR/$SITE"

if [ -d "$DESTINATION" ]; then
    echo -e "${RED}   ✗ Destination already exists: $DESTINATION${NC}"
    echo -e "${YELLOW}   Creating backup name...${NC}"
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    DESTINATION="$ARCHIVE_DIR/${SITE}-archived-${TIMESTAMP}"
fi

# Use docker to move the directory (to handle root-owned files)
docker run --rm -v "$DEPLOYMENTS_DIR:/deployments" -v "$ARCHIVE_DIR:/archive" alpine sh -c "mv /deployments/$SITE /archive/$(basename $DESTINATION)"

# Fix ownership to current user
docker run --rm -v "$DESTINATION:/site" alpine chown -R $(id -u):$(id -g) /site

echo -e "${GREEN}   ✓ Moved to: $DESTINATION${NC}"

# Step 4: Ask about webhook
echo -e "${YELLOW}[4/4]${NC} GitHub webhook removal..."
echo ""
read -p "   Remove GitHub webhook for this site? (y/N): " REMOVE_WEBHOOK

if [[ "$REMOVE_WEBHOOK" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}   Checking for webhooks...${NC}"

    # Try to get GitHub repo info from git remote
    if [ -d "$DESTINATION/.git" ]; then
        cd "$DESTINATION"
        REPO_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")

        if [[ "$REPO_URL" =~ github.com[:/]([^/]+)/([^/.]+) ]]; then
            REPO_OWNER="${BASH_REMATCH[1]}"
            REPO_NAME="${BASH_REMATCH[2]}"

            echo -e "${YELLOW}   Found repo: ${REPO_OWNER}/${REPO_NAME}${NC}"

            # Get webhooks
            HOOKS=$(gh api "repos/${REPO_OWNER}/${REPO_NAME}/hooks" 2>/dev/null || echo "[]")

            if [ "$HOOKS" != "[]" ]; then
                # Find webhook with deploy.tomtom.fyi URL
                HOOK_ID=$(echo "$HOOKS" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')

                if [ -n "$HOOK_ID" ]; then
                    echo -e "${YELLOW}   Removing webhook (ID: $HOOK_ID)...${NC}"
                    if gh api -X DELETE "repos/${REPO_OWNER}/${REPO_NAME}/hooks/${HOOK_ID}" > /dev/null 2>&1; then
                        echo -e "${GREEN}   ✓ Webhook removed${NC}"
                    else
                        echo -e "${RED}   ✗ Failed to remove webhook${NC}"
                    fi
                else
                    echo -e "${YELLOW}   ⚠ No matching webhook found${NC}"
                fi
            else
                echo -e "${YELLOW}   ⚠ No webhooks found for this repo${NC}"
            fi
        else
            echo -e "${YELLOW}   ⚠ Could not determine GitHub repo from git remote${NC}"
        fi
    else
        echo -e "${YELLOW}   ⚠ Not a git repository, skipping webhook removal${NC}"
    fi
else
    echo -e "${YELLOW}   ⚠ Skipped webhook removal${NC}"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Site archived successfully!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo -e "   Site: ${BLUE}${SITE}${NC}"
echo -e "   Location: ${GREEN}${DESTINATION}${NC}"
echo -e "   Status: ${GREEN}Offline and archived${NC}"
echo ""
echo -e "${YELLOW}To restore this site later:${NC}"
echo "   1. Move it back: mv \"$DESTINATION\" \"$DEPLOYMENTS_DIR/$SITE\""
echo "   2. Run the startup script or push to GitHub to redeploy"
echo ""

# VibeDeploy

**Cross-platform auto-deployment system for websites to `tomtom.fyi` subdomains.**

Works on macOS, Linux, and Windows (via WSL2).

## Architecture

- **Caddy**: Reverse proxy with automatic HTTPS
- **Cloudflare Tunnel**: Secure tunnel exposing services without port forwarding (wildcard `*.tomtom.fyi`)
- **Webhook Service**: Go service that handles GitHub webhooks and deploys sites
- **Docker**: Each site runs in its own container (nginx for static, custom for apps)

## How It Works

1. Push code to any GitHub repo in your account
2. GitHub webhook hits `https://deploy.tomtom.fyi/webhook`
3. Webhook service clones/pulls the repo
4. Deploys site to `https://{repo-name}.tomtom.fyi`
5. Caddy automatically handles routing and SSL certificates

## Prerequisites

### All Platforms

- **Docker Desktop** - [Download](https://www.docker.com/products/docker-desktop/)
  - Must be running before starting VibeDeploy
  - macOS: Install Docker Desktop for Mac
  - Windows: Install Docker Desktop for Windows (with WSL2 backend)
  - Linux: Install Docker Engine and Docker Compose

- **Git** - Version control
  - macOS: `brew install git` or comes with Xcode Command Line Tools
  - Linux/WSL: `sudo apt install git`

- **GitHub CLI** (optional but recommended)
  - macOS: `brew install gh`
  - Linux/WSL: `sudo apt install gh`

### macOS Specific

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install cloudflared via Homebrew
brew install cloudflare/cloudflare/cloudflared

# Install Docker Desktop for Mac
# Download from: https://www.docker.com/products/docker-desktop/
```

### Linux/WSL2 Specific

```bash
# Install cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb

# Or on ARM-based Linux
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
sudo dpkg -i cloudflared-linux-arm64.deb
```

## Installation

### 1. Clone the Repository

```bash
# Choose your location
cd ~/Projects  # or wherever you keep your projects

# Clone the repo
git clone https://github.com/TRob9/vibe-deploy.git
cd vibe-deploy
```

### 2. Configure Cloudflare Tunnel

You need to authenticate and create a tunnel:

```bash
# Login to Cloudflare
cloudflared tunnel login

# Create a tunnel named 'vibe-deploy'
cloudflared tunnel create vibe-deploy

# Configure DNS for your domain (*.tomtom.fyi)
# This should point to your tunnel
```

**Note:** The tunnel configuration should already exist in `~/.cloudflared/`. If you're setting up on a new machine, you'll need to either:
- Copy your existing `~/.cloudflared/` directory from your other machine
- Or create a new tunnel and update the `vibe-deploy` references

### 3. Configure Environment Variables

Create a `.env` file (copy from `.env.example` if provided):

```bash
cp .env.example .env  # if .env.example exists
# OR create .env manually
nano .env
```

Add your configuration:

```env
# Cloudflare Configuration
CLOUDFLARE_API_TOKEN=your_token_here
CLOUDFLARE_ZONE_ID=your_zone_id_here
DOMAIN=tomtom.fyi

# GitHub Configuration (optional)
GITHUB_WEBHOOK_SECRET=

# Email for Let's Encrypt SSL certificates
ACME_EMAIL=your_email@example.com
```

**IMPORTANT:** Never commit your `.env` file to git! It contains secrets.

### 4. Create Docker Network

VibeDeploy requires a specific Docker network:

```bash
docker network create vibe-deploy_web
```

### 5. Start VibeDeploy

```bash
# Make start script executable
chmod +x start.sh

# Start the system
./start.sh
```

The startup script will:
- Detect your OS (macOS or Linux)
- Check if Docker Desktop is running
- Start the Cloudflare Tunnel
- Start Caddy and the webhook service
- Show you the status of all services

## Setting Up Auto-Deploy for a Repository

For each GitHub repo you want to auto-deploy:

1. Go to repo **Settings** → **Webhooks** → **Add webhook**
2. **Payload URL**: `https://deploy.tomtom.fyi/webhook`
3. **Content type**: `application/json`
4. **Events**: Just the push event
5. Click "Add webhook"

Now whenever you push to `main` or `master` branch, your site will auto-deploy!

## Project Structure

```
vibe-deploy/
├── .env                    # Environment variables (DO NOT COMMIT!)
├── .env.example            # Template for .env configuration
├── .gitignore              # Protects secrets
├── docker-compose.yml      # Service definitions (Caddy + Webhook)
├── Caddyfile              # Caddy routing configuration
├── sites.yaml             # Site definitions for routing
├── start.sh               # Quick startup script (core services only)
├── start-full.sh          # Full startup with site deployment
├── generate-caddy-config.sh # Regenerate Caddy config from sites.yaml
├── archive-site.sh        # Archive old sites
├── windows-shortcuts/     # Windows .bat shortcuts for WSL users
│   ├── Start-VibeDeploy.bat
│   ├── Start-VibeDeploy-Full.bat
│   └── Archive-Site.bat
├── webhook-service/       # Go webhook receiver
│   ├── main.go
│   ├── Dockerfile
│   └── go.mod
└── deployments/           # Deployed sites live here
    ├── site1/
    ├── site2/
    └── ...
```

## Supported App Types

VibeDeploy auto-detects your app type and deploys accordingly:

- **Static sites** (HTML/CSS/JS) - Uses nginx
- **Go apps** (has `go.mod`) - Builds and runs on port 8080
- **Node.js apps** (has `package.json`) - Builds and runs on port 3000
- **Python apps** (has `requirements.txt`) - Runs on port 8000

## Usage

### Starting the System

**Quick Start (core services only):**
```bash
cd ~/Projects/vibe-deploy
./start.sh
```

**Full Start (deploy all sites from deployments/ folder):**
```bash
cd ~/Projects/vibe-deploy
./start-full.sh
```

Use the quick start for daily use, and the full start after rebooting or when you need to redeploy all sites.

### Stopping the System

```bash
# Stop Docker services
docker compose down

# Stop Cloudflare Tunnel
pkill -f "cloudflared tunnel"
```

### Viewing Logs

```bash
# Caddy logs
docker logs -f caddy

# Webhook service logs
docker logs -f vibe-deploy-webhook

# Cloudflare Tunnel logs
tail -f /tmp/cloudflared.log

# Individual site logs
docker logs -f <site-name>
```

### Manual Deployment (Testing)

To manually deploy a site without GitHub webhook:

```bash
# 1. Clone repo
cd ~/Projects/vibe-deploy/deployments
git clone https://github.com/yourusername/your-site.git

# 2. Deploy container (static site example)
docker run -d \
  --name your-site \
  --network vibe-deploy_web \
  -v $(pwd)/your-site:/usr/share/nginx/html:ro \
  nginx:alpine

# 3. Add to sites.yaml
echo "
  your-site.tomtom.fyi:
    container: your-site
    port: 80
    type: static" >> ~/Projects/vibe-deploy/sites.yaml

# 4. Regenerate Caddyfile and reload
cd ~/Projects/vibe-deploy
./generate-caddy-config.sh
```

### Updating a Site

Just push to GitHub! The webhook will handle everything.

Or manually:

```bash
# Navigate to the deployment
cd ~/Projects/vibe-deploy/deployments/your-site

# Pull latest changes
git pull

# Restart the container
docker restart your-site
```

## Platform-Specific Notes

### macOS

- Cloudflare Tunnel logs: `/tmp/cloudflared.log`
- Docker runs in a VM, so performance is slightly different than Linux
- Use `brew services` to manage cloudflared as a service (optional)
- `pgrep` and standard Unix tools work out of the box

### Windows (WSL2)

- Run everything inside WSL2 Ubuntu
- Docker Desktop must have WSL2 integration enabled
- Windows files are accessible at `/mnt/c/Users/...`
- Your WSL home directory is separate from Windows home
- Cloudflare Tunnel runs inside WSL2

**Windows Desktop Shortcuts:**

For convenience, you can create Windows shortcuts to control VibeDeploy:

```cmd
# Copy the .bat files from the repo to your Desktop
# (Do this in PowerShell or File Explorer)

# From File Explorer:
# Navigate to: \\wsl$\Ubuntu\home\YOUR_USERNAME\Projects\vibe-deploy\windows-shortcuts\
# Copy the .bat files to your Desktop

# Then double-click them from Windows to:
# - Start-VibeDeploy.bat: Quick start (just core services)
# - Start-VibeDeploy-Full.bat: Start + deploy all sites from deployments/
# - Archive-Site.bat: Archive a deployed site interactively
```

### Linux (Native)

- Direct Docker access (no VM overhead)
- Can use systemd to manage cloudflared as a service
- Best performance for Docker containers

## Troubleshooting

### Docker Desktop Not Running

```
❌ ERROR: Docker Desktop is not running!
```

**Solution:** Start Docker Desktop and wait for it to fully initialize (green icon in menu bar/system tray).

### Cloudflare Tunnel Won't Start

```
❌ Failed to start Cloudflare Tunnel
```

**Solutions:**
1. Check if you're authenticated: `cloudflared tunnel list`
2. Check tunnel exists: `cloudflared tunnel info vibe-deploy`
3. View logs: `tail -f /tmp/cloudflared.log`
4. Re-authenticate: `cloudflared tunnel login`

### Site Not Accessible

**Check the checklist:**
1. Is Docker running? `docker ps`
2. Is the site container running? `docker ps | grep your-site`
3. Is Caddy running? `docker ps | grep caddy`
4. Is Cloudflare Tunnel running? `pgrep -f cloudflared`
5. Is the site in sites.yaml? `cat sites.yaml | grep your-site`
6. Test locally: `curl -H "Host: your-site.tomtom.fyi" http://localhost/`

### Webhook Not Triggering

1. Check webhook service logs: `docker logs -f vibe-deploy-webhook`
2. Verify GitHub webhook is configured correctly
3. Check webhook delivery in GitHub repo settings
4. Test webhook endpoint: `curl https://deploy.tomtom.fyi/webhook`

### DNS Issues

**"Site not accessible on phone/external devices"**

Common causes:
1. **DNS cache** - Toggle airplane mode or wait 5-10 minutes
2. **Browser cache** - Hard refresh (Cmd/Ctrl+Shift+R) or use incognito
3. **WWW prefix** - VibeDeploy supports both `site.tomtom.fyi` and `www.site.tomtom.fyi`
4. **DNS propagation** - Can take up to 24 hours (unlikely with Cloudflare)

Verify external access:
```bash
curl -s -o /dev/null -w "%{http_code}" https://your-site.tomtom.fyi
# Should return: 200
```

### File Permission Issues

Deployed files may be owned by root (from git operations in Docker container).

**Solution:**
```bash
sudo chown -R $(whoami):$(whoami) ~/Projects/vibe-deploy/deployments/your-site
```

## Advanced Configuration

### Auto-Start on Boot

#### macOS (using launchd)

Create `~/Library/LaunchAgents/com.vibe-deploy.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vibe-deploy</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/YOUR_USERNAME/Projects/vibe-deploy/start.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/vibe-deploy.err</string>
    <key>StandardOutPath</key>
    <string>/tmp/vibe-deploy.out</string>
</dict>
</plist>
```

Then:
```bash
launchctl load ~/Library/LaunchAgents/com.vibe-deploy.plist
```

#### Linux (using systemd)

Create `/etc/systemd/system/vibe-deploy.service`:

```ini
[Unit]
Description=VibeDeploy Auto-Deployment System
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=YOUR_USERNAME
ExecStart=/home/YOUR_USERNAME/Projects/vibe-deploy/start.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Then:
```bash
sudo systemctl enable vibe-deploy
sudo systemctl start vibe-deploy
```

### Using a Custom Domain

1. Update `.env` file with your domain
2. Update Cloudflare Tunnel configuration
3. Update `sites.yaml` with new domain
4. Regenerate Caddyfile: `./generate-caddy-config.sh`

## Contributing

This is a personal deployment system, but feel free to fork and adapt for your own use!

## License

MIT License - Use freely for your own projects.

## Support

For issues or questions:
- Check the troubleshooting section above
- Review Docker logs: `docker logs caddy` and `docker logs vibe-deploy-webhook`
- Check Cloudflare Tunnel logs: `tail -f /tmp/cloudflared.log`

---

**Created:** October 2025
**Platform:** macOS, Linux, Windows (WSL2)
**Status:** ✅ Production Ready

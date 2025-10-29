#!/bin/bash
# Generate Caddyfile from sites.yaml
# Usage: ./generate-caddy-config.sh

set -e

SITES_YAML="sites.yaml"
OUTPUT="Caddyfile"

echo "Generating Caddyfile from $SITES_YAML..."

# Start with header
cat > "$OUTPUT" <<EOF
# Auto-generated Caddyfile for VibeDeploy
# DO NOT EDIT MANUALLY - Edit sites.yaml and regenerate

{
    # Global options
    admin off  # Disable admin API for security
    auto_https off  # Cloudflare Tunnel handles HTTPS
    log {
        output file /var/log/caddy/access.log
        format json
    }
}

EOF

# Parse sites.yaml and generate Caddy blocks
# This is a simple parser - for production you might want to use yq
awk '
/^  [a-z].*:$/ {
    # Extract domain (remove trailing colon)
    domain = $1
    gsub(/:/, "", domain)
    getline; container = $2
    getline; port = $2

    # Generate Caddy block with http:// prefix
    print ""
    print "# " toupper(substr(domain, 1, 1)) substr(domain, 2)
    print "http://" domain ", http://www." domain " {"
    print "    reverse_proxy " container ":" port
    print "}"
}
' "$SITES_YAML" >> "$OUTPUT"

echo "✓ Generated $OUTPUT"

# Reload Caddy if running (restart since admin API is disabled)
if docker ps | grep -q caddy; then
    echo "Reloading Caddy..."
    docker restart caddy
    echo "✓ Caddy restarted"
fi

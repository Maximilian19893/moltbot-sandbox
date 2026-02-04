#!/bin/bash
# Deploy script that loads CLOUDFLARE_API_TOKEN from .dev.vars

# Load token from .dev.vars
if [ -f .dev.vars ]; then
    export $(grep -E '^CLOUDFLARE_API_TOKEN=' .dev.vars | xargs)
fi

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo "Error: CLOUDFLARE_API_TOKEN not found in .dev.vars"
    echo "Add this line to .dev.vars:"
    echo "  CLOUDFLARE_API_TOKEN=your-token-here"
    exit 1
fi

echo "Deploying with API token..."
npm run deploy

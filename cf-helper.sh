#!/bin/bash
# Cloudflare Helper Script
# Lädt Token aus .dev.vars und führt Cloudflare-Operationen aus

# Load token
if [ -f .dev.vars ]; then
    export $(grep -E '^CLOUDFLARE_API_TOKEN=' .dev.vars | xargs)
fi

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo "Error: CLOUDFLARE_API_TOKEN not found"
    exit 1
fi

ACCOUNT_ID="400a279f1ab4f609e371acb8a8fe60d0"
WORKER_NAME="moltbot-sandbox"

case "$1" in
    logs)
        echo "Starting live logs (Ctrl+C to stop)..."
        npx wrangler tail --format pretty
        ;;
    deploy)
        echo "Deploying..."
        npm run deploy
        ;;
    secrets)
        echo "Listing secrets..."
        npx wrangler secret list
        ;;
    status)
        echo "Checking worker status..."
        curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/services/$WORKER_NAME" \
            | npx -y json
        ;;
    trigger)
        echo "Triggering worker request..."
        curl -s -o /dev/null -w "HTTP Status: %{http_code}\nTime: %{time_total}s\n" \
            "https://moltbot-sandbox.max-400.workers.dev/debug/version"
        ;;
    *)
        echo "Usage: bash cf-helper.sh [command]"
        echo ""
        echo "Commands:"
        echo "  logs     - Live worker logs"
        echo "  deploy   - Deploy worker"
        echo "  secrets  - List secrets"
        echo "  status   - Worker status"
        echo "  trigger  - Trigger a request"
        ;;
esac

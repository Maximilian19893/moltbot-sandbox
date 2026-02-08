# Agent Instructions

Guidelines for AI agents working on this codebase.

## Project Overview

This is a Cloudflare Worker that runs [OpenClaw](https://github.com/openclaw/openclaw) (formerly Moltbot/Clawdbot) in a Cloudflare Sandbox container. It provides:
- Proxying to the OpenClaw gateway (web UI + WebSocket)
- Admin UI at `/_admin/` for device management
- API endpoints at `/api/*` for device pairing
- Debug endpoints at `/debug/*` for troubleshooting

**Upstream repo:** [cloudflare/moltworker](https://github.com/cloudflare/moltworker) — check regularly for updates.

**Note:** The CLI tool is now named `openclaw`. Container env vars use `OPENCLAW_*` prefix (e.g., `OPENCLAW_GATEWAY_TOKEN`, `OPENCLAW_DEV_MODE`). The Worker-facing env vars still use `MOLTBOT_GATEWAY_TOKEN` and `DEV_MODE` for backward compatibility.

## Project Structure

```
src/
├── index.ts # Main Hono app, route mounting
├── types.ts # TypeScript type definitions
├── config.ts # Constants (ports, timeouts, paths)
├── auth/ # Cloudflare Access authentication
│ ├── jwt.ts # JWT verification
│ ├── jwks.ts # JWKS fetching and caching
│ └── middleware.ts # Hono middleware for auth
├── gateway/ # OpenClaw gateway management
│ ├── process.ts # Process lifecycle (find, start)
│ ├── env.ts # Environment variable building
│ ├── r2.ts # R2 bucket mounting
│ ├── sync.ts # R2 backup sync logic
│ └── utils.ts # Shared utilities (waitForProcess)
├── routes/ # API route handlers
│ ├── api.ts # /api/* endpoints (devices, gateway)
│ ├── admin.ts # /_admin/* static file serving
│ └── debug.ts # /debug/* endpoints
└── client/ # React admin UI (Vite)
 ├── App.tsx
 ├── api.ts # API client
 └── pages/
```

## Key Patterns

### Environment Variables

- `DEV_MODE` - Skips CF Access auth AND bypasses device pairing (maps to `OPENCLAW_DEV_MODE` for container)
- `DEBUG_ROUTES` - Enables `/debug/*` routes (disabled by default)
- `CLAUDE_SETUP_TOKEN` - Custom addition: enables Claude Max/Pro subscription auth
- See `src/types.ts` for full `MoltbotEnv` interface

### CLI Commands

When calling the OpenClaw CLI from the worker, include `--url ws://localhost:18789` and `--token`:
```typescript
const tokenArg = token ? ` --token ${token}` : '';
sandbox.startProcess(`openclaw devices list --json --url ws://localhost:18789${tokenArg}`)
```

CLI commands take 10-15 seconds due to WebSocket connection overhead. Use `waitForProcess()` helper.

### Success Detection

The CLI outputs "Approved" (capital A). Use case-insensitive checks:
```typescript
stdout.toLowerCase().includes('approved')
```

## Commands

```bash
npm test # Run tests (vitest)
npm run test:watch # Run tests in watch mode
npm run build # Build worker + client
npm run deploy # Build and deploy to Cloudflare
npm run dev # Vite dev server
npm run start # wrangler dev (local worker)
npm run typecheck # TypeScript check
```

## Testing

Tests use Vitest. Test files are colocated with source files (`*.test.ts`).

Current test coverage:
- `auth/jwt.test.ts` - JWT decoding and validation
- `auth/middleware.test.ts` - Auth middleware behavior
- `gateway/env.test.ts` - Environment variable building
- `gateway/process.test.ts` - Process finding logic (with legacy compat)
- `gateway/r2.test.ts` - R2 mounting logic
- `gateway/sync.test.ts` - R2 sync logic (uses exitCode, not stdout)

When adding new functionality, add corresponding tests.

## Code Style

- Use TypeScript strict mode
- Prefer explicit types over inference for function signatures
- Keep route handlers thin - extract logic to separate modules
- Use Hono's context methods (`c.json()`, `c.html()`) for responses

---

## Architecture

```
Browser
 │
 ▼
┌─────────────────────────────────────┐
│ Cloudflare Worker (index.ts) │
│ - Starts OpenClaw in sandbox │
│ - Proxies HTTP/WebSocket requests │
│ - Injects gateway token for WS │
│ - Passes secrets as env vars │
└──────────────┬──────────────────────┘
 │
 ▼
┌─────────────────────────────────────┐
│ Cloudflare Sandbox Container │
│ ┌───────────────────────────────┐ │
│ │ OpenClaw Gateway │ │
│ │ - Control UI on port 18789 │ │
│ │ - WebSocket RPC protocol │ │
│ │ - Agent runtime │ │
│ └───────────────────────────────┘ │
└─────────────────────────────────────┘
```

### Key Files

| File | Purpose |
|------|---------|
| `src/index.ts` | Worker that manages sandbox lifecycle and proxies requests |
| `Dockerfile` | Container image based on `cloudflare/sandbox` with Node 22 + OpenClaw |
| `start-openclaw.sh` | Startup script: restores R2, runs `openclaw onboard`, patches config, starts gateway |
| `wrangler.jsonc` | Cloudflare Worker + Container configuration |

## Custom Additions (Not in Upstream)

This repo has custom additions not found in the upstream `cloudflare/moltworker`:

### CLAUDE_SETUP_TOKEN
Enables Claude Max/Pro subscription auth via setup-token (alternative to API key):
- `src/types.ts` - Added to `MoltbotEnv` interface
- `src/gateway/env.ts` - Passed to container
- `src/index.ts` - Accepted as valid auth in `validateRequiredEnv`
- `start-openclaw.sh` - Injected via `openclaw models auth paste-token` or manual `auth-profiles.json`

### GitHub Actions Deploy
- `.github/workflows/deploy.yml` - CI/CD pipeline for automated deployments

## Local Development

```bash
npm install
cp .dev.vars.example .dev.vars
# Edit .dev.vars with your API key or setup-token
npm run start
```

### WebSocket Limitations

Local development with `wrangler dev` has issues proxying WebSocket connections through the sandbox. HTTP requests work but WebSocket connections may fail. Deploy to Cloudflare for full functionality.

## Docker Image Caching

The Dockerfile includes a cache bust comment. When changing `start-openclaw.sh` or skills, bump the version:

```dockerfile
# Build cache bust: 2026-02-08-v30-upgrade-to-openclaw
```

## Gateway Configuration

OpenClaw configuration is built at container startup:

1. R2 backup restored (with migration from legacy `clawdbot/` to `openclaw/` prefix)
2. `openclaw onboard --non-interactive` creates initial config (if no config exists)
3. Node.js config patch adds channels, gateway auth, trusted proxies, AI Gateway model
4. `CLAUDE_SETUP_TOKEN` injected for subscription auth (if set)
5. Gateway starts with `--allow-unconfigured` flag

### Container Environment Variables

These are the env vars passed TO the container:

| Worker Env Var | Container Env Var | Notes |
|---|---|---|
| `ANTHROPIC_API_KEY` | `ANTHROPIC_API_KEY` | Direct pass-through |
| `OPENAI_API_KEY` | `OPENAI_API_KEY` | Direct pass-through |
| `CLOUDFLARE_AI_GATEWAY_API_KEY` | `CLOUDFLARE_AI_GATEWAY_API_KEY` | AI Gateway key |
| `CF_AI_GATEWAY_ACCOUNT_ID` | `CF_AI_GATEWAY_ACCOUNT_ID` | AI Gateway account |
| `CF_AI_GATEWAY_GATEWAY_ID` | `CF_AI_GATEWAY_GATEWAY_ID` | AI Gateway ID |
| `CF_AI_GATEWAY_MODEL` | `CF_AI_GATEWAY_MODEL` | Model override `provider/model-id` |
| `CLAUDE_SETUP_TOKEN` | `CLAUDE_SETUP_TOKEN` | Custom: subscription auth |
| `MOLTBOT_GATEWAY_TOKEN` | `OPENCLAW_GATEWAY_TOKEN` | Renamed for container |
| `DEV_MODE` | `OPENCLAW_DEV_MODE` | Renamed for container |
| `TELEGRAM_BOT_TOKEN` | `TELEGRAM_BOT_TOKEN` | Direct |
| `SLACK_BOT_TOKEN` | `SLACK_BOT_TOKEN` | Direct |
| `SLACK_APP_TOKEN` | `SLACK_APP_TOKEN` | Direct |
| `CF_ACCOUNT_ID` | `CF_ACCOUNT_ID` | For R2 + Workers AI |
| `CDP_SECRET` | `CDP_SECRET` | Browser rendering |
| `WORKER_URL` | `WORKER_URL` | Public worker URL |

## R2 Storage Notes

R2 is mounted via s3fs at `/data/moltbot`. Important gotchas:

- **rsync compatibility**: Use `rsync -r --no-times` instead of `rsync -a`. s3fs doesn't support setting timestamps.
- **R2 prefix migration**: Sync always writes to `openclaw/` prefix. On restore, checks `openclaw/` first, then falls back to legacy `clawdbot/`.
- **Cron guard**: Cron sync skips if gateway hasn't started yet (prevents race condition).
- **Exit code checks**: Use `exitCode` instead of stdout parsing to verify file existence (avoids log-flush races).
- **Never delete R2 data**: The mount directory `/data/moltbot` IS the R2 bucket.

## Common Tasks

### Adding a New API Endpoint

1. Add route handler in `src/routes/api.ts`
2. Add types if needed in `src/types.ts`
3. Update client API in `src/client/api.ts` if frontend needs it
4. Add tests

### Adding a New Environment Variable

1. Add to `MoltbotEnv` interface in `src/types.ts`
2. If passed to container, add to `buildEnvVars()` in `src/gateway/env.ts`
3. Update `.dev.vars.example`
4. Document in README.md secrets table

### Syncing with Upstream

```bash
# Check latest upstream changes
git remote add upstream https://github.com/cloudflare/moltworker.git 2>/dev/null
git fetch upstream
git log upstream/main --oneline -10
```

Key files to check for upstream changes:
- `start-openclaw.sh` - Startup logic
- `src/gateway/sync.ts` - R2 sync logic
- `src/gateway/env.ts` - Env var mapping
- `Dockerfile` - OpenClaw version and dependencies

### Debugging

```bash
# View live logs
npx wrangler tail

# Check secrets
npx wrangler secret list
```

Enable debug routes with `DEBUG_ROUTES=true` and check `/debug/processes`.

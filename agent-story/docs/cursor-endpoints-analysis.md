# Cursor / Agent Story Endpoint Analysis

Generated: 2026-07-05T22:20:43.610Z
Total captured interactions: **93**

## Hosts

- `api2.cursor.sh` — 50 requests
- `api3.cursor.sh` — 30 requests
- `westus2-0.in.applicationinsights.azure.com` — 3 requests
- `mcp.context7.com` — 2 requests
- `marketplace.cursorapi.com` — 2 requests
- `cursor.com` — 2 requests
- `registry.npmjs.org` — 2 requests
- `workoscdn.com` — 1 requests
- `metrics.cursor.sh` — 1 requests

## Categories

- **telemetry** — 31
- **auth** — 24
- **agent** — 20
- **other** — 8
- **updates** — 4
- **extensions** — 4
- **billing** — 2

## Endpoints (by volume)

| Count | Method | Path | Category | Hosts | Status codes |
|------:|--------|------|----------|-------|--------------|
| 30 | POST | `/tev1/v1/rgstr` | telemetry | api3.cursor.sh | 202:30 |
| 22 | GET | `/auth/full_stripe_profile` | auth | api2.cursor.sh | 200:22 |
| 20 | POST | `/aiserver.v1.OnlineMetricsService/ReportAgentSnapshot` | agent | api2.cursor.sh | 200:20 |
| 8 | CONNECT | `/` | other | mcp.context7.com, registry.npmjs.org, westus2-0.in.applicationinsights.azure.com, workoscdn.com | 0:8 |
| 4 | GET | `/updates/api/update/win32-x64-user/cursor/3.9.16/909ab2a165df0ee7dc0be2380187c4107e543d4565a8d37038200da94b47252c/stable` | updates | api2.cursor.sh | 204:4 |
| 2 | GET | `/extensions-control` | extensions | api2.cursor.sh | 200:2 |
| 2 | OPTIONS | `/auth/full_stripe_profile` | auth | api2.cursor.sh | 204:2 |
| 1 | POST | `/_apis/public/gallery/extensionquery` | extensions | marketplace.cursorapi.com | 200:1 |
| 1 | POST | `/api/dashboard/get-current-period-usage` | billing | cursor.com | 200:1 |
| 1 | GET | `/api/usage-summary` | billing | cursor.com | 200:1 |
| 1 | OPTIONS | `/_apis/public/gallery/extensionquery` | extensions | marketplace.cursorapi.com | 204:1 |
| 1 | POST | `/api/4508016051945472/envelope/` | telemetry | metrics.cursor.sh | 200:1 |

## Capture policy

- MITM + full body capture: Cursor domains (`*.cursor.sh`, `*.cursor.com`, `*.cursorapi.com`) and configured AI provider domains.
- Direct tunnel (no body capture): hosts in Chromium `--proxy-bypass-list` / Node `NO_PROXY` (localhost, Git hosts).
- All captured traffic is forwarded immediately; persistence runs asynchronously after response end.
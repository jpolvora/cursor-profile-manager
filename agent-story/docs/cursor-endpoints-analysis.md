# Cursor / Agent Story Endpoint Analysis

Generated: 2026-07-05T22:05:57.972Z
Total captured interactions: **25**

## Hosts

- `api2.cursor.sh` — 16 requests
- `api3.cursor.sh` — 8 requests
- `westus2-0.in.applicationinsights.azure.com` — 1 requests

## Categories

- **auth** — 9
- **telemetry** — 8
- **agent** — 6
- **updates** — 1
- **other** — 1

## Endpoints (by volume)

| Count | Method | Path | Category | Hosts | Status codes |
|------:|--------|------|----------|-------|--------------|
| 9 | GET | `/auth/full_stripe_profile` | auth | api2.cursor.sh | 200:9 |
| 8 | POST | `/tev1/v1/rgstr` | telemetry | api3.cursor.sh | 202:8 |
| 6 | POST | `/aiserver.v1.OnlineMetricsService/ReportAgentSnapshot` | agent | api2.cursor.sh | 200:6 |
| 1 | GET | `/updates/api/update/win32-x64-user/cursor/3.9.16/909ab2a165df0ee7dc0be2380187c4107e543d4565a8d37038200da94b47252c/stable` | updates | api2.cursor.sh | 204:1 |
| 1 | CONNECT | `/` | other | westus2-0.in.applicationinsights.azure.com | 0:1 |

## Capture policy

- MITM + full body capture: Cursor domains (`*.cursor.sh`, `*.cursor.com`, `*.cursorapi.com`) and configured AI provider domains.
- Direct tunnel (no body capture): hosts in Chromium `--proxy-bypass-list` / Node `NO_PROXY` (localhost, Git hosts).
- All captured traffic is forwarded immediately; persistence runs asynchronously after response end.
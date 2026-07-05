# Pass-Through Proxy Traffic Analysis

Generated: 2026-07-05T22:31:52.019Z
Total logged events: **13**

## Event kinds

- **connect** — 13

## Host capture policy (vs default MITM)

| Policy | Meaning | Host hits |
|--------|---------|----------:|
| default_mitm | Host is in default Agent Story MITM list | 9 |
| not_in_default_mitm | Seen through pass-through but **not** MITM-captured by default | 4 |
| expected_bypass | localhost / loopback | 0 |

## Hosts (by volume)

- `api2.cursor.sh` — 4 (default_mitm)
- `mcp.context7.com` — 2 (not_in_default_mitm)
- `cursor.com` — 2 (default_mitm)
- `metrics.cursor.sh` — 1 (default_mitm)
- `api3.cursor.sh` — 1 (default_mitm)
- `marketplace.cursorapi.com` — 1 (default_mitm)
- `workoscdn.com` — 1 (not_in_default_mitm)
- `github.com` — 1 (not_in_default_mitm)

## Discovery: hosts not in default MITM

- `mcp.context7.com` — 2 events
- `github.com` — 1 events
- `workoscdn.com` — 1 events

## Categories

- **other** — 12
- **extensions** — 1

## Endpoints (by volume)

| Count | Kind | Method | Host | Path | Category | Default MITM? |
|------:|------|--------|------|------|----------|---------------|
| 4 | connect | CONNECT | api2.cursor.sh | `/` | other | yes |
| 2 | connect | CONNECT | mcp.context7.com | `/` | other | no |
| 2 | connect | CONNECT | cursor.com | `/` | other | yes |
| 1 | connect | CONNECT | metrics.cursor.sh | `/` | other | yes |
| 1 | connect | CONNECT | api3.cursor.sh | `/` | other | yes |
| 1 | connect | CONNECT | marketplace.cursorapi.com | `/` | extensions | yes |
| 1 | connect | CONNECT | workoscdn.com | `/` | other | no |
| 1 | connect | CONNECT | github.com | `/` | other | no |

## Default MITM domain suffixes

- `.cursor.sh`
- `.cursor.com`
- `cursor.com`
- `cursor.sh`
- `.cursorapi.com`
- `cursorapi.com`

## Notes

- Pass-through proxy logs CONNECT hostnames and plain HTTP metadata without decrypting TLS.
- Compare **not_in_default_mitm** hosts here against missing chat/agent traffic in the SQLite capture DB.
- Re-run with `npm run analyze-pass-through-log` after using an **Alternative** proxied profile.
# Agent Story - Specification

## 1. Overview
Agent Story is a developer tool designed to intercept, record, and visualize interactions (chats, history, and prompts) from the Cursor IDE's AI agents. It acts as a proxy, capturing the raw data exchanged between Cursor and its backend, saving it to a local database, and providing a web interface to query and read these interactions in a formatted manner (pretty-print, code highlighting, markdown).

## 2. Core Features
- **Traffic Interception**: An HTTPS proxy that Cursor connects through. It decrypts, inspects, and forwards the AI-related traffic.
- **Data Persistence**: A database to store intercepted requests and responses, grouped by conversation or session.
- **Search & Query**: Ability to filter and search through historical prompts and responses.
- **Rich Visualization**: A Web UI that renders the intercepted data using markdown parsing, syntax highlighting for code blocks, and clear conversation threads.

## 3. Architecture (MVP)
- **Proxy Layer**: A local Node.js MITM (Man-In-The-Middle) proxy. It will require generating a local Certificate Authority (CA) and telling Cursor to trust it (or disabling certificate errors).
- **Database Layer**: SQLite, chosen for being simple, local, and zero-configuration.
- **Visualization Layer**: A local web application (e.g., Next.js or Vite + React) that reads from the SQLite database and renders the UI with `react-markdown`.

## 4. Open Questions & Gaps
To finalize this specification, several technical details must be validated:
- How does Cursor handle its API traffic? Can it be easily proxied via `HTTP_PROXY` or does it require injecting arguments like `--proxy-server` and `--ignore-certificate-errors`?
- Cursor's API payload format: We need to reverse-engineer the JSON payloads to correctly group messages into "conversations".
- What specific endpoints does Cursor use for its chat and agent features? (e.g., `api2.cursor.sh`).

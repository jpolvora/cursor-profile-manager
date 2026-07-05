<div align="center">
  <h1>📖 Agent Story</h1>
  <p><strong>Intercept, Record, and Visualize Cursor IDE AI Interactions</strong></p>
  
  [![Node.js](https://img.shields.io/badge/Node.js-18+-success?logo=node.js&logoColor=white)](#)
  [![React](https://img.shields.io/badge/React-Vite-blue?logo=react&logoColor=white)](#)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](#)
</div>

---

**Agent Story** is a developer tool designed to act as a Man-In-The-Middle (MITM) proxy for the Cursor IDE. It intercepts the raw AI traffic (chats, history, and prompts), records the JSON payloads in a local database, and provides a beautiful web interface to query, read, and visualize these interactions.

*Original objective: criar um proxy para cursor ide que intercepta os chats/historicos/prompts de agent, registrar e agrupar num banco de dados, permitir consultas, com visualização formatada pretty-print / codigo / markdown etc.*

## ✨ Features

- **🛡️ MITM Proxy Engine**: A local Node.js HTTPS proxy that seamlessly sits between Cursor and its API backend to capture traffic.
- **💾 Local Persistence**: Uses SQLite (`better-sqlite3`) for fast, zero-configuration storage of raw JSON requests and responses.
- **🎨 Beautiful Dashboard**: A stunning, modern web interface built with React and Vite. It features real-time polling, markdown rendering, and syntax highlighting for intercepted prompts.
- **🔍 Deep Inspection**: View exact headers, status codes, and payloads sent and received by the AI agents.

## 🏗️ Architecture

The project is split into two main components:

- `server/`: The backend Node.js application. It runs the `http-mitm-proxy`, manages the SQLite database (`agent-story.db`), and exposes a lightweight Express REST API for the frontend.
- `ui/`: The frontend React application bootstrapped with Vite. Uses `lucide-react` for iconography and `react-markdown` for rendering chat payloads.

---

## 🚀 Getting Started

> **Embedded in Cursor Profile Manager:** when using this repo as `cursor-profile-manager/agent-story/`, start/stop the proxy and UI from the manager toolbar (**Start Agent Story**). For standalone development, use the steps below.

### Prerequisites

- [Node.js](https://nodejs.org/) (v18 or higher)
- npm or yarn

### 1. Start the Backend Proxy

The proxy intercepts HTTPS traffic on port `8080` and exposes the REST API on port `3001`.

```bash
cd server
npm install
node index.js
```

### 2. Start the React Dashboard

The frontend UI runs on port `5173`.

```bash
cd ui
npm install
npm run dev
```

Open your browser and navigate to `http://localhost:5173`.

---

## 🕵️‍♂️ Usage: Intercepting Cursor Traffic

To capture Cursor's AI traffic, you must instruct the Cursor application to route its network requests through our local MITM proxy and ignore self-signed certificate errors.

Launch Cursor from your terminal (or create a custom shortcut) using the following arguments:

```bash
cursor --proxy-server="http://127.0.0.1:8080" --ignore-certificate-errors
```

**Workflow:**
1. Keep both the Agent Story `server` and `ui` running.
2. Launch Cursor with the proxy arguments above.
3. Open a file in Cursor and interact with the AI (Cmd/Ctrl + K, or the Chat pane).
4. Watch the raw JSON payloads appear instantly in your Agent Story dashboard!

---

## 🗺️ Roadmap

- [ ] Reverse-engineer Cursor's exact JSON thread schema.
- [ ] Parse and group individual messages into continuous conversation threads in the UI.
- [ ] Add full-text search capabilities across historical prompts.
- [ ] Export captured interactions to Markdown/JSON files.
- [ ] Generate standard SSL Root CA to avoid needing `--ignore-certificate-errors`.

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the issues page or submit a Pull Request.

## 📄 License

This project is licensed under the MIT License.

#!/usr/bin/env bash
# install-hook.sh — Install pre-commit hook for secrets leak detection
# Usage: bash .agents/skills/secrets-leak-review/scripts/install-hook.sh
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || { echo "Not a git repository"; exit 1; })
HOOK_SRC="$REPO_ROOT/.agents/skills/secrets-leak-review/scripts/pre-commit.sh"
HOOK_DST="$REPO_ROOT/.git/hooks/pre-commit"

if [ ! -f "$HOOK_SRC" ]; then
  echo "Error: $HOOK_SRC not found"
  exit 1
fi

# If a hook already exists, back it up
if [ -f "$HOOK_DST" ] && [ ! -L "$HOOK_DST" ]; then
  BACKUP="${HOOK_DST}.bak.$(date +%Y%m%d-%H%M%S)"
  echo "Backing up existing hook to $BACKUP"
  cp "$HOOK_DST" "$BACKUP"
fi

# Symlink (works on Linux/macOS; on Windows use copy)
if ln -sf "../../.agents/skills/secrets-leak-review/scripts/pre-commit.sh" "$HOOK_DST" 2>/dev/null; then
  echo "Installed pre-commit hook (symlink): $HOOK_DST"
else
  # Fallback for Windows
  cp "$HOOK_SRC" "$HOOK_DST"
  chmod +x "$HOOK_DST"
  echo "Installed pre-commit hook (copy): $HOOK_DST"
fi

echo "Done. Pre-commit secrets scan active."

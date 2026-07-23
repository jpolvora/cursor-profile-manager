#!/usr/bin/env bash
# pre-commit.sh — Secrets leak check for git pre-commit hook
# Install: ln -s ../../.agents/skills/secrets-leak-review/scripts/pre-commit.sh .git/hooks/pre-commit
# Or: bash .agents/skills/secrets-leak-review/scripts/install-hook.sh
set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || exit 1)
cd "$REPO_ROOT"

SCANNER="$REPO_ROOT/.agents/skills/secrets-leak-review/scripts/secrets_scanner.sh"

# Only scan staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)
if [ -z "$STAGED_FILES" ]; then
  exit 0
fi

if [ ! -f "$SCANNER" ]; then
  echo -e "${YELLOW}[secrets-leak] Scanner not found at $SCANNER, skipping${NC}"
  exit 0
fi

# Staged-only + hard cap so the hook always finishes
export GIT_STAGED_ONLY=1
export SECRETS_SCAN_MAX_HITS="${SECRETS_SCAN_MAX_HITS:-30}"

# Capture scanner output (scanner exits 0; never block forever on full-tree rg)
SCAN_OUTPUT=$(bash "$SCANNER" 2>&1 || true)

# Check for HIGH findings
if echo "$SCAN_OUTPUT" | rg -q 'HIGH.*must fix'; then
  echo ""
  echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║       SECRETS LEAK DETECTED — COMMIT BLOCKED    ║${NC}"
  echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
  echo ""
  echo "$SCAN_OUTPUT"
  echo ""
  echo -e "${RED}Fix HIGH findings above, or use --no-verify to override.${NC}"
  exit 1
fi

# Warn on MEDIUM
if echo "$SCAN_OUTPUT" | rg -q 'MEDIUM'; then
  echo ""
  echo -e "${YELLOW}[secrets-leak] Medium-severity findings detected:${NC}"
  echo "$SCAN_OUTPUT" | rg 'MEDIUM' -A 10 || true
  echo ""
  echo -e "${YELLOW}Review recommended. Commit proceeding.${NC}"
fi

exit 0

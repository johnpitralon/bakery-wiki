#!/usr/bin/env bash
# One-time repo setup. Run once after cloning:
#   ./setup.sh
set -euo pipefail
cd "$(dirname "$0")"
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/post-commit 2>/dev/null || true
chmod +x scripts/*.sh 2>/dev/null || true
echo "✓ core.hooksPath = .githooks (path guard + auto-push)"

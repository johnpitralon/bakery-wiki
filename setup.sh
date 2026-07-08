#!/usr/bin/env bash
# One-time repo setup. Run once after cloning:
#   ./setup.sh
set -euo pipefail
cd "$(dirname "$0")"
git config core.hooksPath .githooks
echo "✓ core.hooksPath = .githooks (wiki path guard aktivní)"

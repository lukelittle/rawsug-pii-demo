#!/usr/bin/env bash
# The demo GUI: one local page, opened in your browser.
#   scripts/gui.sh          live: requests are signed with your AWS credentials
#   scripts/gui.sh --mock   rehearse with no AWS; the page is labelled MOCK
set -euo pipefail
cd "$(dirname "$0")/.."
exec "$(command -v python3 || command -v python)" gui/server.py "$@"

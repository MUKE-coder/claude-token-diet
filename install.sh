#!/usr/bin/env bash
# Install the token-diet skill without the plugin system.
#   ./install.sh            -> personal (~/.claude/skills/token-diet), all projects
#   ./install.sh --project  -> this repo only (./.claude/skills/token-diet), run from the target repo
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)/skills/token-diet"
if [ "${1:-}" = "--project" ]; then DEST="$PWD/.claude/skills/token-diet"; else DEST="$HOME/.claude/skills/token-diet"; fi
mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
chmod +x "$DEST"/scripts/*.sh "$DEST"/scripts/*.py
command -v python3 >/dev/null || command -v python >/dev/null || echo "WARNING: no python3/python found on PATH — token-diet scripts and hooks need Python 3."
echo "Installed token-diet -> $DEST"
echo "Open Claude Code in your big repo and say: run token-diet   (or type /token-diet)"

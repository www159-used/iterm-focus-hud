#!/usr/bin/env bash
# Run this inside an attached iTerm/Zellij client (ww session workbench).
# CLI new-tab from Cursor agent currently creates empty ghost tabs on this machine.
set -euo pipefail
exec /Users/ww/Documents/skills/worktree/create-worktree/scripts/create_wt_tab.py \
  --session ww \
  --name iterm-focus-hud \
  --cwd /Users/ww/Documents/self/iterm-focus-hud \
  --no-continue \
  "$@"

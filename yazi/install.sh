#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$dir/../lib/link.sh"

link "$dir/yazi.toml" "$HOME/.config/yazi/yazi.toml"
report_missing \
  "yazi:brew install yazi" \
  "fd:brew install fd, for searching by name" \
  "rg:brew install ripgrep, for searching by content"

# yazi opens every file type without a terminal viewer in $EDITOR. An EDITOR set by hand wins.
if ! grep -qE '^export (EDITOR|VISUAL)=' "$HOME/.zshrc" 2>/dev/null; then
  printf '\n# --wait keeps the program that opened the file waiting until its tab is closed.\nexport EDITOR="code --wait"\nexport VISUAL="code --wait"\n' >> "$HOME/.zshrc"
  echo "Set EDITOR and VISUAL to VS Code in ~/.zshrc"
fi

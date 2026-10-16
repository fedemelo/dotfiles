#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$dir/../lib/link.sh"

link "$dir/config.toml" "$HOME/.config/herdr/config.toml"
link_bin "$dir/bin"

report_missing \
  "herdr:see https://herdr.dev" \
  "jq:brew install jq" \
  "fzf:brew install fzf" \
  "glow:brew install glow" \
  "tdf:brew install tdf" \
  "uv:brew install uv" \
  "vd:uv tool install visidata --with pyarrow --with openpyxl" \
  "harlequin:uv tool install 'harlequin[postgres]'" \
  "code:in VS Code, run Shell Command: Install 'code' command in PATH"

# The Markdown viewer's e and r keys need less --lesskey-src, which macOS's own less 581 lacks.
less_major="$(less --version | awk 'NR == 1 { print int($2) }')"
[ "$less_major" -ge 582 ] || echo "Missing: less 582 or later (brew install less)"

command -v herdr >/dev/null 2>&1 || exit 0
herdr config check
herdr server reload-config >/dev/null 2>&1 || echo "Herdr is not running; it reads the config when it starts"

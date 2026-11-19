#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$dir/../lib/link.sh"

user_dir="$HOME/Library/Application Support/Code/User"
link "$dir/settings.json" "$user_dir/settings.json"
link "$dir/keybindings.json" "$user_dir/keybindings.json"

report_missing "code:install VS Code, then run Shell Command: Install 'code' command in PATH"
command -v code >/dev/null 2>&1 || exit 0

# Extension IDs are case-insensitive, and the Marketplace shows them capitalized.
# In the message, {} stands for the extension's ID.
report_unlisted() {
  local listed="$1" wanted="$2" message="$3" extension
  while read -r extension; do
    echo "$listed" | grep -qixF "$extension" || echo "${message//\{\}/$extension}"
  done < "$wanted"
}

report_unlisted "$(code --list-extensions)" "$dir/extensions.txt" \
  "Missing: VS Code extension {} (code --install-extension {})"

# VS Code keeps the extensions disabled for all workspaces in its state database, not in settings.json.
disabled="$(sqlite3 "$user_dir/globalStorage/state.vscdb" \
  "select value from ItemTable where key = 'extensionsIdentifiers/disabled'" 2>/dev/null |
  grep -oE '"id": ?"[^"]+"' | cut -d'"' -f4 || true)"
report_unlisted "$disabled" "$dir/disabled-extensions.txt" \
  "Enabled: VS Code extension {} (in VS Code, choose Disable on it, then Enable (Workspace) where it's needed)"

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
installed="$(code --list-extensions)"
while read -r extension; do
  echo "$installed" | grep -qixF "$extension" ||
    echo "Missing: VS Code extension $extension (code --install-extension $extension)"
done < "$dir/extensions.txt"

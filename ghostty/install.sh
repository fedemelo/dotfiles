#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$dir/../lib/link.sh"

link "$dir/config" "$HOME/.config/ghostty/config"

# Herdr shows images, like tdf's PDF pages, only inside a terminal with Kitty graphics. macOS's
# Terminal.app has none and prints them as garbage. The cask puts no ghostty command on PATH.
[ -d /Applications/Ghostty.app ] || echo "Missing: Ghostty (brew install --cask ghostty), the terminal to run Herdr in"

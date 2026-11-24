#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$dir/../lib/link.sh"

link "$dir/init.lua" "$HOME/.hammerspoon/init.lua"
link "$dir/dictation.lua" "$HOME/.hammerspoon/dictation.lua"
report_missing \
  "hs:brew install --cask hammerspoon" \
  "rec:brew install sox" \
  "whisper-cli:brew install whisper.cpp"

models_dir="$HOME$(sed -n 's|^local modelsDir = home \.\. "\(.*\)"$|\1|p' "$dir/dictation.lua")"
for url in $(grep -oE 'https://[^"]+\.bin' "$dir/dictation.lua"); do
  path="$models_dir/${url##*/}"
  [ -f "$path" ] || echo "Missing: $path (curl -fL --create-dirs -o $path $url)"
done

# Its first launch registers it to start at login. After that it reloads itself when its Lua changes.
if [ -d /Applications/Hammerspoon.app ] && ! pgrep -xq Hammerspoon; then
  open -g -a Hammerspoon
fi

#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$dir/../lib/link.sh"

link "$dir/init.lua" "$HOME/.hammerspoon/init.lua"
link "$dir/dictation.lua" "$HOME/.hammerspoon/dictation.lua"
link "$dir/words.txt" "$HOME/.config/dictation/words.txt"
report_missing \
  "hs:brew install --cask hammerspoon" \
  "rec:brew install sox" \
  "whisper-cli:brew install whisper.cpp"

model_url() {
  case "$1" in
    ggml-silero-*) echo "https://huggingface.co/ggml-org/whisper-vad/resolve/main/$1" ;;
    *) echo "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$1" ;;
  esac
}

for model in $(grep -oE '/[^"]*ggml-[^"]*\.bin' "$dir/dictation.lua"); do
  path="$HOME$model"
  [ -f "$path" ] || echo "Missing: $path (curl -fL --create-dirs -o $path $(model_url "${model##*/}"))"
done

# Its first launch registers it to start at login. After that it reloads itself when its Lua changes.
if [ -d /Applications/Hammerspoon.app ] && ! pgrep -xq Hammerspoon; then
  open -g -a Hammerspoon
fi

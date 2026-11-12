#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$dir/../lib/link.sh"

link "$dir/init.lua" "$HOME/.hammerspoon/init.lua"
link "$dir/dictation.lua" "$HOME/.hammerspoon/dictation.lua"
report_missing \
  "hs:brew install --cask hammerspoon" \
  "rec:brew install sox" \
  "whisper-cli:brew install whisper-cpp"

models_url="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
for model in $(grep -oE '/[^"]*ggml-[^"]*\.bin' "$dir/dictation.lua"); do
  path="$HOME$model"
  [ -f "$path" ] || echo "Missing: $path (curl -fL --create-dirs -o $path $models_url/${model##*/})"
done

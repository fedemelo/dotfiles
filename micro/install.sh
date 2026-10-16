#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$dir/../lib/link.sh"

link "$dir/settings.json" "$HOME/.config/micro/settings.json"
report_missing "micro:brew install micro"

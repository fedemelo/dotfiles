# Sourced by each component's install.sh.

# A file already at the target is backed up only the first time, when the link replaces it.
# After that the target is this repo's link, so re-runs have nothing to back up. An existing
# backup is never overwritten.
link() {
  local source="$1" target="$2"
  mkdir -p "$(dirname "$target")"
  [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ] && return
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ -e "$target.bak" ] || [ -L "$target.bak" ]; then
      echo "FAILED: $target needs a backup, but $target.bak already exists. Move one of them." >&2
      exit 1
    fi
    mv "$target" "$target.bak"
    echo "Backed up $target to $target.bak"
  fi
  ln -s "$source" "$target"
  echo "Linked $target -> $source"
}

# ~/.local/bin is shared with other tools, so only dangling links that point into this
# directory are pruned: scripts renamed or removed here.
link_bin() {
  local dir="$1" bin="$HOME/.local/bin" entry
  mkdir -p "$bin"
  for entry in "$bin"/*; do
    if [ -L "$entry" ] && [ ! -e "$entry" ]; then
      case "$(readlink "$entry")" in
        "$dir"/*) rm "$entry"; echo "Pruned stale link $entry" ;;
      esac
    fi
  done
  for entry in "$dir"/*; do
    link "$entry" "$bin/$(basename "$entry")"
  done
}

# Each argument is "<command>:<how to install it>". Installing is left to the user.
report_missing() {
  local entry
  for entry in "$@"; do
    command -v "${entry%%:*}" >/dev/null 2>&1 || echo "Missing: ${entry%%:*} (${entry#*:})"
  done
}

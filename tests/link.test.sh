#!/usr/bin/env bash
# Tests lib/link.sh against a sandboxed HOME.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

pass=0; fail=0

check() {
  if [ "$2" = "$3" ]; then printf '  PASS %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL %s\n       got:  %s\n       want: %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

new_box() {
  box="$(mktemp -d "$ROOT/box.XXXXXX")"
  mkdir -p "$box/home" "$box/src"
  echo ours > "$box/src/file"
}

# Each call is its own process, as each component's install.sh is.
in_box() { HOME="$box/home" bash -c '. "$1"; shift; "$@"' _ "$repo_root/lib/link.sh" "$@" 2>&1; }

echo "=== link: nothing at the target ==="
new_box
out="$(in_box link "$box/src/file" "$box/home/.config/x/file")"
check "links it, creating the parent directory" "$(readlink "$box/home/.config/x/file")" "$box/src/file"
check "no backup" "$(test -e "$box/home/.config/x/file.bak" && echo present || echo absent)" "absent"

echo "=== link: a real file at the target is backed up once ==="
new_box
echo theirs > "$box/home/file"
in_box link "$box/src/file" "$box/home/file" >/dev/null
check "linked" "$(readlink "$box/home/file")" "$box/src/file"
check "the old file is the backup" "$(cat "$box/home/file.bak")" "theirs"
out="$(in_box link "$box/src/file" "$box/home/file")"
check "a re-run prints nothing" "$out" ""
check "and keeps the one backup" "$(cat "$box/home/file.bak")" "theirs"

echo "=== link: an existing backup is never overwritten ==="
new_box
echo theirs > "$box/home/file"
echo older > "$box/home/file.bak"
out="$(in_box link "$box/src/file" "$box/home/file")"; status=$?
check "fails" "$status" "1"
check "says which" "$(echo "$out" | grep -c "file.bak already exists")" "1"
check "the file is left alone" "$(cat "$box/home/file")" "theirs"
check "and so is the backup" "$(cat "$box/home/file.bak")" "older"

echo "=== link_bin: links each script and prunes only its own dangling links ==="
new_box
mkdir -p "$box/src/bin" "$box/home/.local/bin" "$box/other"
echo a > "$box/src/bin/kept"
ln -s "$box/src/bin/removed" "$box/home/.local/bin/removed"
ln -s "$box/other/gone" "$box/home/.local/bin/not-ours"
in_box link_bin "$box/src/bin" >/dev/null
check "links the script" "$(readlink "$box/home/.local/bin/kept")" "$box/src/bin/kept"
check "prunes a dangling link into the directory" \
  "$(test -L "$box/home/.local/bin/removed" && echo present || echo absent)" "absent"
check "leaves a dangling link from elsewhere" \
  "$(test -L "$box/home/.local/bin/not-ours" && echo present || echo absent)" "present"

echo "=== report_missing ==="
new_box
out="$(in_box report_missing "sh:never shown" "no-such-command-here:brew install it")"
check "reports only the missing command, with its hint" "$out" "Missing: no-such-command-here (brew install it)"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

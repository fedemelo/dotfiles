# dotfiles

Implementation notes for agents working on this repo. `README.md` is for humans and stays short. This file covers how the repo is built, so you can work on it without reading every file.

## Layout

- `install`: the entry point. Installs each component in order.
- `lib/link.sh`: helpers that every component's `install.sh` sources: `link`, `link_bin`, `report_missing`.
- `micro/`, `yazi/`, `herdr/`: one directory per local component, each with its own `install.sh`.
- `tests/install.test.sh`, `tests/link.test.sh`: the suites. CI runs every `tests/*.test.sh` on macOS.

## install

`components` in `install` lists every component in install order: `git-tools agent-config micro yazi herdr`. Each may depend on the ones before it. The skills in agent-config call flags that only a current `git-land` has, so git-tools goes first.

A component is one of two kinds:
- **A separate repo**, listed in `separate_repos`: git-tools and agent-config. It's cloned into `~/code/personal/<name>` from `https://github.com/fedemelo/<name>` if missing, else updated, and then its own `install.sh` runs. These repos must keep working on their own, so nothing here may change them or assume they live inside dotfiles. Plain clones, never submodules or subtrees.
- **A directory here**: everything else. Its `install.sh` runs; a component without one is skipped with a message.

Updating a repo stops the whole run, leaving that repo untouched, when it has uncommitted changes, has no upstream, has commits its remote lacks, or can't fast-forward. Each means someone was working there, and pulling over that is not the script's decision. A failed installer also stops the run. Nothing after the stop is installed.

`--only <component>`, repeatable, limits the run to those components. The install order still applies.

`DOTFILES_CODE_DIR`, `DOTFILES_REMOTE_BASE`, `DOTFILES_SHARE_DIR` and `DOTFILES_MANAGED_DIR` override the clone directory, the remote and the pod signals. They exist for the tests.

## Devspaces pods

`install` refuses to run in a devspaces pod. It checks the same three signals as agent-config's `install.sh`: `/mnt/personal`, `/etc/claude-code` and a `devspaces` executable, all present. It checks first, because git-tools' installer runs before agent-config's gets to refuse, and it sets `core.hooksPath` globally, which conflicts with pod policy. The pod procedure is agent-config's `skills/wire-up/targets/devspaces.md`.

The repo has no `install.sh` at its root on purpose. A pod runs the first of `install.sh`, `bootstrap.sh` or `setup.sh` it finds in `/mnt/personal/dotfiles/` at every start, and that is a different script.

## lib/link.sh

- `link <source> <target>`: symlinks the target to the source. A file already at the target is moved to `<target>.bak` the first time. After that the target is this repo's link, so re-runs back up nothing. If a `.bak` already exists, it fails rather than overwrite it.
- `link_bin <dir>`: links every file in `<dir>` into `~/.local/bin`, and prunes dangling links there that point into `<dir>`. Links from elsewhere are left alone, since other tools install there too.
- `report_missing "<command>:<how to install>" ...`: prints a line for each missing command. Components never install programs: the user chose to install them by hand.

## Components

### micro

Links `settings.json` (soft wrap, word wrap) into `~/.config/micro/`. The Markdown viewer edits with micro.

### yazi

Links `yazi.toml` into `~/.config/yazi/`. Enter opens PDFs, tables (`csv tsv parquet xlsx json jsonl`) and Markdown through `herdr-view`, and everything else in `$EDITOR`. Also appends `EDITOR`/`VISUAL="code --wait"` to `~/.zshrc` when it sets neither. Needs `fd` and `ripgrep` for yazi's name and content search.

### herdr

Links `config.toml` into `~/.config/herdr/` and `bin/*` into `~/.local/bin`, then runs `herdr config check` and reloads the server.

- `config.toml` owns the whole Herdr config, including the user's own settings (theme, toasts, status icons). Change them here.
- The prefix is a backtick. Herdr binds exactly one key after the prefix, and `prefix+prefix` is reserved for typing a literal backtick, so the IDE shortcuts can't be a native two-key sequence. Instead `prefix+space` opens a popup running `herdr-ide`, which reads the next key.
- `herdr-ide`: the menu. Its `entries` table holds `key|label|command|pane-or-here`. A lowercase key splits the focused pane to the right and runs the command there with `exec`, so the pane closes when the program quits. Shift+key runs it in the popup itself. A `here` entry, like VS Code, always runs in the popup. Both forms start in the focused pane's directory, read from `herdr pane list`. Popups aren't panes, so the focused pane is still the one under the popup.
- `herdr-view markdown|pdf|table [file]`: opens a file in its viewer, or picks one under the current directory with fzf, newest first, skipping hidden directories and `node_modules`. Markdown is rendered by glow into `less`, not glow's own viewer, where the left arrow means "back to file list". In it, `e` edits in micro and `r` re-renders, through `less --lesskey-src`, which needs less 582 or later (macOS ships 581; Homebrew's works). Tables run VisiData with one Arrow thread, because multithreaded pyarrow can segfault on some parquet files.
- `herdr-job-status`: one line in the tab bar saying whether a background job is running or wrote output recently. It prints nothing until `~/.config/job-status.conf` exists; the script's header documents that file. Per-machine values like this stay out of the repo.

## Adding things

- **A menu letter**: one line in `entries` in `herdr-ide`. Every letter is free, because only `prefix+space` is bound in Herdr. Lowercase opens in a pane and Shift opens in the popup, so a letter covers both.
- **A Herdr binding outside the menu**: check Herdr's defaults first, with `herdr --default-config | grep -oE '"prefix\+[^"]+"'`. Never use `d`: `prefix+shift+d` closes the workspace. Then validate with `XDG_CONFIG_HOME=<dir with herdr/config.toml> herdr config check`.
- **Machine config** (shell, VS Code, ...): a new directory with an `install.sh` that sources `lib/link.sh`, and its name in `components`. A tool with its own repo goes in `separate_repos` instead.
- **A program a component needs**: a `report_missing` entry with its install command.

## Testing

```sh
for t in tests/*.test.sh; do "$t"; done
```

No network. `install.test.sh` runs a copy of `install` with no components beside it, against local stand-in repos and a throwaway `HOME`, so it never installs the real components. `link.test.sh` runs the helpers in a throwaway `HOME`. Everything must run on macOS's bash 3.2.

Neither suite covers the Herdr scripts, which need a live Herdr and the viewers. Test those by hand in a throwaway pane you create and close yourself, never in the user's panes. The keypress itself can't be sent from an agent, so say what you tested instead.

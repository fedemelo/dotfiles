# dotfiles

Notes for agents. `README.md` is for humans and stays short. This file says how to install the repo and how it's built, so you can work on it without reading every file.

## Installing this repo

When asked to install or set up this repo, do all three steps. The human install in the README is step 2 alone; you also go on to agent-config.

1. In a devspaces pod (`/mnt/personal`, `/etc/claude-code` and a `devspaces` executable all present), skip to step 3. `install` refuses to run there.
2. Clone this repo into `~/code/personal/dotfiles` if it isn't there, run `./install`, then install every program it reports as `Missing:` with the command it gives. Run `./install` again and confirm it reports nothing missing. If it stops at a repo or an installer, report its output and stop.
3. Clone [agent-config](https://github.com/fedemelo/agent-config) into `~/code/personal/agent-config` if it isn't there. Then read its `skills/wire-up/SKILL.md` and follow it. That skill covers the rest: git-tools, the pod procedure, and the checks the installers leave to a human. Don't repeat any of it from here.

## Layout

- `install`: the entry point for humans and agents. Installs each component in order.
- `CLAUDE.md`: imports this file, since Claude Code reads `CLAUDE.md` and not `AGENTS.md`.
- `lib/link.sh`: helpers that every component's `install.sh` sources: `link`, `link_bin`, `report_missing`.
- `ghostty/`, `herdr/`: one directory per local component, each with its own `install.sh`.
- `tests/install.test.sh`, `tests/link.test.sh`: the suites. CI runs every `tests/*.test.sh` on macOS.

## install

`components` in `install` lists every component in install order: `git-tools ghostty herdr`. Each may depend on the ones before it.

agent-config is deliberately not a component. Its setup is an agent's job, through its `/wire-up` skill, and anyone using it has an agent. Keeping it out also keeps the dependencies one-way: dotfiles depends on git-tools and agent-config, agent-config depends on git-tools, and neither refers back to dotfiles. Don't add a reference to dotfiles in either repo. The only place that knows git-tools goes before agent-config is `/wire-up`.

A component is one of two kinds:
- **A separate repo**, listed in `separate_repos`: git-tools. It's cloned into `~/code/personal/<name>` from `https://github.com/fedemelo/<name>` if missing, else updated, and then its own `install.sh` runs. Such a repo must keep working on its own, so nothing here may change them or assume they live inside dotfiles. Plain clones, never submodules or subtrees.
- **A directory here**: everything else. Its `install.sh` runs; a component without one is skipped with a message.

Updating a repo stops the whole run, leaving that repo untouched, when it has uncommitted changes, has no upstream, has commits its remote lacks, or can't fast-forward. Each means someone was working there, and pulling over that is not the script's decision. A failed installer also stops the run. Nothing after the stop is installed.

`--only <component>`, repeatable, limits the run to those components. The install order still applies.

`DOTFILES_CODE_DIR`, `DOTFILES_REMOTE_BASE`, `DOTFILES_SHARE_DIR` and `DOTFILES_MANAGED_DIR` override the clone directory, the remote and the pod signals. They exist for the tests.

## Devspaces pods

`install` refuses to run in a devspaces pod. It checks the same three signals as agent-config's `install.sh`: `/mnt/personal`, `/etc/claude-code` and a `devspaces` executable, all present. git-tools' installer has no such check, and it sets `core.hooksPath` globally, which conflicts with pod policy. In a pod, agent-config's `/wire-up` sets up both tool repos its own way.

The repo has no `install.sh` at its root on purpose. A pod runs the first of `install.sh`, `bootstrap.sh` or `setup.sh` it finds in `/mnt/personal/dotfiles/` at every start, and that is a different script.

## lib/link.sh

- `link <source> <target>`: symlinks the target to the source. A file already at the target is moved to `<target>.bak` the first time. After that the target is this repo's link, so re-runs back up nothing. If a `.bak` already exists, it fails rather than overwrite it.
- `link_bin <dir>`: links every file in `<dir>` into `~/.local/bin`, and prunes dangling links there that point into `<dir>`. Links from elsewhere are left alone, since other tools install there too.
- `report_missing "<command>:<how to install>" ...`: prints a line for each missing command. Components never install programs: the user chose to install them by hand.

## Components

### ghostty

Links `config` (the `Retro Legends` theme) into `~/.config/ghostty/`. Ghostty also reads `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`, after this one, so settings there win; on this machine that file is only Ghostty's commented template. It reports Ghostty as missing when `/Applications/Ghostty.app` isn't there: Herdr must run inside a terminal with Kitty graphics to show images such as tdf's PDF pages, and macOS's Terminal.app has none.

### herdr

Links `config.toml` into `~/.config/herdr/` and `bin/*` into `~/.local/bin`, then runs `herdr config check` and reloads the server.

- `config.toml` owns the whole Herdr config, including the user's own settings (theme, toasts, status icons). Change them here.
- The prefix is Herdr's default, `ctrl+b`. The one binding added is `prefix+space`, a popup running `herdr-open`.
- `herdr-open`: a search box over files, starting in the focused pane's directory, read from `herdr pane list`. Popups aren't panes, so the focused pane is still the one under the popup. It lists that directory, then each parent up to home, each sorted by depth, and fzf keeps that order (`--no-sort --exact`) so nearer files always come first; fuzzy scoring buried nearby files under scattered matches from all over home. `~/Library` and `~/Pictures` are skipped, because listing them took 20 seconds. A typed path that exists (`/`, `~`, `.` or `..` at the start) opens as typed, which covers hidden files and directories. Enter splits the focused pane to the right and runs `herdr-view` there with `exec`, so the pane closes when the viewer quits; `ctrl-o` runs it in the popup.
- `herdr-view <path>`: opens a path in the terminal program for its kind: Markdown in glow, PDFs in tdf, tables (`csv tsv parquet xlsx json jsonl`) in VisiData, anything else, directories included, in VS Code. `--kind` prints which of those it would pick, so `herdr-open` can open VS Code files straight from the popup, without a pane. Markdown is rendered by glow into `less`, not glow's own viewer, where the left arrow means "back to file list". In it, `e` edits in VS Code, waiting until its tab closes, and `r` re-renders, through `less --lesskey-src`, which needs less 582 or later (macOS ships 581; Homebrew's works). Tables run VisiData with one Arrow thread, because multithreaded pyarrow can segfault on some parquet files.
- `herdr-job-status`: one line in the tab bar saying whether a background job is running or wrote output recently. It prints nothing until `~/.config/job-status.conf` exists; the script's header documents that file. Per-machine values like this stay out of the repo.

## Adding things

- **A file type with its own viewer**: one case in `herdr-view`.
- **A Herdr binding**: check Herdr's defaults first, with `herdr --default-config | grep -oE '"prefix\+[^"]+"'`. Never use `d`: `prefix+shift+d` closes the workspace. Then validate with `XDG_CONFIG_HOME=<dir with herdr/config.toml> herdr config check`.
- **Machine config** (shell, VS Code, ...): a new directory with an `install.sh` that sources `lib/link.sh`, and its name in `components`. A tool with its own repo goes in `separate_repos` instead.
- **A program a component needs**: a `report_missing` entry with its install command.

## Testing

```sh
for t in tests/*.test.sh; do "$t"; done
```

No network. `install.test.sh` runs a copy of `install` with no components beside it, against local stand-in repos and a throwaway `HOME`, so it never installs the real components. `link.test.sh` runs the helpers in a throwaway `HOME`. Everything must run on macOS's bash 3.2.

Neither suite covers the Herdr scripts, which need a live Herdr and the viewers. Test those by hand in a throwaway pane you create and close yourself, never in the user's panes. The keypress itself can't be sent from an agent, so say what you tested instead.

# dotfiles

Sets up a machine I own with one command. Agents: read [AGENTS.md](AGENTS.md) instead.

```sh
git clone https://github.com/fedemelo/dotfiles ~/code/personal/dotfiles
~/code/personal/dotfiles/install                    # everything
~/code/personal/dotfiles/install --only herdr       # just one part
```

What it sets up:
- [git-tools](https://github.com/fedemelo/git-tools): cloned or pulled into `~/code/personal`, then installed. It stays a separate repo.
- Herdr as a mini IDE. `ctrl+b` `space` opens a search over files, nearest first. Enter opens the file in a pane on the right, `ctrl-o` in the popup. PDFs, Markdown and tables open in terminal viewers, anything else in VS Code.
- Ghostty, the terminal to run Herdr in, since Terminal.app can't show its images.

It never installs programs. It lists the missing ones and how to install each.

Re-running is safe. It stops at a repo with work in progress rather than pull over it, and backs up any file it replaces once, as `<file>.bak`.

To also set up [agent-config](https://github.com/fedemelo/agent-config), clone it and have an agent run its `/wire-up` skill there.

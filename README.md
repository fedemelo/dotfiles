# dotfiles

Sets up a machine I own with one command. Agents: read [AGENTS.md](AGENTS.md) instead.

```sh
git clone https://github.com/fedemelo/dotfiles ~/code/personal/dotfiles
~/code/personal/dotfiles/install                    # everything
~/code/personal/dotfiles/install --only herdr       # just one part
```

What it sets up:
- [git-tools](https://github.com/fedemelo/git-tools): cloned or pulled into `~/code/personal`, then installed. It stays a separate repo.
- Herdr as a mini IDE. The prefix is `` ` ``, and `` ` `` `space` opens a menu: `f` files, `m` Markdown, `p` PDF, `t` tables, `s` SQL, `c` VS Code. A letter opens it in a pane on the right; Shift+letter opens it in a popup.
- yazi and micro, which the Herdr viewers use.

It never installs programs. It lists the missing ones and how to install each.

Re-running is safe. It stops at a repo with work in progress rather than pull over it, and backs up any file it replaces once, as `<file>.bak`.

To also set up [agent-config](https://github.com/fedemelo/agent-config), clone it and have an agent run its `/wire-up` skill there.

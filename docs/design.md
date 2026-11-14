# How rex-file-picker works

This page explains what happens when you pick a file, and why the plugin is built this way. You don't need it to use the plugin; see the [README](../README.md) for that.

## The flow

Three parts of Rex take part when you run an action:

```
 Local Rex server (~/.config/rex/init.lua)
   pick_file / pick_zoxide_dir / pick_file_<profile>
     dir   <- terminal.process (local server, else rex.server(ctx.server)):
              foreground program's cwd, else the pane shell's cwd
     roots <- Lua `roots` functions run here; `cmd` entries stay strings
     session.new_layer on the Rex server that owns the pane
       (interactive = cfg.interactive_shell so ~/.zshrc etc. set PATH):
       sh -c <picker.sh> file-picker <origin> <dir> <rexcli>
             <list.sh> <preview.sh> <done.sh> <mode> <binds> ... <rules> <roots>
                                    |
                                    v
 Pane's host (local Rex server, or remote Rex server via rex.host / rex hosts add)
   picker.sh  (/bin/sh, private temp dir $D removed on exit)
     writes $D/list.sh, $D/preview.sh, $D/done.sh, $D/rules, $D/rootspec
     sh "$D/list.sh" resolve: pwd | path (~ expanded) | cmd (run in dir)
       -> skip missing folders; canonical paths
     sh "$D/list.sh" list: fd/fdfind (or find) per root, or zoxide query -l
       rows: display <TAB> path-to-insert <TAB> absolute-path <TAB> path-relative-to-pane
     fzf --multi (0.38+), list on the left, sh "$D/preview.sh" {3} on the right
       insert / alt-A / alt-R -> become(sh "$D/done.sh" insert {+2}/{+3}/{+4})
                                 -> host `rex send -b <origin>` "<paths>"
       copy   / alt-a / alt-r -> become(sh "$D/done.sh" copy   {+2}/{+3}/{+4})
                                 -> OSC 52 (or host `copy_cmd`)
       ctrl-t / ctrl-z        -> reload(sh "$D/list.sh" toggle-dirs / toggle-zoxide)
     host `rex focus <origin>`; exit closes the floating layer
                                    |
                                    v
 Rex client app
   renders the floating layer (including kitty graphics from kitten icat and mdcat)
   receives OSC 52 and updates the local clipboard
```

- **No plugin files to install on the host; all CLI tools run there.** The shell scripts and settings travel inline as `argv` because `init.lua` on your local Rex server can't write files onto a remote host. Every tool the picker runs — `fzf` 0.38+ (for `become`), `fd`/`fdfind` or `find`, `mdcat`, `glow`, `bat`/`batcat`, `kitten icat`, `tree`, `file`, `zoxide`, root `cmd`s, `copy_cmd`, and `rex` itself — runs on the pane's host.
- **Remote panes mean panes on a remote Rex host.** A pane on a host registered with `rex hosts add` / `rex.host` (over SSH, Tailscale, etc.) belongs to that host's Rex server (`ctx.server`), so `session.new_layer` opens the picker there. Typing plain `ssh` inside a local shell pane does not create a remote Rex pane; that pane stays on the local Rex server.
- **Insert and focus stay on the pane's server.** The origin pane lives on the same Rex server as the picker, so the host's own `rex` CLI (found via `REX_BIN_DIR`, falling back to the local CLI path) runs `rex send -b <origin>` and `rex focus <origin>` with no round trip to the local server. `-b <origin>` is always passed because the focused pane while picking is the picker itself, and `rex focus` is explicit because Rex doesn't restore focus when a floating layer closes.
- **Four columns per row.** `list.sh` prints `display <TAB> path-to-insert <TAB> absolute-path <TAB> path-relative-to-pane`: `{1}` is shown (`--with-nth=1`), `{+2}` follows the root's `path_style` for `insert`/`copy`, `{+3}` is the canonical absolute path (also passed as `{3}` to `preview.sh`), and `{+4}` is relative to the pane's directory, so `alt-A`/`alt-R` and `alt-a`/`alt-r` need no extra pass.
- **Copy uses OSC 52.** Rex forwards OSC 52 from local and remote panes alike to the Rex client app's clipboard. Two details matter: the copy is dropped if the pane closes right after writing it, so `done.sh` sleeps 0.5s before exiting; and a copy written in the very first moment of a new pane can be lost, which an interactive pick never hits.
- **Lua functions run on the local Rex server, commands on the host.** A `roots` function runs in `init.lua` and can branch on `ctx.host` or build from `ctx.pwd`, while a `cmd` root runs on the pane's host in the pane's directory and can inspect its disk.

## Roots and paths

Roots are resolved in order, and each file is kept under the first root whose canonical folder (`cd -P && pwd -P`) contains it, so a pane directory inside a git root lists its files once, as pane-directory rows. Rows from roots other than `pwd` show `[label]` ahead of the path. Inserted paths are relative to the pane's directory (`../` as needed) or absolute, per root.

Inside `$D`, fields are separated by `\037` (US) and lists inside a field by `\036` (RS), never by tabs or spaces: `read` collapses runs of whitespace separators, which would shift empty fields.

## Previews

`preview.sh` walks `$D/rules` in order. The first rule whose pattern matches decides; within it, the first command whose first word is installed on `PATH` runs with the path as `$1`:

- `directory` matches folders (globs and `mime:` patterns never match folders).
- `mime:<pattern>` asks `file --mime-type`, only when a rule needs it.
- A glob with `/` matches the end of the path; any other glob matches the file name.

Default tool chain:

- Folders: `tree -C -L 2`, then `ls -la`.
- Markdown (`*.md`, `*.markdown`): `mdcat --ansi --image-protocol kitty` (with a plain `mdcat --ansi` fallback for older `mdcat` without `--image-protocol`), then `glow -w`, `bat`, `batcat`, `cat`.
- Images (`mime:image/*` and common image extensions): `kitten icat --transfer-mode=stream --unicode-placeholder` (`stream` works over remote panes; `--unicode-placeholder` keeps the image inside fzf's preview box).
- Everything else (`*`): `bat`, `batcat`, `cat`.

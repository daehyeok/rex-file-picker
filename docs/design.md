# How rex-file-picker works

This page explains what happens when you pick a file, and why the plugin is built this way. You don't need it to use the plugin; see the [README](../README.md) for that.

## The flow

```
 pick_file / pick_zoxide_dir / pick_file_<profile>   (Rex config, client)
   dir   <- the pane's working directory (terminal process info: the
            foreground program's cwd, else the shell's)
   roots <- `roots`: Lua functions are called here; commands stay strings
   new floating pane on the server that owns the pane:
     sh -c <picker.sh> <origin> <dir> ... <list.sh> <preview.sh> <done.sh>
           <mode> <keys> ... <preview rules> <roots>
                                   |
 picker.sh  (pane's host, /bin/sh, private temp dir removed on exit)
   writes list.sh, preview.sh, done.sh, rules and roots into the temp dir
   resolve roots in order: pwd | path (~ expanded) | cmd (run in dir)
     -> skip missing folders; canonical paths
   list: fd (or find) per root -> each file once, first root wins
     rows: display <TAB> path to insert <TAB> absolute path
   fzf --multi, list on the left, preview on the right
     insert key -> done.sh insert: host `rex send -b <origin>` "<paths>"
     copy key   -> done.sh copy: OSC 52 (or copy_cmd)
     ctrl-t / ctrl-z -> reload the list in another mode
   focus back to the origin pane; exit closes the floating pane
```

- **Nothing to install on the host but fzf.** The scripts travel as arguments, like the plugin's settings, because the client can't write files on a remote host.
- **Insert needs no round trip to the client.** The origin pane lives on the same Rex server as the picker, so the host's own `rex send` (found through `REX_BIN_DIR`, which Rex sets in its panes) types into it. The origin block is always passed: with no block, `rex send` would type into the focused pane, which is the picker.
- **Copy uses OSC 52.** Rex forwards it to the client's clipboard, local or remote. Two details matter: the copy is dropped if the pane closes right after writing it, so the picker waits half a second; and a copy written in the first moment of a new pane can be lost, which a real pick never hits.
- **Focus** goes back to the origin pane explicitly, because Rex doesn't do that when a floating pane closes.
- **Lua functions run on the client, commands on the host.** A function can choose by host or build from the pane's directory; a command can look at the host's disk.

## Roots and paths

Roots are resolved in order, and each file is kept under the first root whose canonical folder contains it, so a pane directory inside a git root lists its files once, as pane-directory rows. Rows from roots other than the pane's directory show the root's label. Inserted paths are relative to the pane's directory (`../` as needed) or absolute, per root.

Inside the temp dir, fields are separated by `\037` and lists inside a field by `\036`, never by tabs: `read` collapses runs of whitespace separators, which would shift empty fields.

## Previews

`preview.sh` walks the rules in order. The first rule whose pattern matches decides; within it the first command whose first word is installed runs with the path as `$1`. Globs never match folders; `directory` does. `mime:` patterns ask `file --mime-type`, only when a rule needs it. Images use `kitten icat` with `--transfer-mode=stream` (works over remote panes) and `--unicode-placeholder` (fzf keeps the image inside the preview window).

## Why this design

| Way | Why not |
|---|---|
| a helper binary installed on every host | an install step per host; `sh` scripts passed as arguments need none |
| sending the pick back to the client (a dispatcher watching the pane's title, as rex-fzf-links does) | needed there because links open on the client; here the target pane is on the picker's own server |
| a real Rex split instead of a floating pane | changes your layout each time, and needs cleanup when it closes |
| `--git-root` and similar flags | a root with a command (`git rev-parse --show-toplevel`) covers it, and any other folder a command can find |

#!/bin/sh
# Tests for share/picker.sh with stub fzf and rex. Run from anywhere:
# sh path/to/picker_sh_test.sh
dir=$(cd "$(dirname "$0")" && pwd)
share=$dir/../share
t=$(mktemp -d "${TMPDIR:-/tmp}/picker_sh_test.XXXXXX")
trap 'rm -rf "$t"' EXIT
t=$(cd -P "$t" && pwd -P)
pass=0 fail=0
eq() { # NAME GOT WANT
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL: %s\n  want: %s\n  got:  %s\n' "$1" "$3" "$2"; fi
}
has() { # NAME HAYSTACK NEEDLE
  case $2 in *"$3"*) pass=$((pass + 1)) ;; *) fail=$((fail + 1)); printf 'FAIL: %s\n  missing: %s\n  in: %s\n' "$1" "$3" "$2" ;; esac
}
lacks() { # NAME HAYSTACK NEEDLE
  case $2 in *"$3"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: %s\n' "$1" "$3" ;; *) pass=$((pass + 1)) ;; esac
}
TAB=$(printf '\t') RS=$(printf '\036')

# The picker searches PATH only. It runs with an isolated PATH: $bin holds
# the stubs (fzf, rex, zoxide) and $sys links to just the system tools the
# scripts need, so no other fzf or zoxide can be found.
export HOME="$t/home"
bin=$t/bin sys=$t/sys
mkdir -p "$bin" "$sys" "$HOME/.local/bin" "$t/pane/sub"
for tool in sh cat awk sed find mktemp rm mkdir stty dd hostname tr head; do
  p=$(command -v "$tool") && ln -s "$p" "$sys/$tool"
done
: > "$t/pane/a.txt"
cat > "$bin/fzf" <<EOF
#!/bin/sh
for a in "\$@"; do printf '%s\n' "\$a"; done > "$t/fzf_args"
cat > "$t/fzf_in"
EOF
cat > "$bin/rex" <<EOF
#!/bin/sh
echo "\$*" >> "$t/rex_log"
EOF
chmod +x "$bin/fzf" "$bin/rex"
unset REX_BIN_DIR

binds=$(printf 'enter\tinsert\nctrl-y\tcopy\nalt-A\tinsert_absolute\nalt-R\tinsert_relative\nalt-a\tcopy_absolute\nalt-r\tcopy_relative\nesc\tclose\nctrl-g\tclose\nctrl-n\tdown\nalt-v\tpage_up\nctrl-t\ttoggle_dirs\nctrl-z\ttoggle_zoxide\nctrl-/\ttoggle_preview')
open_picker() { # MODE ROOTFIELDS...
  mode=$1; shift
  : > "$t/rex_log"; rm -f "$t/fzf_args" "$t/fzf_in"
  PATH="$bin:$sys" "$sys/sh" -c "$(cat "$share/picker.sh")" file-picker block:o "$t/pane" "$bin/rex" \
    "$(cat "$share/list.sh")" "$(cat "$share/preview.sh")" "$(cat "$share/done.sh")" \
    "$mode" "$binds" "--no-mouse" "" absolute "right,55%" "enter insert" \
    1 "*" "cat \"\$1\"" "$@" < /dev/null > "$t/out" 2>&1
}

open_picker files pwd "" "" relative 0 1 ""
a=$(cat "$t/fzf_args")
has "multi" "$a" "--multi"
has "header lines" "$a" "--header-lines=1"
has "hint" "$a" "--header=enter insert"
has "preview window" "$a" "--preview-window=right,55%"
has "insert bind" "$a" "--bind=enter:become(sh "
has "insert uses insert paths" "$a" "/done.sh insert {+2})"
has "copy bind" "$a" "/done.sh copy {+2})"
has "insert absolute bind" "$a" "--bind=alt-A:become(sh "
has "insert absolute uses absolute paths" "$a" "/done.sh insert {+3})"
has "insert relative uses relative paths" "$a" "/done.sh insert {+4})"
has "copy absolute uses absolute paths" "$a" "/done.sh copy {+3})"
has "copy relative uses relative paths" "$a" "/done.sh copy {+4})"
has "close esc" "$a" "--bind=esc:abort"
has "close ctrl-g" "$a" "--bind=ctrl-g:abort"
has "emacs down" "$a" "--bind=ctrl-n:down"
has "page up" "$a" "--bind=alt-v:page-up"
has "dirs toggle" "$a" "/list.sh toggle-dirs)+first"
has "preview toggle" "$a" "--bind=ctrl-/:toggle-preview"
lacks "no zoxide, no toggle" "$a" "toggle-zoxide"
has "extra fzf options" "$a" "--no-mouse"
eq "list header" "$(sed -n 1p "$t/fzf_in")" files
has "list row" "$(cat "$t/fzf_in")" "a.txt${TAB}a.txt${TAB}$t/pane/a.txt${TAB}a.txt"
has "focus back after" "$(cat "$t/rex_log")" "focus block:o"

open_picker dirs pwd "" "" relative 0 1 ""
eq "dirs mode header" "$(sed -n 1p "$t/fzf_in")" directories
has "dirs row" "$(cat "$t/fzf_in")" "sub/${TAB}sub"

open_picker files path "$t/missing" "" absolute 0 1 ""
has "nothing to search" "$(cat "$t/out")" "Nothing to search"
eq "no fzf when nothing to search" "$(test -f "$t/fzf_args" && echo ran)" ""
has "focus after message" "$(cat "$t/rex_log")" "focus block:o"

open_picker zoxide
has "zoxide missing" "$(cat "$t/out")" "zoxide is not installed"

printf '#!/bin/sh\necho "%s"\n' "$t/pane" > "$bin/zoxide"; chmod +x "$bin/zoxide"
open_picker zoxide
eq "zoxide header" "$(sed -n 1p "$t/fzf_in")" "zoxide directories"
has "zoxide toggle bound" "$(cat "$t/fzf_args")" "/list.sh toggle-zoxide)+first"

# An fzf outside PATH (e.g. only in ~/.local/bin) is not used.
mv "$bin/fzf" "$HOME/.local/bin/fzf"
open_picker files pwd "" "" relative 0 1 ""
has "fzf missing" "$(cat "$t/out")" "fzf not found"
has "message shows the PATH searched" "$(cat "$t/out")" "PATH=$bin:$sys"
eq "fzf outside PATH not run" "$(test -f "$t/fzf_args" && echo ran)" ""
: "$RS"

printf 'picker_sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

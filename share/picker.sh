# shellcheck shell=sh
# picker.sh: the file picker pane. Runs on the pane's host under /bin/sh,
# passed inline to `sh -c`, so the host needs no copy of the plugin. It writes
# its helper scripts into a private temp dir, removed when it exits.
#
# Arguments:
#   $1 origin     the pane the picker was opened from
#   $2 pane_dir   that pane's working directory ("" = $HOME)
#   $3 rexcli     client's rex CLI path, used when `rex` isn't on PATH (local panes)
#   $4 $5 $6      the text of share/list.sh, share/preview.sh, share/done.sh
#   $7 mode       files | dirs | zoxide
#   $8 binds      picker keys, one "KEY<TAB>ACTION" per line (ACTION: insert
#                 copy insert_absolute insert_relative copy_absolute
#                 copy_relative close up down page_up page_down first last
#                 toggle_dirs toggle_zoxide toggle_preview)
#   $9 fzf_opts   extra fzf flags, word-split
#   ${10} copy_cmd   shell command fed the text on stdin ("" = OSC 52)
#   ${11} zstyle     path style for zoxide rows (relative | absolute)
#   ${12} pwin       fzf --preview-window value
#   ${13} hint       key hint shown in the header
#   ${14} N          number of preview rules
#   then N rules, 2 fields each (matches, commands; items joined by \036),
#   then 7 fields per root (see list.sh: rootspec)
origin=$1 pane_dir=$2 rexcli=$3 list_sh=$4 preview_sh=$5 done_sh=$6 mode=$7 binds=$8 fzf_opts=$9
shift 9
copy_cmd=$1 zstyle=$2 pwin=$3 hint=$4 nrules=$5
shift 5

REX=${REX_BIN_DIR:+$REX_BIN_DIR/}rex
command -v "$REX" >/dev/null 2>&1 || REX=$rexcli

# say MESSAGE: show it until a key or about a second passes, give focus
# back to the origin pane, and exit (which closes this pane).
say() {
  printf '\033[?25l %s' "$1"
  old=$(stty -g 2>/dev/null)
  stty -icanon -echo min 0 time 10 2>/dev/null
  dd bs=1 count=1 >/dev/null 2>&1
  [ -n "$old" ] && stty "$old" 2>/dev/null
  "$REX" focus "$origin" >/dev/null 2>&1
  exit 0
}

if ! command -v fzf >/dev/null 2>&1; then
  printf '\n  \033[1mfzf not found on %s\033[0m\n  PATH=%s\n\n  press any key to close\n' "$(hostname)" "$PATH"
  stty -icanon -echo min 1 2>/dev/null; dd bs=1 count=1 >/dev/null 2>&1
  "$REX" focus "$origin" >/dev/null 2>&1
  exit 0
fi

D=$(mktemp -d "${TMPDIR:-/tmp}/rex-file-picker.XXXXXX") || exit 0
trap 'rm -rf "$D"' EXIT
trap 'exit 0' HUP INT TERM
ORIGIN=$origin COPY_CMD=$copy_cmd
export D REX ORIGIN COPY_CMD SHELL=/bin/sh
printf '%s\n' "$list_sh" > "$D/list.sh"
printf '%s\n' "$preview_sh" > "$D/preview.sh"
printf '%s\n' "$done_sh" > "$D/done.sh"

i=0
while [ "$i" -lt "$nrules" ] && [ $# -ge 2 ]; do
  printf '%s\037%s\n' "$1" "$2"
  shift 2
  i=$((i + 1))
done > "$D/rules"
while [ $# -ge 7 ]; do
  printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7"
  shift 7
done > "$D/rootspec"

pd=''
[ -n "$pane_dir" ] && pd=$(cd -P -- "$pane_dir" 2>/dev/null && pwd -P)
[ -n "$pd" ] || pd=$(cd -P -- "$HOME" && pwd -P)
printf '%s\n' "$pd" > "$D/pwd"
printf '%s\n' "$zstyle" > "$D/zstyle"
cd "$pd" || exit 0

has_zoxide=0
command -v zoxide >/dev/null 2>&1 && has_zoxide=1
if [ "$mode" = zoxide ]; then
  [ "$has_zoxide" = 1 ] || say "zoxide is not installed on $(hostname)"
  echo files > "$D/last"
else
  printf '%s\n' "$mode" > "$D/last"
fi
printf '%s\n' "$mode" > "$D/mode"

sh "$D/list.sh" resolve
[ "$mode" = zoxide ] || [ -s "$D/roots" ] || say "Nothing to search: none of the roots exist here"

set -f # keys and fzf options are not file patterns
TAB=$(printf '\t')
# shellcheck disable=SC2016 # $D expands in fzf's subshell
set -- fzf --multi --layout=reverse --delimiter="$TAB" --with-nth=1 --header-lines=1 \
  --prompt='> ' --header="$hint" \
  --preview='sh "$D/preview.sh" {3}' --preview-window="$pwin"
# shellcheck disable=SC2016 # $D expands in fzf's subshell
while IFS=$TAB read -r key action; do
  [ -n "$key" ] || continue
  case $action in
    insert) a='become(sh "$D/done.sh" insert {+2})' ;;
    copy) a='become(sh "$D/done.sh" copy {+2})' ;;
    insert_absolute) a='become(sh "$D/done.sh" insert {+3})' ;;
    insert_relative) a='become(sh "$D/done.sh" insert {+4})' ;;
    copy_absolute) a='become(sh "$D/done.sh" copy {+3})' ;;
    copy_relative) a='become(sh "$D/done.sh" copy {+4})' ;;
    close) a=abort ;;
    up | down | first | last) a=$action ;;
    page_up) a=page-up ;;
    page_down) a=page-down ;;
    toggle_preview) a=toggle-preview ;;
    toggle_dirs) a='reload(sh "$D/list.sh" toggle-dirs)+first' ;;
    toggle_zoxide)
      [ "$has_zoxide" = 1 ] || continue
      a='reload(sh "$D/list.sh" toggle-zoxide)+first' ;;
    *) continue ;;
  esac
  set -- "$@" "--bind=$key:$a"
done <<EOF
$binds
EOF
# shellcheck disable=SC2086 # extra fzf flags are meant to be split
set -- "$@" $fzf_opts

sh "$D/list.sh" list | "$@"
"$REX" focus "$origin" >/dev/null 2>&1
exit 0

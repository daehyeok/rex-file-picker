# shellcheck shell=sh
# preview.sh PATH: fzf's preview of one entry. Runs on the pane's host under
# /bin/sh, from the picker's private directory $D.
#
# $D/rules holds the preview rules in order, one per line:
#   matches US commands      (US = \037; items inside each field split by RS = \036)
# A match is `directory`, `mime:<pattern>` (from `file --mime-type`), a glob
# with a / (matched against the end of the path, so docs/*.txt matches
# /any/where/docs/n.txt) or a glob (matched against the file name). Globs and mime patterns never match directories. The first rule
# that matches is used, and in it the first command whose first word is
# installed runs, as `sh -c COMMAND preview PATH`, so it sees the path as $1.
# No match, or nothing installed, shows an empty preview.
set -f
US=$(printf '\037') RS=$(printf '\036')
f=$1
[ -n "$f" ] && [ -e "$f" ] || exit 0
base=${f##*/}
isdir=0
[ -d "$f" ] && isdir=1
mime=''

# matches LIST: true when one of the RS-separated patterns fits the entry.
matches() {
  IFS=$RS
  for m in $1; do
    case $m in
      directory) [ "$isdir" = 1 ] && return 0 ;;
      mime:*)
        [ "$isdir" = 1 ] && continue
        [ -n "$mime" ] || mime=$(file --mime-type -b -- "$f" 2>/dev/null)
        [ -n "$mime" ] || mime=unknown
        # shellcheck disable=SC2254 # the pattern is meant to match
        case $mime in ${m#mime:}) return 0 ;; esac ;;
      */*)
        # shellcheck disable=SC2254
        [ "$isdir" = 0 ] && case $f in $m | */$m) return 0 ;; esac ;;
      *)
        # shellcheck disable=SC2254
        [ "$isdir" = 0 ] && case $base in $m) return 0 ;; esac ;;
    esac
  done
  return 1
}

while IFS=$US read -r list cmds; do
  matches "$list" || continue
  IFS=$RS
  for c in $cmds; do
    w=${c%% *}
    if command -v "$w" >/dev/null 2>&1; then
      unset IFS
      exec sh -c "$c" preview "$f"
    fi
  done
  exit 0
done < "$D/rules"
exit 0

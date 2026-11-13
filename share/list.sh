# shellcheck shell=sh
# list.sh: root resolution and the picker's list. Runs on the pane's host
# under /bin/sh, from the picker's private directory $D:
#
#   sh "$D/list.sh" resolve        $D/rootspec -> $D/roots (usable roots only)
#   sh "$D/list.sh" list           the rows for the current mode ($D/mode)
#   sh "$D/list.sh" toggle-dirs    files <-> directories, then list
#   sh "$D/list.sh" toggle-zoxide  zoxide <-> the last files/dirs mode, then list
#
# Files in $D: pwd (the pane's directory, canonical), rootspec, roots, mode,
# last, zstyle. Fields inside them are separated by \037 (US), lists inside a
# field by \036 (RS); neither is whitespace, so empty fields survive `read`.
#
# rootspec: kind US value US label US style US hidden US ignore US exclude
#   kind: pwd | path | cmd; cmd runs with sh -c in the pane's directory and
#   prints one directory per line (its exit status is ignored).
# roots:    canonical-dir US label US style US hidden US ignore US exclude US is-pwd
#
# The list is one header row (the mode), then rows
#   display <TAB> path-to-insert <TAB> absolute-path <TAB> path-relative-to-pane
# Each file is listed once, under the first root that contains it.
# FP_FINDER=find forces the find fallback (used by the tests).
set -f
US=$(printf '\037') RS=$(printf '\036') SOH=$(printf '\001')
pwd_dir=$(cat "$D/pwd")

# canon DIR: DIR with symlinks resolved, or nothing if it isn't a directory.
canon() { (cd -P -- "$1" 2>/dev/null && pwd -P); }

# expand PATH: absolute, with a leading ~ expanded; relative to the pane's dir.
expand() {
  case $1 in
    \~) printf '%s\n' "$HOME" ;;
    \~/*) printf '%s/%s\n' "$HOME" "${1#??}" ;;
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$pwd_dir" "$1" ;;
  esac
}

resolve() {
  : > "$D/roots"
  while IFS=$US read -r kind value label style hidden ignore excl; do
    case $kind in
      pwd) dirs=$pwd_dir ;;
      path) dirs=$(expand "$value") ;;
      # A command's exit status doesn't matter: only the folders it prints.
      cmd) dirs=$(cd "$pwd_dir" 2>/dev/null && sh -c "$value" 2>/dev/null </dev/null) ;;
      *) continue ;;
    esac
    printf '%s\n' "$dirs" | while IFS= read -r d; do
      [ -n "$d" ] || continue
      d=$(expand "$d")
      c=$(canon "$d")
      [ -n "$c" ] || continue
      ispwd=0 l=$label
      if [ "$kind" = pwd ]; then
        ispwd=1
      elif [ -z "$l" ]; then
        l=${c##*/}
        [ -n "$l" ] || l=/
      fi
      printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\n' "$c" "$l" "$style" "$hidden" "$ignore" "$excl" "$ispwd"
    done >> "$D/roots"
  done < "$D/rootspec"
}

# find_in DIR TYPE HIDDEN IGNORE EXCLUDES: paths under DIR, relative to it.
# TYPE is f or d. fd follows its own defaults for hidden and ignored files
# unless HIDDEN=1 (--hidden, .git still left out) or IGNORE=0 (--no-ignore).
# find can't read ignore files; it leaves out .git and, unless HIDDEN=1,
# every hidden name. EXCLUDES are glob patterns (find: on the name).
find_in() (
  cd "$1" 2>/dev/null || exit 0
  t=$2 hidden=$3 ignore=$4 excl=$5
  fdbin=''
  if [ "${FP_FINDER:-}" != find ]; then
    fdbin=$(command -v fd 2>/dev/null || command -v fdfind 2>/dev/null)
  fi
  if [ -n "$fdbin" ]; then
    set -- "$fdbin" --type "$t" --color=never
    [ "$hidden" = 1 ] && set -- "$@" --hidden --exclude .git
    [ "$ignore" = 0 ] && set -- "$@" --no-ignore
  else
    set -- find . -mindepth 1 '(' -name .git
    [ "$hidden" = 1 ] || set -- "$@" -o -name '.*'
  fi
  IFS=$RS
  for p in $excl; do
    if [ -n "$fdbin" ]; then set -- "$@" --exclude "$p"; else set -- "$@" -o -name "$p"; fi
  done
  unset IFS
  [ -n "$fdbin" ] || set -- "$@" ')' -prune -o -type "$t" -print
  "$@" </dev/null 2>/dev/null | sed -e 's|^\./||' -e 's|/$||'
)

# The awk helpers both listers share: rel(target, base) is target relative to
# base (both absolute and canonical).
AWK_REL='
function rel(t, b,   tt, bb, nt, nb, i, j, out) {
  if (t == b) return "."
  if (b == "/") return substr(t, 2)
  nt = split(substr(t, 2), tt, "/"); nb = split(substr(b, 2), bb, "/")
  i = 1
  while (i <= nt && i <= nb && tt[i] == bb[i]) i++
  out = ""
  for (j = i; j <= nb; j++) out = out "../"
  for (j = i; j <= nt; j++) out = out tt[j] (j < nt ? "/" : "")
  sub(/\/$/, "", out)
  return out
}'

list_roots() {
  t=f slash=''
  [ "$1" = dirs ] && t=d slash=/
  while IFS=$US read -r c l style hidden ignore excl ispwd; do
    printf '%s%s\037%s\037%s\037%s\n' "$SOH" "$c" "$l" "$style" "$ispwd"
    find_in "$c" "$t" "$hidden" "$ignore" "$excl"
  done < "$D/roots" | awk -v pwd="$pwd_dir" -v slash="$slash" -v us="$US" -v soh="$SOH" "$AWK_REL"'
    substr($0, 1, 1) == soh {
      split(substr($0, 2), f, us)
      root = f[1]; label = f[2]; style = f[3]; ispwd = f[4]
      next
    }
    $0 == "" || index($0, "\t") { next }
    {
      abs = (root == "/" ? "" : root) "/" $0
      if (abs in seen) next
      seen[abs] = 1
      ins = (style == "relative") ? rel(abs, pwd) : abs
      disp = (ispwd == "1") ? $0 : "[" label "] " $0
      print disp slash "\t" ins "\t" abs "\t" rel(abs, pwd)
    }'
}

list_zoxide() {
  style=$(cat "$D/zstyle" 2>/dev/null)
  zoxide query -l 2>/dev/null | awk -v pwd="$pwd_dir" -v style="${style:-absolute}" -v home="$HOME" "$AWK_REL"'
    $0 == "" || index($0, "\t") { next }
    {
      abs = $0
      ins = (style == "relative") ? rel(abs, pwd) : abs
      disp = abs
      if (home != "" && index(abs, home "/") == 1) disp = "~" substr(abs, length(home) + 1)
      else if (abs == home) disp = "~"
      print disp "/\t" ins "\t" abs "\t" rel(abs, pwd)
    }'
}

list() {
  mode=$(cat "$D/mode" 2>/dev/null)
  case $mode in
    zoxide) echo "zoxide directories"; list_zoxide ;;
    dirs) echo "directories"; list_roots dirs ;;
    *) echo "files"; list_roots files ;;
  esac
}

set_mode() {
  printf '%s\n' "$1" > "$D/mode"
  [ "$1" = zoxide ] || printf '%s\n' "$1" > "$D/last"
}

case $1 in
  resolve) resolve ;;
  list) list ;;
  toggle-dirs)
    case $(cat "$D/mode" 2>/dev/null) in
      dirs) set_mode files ;;
      *) set_mode dirs ;;
    esac
    list ;;
  toggle-zoxide)
    if [ "$(cat "$D/mode" 2>/dev/null)" = zoxide ]; then
      last=$(cat "$D/last" 2>/dev/null)
      set_mode "${last:-files}"
    else
      set_mode zoxide
    fi
    list ;;
esac

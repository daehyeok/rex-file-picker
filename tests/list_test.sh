#!/bin/sh
# Tests for share/list.sh. Run from anywhere: sh path/to/list_test.sh
# Runs with fd when it is installed, and always with the find fallback.
dir=$(cd "$(dirname "$0")" && pwd)
list_sh=$dir/../share/list.sh
t=$(mktemp -d "${TMPDIR:-/tmp}/list_test.XXXXXX")
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
US=$(printf '\037') RS=$(printf '\036') TAB=$(printf '\t')

# A project (a git repo when git is installed) with the pane in src/, and a
# notes folder.
P=$t/proj N=$t/notes
mkdir -p "$P/src" "$P/build" "$N" "$t/home/.local/bin"
( cd "$P" && git init -q 2>/dev/null ) || mkdir -p "$P/.git"
echo 'build/' > "$P/.gitignore"
: > "$P/a.lua"; : > "$P/src/b.lua"; : > "$P/build/out.o"; : > "$P/.hidden"; : > "$P/my file.txt"
: > "$N/x.md"; : > "$N/y.txt"
export HOME="$t/home"

D=$t/D
mkdir -p "$D"
export D
# rootspec ROWS...: each row "kind|value|label|style|hidden|ignore|exclude" (| -> US)
rootspec() {
  : > "$D/rootspec"
  for row in "$@"; do printf '%s\n' "$row" | tr '|' "$US" >> "$D/rootspec"; done
}
setup() { # MODE
  printf '%s\n' "$P/src" > "$D/pwd"
  printf '%s\n' "$1" > "$D/mode"
  printf '%s\n' "$1" > "$D/last"
  echo absolute > "$D/zstyle"
  sh "$list_sh" resolve
}
rows() { sh "$list_sh" "${1:-list}" | sed 1d | sort; }
header() { sh "$list_sh" list | sed -n 1p; }

std_roots() {
  rootspec "pwd|||relative|0|1|" "cmd|cd .. && pwd|git|relative|0|1|" "path|$N|notes|absolute|0|1|"
}

run_suite() { # NAME (finder already chosen through FP_FINDER)
  s=$1
  std_roots; setup files
  eq "$s: resolved roots" "$(wc -l < "$D/roots" | tr -d ' ')" 3
  eq "$s: header" "$(header)" files
  r=$(rows)
  has "$s: pwd row relative" "$r" "b.lua${TAB}b.lua${TAB}$P/src/b.lua"
  has "$s: git row relative to pane" "$r" "[git] a.lua${TAB}../a.lua${TAB}$P/a.lua"
  has "$s: space kept" "$r" "[git] my file.txt${TAB}../my file.txt"
  has "$s: notes absolute" "$r" "[notes] x.md${TAB}$N/x.md${TAB}$N/x.md${TAB}../../notes/x.md"
  has "$s: git row relative field" "$r" "[git] a.lua${TAB}../a.lua${TAB}$P/a.lua${TAB}../a.lua"
  has "$s: pwd row relative field" "$r" "b.lua${TAB}b.lua${TAB}$P/src/b.lua${TAB}b.lua"
  lacks "$s: pane file listed once" "$r" "[git] src/b.lua"
  lacks "$s: hidden left out" "$r" ".hidden"
  lacks "$s: .git left out" "$r" ".git/"

  # directories
  r=$(sh "$list_sh" toggle-dirs | sed 1d | sort)
  eq "$s: dirs mode" "$(cat "$D/mode")" dirs
  has "$s: dir row" "$r" "[git] src/${TAB}.${TAB}$P/src"
  lacks "$s: no files in dirs mode" "$r" "a.lua"
  sh "$list_sh" toggle-dirs > /dev/null
  eq "$s: back to files" "$(cat "$D/mode")" files

  # hidden on (.git still out), excludes
  rootspec "pwd|||relative|1|1|" "cmd|cd .. && pwd|git|relative|1|1|" "path|$N|notes|absolute|1|1|*.md"
  setup files
  r=$(rows)
  has "$s: hidden listed" "$r" "[git] .hidden"
  lacks "$s: .git still out" "$r" ".git/"
  lacks "$s: exclude" "$r" "x.md"
  has "$s: exclude keeps others" "$r" "[notes] y.txt"

  # a command's output counts even when it exits non-zero
  rootspec "cmd|echo $N; false|n|absolute|0|1|"
  setup files
  has "$s: failing command's output used" "$(rows)" "[n] x.md"

  # roots are skipped when unusable; nothing left
  rootspec "cmd|false|x|absolute|0|1|" "path|$t/missing|m|absolute|0|1|"
  setup files
  eq "$s: unusable roots skipped" "$(wc -c < "$D/roots" | tr -d ' ')" 0

  # external only, ~ expansion, default label, relative path style
  mkdir -p "$HOME/docs"; : > "$HOME/docs/d.txt"
  rootspec "path|~/docs||relative|0|1|"
  setup files
  r=$(rows)
  has "$s: ~ expanded, label from dir" "$r" "[docs] d.txt${TAB}../../home/docs/d.txt"
  lacks "$s: no pane files" "$r" "b.lua"
}

if command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1; then
  unset FP_FINDER
  run_suite fd
  std_roots; setup files
  if [ -d "$P/.git" ] && command -v git >/dev/null 2>&1; then
    lacks "fd: .gitignore honored" "$(rows)" "build/out.o"
    rootspec "cmd|cd .. && pwd|git|relative|0|0|"
    setup files
    has "fd: ignore off" "$(rows)" "[git] build/out.o"
  fi
fi
FP_FINDER='find'; export FP_FINDER
run_suite find
std_roots; setup files
has "find: ignore files not read" "$(rows)" "[git] build/out.o"
unset FP_FINDER

# zoxide (stubbed)
cat > "$t/home/.local/bin/zoxide" <<EOF
#!/bin/sh
printf '%s\n' "$HOME/code" "$P" "/srv/data"
EOF
chmod +x "$t/home/.local/bin/zoxide"
PATH="$t/home/.local/bin:$PATH"
std_roots; setup files
r=$(sh "$list_sh" toggle-zoxide)
eq "zoxide header" "$(printf '%s\n' "$r" | sed -n 1p)" "zoxide directories"
# shellcheck disable=SC2088 # the display is meant to show ~
has "zoxide ~ display" "$r" "~/code/${TAB}$HOME/code${TAB}$HOME/code"
has "zoxide abs" "$r" "/srv/data/${TAB}/srv/data"
has "zoxide relative field" "$r" "$P${TAB}.."
eq "zoxide keeps order" "$(printf '%s\n' "$r" | sed -n 2p | cut -f3)" "$HOME/code"
echo relative > "$D/zstyle"
has "zoxide relative style" "$(sh "$list_sh" list)" "${TAB}..${TAB}$P"
r=$(sh "$list_sh" toggle-zoxide)
eq "zoxide back to last" "$(cat "$D/mode")" files
sh "$list_sh" toggle-dirs > /dev/null; sh "$list_sh" toggle-zoxide > /dev/null; sh "$list_sh" toggle-zoxide > /dev/null
eq "zoxide back to dirs" "$(cat "$D/mode")" dirs
: "$RS"

printf 'list: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

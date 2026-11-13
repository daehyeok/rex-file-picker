#!/bin/sh
# Tests for share/done.sh. Run from anywhere: sh path/to/done_test.sh
# `rex` is a stub that logs its arguments.
dir=$(cd "$(dirname "$0")" && pwd)
done_sh=$dir/../share/done.sh
t=$(mktemp -d "${TMPDIR:-/tmp}/done_test.XXXXXX")
trap 'rm -rf "$t"' EXIT
pass=0 fail=0
eq() { # NAME GOT WANT
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL: %s\n  want: %s\n  got:  %s\n' "$1" "$3" "$2"; fi
}
cat > "$t/rex" <<EOF
#!/bin/sh
for a in "\$@"; do printf '[%s]' "\$a"; done >> "$t/log"
echo >> "$t/log"
EOF
chmod +x "$t/rex"
export D="$t" REX="$t/rex" ORIGIN=block:origin

: > "$t/log"
sh "$done_sh" insert a.lua "my file.txt" "it's" /abs/b-c_d.txt
eq "insert sends quoted paths" "$(sed -n 1p "$t/log")" "[send][-b][block:origin][--][a.lua 'my file.txt' 'it'\\''s' /abs/b-c_d.txt]"
eq "insert then focuses origin" "$(sed -n 2p "$t/log")" "[focus][block:origin]"

: > "$t/log"
sh "$done_sh" insert
eq "nothing picked only focuses" "$(cat "$t/log")" "[focus][block:origin]"

: > "$t/log"
COPY_CMD="cat > '$t/clip'" sh "$done_sh" copy "x y" z
eq "copy_cmd gets the text" "$(cat "$t/clip")" "'x y' z"
eq "copy focuses origin" "$(cat "$t/log")" "[focus][block:origin]"

: > "$t/log"
sh "$done_sh" insert '$HOME' 'a;b' '*.md'
eq "shell characters quoted" "$(sed -n 1p "$t/log")" "[send][-b][block:origin][--]['\$HOME' 'a;b' '*.md']"

printf 'done: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

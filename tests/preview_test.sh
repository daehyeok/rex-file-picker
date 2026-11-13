#!/bin/sh
# shellcheck disable=SC2016 # preview commands keep $1 for the preview script
# Tests for share/preview.sh. Run from anywhere: sh path/to/preview_test.sh
# Preview tools are stubs that print their name, so no real tool is needed.
dir=$(cd "$(dirname "$0")" && pwd)
preview_sh=$dir/../share/preview.sh
t=$(mktemp -d "${TMPDIR:-/tmp}/preview_test.XXXXXX")
trap 'rm -rf "$t"' EXIT
pass=0 fail=0
eq() { # NAME GOT WANT
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL: %s\n  want: %s\n  got:  %s\n' "$1" "$3" "$2"; fi
}
US=$(printf '\037') RS=$(printf '\036')

# The default rules (config.lua), with the commands shortened.
D=$t/D
mkdir -p "$D"
export D
rule() { # MATCHES COMMANDS  (each a |-separated list)
  printf '%s%s%s\n' "$(printf '%s' "$1" | tr '|' "$RS")" "$US" "$(printf '%s' "$2" | tr '|' "$RS")" >> "$D/rules"
}
: > "$D/rules"
rule 'directory' 'tree "$1"|ls -d "$1"'
rule '*.md|*.markdown' 'mdcat "$1"|glow "$1"|bat "$1"|cat "$1"'
rule 'mime:image/*|*.png|*.jpg' 'kitten icat "$1"'
rule 'docs/*.txt' 'bat --docs "$1"'
rule '*' 'bat "$1"|cat "$1"'

# stubs DIR TOOL...: a bin dir holding a stub per TOOL (prints "TOOL ARGS"),
# plus links to the real sh, cat, ls and sed.
stubs() {
  b=$1; shift
  rm -rf "$b"; mkdir -p "$b"
  for tool in "$@"; do
    printf '#!/bin/sh\necho %s "$@"\n' "$tool" > "$b/$tool"
    chmod +x "$b/$tool"
  done
  for real in sh cat ls sed; do ln -s "$(command -v "$real")" "$b/$real"; done
}
f=$t/files
mkdir -p "$f/dir" "$f/docs"
echo hello > "$f/a.txt"
echo '# t' > "$f/r.md"
: > "$f/p.png"
: > "$f/photo"
echo doc > "$f/docs/n.txt"

prev() { # BIN FILE
  PATH=$1 sh "$preview_sh" "$2" 2>&1
}

stubs "$t/all" tree mdcat bat kitten
eq "dir uses tree" "$(prev "$t/all" "$f/dir")" "tree $f/dir"
eq "markdown uses mdcat" "$(prev "$t/all" "$f/r.md")" "mdcat $f/r.md"
eq "text uses bat" "$(prev "$t/all" "$f/a.txt")" "bat $f/a.txt"
eq "image uses kitten" "$(prev "$t/all" "$f/p.png")" "kitten icat $f/p.png"
eq "glob with / matches path" "$(prev "$t/all" "$f/docs/n.txt")" "bat --docs $f/docs/n.txt"
eq "missing file shows nothing" "$(prev "$t/all" "$f/nope")" ""

stubs "$t/glow" tree glow bat kitten
eq "markdown without mdcat uses glow" "$(prev "$t/glow" "$f/r.md")" "glow $f/r.md"

stubs "$t/nomd" tree bat kitten
eq "markdown without mdcat or glow uses bat" "$(prev "$t/nomd" "$f/r.md")" "bat $f/r.md"

stubs "$t/plain"
eq "text without bat uses cat" "$(prev "$t/plain" "$f/a.txt")" "hello"
eq "image without kitten shows nothing" "$(prev "$t/plain" "$f/p.png")" ""
eq "dir without tree uses ls" "$(prev "$t/plain" "$f/dir")" "$f/dir"

# mime: from `file`, for a name without an image extension
stubs "$t/mime" kitten bat
printf '#!/bin/sh\necho image/png\n' > "$t/mime/file"; chmod +x "$t/mime/file"
eq "mime match" "$(prev "$t/mime" "$f/photo")" "kitten icat $f/photo"
printf '#!/bin/sh\necho text/plain\n' > "$t/mime/file"
eq "mime miss falls through" "$(prev "$t/mime" "$f/photo")" "bat $f/photo"

# A custom rule ahead of the defaults
mv "$D/rules" "$D/rules.def"
rule '*.json' 'jq -C . "$1"'
cat "$D/rules.def" >> "$D/rules"
stubs "$t/jq" jq bat
echo '{}' > "$f/c.json"
eq "custom rule" "$(prev "$t/jq" "$f/c.json")" "jq -C . $f/c.json"

printf 'preview: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

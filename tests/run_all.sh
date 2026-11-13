#!/bin/sh
# run_all.sh [lua|shell|all]: run the plugin's tests. Run from anywhere.
# Lua tests use `lua` (5.1 or LuaJIT) when it's on PATH, else `rex do`.
dir=$(cd "$(dirname "$0")" && pwd)
what=${1:-all}
status=0

if [ "$what" != shell ]; then
  if command -v lua >/dev/null 2>&1; then run="lua"
  elif command -v rex >/dev/null 2>&1; then run="rex do"
  else echo "run_all: neither lua nor rex found" >&2; exit 1
  fi
  for t in "$dir"/*_test.lua; do
    # $run is one or two words on purpose
    # shellcheck disable=SC2086
    out=$($run "$t" 2>&1) || status=1
    printf '%s\n' "$out" | grep -v '^"ok"$'
    case $out in *" passed, 0 failed"*) ;; *) status=1 ;; esac
  done
fi
if [ "$what" != lua ]; then
  for t in "$dir"/*_test.sh; do
    sh "$t" || status=1
  done
fi
exit $status

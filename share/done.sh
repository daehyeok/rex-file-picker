# shellcheck shell=sh
# done.sh insert|copy PATH...: acts on a pick. fzf runs it in place of itself
# (become), on the pane's host, with the chosen paths as arguments.
#
#   insert  types the paths into the origin pane with the host's `rex send`
#           (the origin pane lives on the same Rex server as the picker)
#   copy    puts them on the clipboard of the machine running the Rex app,
#           with OSC 52, or pipes them to COPY_CMD when it is set
#
# Paths are shell-quoted when needed and joined by spaces; no newline is
# added, so nothing runs. Focus then goes back to the origin pane (Rex
# doesn't do that when a floating pane closes).
#
# Environment: D (private dir), REX (rex CLI), ORIGIN (origin block),
# COPY_CMD (optional).
act=$1
shift

# quote ARG: ARG as one shell word.
quote() {
  case $1 in
    '' | *[!A-Za-z0-9_./+:@%=,-]*)
      printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" ;;
    *) printf '%s' "$1" ;;
  esac
}

text=''
for p in "$@"; do
  q=$(quote "$p")
  text="${text:+$text }$q"
done

focus() { "$REX" focus "$ORIGIN" >/dev/null 2>&1; }

fail() {
  printf '\n  \033[1mCould not %s:\033[0m\n  %s\n\n  press any key to close\n' "$act" "$(cat "$D/err" 2>/dev/null)"
  stty -icanon -echo min 1 2>/dev/null
  dd bs=1 count=1 >/dev/null 2>&1
}

[ -n "$text" ] || { focus; exit 0; }
case $act in
  insert)
    "$REX" send -b "$ORIGIN" -- "$text" >/dev/null 2>"$D/err" || fail ;;
  copy)
    if [ -n "${COPY_CMD:-}" ]; then
      printf '%s' "$text" | sh -c "$COPY_CMD" >/dev/null 2>"$D/err" || fail
    else
      printf '\033]52;c;%s\007' "$(printf '%s' "$text" | base64 | tr -d '\n')" > /dev/tty
      # The terminal drops a copy whose pane closes right away.
      sleep 0.5
    fi ;;
esac
focus
exit 0

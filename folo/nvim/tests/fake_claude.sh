#!/bin/sh
# Stands in for the claude CLI. Records calls; FAKE_CLAUDE_MODE selects a failure.
input=$(cat)
case "$*" in
  *"SUMMARY PROMPT"*) kind=summary ;;
  *) kind=translation ;;
esac
first=$(printf '%s\n' "$input" | head -n 1)
{
  printf 'start %s %s\n' "$kind" "$first"
  printf 'args %s\n' "$*"
  printf 'env %s\n' "$CLAUDE_CONFIG_DIR"
  printf 'cwd %s\n' "$(pwd)"
} >> "$FAKE_CLAUDE_LOG"
sleep 0.2
printf 'end %s %s\n' "$kind" "$first" >> "$FAKE_CLAUDE_LOG"
case "$FAKE_CLAUDE_MODE" in
  login) echo 'Not logged in' ; exit 1 ;;
  empty) exit 0 ;;
  slow) exec sleep 5 ;;
esac
if [ "$kind" = summary ]; then echo "SUMMARY of $first"; else echo "TRANSLATION of $first"; fi

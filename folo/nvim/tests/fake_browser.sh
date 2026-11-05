#!/bin/sh
# Stands in for headless Chrome; records argv and fails for URLs ending in /fail.
for last; do :; done
printf '%s\n' "$*" >> "$FAKE_BROWSER_LOG"
case "$last" in
  */fail) echo 'crashed' >&2; exit 2 ;;
esac
echo '<html><body><main><p>Rendered by browser</p></main></body></html>'

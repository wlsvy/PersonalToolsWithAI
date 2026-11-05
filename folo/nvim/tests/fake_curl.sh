#!/bin/sh
# Stands in for curl on PATH. Serves fixtures by URL; appends the -w trailer like curl does.
for last; do :; done
printf '%s\n' "$*" >> "$FAKE_CURL_LOG"
case "$last" in
  */page) printf '<html><head><script>BAD</script></head><body><nav>MENU</nav><article><p>Curl article text</p></article></body></html>\n200 text/html; charset=utf-8' ;;
  */denied) printf 'nope\n403 text/html' ;;
  */pdf) printf 'bin\n200 application/pdf' ;;
  */down) echo 'could not resolve' >&2; exit 6 ;;
  *) printf '<html><body><p>Generic page</p></body></html>\n200 text/html' ;;
esac

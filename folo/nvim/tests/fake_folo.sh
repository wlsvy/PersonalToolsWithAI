#!/bin/sh
# Stands in for the folo CLI. Records argv; FAKE_FOLO_MODE selects a failure.
printf '%s\n' "$*" >> "$FAKE_FOLO_LOG"
case "$FAKE_FOLO_MODE" in
  unauthorized)
    echo '{"ok":false,"data":null,"error":{"code":"UNAUTHORIZED","message":"Missing token."}}' >&2
    exit 1 ;;
  crash) echo 'boom' >&2; exit 3 ;;
  badjson) echo 'not json'; exit 0 ;;
  slow) exec sleep 5 ;;
esac
case "$*" in
  *"timeline"*"--cursor 2026-01-01"*)
    echo '{"ok":true,"data":{"entries":[{"read":true,"feeds":{"title":"F2"},"entries":{"id":"3","title":"third","url":"https://x/3","publishedAt":"2025-12-31T00:00:00Z"}}],"nextCursor":"2025-12-31T00:00:00Z","hasNext":false},"error":null}' ;;
  *timeline*)
    echo '{"ok":true,"data":{"entries":[{"read":false,"feeds":{"title":"F1"},"entries":{"id":"1","title":"first\nline","url":"https://x/1","publishedAt":"2026-01-02T00:00:00Z"}},{"read":true,"feeds":{"title":null},"entries":{"id":"2","title":"second","url":null,"publishedAt":"2026-01-01T00:00:00Z"}}],"nextCursor":"2026-01-01T00:00:00Z","hasNext":true},"error":null}' ;;
  *"entry get 1"*)
    echo '{"ok":true,"data":{"feeds":{"title":"F1"},"entries":{"id":"1","title":"first","url":"https://x/1","content":"<p>body</p>","publishedAt":"2026-01-02T00:00:00Z"}},"error":null}' ;;
  *"entry get 2"*)
    echo '{"ok":true,"data":{"feeds":{"title":"F1"},"entries":{"id":"2","title":"second","url":"https://x/2","content":null}},"error":null}' ;;
  *"entry get 404"*) echo '{"ok":true,"data":null,"error":null}' ;;
  *"entry read 2"*) echo '{"ok":true,"data":{"content":"<p>readable</p>"},"error":null}' ;;
  *"entry mark-"*) echo '{"ok":true,"data":null,"error":null}' ;;
  *) echo '{"ok":false,"data":null,"error":{"code":"INVALID_ARGUMENT","message":"unexpected"}}' >&2; exit 1 ;;
esac

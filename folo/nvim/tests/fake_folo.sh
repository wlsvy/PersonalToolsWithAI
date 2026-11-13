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
  *"unread list"*)
    echo '{"ok":true,"data":{"total":16,"items":[{"feedId":"f1","title":"Small","category":"AI","view":0,"unreadCount":2},{"feedId":"f2","title":"Big","category":"AI","view":0,"unreadCount":5},{"feedId":"f3","title":"Loose","category":null,"view":0,"unreadCount":1},{"feedId":"f4","title":"News feed","category":"News","view":0,"unreadCount":8},{"feedId":"f5","title":"Social","category":"News","view":1,"unreadCount":100}]},"error":null}' ;;
  *"subscription list"*)
    echo '{"ok":true,"data":{"subscriptions":[{"category":"News"},{"category":"AI"},{"category":null},{"category":"AI"},{}]},"error":null}' ;;
  *"collection add 404"*)
    echo '{"ok":false,"data":null,"error":{"code":"NOT_FOUND","message":"no entry"}}' >&2; exit 1 ;;
  *"collection add"*|*"collection remove"*) echo '{"ok":true,"data":null,"error":null}' ;;
  *"collection list"*"--cursor 2026-02-05T00:00:00Z"*)
    echo '{"ok":true,"data":{"entries":[{"read":true,"collections":{"createdAt":"2026-02-04T00:00:00Z"},"feeds":{"title":"F3"},"entries":{"id":"10","title":"saved two","url":"https://x/10","publishedAt":"2026-03-01T00:00:00Z"}}],"nextCursor":"2026-03-01T00:00:00Z","hasNext":false},"error":null}' ;;
  *"collection list"*)
    echo '{"ok":true,"data":{"entries":[{"read":true,"collections":{"createdAt":"2026-02-05T00:00:00Z"},"feeds":{"title":"F3"},"entries":{"id":"9","title":"saved","url":"https://x/9","publishedAt":"2026-02-01T00:00:00Z"}}],"nextCursor":"2026-02-01T00:00:00Z","hasNext":true},"error":null}' ;;
  *"--category News"*)
    echo '{"ok":true,"data":{"entries":[{"read":false,"feeds":{"title":"F4","siteUrl":"https://www.GitHub.com/blog"},"entries":{"id":"7","title":"news item","url":"https://x/7","publishedAt":"2026-03-01T00:00:00Z"}}],"nextCursor":"2026-03-01T00:00:00Z","hasNext":false},"error":null}' ;;
  *"timeline"*"--cursor 2026-01-01"*)
    echo '{"ok":true,"data":{"entries":[{"read":true,"feeds":{"title":null},"entries":{"id":"2","title":"second","url":null,"publishedAt":"2026-01-01T00:00:00Z"}},{"read":true,"feeds":{"title":"F2"},"entries":{"id":"3","title":"third","url":"javascript:alert(1)","publishedAt":"2025-12-31T00:00:00Z"}}],"nextCursor":"2025-12-31T00:00:00Z","hasNext":false},"error":null}' ;;
  *timeline*)
    echo '{"ok":true,"data":{"entries":[{"read":false,"feeds":{"title":"F1"},"entries":{"id":"1","title":"first\nline","url":"https://x/1","publishedAt":"2026-01-02T00:00:00Z"}},{"read":true,"collections":{"createdAt":"2026-01-03T00:00:00Z"},"feeds":{"title":null},"entries":{"id":"2","title":"second","url":null,"publishedAt":"2026-01-01T00:00:00Z"}}],"nextCursor":"2026-01-01T00:00:00Z","hasNext":true},"error":null}' ;;
  *"entry get 1"*)
    echo '{"ok":true,"data":{"feeds":{"title":"F1"},"entries":{"id":"1","title":"first","url":"https://x/1","content":"<p>body</p>","publishedAt":"2026-01-02T00:00:00Z"}},"error":null}' ;;
  *"entry get 2"*)
    echo '{"ok":true,"data":{"feeds":{"title":"F1"},"entries":{"id":"2","title":"second","url":"https://x/2","content":"<a href=\"https://x/2\">Comments</a>"}},"error":null}' ;;
  *"entry get 3"*)
    echo '{"ok":true,"data":{"feeds":{"title":"F1"},"entries":{"id":"3","title":"third","url":"https://x/3","content":"<p>short</p>"}},"error":null}' ;;
  *"entry read 1"*) echo '{"ok":true,"data":{"content":"<p>full article</p>"},"error":null}' ;;
  *"entry read 3"*) echo '{"ok":true,"data":null,"error":null}' ;;
  *"entry get 404"*) echo '{"ok":true,"data":null,"error":null}' ;;
  *"entry read 2"*) echo '{"ok":true,"data":{"content":"<p>readable</p>"},"error":null}' ;;
  *"entry get 8"*)
    echo '{"ok":true,"data":{"feeds":{"title":"F1"},"entries":{"id":"8","title":"folo readable","url":"https://x/8","content":"<a href=\"https://x/8\">Comments</a>"}},"error":null}' ;;
  *"entry read 8"*) echo '{"ok":true,"data":{"content":"<p>LONGFOLO LONGFOLO LONGFOLO LONGFOLO LONGFOLO</p>"},"error":null}' ;;
  *"entry mark-"*) echo '{"ok":true,"data":null,"error":null}' ;;
  *) echo '{"ok":false,"data":null,"error":{"code":"INVALID_ARGUMENT","message":"unexpected"}}' >&2; exit 1 ;;
esac

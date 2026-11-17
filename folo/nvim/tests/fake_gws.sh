#!/bin/sh
# Stands in for the gws CLI. Records argv; FAKE_GWS_MODE selects a failure or an empty inbox.
printf '%s\n' "$*" >> "$FAKE_FOLO_LOG"
echo 'Using keyring backend: keyring' >&2
case "$FAKE_GWS_MODE" in
  auth)
    echo '{"error":{"code":401,"message":"Gmail auth failed: No credentials found. Run `gws auth setup` to configure.","reason":"authError"}}'
    exit 2 ;;
  empty) echo '{"query":"is:unread","resultSizeEstimate":0}'; exit 0 ;;
esac
echo '{"messages":[{"id":"m1","from":"\"Alice Kim\" <alice@example.com>","subject":"Lunch\non Friday?","date":"Tue, 17 Nov 2026 11:37:59 +0000 (GMT)"},{"id":"m2","from":"bob@example.com","subject":"Report","date":"Mon, 16 Nov 2026 08:00:00 +0900"}],"query":"is:unread","resultSizeEstimate":42}'

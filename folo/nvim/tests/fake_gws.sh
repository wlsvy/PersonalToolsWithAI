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
case "$*" in
  *"messages get"*'"id":"m1"'*) echo '{"id": "m1", "payload": {"mimeType": "multipart/alternative", "headers": [{"name": "Subject", "value": "Lunch on Friday?"}, {"name": "From", "value": "Alice Kim <alice@example.com>"}, {"name": "Date", "value": "Tue, 17 Nov 2026 11:37:59 +0000"}], "parts": [{"mimeType": "text/plain", "filename": "", "headers": [{"name": "Content-Type", "value": "text/plain; charset=UTF-8"}], "body": {"size": 1, "data": "UGxhaW4gYm9keSA_Pw0Kc2Vjb25kIGxpbmU"}}, {"mimeType": "text/html", "filename": "", "headers": [{"name": "Content-Type", "value": "text/html; charset=UTF-8"}], "body": {"size": 1, "data": "PHA-SFRNTCBib2R5PC9wPg"}}]}}'; exit 0 ;;
  *"messages get"*'"id":"m2"'*) echo '{"id": "m2", "payload": {"mimeType": "multipart/mixed", "headers": [{"name": "Subject", "value": "Report"}, {"name": "From", "value": "bob@example.com"}, {"name": "Date", "value": "Mon, 16 Nov 2026 08:00:00 +0900"}], "parts": [{"mimeType": "multipart/alternative", "filename": "", "headers": [], "body": {"size": 0}, "parts": [{"mimeType": "text/html", "filename": "", "headers": [{"name": "Content-Type", "value": "text/html; charset=\"euc-kr\""}], "body": {"size": 1, "data": "PHA-uriw7bytIMO3us7H1bTPtNk8L3A-"}}]}, {"mimeType": "application/pdf", "filename": "report.pdf", "headers": [], "body": {"size": 10, "attachmentId": "att1"}}]}}'; exit 0 ;;
esac
echo '{"messages":[{"id":"m1","from":"\"Alice Kim\" <alice@example.com>","subject":"Lunch\non Friday?","date":"Tue, 17 Nov 2026 11:37:59 +0000 (GMT)"},{"id":"m2","from":"bob@example.com","subject":"Report","date":"Mon, 16 Nov 2026 08:00:00 +0900"}],"query":"is:unread","resultSizeEstimate":42}'

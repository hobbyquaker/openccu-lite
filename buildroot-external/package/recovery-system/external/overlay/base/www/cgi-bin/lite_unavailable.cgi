#!/bin/sh
# openccu-lite: the recovery's answer on the running system's API and addon paths
# (lighttpd.conf's error-handler-404 for /api/, /addons/ and /.well-known/acme-challenge/):
# 503 with Retry-After, so a client retries instead of following a redirect to the recovery's
# page - JSON under /api/ as occulited's lighttpd answers while it starts, a line of text
# elsewhere. REQUEST_URI is the client's original path under an error handler.
case "${REQUEST_URI:-}" in
  /api/*)
    printf 'Status: 503 Service Unavailable\r\nRetry-After: 30\r\nCache-Control: no-store\r\nContent-Type: application/json\r\n\r\n'
    printf '{"error":"updating","message":"the system is in its recovery system, installing an update or restoring a backup"}\n'
    ;;
  *)
    printf 'Status: 503 Service Unavailable\r\nRetry-After: 30\r\nCache-Control: no-store\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n'
    printf 'the system is in its recovery system, installing an update or restoring a backup\n'
    ;;
esac

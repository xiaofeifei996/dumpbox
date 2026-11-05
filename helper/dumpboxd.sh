#!/bin/bash
# dumpboxd: root queue worker, talks to DumpBox.app via NSUserDefaults plist.
PLIST=/var/mobile/Library/Preferences/com.dumpbox.app.plist

while true; do
  if [ -f "$PLIST" ]; then
    BID=$(plutil -key request "$PLIST" 2>/dev/null | head -1 | tr -d '\r\n')
    STATUS=$(plutil -key status "$PLIST" 2>/dev/null | head -1 | tr -d '\r\n')
    if [ -n "$BID" ] && [ "$STATUS" != "DONE" ] && [ "$STATUS" != "RUNNING" ]; then
      plutil -key status -value "RUNNING" "$PLIST" >/dev/null 2>&1 || true
      OUT=$(/usr/local/bin/dumpbox "$BID" 2>&1)
      plutil -key result -value "$OUT" "$PLIST" >/dev/null 2>&1 || true
      plutil -key status -value "DONE" "$PLIST" >/dev/null 2>&1 || true
    fi
  fi
  sleep 1
done

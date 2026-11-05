#!/bin/bash
# dumpboxd: root queue worker, talks to DumpBox.app via NSUserDefaults plist.
PLIST=/var/mobile/Library/Preferences/com.dumpbox.app.plist

while true; do
  if [ -f "$PLIST" ]; then
    BID=$(plutil -extract request raw "$PLIST" 2>/dev/null)
    STATUS=$(plutil -extract status raw "$PLIST" 2>/dev/null)
    if [ -n "$BID" ] && [ "$STATUS" != "DONE" ] && [ "$STATUS" != "RUNNING" ]; then
      plutil -replace status -string "RUNNING" "$PLIST" 2>/dev/null || \
        plutil -insert status -string "RUNNING" "$PLIST" 2>/dev/null || true
      OUT=$(/usr/local/bin/dumpbox "$BID" 2>&1)
      plutil -replace result -string "$OUT" "$PLIST" 2>/dev/null || \
        plutil -insert result -string "$OUT" "$PLIST" 2>/dev/null || true
      plutil -replace status -string "DONE" "$PLIST" 2>/dev/null || \
        plutil -insert status -string "DONE" "$PLIST" 2>/dev/null || true
    fi
  fi
  sleep 1
done

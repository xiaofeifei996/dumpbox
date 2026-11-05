#!/bin/bash
# dumpboxd: root queue worker for DumpBox.app
DIR=/var/mobile/Documents/DumpBox
mkdir -p "$DIR"
chown mobile:mobile "$DIR" 2>/dev/null || true

while true; do
  if [ -f "$DIR/request" ]; then
    BID=$(cat "$DIR/request" 2>/dev/null | tr -d '\r\n')
    rm -f "$DIR/request"
    : > "$DIR/result"
    chmod 666 "$DIR/result" 2>/dev/null || true
    if [ -n "$BID" ]; then
      /usr/local/bin/dumpbox "$BID" >> "$DIR/result" 2>&1
    else
      echo "ERROR: empty request" >> "$DIR/result"
    fi
    echo "DONE" >> "$DIR/result"
  fi
  sleep 1
done

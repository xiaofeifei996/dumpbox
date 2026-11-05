#!/bin/bash
# dumpbox <bundle-id> [output-dir]
# Must run as root. File work happens as mobile because RootHide redirects
# root's /private/var away from the real app containers.
set -u

BID="${1:-}"
if [ -z "$BID" ]; then
  echo "usage: dumpbox <bundle-id> [output-dir]"
  exit 1
fi
OUTDIR="${2:-/var/mobile/Documents/DumpBox}"
TWEAK_DIR=/usr/lib/TweakInject
DYLIB=/usr/local/share/DumpBox.dylib
PLIST="$TWEAK_DIR/DumpBox.plist"

mkdir -p "$OUTDIR"
chown mobile:mobile "$OUTDIR" 2>/dev/null || true
cp -f "$DYLIB" "$TWEAK_DIR/DumpBox.dylib" || { echo "ERROR: copy dylib"; exit 2; }
chmod 755 "$TWEAK_DIR/DumpBox.dylib"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Filter</key>
  <dict>
    <key>Bundles</key>
    <array><string>$BID</string></array>
  </dict>
</dict>
</plist>
EOF
chmod 644 "$PLIST"
echo "TWEAK_INSTALLED"

sudo -u mobile /bin/bash -s "$BID" "$OUTDIR" <<'MOBILE_EOF'
BID="$1"
OUTDIR="$2"
mkdir -p "$OUTDIR"

INFO=$(uicache -i "$BID" 2>/dev/null) || true
APP_PATH=$(printf '%s\n' "$INFO" | sed -n 's/^Path: //p' | head -1)
DATA_PATH=$(printf '%s\n' "$INFO" | sed -n 's/^Data Container Path: //p' | head -1)

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "ERROR: app not found: $BID"
  exit 2
fi
if [ -z "$DATA_PATH" ] || [ "$DATA_PATH" = "(null)" ] || [ ! -d "$DATA_PATH" ]; then
  echo "ERROR: data container not found"
  exit 2
fi

EXE=$(basename "$APP_PATH" .app)
echo "APP=$APP_PATH"
echo "DATA=$DATA_PATH"

killall -9 "$EXE" 2>/dev/null || true
sleep 1
uiopen --bundleid "$BID" 2>/dev/null || true

DUMP="$DATA_PATH/Documents/${BID}_dump"
i=0
while [ $i -lt 120 ]; do
  [ -f "$DUMP" ] && break
  sleep 1
  i=$((i + 1))
done

if [ ! -f "$DUMP" ]; then
  echo "ERROR: dump timeout"
  exit 3
fi

SIZE=$(wc -c < "$DUMP" | tr -d ' ')
echo "DUMP=$DUMP"
echo "SIZE=$SIZE"

WORK=$(mktemp -d /tmp/dumpbox.XXXXXX)
mkdir -p "$WORK/Payload"
cp -a "$APP_PATH" "$WORK/Payload/" || { echo "ERROR: copy app bundle"; rm -rf "$WORK"; exit 4; }

APP_IN_PKG="$WORK/Payload/$(basename "$APP_PATH")"
cp -f "$DUMP" "$APP_IN_PKG/$EXE"
rm -rf "$APP_IN_PKG/_CodeSignature" "$APP_IN_PKG/SC_Info"

ENT="$WORK/ent.plist"
ldid2 -e "$DUMP" > "$ENT" 2>/dev/null || true
if [ -s "$ENT" ]; then
  ldid2 -S"$ENT" "$APP_IN_PKG/$EXE" || echo "ERROR: sign"
else
  ldid2 -S "$APP_IN_PKG/$EXE" || echo "ERROR: sign"
fi

OUT_IPA="$OUTDIR/${EXE}-decrypted.ipa"
rm -f "$OUT_IPA"
( cd "$WORK" && zip -qry "$OUT_IPA" Payload ) || { echo "ERROR: zip"; rm -rf "$WORK"; exit 5; }
rm -rf "$WORK"

echo "IPA=$OUT_IPA"
ls -lh "$OUT_IPA" 2>/dev/null || true
exit 0
MOBILE_EOF

RC=$?
rm -f "$PLIST" "$TWEAK_DIR/DumpBox.dylib"
exit $RC

#!/bin/bash
# Packages the app into "Liquid Desktop.dmg" with a branded drag-to-install
# window (background art, icon positions, volume icon). Uses dmgbuild from a
# private virtualenv under .build so no Finder scripting is needed.
# usage: make-dmg.sh <app-path> <dmg-path> <volume-name>
set -euo pipefail

APP="$1"
DMG="$2"
VOLUME="$3"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.build/dmg"
VENV="$ROOT/.build/venv"
mkdir -p "$WORK"

if [[ ! -x "$VENV/bin/python" ]] || ! "$VENV/bin/python" -c "import dmgbuild" 2>/dev/null; then
    python3 -m venv "$VENV"
    PIP_USER=false "$VENV/bin/pip" install -q dmgbuild
fi

swiftc -O -framework AppKit "$ROOT/Tools/DMGBackground/main.swift" -o "$WORK/DMGBackground"
"$WORK/DMGBackground" "$WORK/background.png" 1
"$WORK/DMGBackground" "$WORK/background@2x.png" 2
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" >/dev/null

cat > "$WORK/settings.py" <<PY
import os.path
application = "$APP"
appname = os.path.basename(application)
format = "UDZO"
compression_level = 9
filesystem = "HFS+"
files = [application]
symlinks = {"Applications": "/Applications"}
icon = "$APP/Contents/Resources/AppIcon.icns"
badge_icon = None
icon_locations = {appname: (180, 200), "Applications": (480, 200)}
background = "$WORK/background.tiff"
window_rect = ((200, 140), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
icon_size = 112
text_size = 13
PY

rm -f "$DMG"
"$VENV/bin/dmgbuild" -s "$WORK/settings.py" "$VOLUME" "$DMG" >/dev/null

IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ "$IDENTITY" == Developer\ ID* ]]; then
    codesign --force --sign "$IDENTITY" --timestamp "$DMG"
fi

echo "Built    $DMG ($(du -h "$DMG" | cut -f1))"

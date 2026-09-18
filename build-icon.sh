#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"

# Only icon regeneration needs librsvg. Normal app builds use the checked-in ICNS.
command -v rsvg-convert >/dev/null 2>&1 || {
    echo "Icon regeneration requires rsvg-convert (librsvg)." >&2
    exit 1
}
mkdir -p build/AppIcon.iconset
for size in 16 32 128 256 512; do
    rsvg-convert -w "$size" -h "$size" assets/AppIcon.svg \
        -o "build/AppIcon.iconset/icon_${size}x${size}.png"
    double=$((size * 2))
    rsvg-convert -w "$double" -h "$double" assets/AppIcon.svg \
        -o "build/AppIcon.iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns build/AppIcon.iconset -o assets/AppIcon.icns
cp build/AppIcon.iconset/icon_512x512@2x.png assets/AppIcon.png
echo "Generated assets/AppIcon.icns and the 1024-pixel PNG preview."

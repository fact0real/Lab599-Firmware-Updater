# App icon

`AppIcon.svg` is the editable vector master. The supplied Lab599 logo paths,
white lettering and red `#DC2F47` are preserved, with a graphite enclosure and
a firmware-chip/update-arrow symbol added for this unofficial utility.

`AppIcon.png` is the 1024-pixel transparent preview. `AppIcon.icns` contains
standard macOS 16, 32, 128, 256 and 512-point sizes at 1x and 2x scale.

Regenerate with `sh build-icon.sh` (requires `rsvg-convert` from librsvg and
macOS `iconutil`). `sh build-updater.sh` embeds the existing ICNS and signs the
completed app bundle; it does not need librsvg.

The source logo was supplied by the user as `/Users/factoreal/Downloads/header_logo.svg`.
This adaptation does not establish permission to redistribute Lab599 branding
or imply Lab599 endorsement. Resolve branding permission before public release.

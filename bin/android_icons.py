#!/usr/bin/env python3
"""Generate the Android launcher icons for the Capacitor app from the iOS icon.

`npx cap add android` only drops in Capacitor's DEFAULT launcher icons (a white
adaptive background + generic foreground), and `android/` is gitignored, so the
real Agent44 icon has to be (re)generated whenever the native project is created
or refreshed. Run this after `npx cap add android`:

    python3 bin/android_icons.py

Source of truth is the committed iOS app icon (1024x1024). This writes:
  - legacy ic_launcher.png / ic_launcher_round.png at every density
  - the adaptive foreground (ic_launcher_foreground.png), the full icon scaled
    into the adaptive safe zone so the antennae aren't clipped by the mask
  - the adaptive background color (values/ic_launcher_background.xml)

Requires Pillow (pip install Pillow).
"""

import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("Pillow is required: pip install Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png")
RES = os.path.join(ROOT, "android/app/src/main/res")

# Brand orange = the iOS icon's outer color (inner square is #F26B1F).
BACKGROUND = "#F28E1C"

# Legacy launcher icon is 48dp; adaptive foreground is 108dp.
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
FOREGROUND = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
# Fraction of the 108dp foreground the icon fills. Android only guarantees the
# center ~66% of an adaptive icon is visible; the rest can be masked away.
SAFE_SCALE = 0.66


def circle_mask(img):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, img.size[0], img.size[1]), fill=255)
    out = img.copy()
    out.putalpha(mask)
    return out


def main():
    if not os.path.isfile(SRC):
        sys.exit(f"Source icon not found: {SRC}")
    if not os.path.isdir(RES):
        sys.exit(f"{RES} not found. Run `npx cap add android` first.")

    icon = Image.open(SRC).convert("RGBA")

    for density, size in LEGACY.items():
        base = icon.resize((size, size), Image.LANCZOS)
        base.save(os.path.join(RES, f"mipmap-{density}/ic_launcher.png"))
        circle_mask(base).save(os.path.join(RES, f"mipmap-{density}/ic_launcher_round.png"))

    for density, size in FOREGROUND.items():
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        inner = int(size * SAFE_SCALE)
        scaled = icon.resize((inner, inner), Image.LANCZOS)
        offset = (size - inner) // 2
        canvas.paste(scaled, (offset, offset), scaled)
        canvas.save(os.path.join(RES, f"mipmap-{density}/ic_launcher_foreground.png"))

    with open(os.path.join(RES, "values/ic_launcher_background.xml"), "w") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<resources>\n"
            f'    <color name="ic_launcher_background">{BACKGROUND}</color>\n'
            "</resources>\n"
        )

    print(f"Android launcher icons generated in {RES} (background {BACKGROUND}).")


if __name__ == "__main__":
    main()

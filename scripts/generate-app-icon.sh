#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES_DIR="$ROOT_DIR/apps/mac-client/Resources"
MASTER_PNG="$RES_DIR/AppIcon-master.png"
ICNS_FILE="$RES_DIR/AppIcon.icns"

mkdir -p "$RES_DIR"

python3 - "$MASTER_PNG" <<'PY'
import sys
from PIL import Image, ImageDraw, ImageFilter

def lerp(a, b, t):
    return int(round(a + (b - a) * t))

def rounded_mask(width, height, radius):
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1), radius=radius, fill=255)
    return mask

def gradient_pill(width, height, radius, start_rgb, end_rgb, opacity):
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    px = img.load()
    denom = max(width + height - 2, 1)
    for y in range(height):
        for x in range(width):
            t = (x + y) / denom
            px[x, y] = (
                lerp(start_rgb[0], end_rgb[0], t),
                lerp(start_rgb[1], end_rgb[1], t),
                lerp(start_rgb[2], end_rgb[2], t),
                255,
            )
    mask = rounded_mask(width, height, radius)
    alpha_scale = int(round(255 * opacity))
    img.putalpha(mask.point(lambda p: p * alpha_scale // 255))
    return img

def solid_pill(width, height, radius, rgb, opacity):
    img = Image.new("RGBA", (width, height), rgb + (255,))
    mask = rounded_mask(width, height, radius)
    alpha_scale = int(round(255 * opacity))
    img.putalpha(mask.point(lambda p: p * alpha_scale // 255))
    return img

def add_bar(canvas, bar_img, center_xy, angle_deg, shadow_offset_y, shadow_blur, shadow_alpha):
    rotated = bar_img.rotate(angle_deg, resample=Image.BICUBIC, expand=True)
    rx = int(round(center_xy[0] - rotated.width / 2))
    ry = int(round(center_xy[1] - rotated.height / 2))

    shadow_mask = rotated.split()[-1].filter(ImageFilter.GaussianBlur(shadow_blur))
    shadow_alpha_scale = int(round(255 * shadow_alpha))
    shadow = Image.new("RGBA", rotated.size, (0, 0, 0, 0))
    shadow.putalpha(shadow_mask.point(lambda p: p * shadow_alpha_scale // 255))

    canvas.alpha_composite(shadow, (rx, ry + shadow_offset_y))
    canvas.alpha_composite(rotated, (rx, ry))

output_path = sys.argv[1]
size = 1024
scale = size / 512.0
corner = int(round(115 * scale))

image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=corner, fill=(0x2F, 0x2B, 0x42, 255))

group_x = 256 * scale
group_y = 266 * scale
bar_w = int(round(56 * scale))
bar_h = int(round(240 * scale))
bar_r = int(round(28 * scale))
shadow_offset = int(round(15 * scale))
shadow_blur = int(round(10 * scale))

left_bar = gradient_pill(
    bar_w, bar_h, bar_r,
    (0xE6, 0xE6, 0xFA),
    (0x96, 0x7B, 0xB6),
    0.90,
)
right_bar = solid_pill(
    bar_w, bar_h, bar_r,
    (0x4A, 0xFA, 0x9C),
    0.95,
)

add_bar(
    image,
    left_bar,
    (group_x + (-57 * scale), group_y + (-20 * scale)),
    35,
    shadow_offset,
    shadow_blur,
    0.30,
)
add_bar(
    image,
    right_bar,
    (group_x + (53 * scale), group_y + (-20 * scale)),
    -35,
    shadow_offset,
    shadow_blur,
    0.30,
)

image.save(output_path, "PNG")
print(output_path)
PY

ICONSET_PARENT="$(mktemp -d "$RES_DIR/.AppIcon.XXXXXX")"
ICONSET_DIR="$ICONSET_PARENT/icon.iconset"
mkdir -p "$ICONSET_DIR"

sips -z 16 16 "$MASTER_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$MASTER_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$MASTER_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$MASTER_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$MASTER_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$MASTER_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$MASTER_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$MASTER_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$MASTER_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$MASTER_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"
rm -rf "$ICONSET_PARENT"
echo "[ok] generated icon: $ICNS_FILE"

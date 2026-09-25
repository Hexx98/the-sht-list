"""Addon icon for The Sh*t List: a list with a verdict on it.

64x64 TGA (what WoW's ## IconTexture wants), plus a 256x256 PNG for the CurseForge page.
A dark slate card with three "entry" lines, a green thumb on the top one and a red thumb
on the bottom, so it reads as "people, judged" even at 16 pixels in the addon list.
"""
from PIL import Image, ImageDraw
import os

K = 8  # supersample


def draw_icon(size):
    W = size * K
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = W / 64.0  # one "icon pixel"

    def box(x0, y0, x1, y1, r, fill):
        d.rounded_rectangle([x0 * u, y0 * u, x1 * u, y1 * u], radius=r * u, fill=fill)

    # card
    box(3, 3, 61, 61, 8, (18, 20, 24, 255))
    box(5, 5, 59, 59, 6, (38, 42, 50, 255))
    # header bar
    box(5, 5, 59, 17, 6, (58, 30, 34, 255))
    box(9, 9, 46, 13, 2, (210, 80, 80, 255))

    # three entries: name line + verdict dot
    rows = [
        (24, "good", (86, 214, 108, 255)),
        (40, "bad", (226, 84, 80, 255)),
    ]
    for y, kind, colour in rows:
        box(9, y + 2, 38, y + 8, 3, (120, 126, 138, 255))
        d.ellipse([42 * u, y * u, 56 * u, (y + 14) * u], fill=colour)
        # tick or cross inside the dot
        cx, cy = 49 * u, (y + 7) * u
        w = int(2.0 * u)
        if kind == "good":
            d.line([(cx - 3.0 * u, cy), (cx - 0.6 * u, cy + 2.6 * u), (cx + 3.2 * u, cy - 2.8 * u)],
                   fill=(16, 44, 22, 255), width=w, joint="curve")
        else:
            d.line([(cx - 2.6 * u, cy - 2.6 * u), (cx + 2.6 * u, cy + 2.6 * u)], fill=(56, 14, 14, 255), width=w)
            d.line([(cx - 2.6 * u, cy + 2.6 * u), (cx + 2.6 * u, cy - 2.6 * u)], fill=(56, 14, 14, 255), width=w)

    return img.resize((size, size), Image.LANCZOS)


out = r"H:\World of Warcraft\_classic_beta_\Interface\AddOns\TheShtList\media"
os.makedirs(out, exist_ok=True)
icon = draw_icon(64)
icon.save(os.path.join(out, "icon.tga"), compression=None)
draw_icon(256).save(os.path.join(os.path.dirname(__file__), "icon-256.png"))
# preview at the size it appears in the addon list, next to a big version
prev = Image.new("RGBA", (256 + 16 + 64, 256), (32, 32, 36, 255))
prev.paste(draw_icon(256), (0, 0))
prev.paste(icon.resize((64, 64), Image.LANCZOS), (272, 8))
prev.paste(icon.resize((16, 16), Image.LANCZOS).resize((64, 64), Image.NEAREST), (272, 88))
prev.save(os.path.join(os.path.dirname(__file__), "icon-preview.png"))
print("wrote", os.path.join(out, "icon.tga"), os.path.getsize(os.path.join(out, "icon.tga")), "bytes")

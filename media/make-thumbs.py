"""Draw thumbs-up / thumbs-down icons for The Shit List.

WoW wants uncompressed TGA with power-of-two dimensions. Inline texture markup (|T...|t)
can't be tinted, so the colour is baked in: one green file, one red file. Drawn at 8x and
downscaled for smooth edges, with a dark outline so they read on any row background.
"""
from PIL import Image, ImageDraw, ImageFilter

S = 64          # final size
K = 8           # supersample factor
W = S * K

OUTLINE = (12, 14, 12, 255)
GREEN = (74, 222, 96, 255)
GREEN_DARK = (32, 140, 56, 255)
RED = (240, 72, 68, 255)
RED_DARK = (150, 30, 28, 255)


def rr(draw, box, radius, fill):
    draw.rounded_rectangle([c * K for c in box], radius=radius * K, fill=fill)


def draw_thumb(fill, shade):
    """A thumbs-up, drawn in a 64x64 box: cuff at lower left, palm block, thumb up."""
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # outline pass: same shapes, fatter, in near-black
    for pass_fill, grow in ((OUTLINE, 2.5), (fill, 0)):
        g = grow
        # cuff / wrist at the lower left
        rr(d, (6 - g, 33 - g, 23 + g, 58 + g), 4, pass_fill)
        # palm / fist
        rr(d, (19 - g, 27 - g, 55 + g, 58 + g), 9, pass_fill)
        # thumb sticking up
        rr(d, (22 - g, 6 - g, 37 + g, 36 + g), 7.5, pass_fill)

    # finger creases on the palm, in the darker shade
    for y in (36.5, 44, 51.5):
        d.rounded_rectangle([c * K for c in (30, y, 52, y + 2.2)], radius=1.1 * K, fill=shade)
    # a little shading where the thumb meets the palm
    d.rounded_rectangle([c * K for c in (23, 30, 37, 32.2)], radius=1.1 * K, fill=shade)

    return img.resize((S, S), Image.LANCZOS)


up = draw_thumb(GREEN, GREEN_DARK)
down = draw_thumb(RED, RED_DARK).transpose(Image.FLIP_TOP_BOTTOM).transpose(Image.FLIP_LEFT_RIGHT)

out = r"H:\World of Warcraft\_classic_beta_\Interface\AddOns\TheShitList\media"
import os
os.makedirs(out, exist_ok=True)
up.save(os.path.join(out, "thumbsup.tga"), compression=None)
down.save(os.path.join(out, "thumbsdown.tga"), compression=None)

# also a preview PNG so the icons can be checked without launching the game
preview = Image.new("RGBA", (S * 2 + 24, S + 16), (40, 40, 44, 255))
preview.paste(up, (8, 8), up)
preview.paste(down, (S + 16, 8), down)
preview.resize(((S * 2 + 24) * 3, (S + 16) * 3), Image.NEAREST).save(
    os.path.join(os.path.dirname(__file__), "thumbs-preview.png"))

for f in ("thumbsup.tga", "thumbsdown.tga"):
    p = os.path.join(out, f)
    print(f, os.path.getsize(p), "bytes", Image.open(p).size, Image.open(p).mode)

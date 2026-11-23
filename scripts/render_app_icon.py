"""Render the Hush app icon (design 08) into App/Hush/Assets.xcassets/AppIcon.appiconset.

Graphite rounded square; a cobalt dot followed by two fading frosted-glass dots.
Requires Pillow.
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "App/Hush/Assets.xcassets/AppIcon.appiconset"
S = 4096  # supersampled canvas, scaled down at the end

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))

def vgradient(size, top, bottom):
    w, h = size
    g = Image.new("RGBA", size)
    d = ImageDraw.Draw(g)
    for y in range(h):
        d.line([(0, y), (w, y)], fill=lerp(top, bottom, y / max(h - 1, 1)))
    return g

def circle_mask(size, box):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).ellipse(box, fill=255)
    return m

def render():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # macOS icon grid: 824/1024 body, centred, corner radius ~ 185/1024.
    inset = int(S * 100 / 1024)
    body = (inset, inset, S - inset, S - inset)
    radius = int(S * 185 / 1024)

    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((body[0], body[1] + S // 64, body[2], body[3] + S // 64), radius, fill=(10, 12, 18, 150))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(S // 60)))

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(body, radius, fill=255)
    bg = vgradient((S, S), (44, 46, 52, 255), (18, 19, 22, 255))
    img.paste(bg, (0, 0), mask)

    # hairline highlight on the top edge
    hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(hl).rounded_rectangle(body, radius, outline=(255, 255, 255, 30), width=S // 256)
    img.alpha_composite(hl)

    unit = (body[2] - body[0]) / 300  # design was drawn on a 300px tile
    ox, oy = body[0], body[1]
    def box(x, y, d): return (int(ox + x * unit), int(oy + y * unit), int(ox + (x + d) * unit), int(oy + (y + d) * unit))

    # dot 1: cobalt
    b1 = box(52, 104, 96)
    blue = vgradient((S, S), (56, 134, 249, 255), (5, 75, 188, 255))
    blue_local = vgradient((b1[2] - b1[0], b1[3] - b1[1]), (56, 134, 249, 255), (5, 75, 188, 255))
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    layer.paste(blue_local, (b1[0], b1[1]))
    img.paste(layer, (0, 0), circle_mask((S, S), b1))

    # dot 2: frosted glass, with a soft drop shadow
    b2 = box(124, 118, 68)
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse((b2[0], b2[1] + int(6 * unit), b2[2], b2[3] + int(6 * unit)), fill=(0, 0, 0, 90))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(int(8 * unit))))
    glass = vgradient((b2[2] - b2[0], b2[3] - b2[1]), (255, 255, 255, 236), (206, 209, 216, 190))
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    layer.paste(glass, (b2[0], b2[1]))
    m2 = circle_mask((S, S), b2)
    # frosted: blur what's underneath inside the dot, then lay the glass on top
    under = img.filter(ImageFilter.GaussianBlur(int(10 * unit)))
    img.paste(under, (0, 0), m2)
    img.paste(Image.alpha_composite(img, layer), (0, 0), m2)

    # dot 3: faint glass
    b3 = box(206, 132, 40)
    faint = vgradient((b3[2] - b3[0], b3[3] - b3[1]), (255, 255, 255, 150), (214, 216, 222, 80))
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    layer.paste(faint, (b3[0], b3[1]))
    m3 = circle_mask((S, S), b3)
    img.paste(Image.alpha_composite(img, layer), (0, 0), m3)
    return img

def main():
    os.makedirs(OUT, exist_ok=True)
    master = render()
    images = []
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            master.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)

if __name__ == "__main__":
    main()

# Builds every app icon from assets/icon/logo.png:
#
#   python tool/make_icons.py        (needs Pillow: pip install pillow)
#
#   * ic_launcher.png             legacy icon, the logo with its own rounded corners
#   * ic_launcher_foreground.png  adaptive icon (Android 8+): the logo shrunk so the
#                                 bag sits in the safe zone, its edge melting into
#                                 the teal background so any launcher mask looks clean
#   * ic_launcher_monochrome.png  themed icon (Android 13+): bag and handle in one
#                                 tone, the man's outline, face, cane and shawl cut out
#   * play_store_512.png          opaque full-bleed square (Play adds its own mask)
#   * assets/icon/logo_app.png    small copy with transparent corners for in-app use
import os
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "icon", "logo.png")
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
TEAL = (10, 98, 98)
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def rounded_mask(size, radius, scale=4):
    big = Image.new("L", (size * scale, size * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, size * scale - 1, size * scale - 1), radius * scale, fill=255)
    return big.resize((size, size), Image.LANCZOS)


def load():
    logo = Image.open(SRC).convert("RGB")
    n = logo.size[0]
    # the art sits on a rounded square with black outside the corners
    radius = int(n * 0.125)
    inside = rounded_mask(n, radius).filter(ImageFilter.MinFilter(9))
    full = Image.new("RGB", (n, n), TEAL)
    full.paste(logo, (0, 0), inside)
    return logo, full, radius


def save(img, path, px):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((px, px), Image.LANCZOS).save(path, optimize=True)
    print("wrote", os.path.relpath(path, ROOT), f"{px}x{px}")


def main():
    logo, full, radius = load()
    n = full.size[0]

    # legacy: the logo as drawn, corners transparent instead of black
    legacy = full.convert("RGBA")
    legacy.putalpha(rounded_mask(n, radius))

    # adaptive foreground on the 108-unit grid; the logo fills 72 units so the
    # bag sits inside the 66-unit safe circle, and its border fades into plain teal
    grid = 1080
    art = int(grid * 72 / 108)
    fg = Image.new("RGB", (grid, grid), TEAL)
    feather = Image.new("L", (art, art), 0)
    edge = int(art * 0.07)
    ImageDraw.Draw(feather).rounded_rectangle((edge, edge, art - edge, art - edge), edge * 2, fill=255)
    feather = feather.filter(ImageFilter.GaussianBlur(edge * 0.6))
    off = (grid - art) // 2
    fg.paste(full.resize((art, art), Image.LANCZOS), (off, off), feather)

    # monochrome: anything bright (cream bag, gold handle and studs) is kept,
    # dark detail inside the bag becomes a hole
    small = full.resize((art, art), Image.LANCZOS)
    r, g, b = small.split()
    lum = Image.merge("RGB", (r, g, b)).convert("L")
    # cream and white only; the soft grey folds of the robe and shawl are cut
    # too, so the man's outline survives in a single tone
    bright = lum.point(lambda v: 255 if v > 205 else 0)
    # gold is warm and light; skin is warm but darker, so it stays a hole
    warm = ImageChops.subtract(r, b).point(lambda v: 255 if v > 70 else 0)
    light = g.point(lambda v: 255 if v > 140 else 0)
    gold = ImageChops.multiply(warm, light)
    shape = ImageChops.lighter(bright, gold).filter(ImageFilter.MedianFilter(5))
    mono = Image.new("RGBA", (grid, grid), (0, 0, 0, 0))
    white = Image.new("RGBA", (art, art), (255, 255, 255, 255))
    mono.paste(white, (off, off), shape)

    for name, mult in DENSITIES.items():
        folder = os.path.join(RES, f"mipmap-{name}")
        save(legacy, os.path.join(folder, "ic_launcher.png"), int(48 * mult))
        save(fg, os.path.join(folder, "ic_launcher_foreground.png"), int(108 * mult))
        save(mono, os.path.join(folder, "ic_launcher_monochrome.png"), int(108 * mult))

    save(full, os.path.join(ROOT, "assets", "icon", "play_store_512.png"), 512)
    save(legacy, os.path.join(ROOT, "assets", "icon", "logo_app.png"), 384)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Purpose-built social images for LevelSelect.

Link unfurlers (Reddit, Mastodon, Bluesky, iMessage, Slack) show a small,
hard-cropped thumbnail — a UI screenshot turns to mush at that size, which
is exactly what happened when the site had no og:image and Reddit scavenged
one off the page. These are built to read at thumbnail size: wordmark, one
short line, one device shot, nothing else.

Palette and font are the site's own (style.css / Theme.swift), so a preview
looks like the thing it links to.

    python3 scripts/make-social-images.py
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
PUB = ROOT / "public"
OUT = PUB / "social"
OUT.mkdir(parents=True, exist_ok=True)

GROUND      = (13, 10, 23)
GROUND_LIFT = (26, 18, 46)
ACCENT      = (148, 92, 250)
TORCH       = (245, 163, 77)
TORCH_DEEP  = (138, 74, 18)
INK         = (239, 234, 251)
MUTED       = (153, 144, 184)

# NOT necessarily the hero's shot — these are chosen for legibility at
# thumbnail size, which is the only job a link preview has. The Home shelf is a
# dense grid of small covers: fine on the site, mush in a Reddit unfurl. A game
# page carries one big logo that survives being shrunk. The hero went back to
# Home when the site turned out to have no picture of the app's front door
# anywhere; this stayed put on purpose.
#
# Updated to the build-33 shot 2026-08-30. Same composition and the same
# reasoning — a game page, not Home — just the current app. Build 33's Home
# does now carry a big pixel name that would survive a thumbnail, but a
# wordmark over key art still beats it, and the unfurl should look like the
# thing people are shown first when they open a game.
PHONE_SHOT = "iphone-33-layout-showcase.webp"
IPAD_SHOT  = "ipad-01-split-tracker.webp"

PIXEL = str(PUB / "assets" / "PressStart2P-Regular.ttf")
SANS  = "/System/Library/Fonts/SFNS.ttf"


def gradient(size):
    """The app's own vertical background."""
    w, h = size
    img = Image.new("RGB", (1, h))
    px = img.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        px[0, y] = tuple(round(GROUND_LIFT[i] + (GROUND[i] - GROUND_LIFT[i]) * t) for i in range(3))
    return img.resize(size, Image.BILINEAR).convert("RGBA")


def glow(img, center, radius, colour, strength=0.30):
    """Soft torchlight, the same halo the site puts behind its hero."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x, y = center
    d.ellipse([x - radius, y - radius, x + radius, y + radius],
              fill=colour + (int(255 * strength),))
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.55))
    return Image.alpha_composite(img, layer)


def shot(name, height):
    im = Image.open(PUB / "assets" / "shots" / name).convert("RGBA")
    w = round(im.width * height / im.height)
    return im.resize((w, height), Image.LANCZOS)


def devices(pair, height):
    """The hero art: one phone, or the site's phone-in-front-of-iPad pairing.

    `height` is the tallest device, so callers can budget vertical space and
    keep text clear of the art — the square's URL used to land on top of the
    phone because nothing was measuring this.
    """
    # The pairing mirrors the hero's arrangement — phone in front of iPad —
    # so a preview reads as the same product. The individual shots are picked
    # for thumbnail legibility instead; see PHONE_SHOT.
    phone = shot(PHONE_SHOT, height)
    if not pair:
        return phone

    pad = shot(IPAD_SHOT, round(height * 0.74))
    overlap = round(phone.width * 0.46)
    canvas = Image.new("RGBA", (phone.width + pad.width - overlap, height), (0, 0, 0, 0))
    # iPad behind and slightly high, phone in front-left — the arrangement the
    # homepage hero uses, so the two read as one product on several screens.
    canvas.alpha_composite(pad, (phone.width - overlap, round(height * 0.10)))
    canvas.alpha_composite(phone, (0, 0))
    return canvas


def wordmark(img, xy, size, anchor="lt"):
    """The site's wordmark, both shadows included.

    style.css uses *two*: a zero-blur offset at 0.16em for legibility (pixel
    strokes are thin and blur eats their corners) and a soft torch glow at
    0.65em that fills the gaps between strokes. Drawing only the hard one —
    as the first pass did — gives a wordmark that reads thin and unlit next
    to the real thing. CSS blur radius r is roughly a Gaussian sigma of r/2.
    """
    f = ImageFont.truetype(PIXEL, size)
    x, y = xy

    glow_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow_layer).text((x, y), "LevelSelect", font=f,
                                    fill=TORCH + (77,), anchor=anchor)   # .3 alpha
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(size * 0.65 / 2))
    img = Image.alpha_composite(img, glow_layer)

    d = ImageDraw.Draw(img)
    d.text((x, y + size * 0.16), "LevelSelect", font=f, fill=TORCH_DEEP, anchor=anchor)
    d.text((x, y), "LevelSelect", font=f, fill=TORCH, anchor=anchor)
    return img


def sans(size, weight=400):
    """SF Pro at a real weight.

    Its variable axes are [Width, Optical Size, GRAD, Weight] — passing a
    single value sets WIDTH, not weight, which stretches every letterform to
    the 150 maximum. Set all four, and let optical size track the point size
    the way the system does.
    """
    f = ImageFont.truetype(SANS, size)
    try:
        f.set_variation_by_axes([100, max(17, min(96, size)), 400, weight])
    except Exception:
        pass
    return f


# ─────────────────────────── 1200x630 — link previews ───────────────────────
def open_graph(pair):
    W, H = 1200, 630
    img = gradient((W, H))
    img = glow(img, (250, 250), 340, TORCH, 0.20)
    img = glow(img, (980, 430), 380, ACCENT, 0.16)

    icon = Image.open(PUB / "assets" / "icon.png").convert("RGBA").resize((128, 128), Image.LANCZOS)
    img.paste(icon, (74, 92), icon)

    img = wordmark(img, (74, 250), 62)
    d = ImageDraw.Draw(img)
    d.text((74, 352), "Every game you're playing,", font=sans(32, 400), fill=INK)
    d.text((74, 396), "and exactly where you left off.", font=sans(32, 400), fill=INK)
    d.text((74, 462), "Library · session timer · progress tracker",
           font=sans(24, 400), fill=MUTED)
    d.text((74, 508), "iPhone · iPad · Mac · Watch", font=sans(22, 400), fill=MUTED)
    d.text((74, 560), "levelselect.app", font=sans(28, 600), fill=TORCH)

    # Bled off the right edge so a crop can't behead it. The pair starts
    # further right and stands shorter: the wordmark runs to ~x756 at 62px
    # (Press Start 2P is one em per character), and the phone was landing on
    # its final letter.
    art = devices(pair, 700 if not pair else 470)
    img.alpha_composite(art, (835, 92) if not pair else (788, 84))
    return img, f"og{'-2up' if pair else ''}.png"


# ─────────────────────────── 1080x1920 — Instagram story ────────────────────
def story(pair):
    W, H = 1080, 1920
    img = gradient((W, H))
    img = glow(img, (540, 430), 520, TORCH, 0.20)
    img = glow(img, (540, 1500), 620, ACCENT, 0.16)

    icon = Image.open(PUB / "assets" / "icon.png").convert("RGBA").resize((150, 150), Image.LANCZOS)
    img.paste(icon, (465, 300), icon)

    img = wordmark(img, (540, 495), 66, anchor="mt")
    d = ImageDraw.Draw(img)
    d.text((540, 610), "Every game you're playing,", font=sans(34, 400), fill=INK, anchor="mt")
    d.text((540, 656), "and exactly where you left off.", font=sans(34, 400), fill=INK, anchor="mt")

    # Art sits between the tagline and the footer, scaled to whatever room is
    # left rather than a fixed height that could collide with either.
    top, footer_top = 770, 1700
    art = devices(pair, min(900, footer_top - top - 40))
    if art.width > W - 80:
        art = art.resize((W - 80, round(art.height * (W - 80) / art.width)), Image.LANCZOS)
    img.alpha_composite(art, ((W - art.width) // 2, top))

    d.text((540, footer_top + 12), "TestFlight beta", font=sans(30, 600), fill=MUTED, anchor="mt")
    d.text((540, footer_top + 62), "levelselect.app", font=sans(46, 700), fill=TORCH, anchor="mt")
    return img, f"instagram-story{'-2up' if pair else ''}.png"


# ─────────────────────────── 1080x1080 — feed square ────────────────────────
def square(pair):
    W = H = 1080
    img = gradient((W, H))
    img = glow(img, (540, 300), 420, TORCH, 0.20)

    icon = Image.open(PUB / "assets" / "icon.png").convert("RGBA").resize((120, 120), Image.LANCZOS)
    img.paste(icon, (480, 104), icon)

    img = wordmark(img, (540, 268), 54, anchor="mt")
    d = ImageDraw.Draw(img)
    d.text((540, 366), "Every game you're playing,", font=sans(29, 400), fill=INK, anchor="mt")
    d.text((540, 406), "and exactly where you left off.", font=sans(29, 400), fill=INK, anchor="mt")

    top, footer_top = 486, 990
    art = devices(pair, footer_top - top - 36)
    if art.width > W - 80:
        art = art.resize((W - 80, round(art.height * (W - 80) / art.width)), Image.LANCZOS)
    img.alpha_composite(art, ((W - art.width) // 2, top))

    d.text((540, footer_top + 6), "levelselect.app", font=sans(34, 700), fill=TORCH, anchor="mt")
    return img, f"instagram-square{'-2up' if pair else ''}.png"


for build in (open_graph, story, square):
    for pair in (False, True):
        img, name = build(pair)
        img.convert("RGB").save(OUT / name, quality=94)
        print(f"{name}  {img.size[0]}x{img.size[1]}")

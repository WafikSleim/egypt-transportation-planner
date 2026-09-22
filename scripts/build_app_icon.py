"""Draw the app icon, the adaptive foreground and the two splash marks.

Run after changing any proportion here:

    python scripts/build_app_icon.py

Both the SVG and the PNG for each asset come out of this file, so they cannot
drift apart. The SVGs are the human-readable record; the PNGs are what
`flutter_launcher_icons` and `flutter_native_splash` actually consume.

THE MARK IS ONE IDEA: a trip. A small node where you are, a route that turns
twice, a larger node where you are going. No vehicle, no map, no lettering —
all three turn to mush at 48dp on a cheap phone, which is the size that
decides whether an icon works.

THE JOURNEY RUNS RIGHT TO LEFT, because every screen in this app is RTL and
the trip should start on the side an Egyptian reader starts on. Mirroring it
would match the English port rather than the source language.

THE COLOUR IS THE ACCENT, AND THAT IS A RULE, NOT A PREFERENCE. `#4A3FA0` is
chosen in docs/design-system.md precisely because it is neither a licence-plate
colour nor a metro line colour. Microbus orange, tomnaya blue and the three
metro colours all *mean* something in this product; spending one on branding
would make the launcher icon claim a mode, and would cheapen that colour on
every screen inside.

THE NODES MUST NOT TOUCH THE ROUTE. Each node sits a clear gap away from the
end of the stroke. The first draft of this mark had the small node barely
wider than the stroke itself and overlapping it, which made it read as a
rounded line-end rather than as a stop — the icon became a bent pipe with a
knob on it. Keep `GAP` positive and keep every node radius comfortably larger
than half the stroke width, or the whole idea stops being legible.
"""

import io
import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "app", "assets", "icon")

ACCENT = "#4A3FA0"      # design-system accent, light
ACCENT_DARK = "#9A90F0"  # design-system accent, dark
INK_ON_ACCENT = "#FBFAF7"  # the `bg` token: warm, not pure white

# Geometry of the mark, in a 1024 frame, measured from the frame centre.
# Everything else is derived from these six numbers.
STROKE = 96
SMALL_R = 80
LARGE_R = 126
GAP = 28                 # clear space between a node and the end of the route
SMALL_AT = (738, 800)    # where you are
LARGE_AT = (330, 262)    # where you are going, larger so the mark has a direction
CORNER_Y = 540           # the horizontal run

FRAME = 1024
CENTRE = FRAME / 2


def route_points():
    """The polyline, stopping short of both nodes by [GAP]."""
    start_y = SMALL_AT[1] - SMALL_R - GAP - STROKE / 2
    end_y = LARGE_AT[1] + LARGE_R + GAP + STROKE / 2
    return [
        (SMALL_AT[0], start_y),
        (SMALL_AT[0], CORNER_Y),
        (LARGE_AT[0], CORNER_Y),
        (LARGE_AT[0], end_y),
    ]


def mark_radius():
    """Distance from the frame centre to the outermost edge of the mark.

    Used to size the mark inside Android's adaptive safe circle and inside the
    splash circle, both of which crop anything outside them without warning.
    """
    out = 0.0
    for (x, y), r in ((SMALL_AT, SMALL_R), (LARGE_AT, LARGE_R)):
        out = max(out, math.hypot(x - CENTRE, y - CENTRE) + r)
    return out


def scaled(scale, frame):
    """The mark scaled about its centre and re-centred in `frame`."""
    c = frame / 2

    def place(p):
        return (c + (p[0] - CENTRE) * scale, c + (p[1] - CENTRE) * scale)

    return {
        "stroke": STROKE * scale,
        "small": (place(SMALL_AT), SMALL_R * scale),
        "large": (place(LARGE_AT), LARGE_R * scale),
        "route": [place(p) for p in route_points()],
    }


def svg(geo, frame, colour, background=None):
    path = " ".join(
        ("M" if i == 0 else "L") + " {:.0f} {:.0f}".format(*p)
        for i, p in enumerate(geo["route"])
    )
    bg = ('  <rect width="{0}" height="{0}" fill="{1}"/>\n'.format(frame, background)
          if background else "")
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {0} {0}" '
        'width="{0}" height="{0}">\n{1}'
        '  <g fill="none" stroke="{2}" stroke-width="{3:.0f}" '
        'stroke-linecap="round" stroke-linejoin="round">\n'
        '    <path d="{4}"/>\n'
        '  </g>\n'
        '  <circle cx="{5:.0f}" cy="{6:.0f}" r="{7:.0f}" fill="{2}"/>\n'
        '  <circle cx="{8:.0f}" cy="{9:.0f}" r="{10:.0f}" fill="{2}"/>\n'
        '</svg>\n'
    ).format(
        frame, bg, colour, geo["stroke"], path,
        geo["small"][0][0], geo["small"][0][1], geo["small"][1],
        geo["large"][0][0], geo["large"][0][1], geo["large"][1],
    )


def png(geo, frame, colour, background=None, ss=4):
    """Drawn at 4x and downscaled, since PIL has no antialiasing of its own."""
    size = frame * ss
    img = Image.new("RGBA", (size, size), background or (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    width = int(round(geo["stroke"] * ss))
    pts = [(x * ss, y * ss) for x, y in geo["route"]]
    draw.line(pts, fill=colour, width=width)
    # Round every join and both caps. PIL's `joint="curve"` does not round the
    # ends, and a square end here reads as a broken route.
    for x, y in pts:
        r = width / 2
        draw.ellipse([x - r, y - r, x + r, y + r], fill=colour)

    for (cx, cy), r in (geo["small"], geo["large"]):
        cx, cy, r = cx * ss, cy * ss, r * ss
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=colour)

    return img.resize((frame, frame), Image.LANCZOS)


def write(name, geo, frame, colour, svg_bg=None, png_bg=None):
    io.open(os.path.join(OUT, name + ".svg"), "w", encoding="utf-8",
            newline="\n").write(svg(geo, frame, colour, svg_bg))
    png(geo, frame, colour, png_bg).save(os.path.join(OUT, name + ".png"))
    print("  {}.svg + {}.png".format(name, name))


def main():
    os.makedirs(OUT, exist_ok=True)

    # The gap is measured from the outer edge of the round cap to the edge of
    # the node, which is what the eye actually sees - not from the path vertex.
    cap_end = route_points()[0][1] + STROKE / 2
    node_edge = SMALL_AT[1] - SMALL_R
    assert SMALL_R > STROKE / 2 + 8, "the small node would read as a line-end"
    assert abs((node_edge - cap_end) - GAP) < 1,         "the route overlaps the node it points at"
    print("mark radius {:.0f} in a {} frame".format(mark_radius(), FRAME))

    # The full square: iOS, and Android's legacy launcher.
    write("icon", scaled(1.0, FRAME), FRAME, INK_ON_ACCENT, svg_bg=ACCENT,
          png_bg=ACCENT)

    # Android adaptive foreground. The safe zone is the inner 66.6% circle;
    # anything outside it is cropped by some launcher masks and not others,
    # which is how an icon ends up looking fine on one phone and clipped on
    # the next.
    safe = FRAME * 0.666 / 2
    write("icon-foreground", scaled(safe / mark_radius(), FRAME), FRAME,
          INK_ON_ACCENT)

    # Splash. Android 12+ masks the splash icon to a circle far tighter than
    # most people expect, so the mark is sized for that and the same image
    # serves the legacy slot too.
    splash_frame = 1152
    splash_scale = (560 / 2) / mark_radius() * (FRAME / FRAME)
    geo = scaled(splash_scale, splash_frame)
    write("splash", geo, splash_frame, ACCENT)
    write("splash-dark", geo, splash_frame, ACCENT_DARK)

    print("done")


if __name__ == "__main__":
    main()

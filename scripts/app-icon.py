"""Render the Health app icon and its three design drafts with Pillow."""

from math import cos, radians, sin
from pathlib import Path

from PIL import Image, ImageDraw


SIZE = 1024
SCALE = 4
CANVAS = (SIZE * SCALE, SIZE * SCALE)
ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "forma-ios/Forma/Resources/Assets.xcassets/AppIcon.appiconset"
DRAFTS = ROOT / ".teamarbeit/icon-entwuerfe"


def scaled(point):
    return tuple(round(value * SCALE) for value in point)


def silhouette(start, curves):
    """Rasterize a closed outline made of cubic Bézier segments."""
    mask = Image.new("L", CANVAS)
    points = [scaled(start)]
    for control_a, control_b, end in curves:
        for step in range(1, 65):
            t = step / 64
            u = 1 - t
            points.append(scaled(tuple(
                u**3 * a + 3 * u**2 * t * b + 3 * u * t**2 * c + t**3 * d
                for a, b, c, d in zip(start, control_a, control_b, end)
            )))
        start = end
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask


def auftrieb():
    # A rising shoulder and an inward-folded end shape the open arch.
    # The slim left tip ends in a short capsule.
    return silhouette((197, 619), (
        ((186, 461), (281, 327), (425, 270)),
        ((566, 214), (720, 262), (790, 384)),
        ((855, 498), (831, 644), (739, 731)),
        ((694, 774), (628, 781), (594, 738)),
        ((567, 704), (584, 672), (620, 641)),
        ((679, 590), (702, 513), (663, 451)),
        ((624, 388), (545, 362), (462, 389)),
        ((361, 422), (306, 508), (304, 613)),
        ((303, 653), (282, 678), (249, 679)),
        ((218, 680), (199, 654), (197, 619)),
    ))


def kern():
    mask = Image.new("L", CANVAS)
    draw = ImageDraw.Draw(mask)
    x, y = 512, 503
    radius, width = 265, 104
    angles = (140, 400)
    draw.arc(scaled((x - radius, y - radius, x + radius, y + radius)),
             *angles, fill=255, width=width * SCALE)
    for degrees in angles:
        angle = radians(degrees)
        half_width = width / 2
        cap_x = x + (radius - half_width) * cos(angle)
        cap_y = y + (radius - half_width) * sin(angle)
        draw.ellipse(scaled((cap_x - half_width, cap_y - half_width,
                             cap_x + half_width, cap_y + half_width)), fill=255)
    draw.rounded_rectangle(scaled((440, 456, 584, 775)), radius=72 * SCALE, fill=255)
    return mask


def relais():
    # Two offset capsules share a shoulder, forming a compact ascending step.
    return silhouette((222, 654), (
        ((222, 541), (302, 489), (399, 489)),
        ((484, 489), (523, 459), (523, 383)),
        ((523, 301), (574, 247), (654, 247)),
        ((740, 247), (801, 308), (801, 398)),
        ((801, 510), (723, 567), (624, 567)),
        ((539, 567), (500, 597), (500, 661)),
        ((500, 726), (445, 777), (365, 777)),
        ((285, 777), (222, 727), (222, 654)),
    ))


def render(mask, ground, light, top, bottom):
    # Position the soft highlight above the middle. iOS supplies the corner mask.
    falloff = Image.radial_gradient("L").transform(
        CANVAS, Image.Transform.AFFINE, (0.0425, 0, 41, 0, 0.0425, 74),
        resample=Image.Resampling.BILINEAR,
    )
    background = Image.composite(
        Image.new("RGB", CANVAS, ground), Image.new("RGB", CANVAS, light), falloff,
    )
    tone = Image.linear_gradient("L").resize(CANVAS, Image.Resampling.BILINEAR)
    mark = Image.composite(
        Image.new("RGB", CANVAS, bottom), Image.new("RGB", CANVAS, top), tone,
    )
    artwork = Image.composite(mark, background, mask)
    return artwork.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def main():
    DRAFTS.mkdir(parents=True, exist_ok=True)
    standard = ("#C9D8CB", "#F2FAE9", "#171D1C", "#305C45")
    winner = auftrieb()
    default_icon = render(winner, *standard)
    default_icon.save(DRAFTS / "01-auftrieb.png")
    render(kern(), *standard).save(DRAFTS / "02-kern.png")
    render(relais(), *standard).save(DRAFTS / "03-relais.png")

    default_icon.save(ASSETS / "icon.png")
    render(winner, "#111313", "#303733", "#E5FFC8", "#70B88D").save(
        ASSETS / "icon-dark.png"
    )
    render(winner, "#000000", "#000000", "#FFFFFF", "#DDDDDD").convert("L").save(
        ASSETS / "icon-tinted.png"
    )


if __name__ == "__main__":
    main()

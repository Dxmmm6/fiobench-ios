#!/usr/bin/env python3
"""Generate the 1024x1024 app icon without third-party dependencies."""

import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "FioBench" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"


def lerp(a, b, t):
    return int(round(a + (b - a) * t))


def rounded_rect_distance(x, y, left, top, right, bottom, radius):
    cx = min(max(x, left + radius), right - radius)
    cy = min(max(y, top + radius), bottom - radius)
    return math.hypot(x - cx, y - cy)


def pixel(x, y):
    # Deep navy background with a soft blue glow.
    t = y / (SIZE - 1)
    r = lerp(10, 20, t)
    g = lerp(13, 31, t)
    b = lerp(18, 48, t)

    # Diagonal blue field.
    d = (x + y) / (2.0 * SIZE)
    glow = max(0.0, 1.0 - d)
    r = min(255, int(r + 18 * glow))
    g = min(255, int(g + 44 * glow))
    b = min(255, int(b + 90 * glow))

    # Inset rounded panel.
    panel_dist = rounded_rect_distance(x, y, 72, 72, 952, 952, 190)
    if panel_dist <= 190:
        edge = max(0.0, min(1.0, (190 - panel_dist) / 12.0))
        pr = lerp(r, 28, 0.72 * edge)
        pg = lerp(g, 40, 0.72 * edge)
        pb = lerp(b, 66, 0.72 * edge)
        r, g, b = int(pr), int(pg), int(pb)

        # Three ascending bars.
        bars = [
            (250, 585, 340),
            (438, 455, 470),
            (626, 300, 670),
        ]
        for left, top, bottom in bars:
            right = left + 136
            bd = rounded_rect_distance(x, y, left, top, right, bottom, 30)
            if bd <= 30:
                aa = max(0.0, min(1.0, (30 - bd) / 3.0))
                r = lerp(r, 245, aa)
                g = lerp(g, 248, aa)
                b = lerp(b, 252, aa)

        # Accent baseline.
        if 250 <= x <= 790 and 735 <= y <= 748:
            aa = 1.0 if 738 <= y <= 745 else 0.45
            r = lerp(r, 76, aa)
            g = lerp(g, 141, aa)
            b = lerp(b, 255, aa)

        # Thin top highlight.
        if abs(panel_dist - 187.0) < 2.2:
            r = min(255, r + 16)
            g = min(255, g + 28)
            b = min(255, b + 44)

    return r, g, b


def chunk(kind, data):
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    )


def main():
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)  # filter type: None
        for x in range(SIZE):
            r, g, b = pixel(x, y)
            raw.extend((r & 0xFF, g & 0xFF, b & 0xFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(png)
    print(f"wrote {OUT} ({len(png)} bytes)")


if __name__ == "__main__":
    main()

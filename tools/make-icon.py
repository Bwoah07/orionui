"""Draws OrionUI's addon icon (our own media, Stig 2026-10-02).

Writes OrionUI/Media/Textures/OrionIcon.tga, 64x64 32-bit: a dark rounded square, an
OrionUI-blue orbit ring and Orion's belt (three stars) with two shoulder/foot stars.
Pure Python (no PIL), 4x4 supersampling. Re-run after changing the design.
"""
import math
import os
import struct

SIZE = 64
SS = 4
OUT = os.path.join(os.path.dirname(__file__), "..", "OrionUI", "Media", "Textures", "OrionIcon.tga")

BLUE = (0.25, 0.56, 0.98)          # a touch brighter than the UI accent so it reads small
TOP, BOTTOM = (0.11, 0.14, 0.21), (0.04, 0.05, 0.08)
STAR = (0.92, 0.96, 1.0)
RADIUS = 0.2                         # rounded-square corner radius

BELT = [(0.35, 0.585, 0.052), (0.5, 0.5, 0.062), (0.65, 0.415, 0.052)]
EXTRA = [(0.26, 0.24, 0.034), (0.75, 0.77, 0.04)]
RING_RX, RING_RY, RING_ANGLE, RING_W = 0.37, 0.15, math.radians(-29.6), 0.035


def in_square(x, y):
    m = 0.02
    if x < m or y < m or x > 1 - m or y > 1 - m:
        return False
    cx = min(max(x, m + RADIUS), 1 - m - RADIUS)
    cy = min(max(y, m + RADIUS), 1 - m - RADIUS)
    return (x - cx) ** 2 + (y - cy) ** 2 <= RADIUS ** 2


def ring(x, y):
    """Coverage of the tilted ellipse stroke at (x, y)."""
    dx, dy = x - 0.5, y - 0.5
    c, s = math.cos(-RING_ANGLE), math.sin(-RING_ANGLE)
    u, v = dx * c - dy * s, dx * s + dy * c
    d = math.sqrt((u / RING_RX) ** 2 + (v / RING_RY) ** 2)
    # approximate distance to the ellipse in texture units
    dist = abs(d - 1) * min(RING_RX, RING_RY) * 1.6
    return 1.0 if dist <= RING_W / 2 else 0.0


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def shade(x, y):
    """Colour (r, g, b) and alpha of one sample."""
    if not in_square(x, y):
        return (0, 0, 0), 0.0
    col = mix(TOP, BOTTOM, y)
    # faint blue haze in the middle
    haze = math.exp(-((x - 0.5) ** 2 + (y - 0.5) ** 2) / 0.06) * 0.35
    col = mix(col, BLUE, haze * 0.5)
    if ring(x, y):
        col = mix(col, BLUE, 0.95)
    for sx, sy, r in BELT + EXTRA:
        d2 = (x - sx) ** 2 + (y - sy) ** 2
        glow = math.exp(-d2 / (r * r * 2.2)) * 0.85
        col = mix(col, mix(BLUE, STAR, 0.5), min(1, glow))
        if d2 <= (r * 0.55) ** 2:
            col = STAR
    return col, 1.0


def main():
    px = bytearray()
    for row in range(SIZE):
        for colx in range(SIZE):
            acc, alpha = [0.0, 0.0, 0.0], 0.0
            for sy in range(SS):
                for sx in range(SS):
                    x = (colx + (sx + 0.5) / SS) / SIZE
                    y = (row + (sy + 0.5) / SS) / SIZE
                    c, a = shade(x, y)
                    for i in range(3):
                        acc[i] += c[i] * a
                    alpha += a
            n = SS * SS
            if alpha > 0:
                r, g, b = (acc[i] / alpha for i in range(3))
            else:
                r = g = b = 0
            px += bytes((round(b * 255), round(g * 255), round(r * 255), round(255 * alpha / n)))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    with open(OUT, "wb") as f:
        f.write(header + px)
    print("wrote", os.path.normpath(OUT))


if __name__ == "__main__":
    main()

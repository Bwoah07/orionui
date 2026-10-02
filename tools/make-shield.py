"""Draws the top bar's guild shield textures (our own media, Stig 2026-10-02).

Writes two white 64x64 32-bit TGAs the game tints at runtime:
  IconShield.tga      the whole shield (filled with the guild's background colour)
  IconShieldEdge.tga  its rim (tinted with the guild's border colour)
Pure Python (no PIL), 4x4 supersampling for smooth edges. Re-run after changing the shape.
"""
import math
import os
import struct

SIZE = 64
SS = 4            # supersamples per axis
RIM = 0.075       # rim thickness, fraction of the texture
OUT = os.path.join(os.path.dirname(__file__), "..", "OrionUI", "Media", "Textures")


def inside(x, y):
    """Heater shield in 0..1 space: rounded top corners, straight sides, curved point."""
    top, mid, bottom, half = 0.07, 0.48, 0.95, 0.39
    dx = abs(x - 0.5)
    if y < top or y > bottom:
        return False
    if y <= mid:
        corner = 0.08
        if dx > half - corner and y < top + corner:   # rounded top corners
            cx, cy = half - corner, top + corner
            return (dx - cx) ** 2 + (y - cy) ** 2 <= corner ** 2
        return dx <= half
    t = (y - mid) / (bottom - mid)
    return dx <= half * (1 - t ** 1.7) ** 0.7


def on_rim(x, y):
    if not inside(x, y):
        return False
    for i in range(16):
        a = i * math.pi / 8
        if not inside(x + RIM * math.cos(a), y + RIM * math.sin(a)):
            return True
    return False


def render(test):
    px = bytearray()
    for row in range(SIZE):
        for col in range(SIZE):
            hits = 0
            for sy in range(SS):
                for sx in range(SS):
                    x = (col + (sx + 0.5) / SS) / SIZE
                    y = (row + (sy + 0.5) / SS) / SIZE
                    hits += test(x, y)
            a = round(255 * hits / (SS * SS))
            px += bytes((255, 255, 255, a))  # BGRA
    return px


def write(name, px):
    # Uncompressed true-colour, 32 bpp, top-left origin with 8 alpha bits (descriptor 0x28),
    # the same header as our other icons.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(header + bytes(px))


write("IconShield.tga", render(inside))
write("IconShieldEdge.tga", render(on_rim))
print("wrote IconShield.tga and IconShieldEdge.tga")

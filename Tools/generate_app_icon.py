"""Generate the demo's original opaque RGB app icon using only the standard library."""

import math
from pathlib import Path
import struct
import zlib


SIZE = 1024
DESTINATION = (
    Path(__file__).resolve().parents[1]
    / "OsmosDemo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
)


def blend(background, foreground, coverage):
    alpha = max(0.0, min(1.0, coverage))
    return tuple(round(a + (b - a) * alpha) for a, b in zip(background, foreground))


def chunk(kind, payload):
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def generate():
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)  # PNG scanline filter: none.
        for x in range(SIZE):
            light = (x + SIZE - y) / (2 * SIZE)
            color = (round(12 + 12 * light), round(51 + 30 * light), round(46 + 25 * light))
            distance = math.hypot(x + 0.5 - 512, y + 0.5 - 512)
            ring_coverage = 1.0 - (abs(distance - 246) - 56)
            color = blend(color, (220, 246, 225), ring_coverage)
            dot_distance = math.hypot(x + 0.5 - 704, y + 0.5 - 320)
            color = blend(color, (18, 64, 55), 86 - dot_distance)
            color = blend(color, (213, 232, 115), 62 - dot_distance)
            rows.extend(color)

    png = b"\x89PNG\r\n\x1a\n"
    # Color type 2 is RGB without an alpha channel, as required for app icons.
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), level=9))
    png += chunk(b"IEND", b"")
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    DESTINATION.write_bytes(png)
    print(f"Generated {SIZE}x{SIZE} opaque RGB icon: {DESTINATION}")


if __name__ == "__main__":
    generate()
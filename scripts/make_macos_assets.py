#!/usr/bin/env python3
import argparse
import os
import struct
import subprocess
import tempfile
import zlib


def write_png(path, width, height, pixels):
    raw_rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            row.extend(pixels[y * width + x])
        raw_rows.append(bytes(row))

    def chunk(kind, payload):
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    data = b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)),
            chunk(b"IDAT", zlib.compress(b"".join(raw_rows), 9)),
            chunk(b"IEND", b""),
        ]
    )
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as file:
        file.write(data)


def point_in_triangle(point, a, b, c):
    px, py = point
    ax, ay = a
    bx, by = b
    cx, cy = c
    denominator = ((by - cy) * (ax - cx)) + ((cx - bx) * (ay - cy))
    if denominator == 0:
        return False

    w1 = (((by - cy) * (px - cx)) + ((cx - bx) * (py - cy))) / denominator
    w2 = (((cy - ay) * (px - cx)) + ((ax - cx) * (py - cy))) / denominator
    w3 = 1 - w1 - w2
    return w1 >= 0 and w2 >= 0 and w3 >= 0


def point_in_polygon(point, vertices):
    x, y = point
    inside = False
    j = len(vertices) - 1
    for i, current in enumerate(vertices):
        xi, yi = current
        xj, yj = vertices[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-9) + xi):
            inside = not inside
        j = i
    return inside


def over(bottom, top):
    br, bg, bb, ba = [value / 255 for value in bottom]
    tr, tg, tb, ta = [value / 255 for value in top]
    out_a = ta + ba * (1 - ta)
    if out_a == 0:
        return (0, 0, 0, 0)

    out_r = (tr * ta + br * ba * (1 - ta)) / out_a
    out_g = (tg * ta + bg * ba * (1 - ta)) / out_a
    out_b = (tb * ta + bb * ba * (1 - ta)) / out_a
    return (
        round(out_r * 255),
        round(out_g * 255),
        round(out_b * 255),
        round(out_a * 255),
    )


def triangle_vertices(size, scale=1.0, offset=(0, 0)):
    vertices = [
        (size * 0.30, size * 0.18),
        (size * 0.30, size * 0.82),
        (size * 0.82, size * 0.50),
    ]
    centroid = (
        sum(vertex[0] for vertex in vertices) / 3,
        sum(vertex[1] for vertex in vertices) / 3,
    )
    return [
        (
            centroid[0] + (vertex[0] - centroid[0]) * scale + offset[0],
            centroid[1] + (vertex[1] - centroid[1]) * scale + offset[1],
        )
        for vertex in vertices
    ]


def make_play_icon_png(path, size):
    samples = 4
    layers = [
        (triangle_vertices(size, 1.02, (size * 0.025, size * 0.025)), (0, 0, 0, 70)),
        (triangle_vertices(size, 1.0), (28, 31, 35, 255)),
        (triangle_vertices(size, 0.82), (255, 255, 255, 255)),
    ]
    pixels = []

    for y in range(size):
        for x in range(size):
            accumulated = [0, 0, 0, 0]
            for sy in range(samples):
                for sx in range(samples):
                    sample = (x + (sx + 0.5) / samples, y + (sy + 0.5) / samples)
                    color = (0, 0, 0, 0)
                    for vertices, fill in layers:
                        if point_in_triangle(sample, vertices[0], vertices[1], vertices[2]):
                            color = over(color, fill)
                    for index, value in enumerate(color):
                        accumulated[index] += value
            count = samples * samples
            pixels.append(tuple(round(value / count) for value in accumulated))

    write_png(path, size, size, pixels)


def make_dmg_background(path):
    width = 640
    height = 360
    samples = 3
    arrow_shadow = [
        (270, 158),
        (350, 158),
        (350, 142),
        (390, 166),
        (350, 190),
        (350, 174),
        (270, 174),
    ]
    arrow = [(x, y - 6) for x, y in arrow_shadow]
    layers = [
        (arrow_shadow, (0, 0, 0, 80)),
        (arrow, (190, 196, 204, 235)),
    ]
    pixels = []

    for y in range(height):
        for x in range(width):
            accumulated = [0, 0, 0, 0]
            for sy in range(samples):
                for sx in range(samples):
                    sample = (x + (sx + 0.5) / samples, y + (sy + 0.5) / samples)
                    color = (0, 0, 0, 0)
                    for vertices, fill in layers:
                        if point_in_polygon(sample, vertices):
                            color = over(color, fill)
                    for index, value in enumerate(color):
                        accumulated[index] += value
            count = samples * samples
            pixels.append(tuple(round(value / count) for value in accumulated))

    write_png(path, width, height, pixels)


def make_app_icon(output_path):
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    with tempfile.TemporaryDirectory() as temp_dir:
        iconset = os.path.join(temp_dir, "AppIcon.iconset")
        os.makedirs(iconset)
        for filename, size in sizes.items():
            make_play_icon_png(os.path.join(iconset, filename), size)

        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        subprocess.run(["/usr/bin/iconutil", "-c", "icns", iconset, "-o", output_path], check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=["app-icon", "dmg-background"])
    parser.add_argument("output")
    args = parser.parse_args()

    if args.kind == "app-icon":
        make_app_icon(args.output)
    else:
        make_dmg_background(args.output)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# Pure-Shell - an open-source SSH client
# Copyright (C) 2026 Janos-Raul
# SPDX-License-Identifier: GPL-3.0-or-later
"""Writes the Windows app icon from the SVG master (no dependencies).

    python tool/make-windows-icon.py

Reads assets/icon/pure-shell-icon.svg (written by tool/make-icons.py, the
"framed" >_ design), renders it at the usual Windows icon sizes with 4 x 4
supersampling, and writes windows/runner/resources/app_icon.ico (PNG
entries). Only the shapes the master uses are understood: the background
rect, the rounded frame (stroked rect) and the round-capped polylines.
"""
import os
import re
import struct
import zlib

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SVG = os.path.join(ROOT, "assets/icon/pure-shell-icon.svg")
ICO = os.path.join(ROOT, "windows/runner/resources/app_icon.ico")
SIZES = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
SS = 4  # samples per axis


def _attrs(tag):
    return dict(re.findall(r'([\w-]+)="([^"]*)"', tag))


def _hex(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def parse(svg):
    size = float(_attrs(re.search(r"<svg[^>]*>", svg).group(0))["width"])
    rects = [_attrs(t) for t in re.findall(r"<rect[^>]*>", svg)]
    bg = _hex(next(r["fill"] for r in rects if r.get("fill", "none") != "none"))
    f = next(r for r in rects if r.get("fill") == "none")
    frame = dict(x=float(f["x"]), y=float(f["y"]), w=float(f["width"]),
                 h=float(f["height"]), r=float(f["rx"]),
                 sw=float(f["stroke-width"]), color=_hex(f["stroke"]))
    g = _attrs(re.search(r"<g[^>]*>", svg).group(0))
    lines = []
    for d in re.findall(r'<path d="([^"]*)"', svg):
        pts = [(float(x), float(y))
               for x, y in re.findall(r"[ML]\s*([\d.]+)\s+([\d.]+)", d)]
        lines.append(pts)
    prompt = dict(lines=lines, sw=float(g["stroke-width"]), color=_hex(g["stroke"]))
    return size, bg, frame, prompt


def _seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    t = 0.0 if t < 0 else 1.0 if t > 1 else t
    qx, qy = ax + t * dx - px, ay + t * dy - py
    return (qx * qx + qy * qy) ** 0.5


def _rrect_dist(px, py, f):
    """Signed distance to the rounded rectangle's outline (centre line)."""
    hx, hy = f["w"] / 2, f["h"] / 2
    cx, cy = f["x"] + hx, f["y"] + hy
    qx = abs(px - cx) - (hx - f["r"])
    qy = abs(py - cy) - (hy - f["r"])
    outside = (max(qx, 0) ** 2 + max(qy, 0) ** 2) ** 0.5
    return outside + min(max(qx, qy), 0) - f["r"]


def render(n, master, bg, frame, prompt):
    k = master / n  # master units per output pixel
    segs = [(a, b) for pts in prompt["lines"] for a, b in zip(pts, pts[1:])]
    half_p = prompt["sw"] / 2
    half_f = frame["sw"] / 2
    rows = []
    for y in range(n):
        row = bytearray()
        for x in range(n):
            cov_p = cov_f = 0
            for sy in range(SS):
                for sx in range(SS):
                    px = (x + (sx + 0.5) / SS) * k
                    py = (y + (sy + 0.5) / SS) * k
                    if any(_seg_dist(px, py, *a, *b) <= half_p for a, b in segs):
                        cov_p += 1
                    elif abs(_rrect_dist(px, py, frame)) <= half_f:
                        cov_f += 1
            a_p, a_f = cov_p / SS ** 2, cov_f / SS ** 2
            rgb = [bg[i] * (1 - a_p - a_f) + prompt["color"][i] * a_p
                   + frame["color"][i] * a_f for i in range(3)]
            row += bytes(int(round(c)) for c in rgb) + b"\xff"
        rows.append(bytes(row))
    return rows


def png(n, rows):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))
    raw = b"".join(b"\x00" + r for r in rows)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def main():
    with open(SVG, encoding="utf-8") as fh:
        master, bg, frame, prompt = parse(fh.read())
    images = [(n, png(n, render(n, master, bg, frame, prompt))) for n in SIZES]
    header = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    entries = b""
    for n, data in images:
        side = 0 if n >= 256 else n
        entries += struct.pack("<BBBBHHII", side, side, 0, 0, 1, 32,
                               len(data), offset)
        offset += len(data)
    with open(ICO, "wb") as fh:
        fh.write(header + entries + b"".join(d for _, d in images))
    print(f"wrote {os.path.relpath(ICO, ROOT)}: "
          + ", ".join(str(n) for n in SIZES))


if __name__ == "__main__":
    main()

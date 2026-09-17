#!/usr/bin/env python3
"""Deterministically isolate target-density plane cards from one RGBA source.

This helper is intentionally offline and non-generative. A recipe selects exact
4-connected source-alpha components by opaque seed, optionally clips them with
integer polygons, adds transparent padding, BOX downsamples, and alpha-cuts the
result. The sprite pipeline independently reproduces every output from the
hash-bound parent and serialized recipe before it accepts a source plan.
"""

from __future__ import annotations

from io import BytesIO

from PIL import Image


PROFILE = "source-component-depth-cards-v1"


def _inside_polygon(x: int, y: int, polygon: list[list[int]]) -> bool:
    inside = False
    previous = polygon[-1]
    for current in polygon:
        x1, y1 = previous
        x2, y2 = current
        if (y1 > y) != (y2 > y):
            left = (x2 - x1) * (y - y1)
            right = (x - x1) * (y2 - y1)
            if (left > right) == (y2 > y1):
                inside = not inside
        previous = current
    return inside


def _alpha_component(parent: Image.Image, seed: list[int], threshold: int) -> set[tuple[int, int]]:
    width, height = parent.size
    seed_x, seed_y = seed
    if not (0 <= seed_x < width and 0 <= seed_y < height):
        raise ValueError("component seed lies outside source")
    if parent.getpixel((seed_x, seed_y))[3] < threshold:
        raise ValueError("component seed is transparent")
    selected: set[tuple[int, int]] = set()
    pending = [(seed_x, seed_y)]
    while pending:
        x, y = pending.pop()
        if (x, y) in selected or parent.getpixel((x, y))[3] < threshold:
            continue
        selected.add((x, y))
        if x > 0:
            pending.append((x - 1, y))
        if x + 1 < width:
            pending.append((x + 1, y))
        if y > 0:
            pending.append((x, y - 1))
        if y + 1 < height:
            pending.append((x, y + 1))
    return selected


def build_card(parent: Image.Image, parameters: dict) -> tuple[Image.Image, set[tuple[int, int]]]:
    if parameters["profile"] != PROFILE:
        raise ValueError("unsupported profile")
    parent = parent.convert("RGBA")
    role = parameters["role"]
    threshold = parameters["alphaThreshold"]
    crop_left, crop_top, crop_width, crop_height = parameters["sourceCropPx"]
    padding = parameters["paddingPx"]
    selected_components: set[tuple[int, int]] = set()
    for seed in parameters["roleSeedsSourcePx"][role]:
        selected_components.update(_alpha_component(parent, seed, threshold))
    polygons = parameters["roleClipPolygonsSourcePx"][role]
    selected: set[tuple[int, int]] = set()
    card = Image.new("RGBA", (crop_width + padding * 2, crop_height + padding * 2), (0, 0, 0, 0))
    for local_y in range(crop_height):
        source_y = crop_top + local_y
        for local_x in range(crop_width):
            source_x = crop_left + local_x
            if (source_x, source_y) not in selected_components:
                continue
            if polygons and not any(_inside_polygon(source_x, source_y, polygon) for polygon in polygons):
                continue
            red, green, blue, alpha = parent.getpixel((source_x, source_y))
            if alpha < threshold:
                continue
            card.putpixel((local_x + padding, local_y + padding), (red, green, blue, 255))
            selected.add((source_x, source_y))
    reduced = card.resize(tuple(parameters["outputSizePx"]), resample=Image.Resampling.BOX)
    normalized = Image.new("RGBA", reduced.size, (0, 0, 0, 0))
    for y in range(reduced.height):
        for x in range(reduced.width):
            red, green, blue, alpha = reduced.getpixel((x, y))
            if alpha >= threshold:
                normalized.putpixel((x, y), (red, green, blue, 255))
    return normalized, selected


def encode_png(image: Image.Image) -> bytes:
    output = BytesIO()
    image.save(output, format="PNG", optimize=False, compress_level=9)
    return output.getvalue()

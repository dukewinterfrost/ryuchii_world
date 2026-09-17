#!/usr/bin/env python3
"""Build target-density Green Shade tree depth cards from one bound source.

This is deterministic source preparation, not image generation. The selected
left-hand tree is masked into three semantic cards, prefiltered to the intended
portrait review density, and encoded with stable PNG settings. The source plan
binds this script, every parameter below, the parent source, and each output by
SHA-256 so the pipeline can reproduce the transform without executing code from
the plan.
"""

from __future__ import annotations

from hashlib import sha256
from io import BytesIO
from pathlib import Path

from PIL import Image


HERE = Path(__file__).resolve().parent
SOURCE_SHA256 = "1a1a4e145f21f09199e3ed0afd6f63eb8851011d1bdc20855cb6e461f9b0c364"
SOURCE = HERE / "sources" / f"{SOURCE_SHA256}.png"

# These constants are serialized verbatim in source-plan.json's derivedImages
# records. Keep both representations synchronized.
PROFILE = "green-shade-tree-depth-cards-v2"
CROP_PX = (128, 0, 744, 744)
PADDING_PX = 24
OUTPUT_SIZE_PX = (256, 256)
ALPHA_THRESHOLD = 128
RESAMPLE = "box"
MIN_OVERLAP_PX = 32
TRUNK_RECT_SOURCE_PX = (220, 265, 560, 479)
CANOPY_ELLIPSES_SOURCE_PX = (
    (500, 160, 260, 135),
    (265, 180, 125, 95),
    (335, 112, 135, 85),
    (465, 72, 145, 58),
    (610, 94, 155, 78),
    (710, 178, 150, 108),
    (360, 245, 170, 100),
    (570, 250, 185, 110),
    (735, 245, 105, 85),
)
FACADE_ELLIPSES_SOURCE_PX = (
    (500, 620, 220, 160),
    (330, 695, 160, 72),
    (680, 690, 150, 82),
)


def _inside_ellipse(x: int, y: int, ellipse: tuple[int, int, int, int]) -> bool:
    """Integer-only ellipse test shared by the pipeline reproducer."""
    center_x, center_y, radius_x, radius_y = ellipse
    delta_x = x - center_x
    delta_y = y - center_y
    return delta_x * delta_x * radius_y * radius_y + delta_y * delta_y * radius_x * radius_x <= radius_x * radius_x * radius_y * radius_y


def _inside_rect(x: int, y: int, rect: tuple[int, int, int, int]) -> bool:
    left, top, width, height = rect
    return left <= x < left + width and top <= y < top + height


def _role_selected(role: str, source_x: int, source_y: int) -> bool:
    canopy = any(_inside_ellipse(source_x, source_y, ellipse) for ellipse in CANOPY_ELLIPSES_SOURCE_PX)
    trunk = _inside_rect(source_x, source_y, TRUNK_RECT_SOURCE_PX)
    facade = any(_inside_ellipse(source_x, source_y, ellipse) for ellipse in FACADE_ELLIPSES_SOURCE_PX)
    if role == "canopy":
        return canopy
    if role == "interior":
        # The trunk remains behind the canopy and root card. These broad,
        # naturally occluded overlaps replace fragile horizontal slice joins.
        return trunk
    if role == "facade":
        return trunk and facade
    raise ValueError(f"Unknown tree role: {role}")


def _build_source_density_card(source: Image.Image, role: str) -> Image.Image:
    crop_left, crop_top, crop_width, crop_height = CROP_PX
    card = Image.new(
        "RGBA",
        (crop_width + PADDING_PX * 2, crop_height + PADDING_PX * 2),
        (0, 0, 0, 0),
    )
    for local_y in range(crop_height):
        source_y = crop_top + local_y
        for local_x in range(crop_width):
            source_x = crop_left + local_x
            red, green, blue, alpha = source.getpixel((source_x, source_y))
            if alpha < ALPHA_THRESHOLD or not _role_selected(role, source_x, source_y):
                continue
            card.putpixel(
                (local_x + PADDING_PX, local_y + PADDING_PX),
                (red, green, blue, 255),
            )
    return card


def _target_density(card: Image.Image) -> Image.Image:
    reduced = card.resize(OUTPUT_SIZE_PX, resample=Image.Resampling.BOX)
    normalized = Image.new("RGBA", OUTPUT_SIZE_PX, (0, 0, 0, 0))
    for y in range(reduced.height):
        for x in range(reduced.width):
            red, green, blue, alpha = reduced.getpixel((x, y))
            if alpha >= ALPHA_THRESHOLD:
                normalized.putpixel((x, y), (red, green, blue, 255))
    return normalized


def build() -> dict[str, str]:
    raw = SOURCE.read_bytes()
    if sha256(raw).hexdigest() != SOURCE_SHA256:
        raise RuntimeError("Immutable Green Shade Tree source hash changed")
    source = Image.open(BytesIO(raw)).convert("RGBA")
    bindings: dict[str, str] = {}
    for role in ("canopy", "interior", "facade"):
        image = _target_density(_build_source_density_card(source, role))
        output = BytesIO()
        image.save(output, format="PNG", optimize=False, compress_level=9)
        payload = output.getvalue()
        digest = sha256(payload).hexdigest()
        destination = HERE / "sources" / f"{digest}.png"
        if destination.exists() and destination.read_bytes() != payload:
            raise RuntimeError(f"Hash collision at {destination}")
        destination.write_bytes(payload)
        bindings[role] = digest
    return bindings


if __name__ == "__main__":
    for name, value in sorted(build().items()):
        print(f"{name}: sha256:{value}")

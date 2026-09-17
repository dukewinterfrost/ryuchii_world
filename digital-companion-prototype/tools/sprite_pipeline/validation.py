"""Portable asset contracts for sprites, arenas, and sprite-in-3D environments."""

from __future__ import annotations

from collections import deque
import math
import re
from typing import Any

from .common import identifier, require
from .restricted_sources import DIGIMONUP_ORIGINAL_HASHES, restricted_classification

FACINGS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
ACTIONS = ["idle", "move", "basic_attack", "special_attack", "guard", "evade", "hit", "defeat"]
KINDS = ("animation", "atlas", "tileset", "arena", "environment", "habitat")
PROVIDERS = ("codex-imagegen", "pixellab", "manual")
LICENSE_CLASSES = ("private-prototype-only", "commercial-use-cleared", "public-domain")
PROVENANCE_KINDS = ("hand-authored", "generated", "source-derived", "hybrid")

PRESENTATION_PROFILE = {
    "id": "sprite-in-3d-portrait-v1",
    "version": 1,
    "pixelsPerMeter": 32,
    "fovDegrees": 28,
    "pitchDegrees": 50,
    "spriteTiltDegrees": 8,
    "keepAspect": "width",
}
MAX_TERRAIN_CHUNKS = 64
MAX_SPRITE_PLANES = 512
MAX_PLANE_STACKS = 256
MAX_AMBIENT_PLANES = 64
MAX_HABITAT_PLACEMENTS = 512
MAX_ARENA_PRESENTATION_PLACEMENTS = 256
MIN_RENDER_PRIORITY = -16
MAX_RENDER_PRIORITY = 16


def integers(value: Any, size: int, label: str, minimum: int = 0) -> list[int]:
    require(isinstance(value, list) and len(value) == size and
            all(type(v) is int and v >= minimum for v in value), label + " must be integers")
    return value


def point(value: Any, label: str) -> None:
    require(isinstance(value, dict) and set(value) == {"x", "y"}, label + " must contain x,y")
    require(all(type(v) in (int, float) and 0 <= v <= 1 for v in value.values()),
            label + " must be normalized to [0,1]")


def _number(value: Any, label: str, minimum: float | None = None,
            maximum: float | None = None) -> float:
    require(type(value) in (int, float) and value == value and abs(value) != float("inf"),
            label + " must be finite")
    result = float(value)
    require(minimum is None or result >= minimum, label + " is below its minimum")
    require(maximum is None or result <= maximum, label + " exceeds its maximum")
    return result


def _vector(value: Any, size: int, label: str, limit: float = 4096) -> list[float]:
    require(isinstance(value, list) and len(value) == size, label + " must contain %d numbers" % size)
    return [_number(component, label, -limit, limit) for component in value]


def _rect(value: Any, label: str, bounds: tuple[float, float] | None = None,
          allow_negative_origin: bool = False) -> list[float]:
    x, y, width, height = _vector(value, 4, label)
    require(width > 0 and height > 0, label + " needs positive size")
    require(allow_negative_origin or (x >= 0 and y >= 0), label + " needs a nonnegative origin")
    if bounds:
        require(x + width <= bounds[0] and y + height <= bounds[1], label + " lies outside its ground bounds")
    return [x, y, width, height]


def _binding(value: Any, label: str) -> None:
    require(isinstance(value, dict), label + " must be an object")
    require(set(value) <= {"assetId", "revision", "contentSha256"}, label + " contains unsupported fields")
    identifier(value.get("assetId"), label + " assetId")
    identifier(value.get("revision"), label + " revision")
    if "contentSha256" in value:
        digest_value = value["contentSha256"]
        require(isinstance(digest_value, str) and len(digest_value) == 71 and
                digest_value.startswith("sha256:") and
                all(character in "0123456789abcdef" for character in digest_value[7:]),
                label + " contentSha256 is malformed")


def _plane(value: Any, label: str, position_field: str,
           source_sizes: dict[str, tuple[int, int]] | None = None) -> None:
    require(isinstance(value, dict), label + " must be an object")
    identifier(value.get("id"), label + " ID")
    identifier(value.get("source"), label + " source")
    point(value.get("pivot"), label + " pivot")
    _vector(value.get(position_field), 3, label + " " + position_field)
    rotation = _vector(value.get("rotationDegrees"), 3, label + " rotationDegrees", 360)
    require(all(-360 <= component <= 360 for component in rotation), label + " rotation is outside limits")
    require(abs(rotation[1]) <= 0.0001,
            label + " rotationDegrees.y must be 0 for fixed-card environment v1")
    _number(value.get("pixelSize"), label + " pixelSize", 0.0001, 16)
    _alpha_depth(value.get("alphaMode"), value.get("depthBehavior"), label)
    if value.get("alphaMode") == "transparent":
        priority = value.get("renderPriority")
        require(type(priority) is int and MIN_RENDER_PRIORITY <= priority <= MAX_RENDER_PRIORITY,
                "%s transparent/prepass renderPriority must be an integer from %d to %d" %
                (label, MIN_RENDER_PRIORITY, MAX_RENDER_PRIORITY))
    elif "renderPriority" in value:
        require(type(value["renderPriority"]) is int and value["renderPriority"] == 0,
                label + " renderPriority is only meaningful for transparent/prepass content")
    if "sourceRegionPx" in value:
        x, y, width, height = integers(value["sourceRegionPx"], 4, label + " sourceRegionPx")
        require(width > 0 and height > 0, label + " sourceRegionPx needs positive size")
        if source_sizes is not None and value["source"] in source_sizes:
            source_width, source_height = source_sizes[value["source"]]
            require(x + width <= source_width and y + height <= source_height,
                    label + " sourceRegionPx lies outside its source texture")


def _rotated_footprint(rect: list[float], origin: tuple[float, float], degrees: float) -> list[float]:
    """Return the world-ground AABB of a local footprint after rotation/translation."""
    x, y, width, height = rect
    radians = math.radians(degrees)
    cosine, sine = math.cos(radians), math.sin(radians)
    points = []
    for local_x, local_y in ((x, y), (x + width, y), (x + width, y + height), (x, y + height)):
        points.append((origin[0] + local_x * cosine - local_y * sine,
                       origin[1] + local_x * sine + local_y * cosine))
    minimum_x = min(point[0] for point in points)
    minimum_y = min(point[1] for point in points)
    maximum_x = max(point[0] for point in points)
    maximum_y = max(point[1] for point in points)
    return [minimum_x, minimum_y, maximum_x - minimum_x, maximum_y - minimum_y]


def _rect_center(rect: list[float]) -> tuple[float, float]:
    return rect[0] + rect[2] * 0.5, rect[1] + rect[3] * 0.5


def _rect_contains(outer: list[float], inner: list[float], tolerance: float = 0.01) -> bool:
    return (inner[0] >= outer[0] - tolerance and inner[1] >= outer[1] - tolerance and
            inner[0] + inner[2] <= outer[0] + outer[2] + tolerance and
            inner[1] + inner[3] <= outer[1] + outer[3] + tolerance)


def _rect_equal(first: list[float], second: list[float], tolerance: float = 0.01) -> bool:
    return all(abs(left - right) <= tolerance for left, right in zip(first, second))


def _alpha_depth(alpha_mode: Any, depth_behavior: Any, label: str) -> None:
    require(alpha_mode in ("opaque", "alpha-cut", "transparent"), label + " has invalid alphaMode")
    require(depth_behavior in ("write", "prepass"), label + " has invalid depthBehavior")
    expected = "prepass" if alpha_mode == "transparent" else "write"
    require(depth_behavior == expected,
            "%s %s requires depthBehavior %s" % (label, alpha_mode, expected))


_WEB_URI = re.compile(r"\b(?:https?|wss?)://[^\s\"'<>]+", re.IGNORECASE)
_FILE_URI = re.compile(r"\bfile:(?://|/)", re.IGNORECASE)
_WINDOWS_DRIVE = re.compile(r"(?:^|[^A-Za-z0-9])\[?[A-Za-z]:/(?:[^/\s]+/)*", re.IGNORECASE)
_UNC_PATH = re.compile(r"(?:^|[^:])//[^/\s]+(?:/|$)", re.IGNORECASE)
_POSIX_PATH = re.compile(r"(?:^|[^A-Za-z0-9._-])/(?=[A-Za-z0-9._~-])")
_HOME_PATH = re.compile(r"~/(?=[^\s])")


def _contains_absolute_path(value: Any) -> bool:
    if isinstance(value, str):
        normalized = value.replace("\\", "/")
        if _FILE_URI.search(normalized):
            return True
        # URLs are portable references, not local filesystem paths. Strip only
        # known web schemes; strings such as ``host:/private`` remain subject
        # to the local-path checks below.
        without_web_urls = _WEB_URI.sub("", normalized)
        return (without_web_urls.strip() == "/" or
                any(pattern.search(without_web_urls) for pattern in
                    (_WINDOWS_DRIVE, _UNC_PATH, _POSIX_PATH, _HOME_PATH)))
    if isinstance(value, dict):
        return any(_contains_absolute_path(key) or _contains_absolute_path(item)
                   for key, item in value.items())
    if isinstance(value, list):
        return any(_contains_absolute_path(item) for item in value)
    return False


def require_portable_paths(value: Any, label: str) -> None:
    require(not _contains_absolute_path(value),
            label + " must not contain absolute filesystem paths")


def _sha256(value: Any, label: str) -> str:
    require(isinstance(value, str) and len(value) == 71 and value.startswith("sha256:") and
            all(character in "0123456789abcdef" for character in value[7:]),
            label + " must be a sha256 digest")
    return value


def validate_derived_images(plan: dict) -> None:
    """Validate declarative, reproducible source-image transformations."""
    derivations = plan.get("derivedImages", {})
    require(isinstance(derivations, dict) and len(derivations) <= 128,
            "derivedImages must be a bounded object")
    for output_role, derivation in derivations.items():
        identifier(output_role, "derived image role")
        require(output_role in plan["sources"], "Derived image output role is missing from sources")
        require(isinstance(derivation, dict) and
                set(derivation) == {"parentSource", "parentSha256", "recipe", "outputSha256"},
                "Derived image definition has unsupported or missing fields")
        parent_role = identifier(derivation.get("parentSource"), "derived image parentSource")
        require(parent_role in plan["sources"] and parent_role != output_role,
                "Derived image parentSource is missing or self-referential")
        require(derivation.get("parentSha256") == plan["sources"][parent_role]["sha256"],
                "Derived image parentSha256 differs from its source binding")
        require(derivation.get("outputSha256") == plan["sources"][output_role]["sha256"],
                "Derived image outputSha256 differs from its source binding")
        recipe = derivation.get("recipe")
        require(isinstance(recipe, dict) and
                set(recipe) == {"kind", "version", "scriptPath", "scriptSha256", "parameters"} and
                recipe.get("kind") == "scripted-rgba-transform" and recipe.get("version") == 1,
                "Derived image recipe must use scripted-rgba-transform v1")
        script_path = recipe.get("scriptPath")
        require(isinstance(script_path, str) and script_path and not script_path.startswith(".") and
                "/../" not in "/" + script_path.replace("\\", "/") + "/",
                "Derived image recipe needs a portable scriptPath")
        _sha256(recipe.get("scriptSha256"), "derived image scriptSha256")
        parameters = recipe.get("parameters")
        common_fields = {"profile", "sourceCropPx", "outputSizePx", "paddingPx", "resample",
                         "alphaThreshold", "minimumOverlapPx", "role"}
        green_fields = common_fields | {"trunkRectSourcePx", "canopyEllipsesSourcePx",
                                        "facadeEllipsesSourcePx"}
        component_fields = common_fields | {"roleSeedsSourcePx", "roleClipPolygonsSourcePx"}
        require(isinstance(parameters, dict) and
                ((parameters.get("profile") == "green-shade-tree-depth-cards-v2" and
                  set(parameters) == green_fields) or
                 (parameters.get("profile") == "source-component-depth-cards-v1" and
                  set(parameters) == component_fields)),
                "Unsupported deterministic derived-image profile")
        crop = integers(parameters.get("sourceCropPx"), 4, "derived sourceCropPx")
        require(crop[2] > 0 and crop[3] > 0, "derived sourceCropPx needs positive size")
        output_size = integers(parameters.get("outputSizePx"), 2, "derived outputSizePx", 1)
        require(max(output_size) <= 2048, "derived outputSizePx exceeds limit")
        require(type(parameters.get("paddingPx")) is int and 0 <= parameters["paddingPx"] <= 256,
                "derived paddingPx must be a bounded integer")
        require(parameters.get("resample") == "box", "Derived image resample must be box")
        require(type(parameters.get("alphaThreshold")) is int and 1 <= parameters["alphaThreshold"] <= 255,
                "derived alphaThreshold must be a bounded integer")
        require(type(parameters.get("minimumOverlapPx")) is int and
                0 <= parameters["minimumOverlapPx"] <= 1000000,
                "derived minimumOverlapPx must be a bounded integer")
        if parameters["profile"] == "green-shade-tree-depth-cards-v2":
            trunk = integers(parameters.get("trunkRectSourcePx"), 4, "derived trunkRectSourcePx")
            require(trunk[2] > 0 and trunk[3] > 0, "derived trunkRectSourcePx needs positive size")
            for field in ("canopyEllipsesSourcePx", "facadeEllipsesSourcePx"):
                ellipses = parameters.get(field)
                require(isinstance(ellipses, list) and ellipses and len(ellipses) <= 64,
                        field + " must be a bounded nonempty array")
                for ellipse in ellipses:
                    values = integers(ellipse, 4, field + " ellipse")
                    require(values[2] > 0 and values[3] > 0, field + " radii must be positive")
            require(parameters.get("role") in ("canopy", "interior", "facade"),
                    "Derived image role parameter is invalid")
        else:
            roles = {"facade", "interior", "roof"}
            require(parameters.get("role") in roles, "Derived image role parameter is invalid")
            seeds = parameters.get("roleSeedsSourcePx")
            polygons = parameters.get("roleClipPolygonsSourcePx")
            require(isinstance(seeds, dict) and set(seeds) == roles and
                    isinstance(polygons, dict) and set(polygons) == roles,
                    "Component depth-card recipes need all three semantic role masks")
            for role in roles:
                require(isinstance(seeds[role], list) and 1 <= len(seeds[role]) <= 16,
                        "Each component depth-card role needs bounded source seeds")
                for seed in seeds[role]:
                    integers(seed, 2, "derived component seed")
                require(isinstance(polygons[role], list) and len(polygons[role]) <= 16,
                        "Derived component clip polygons must be bounded arrays")
                for polygon in polygons[role]:
                    require(isinstance(polygon, list) and 3 <= len(polygon) <= 64,
                            "Derived component clip polygon must have 3-64 points")
                    for point_value in polygon:
                        integers(point_value, 2, "derived component polygon point")


def validate_environment(value: Any, source_roles: set[str] | None = None,
                         source_sizes: dict[str, tuple[int, int]] | None = None,
                         allow_compiled_bindings: bool = False) -> dict:
    require(isinstance(value, dict), "Environment must be an object")
    require(value.get("presentationProfile") == PRESENTATION_PROFILE,
            "Environment must pin the canonical sprite-in-3D presentationProfile")
    license_data = value.get("license")
    require(isinstance(license_data, dict) and license_data.get("classification") in LICENSE_CLASSES and
            isinstance(license_data.get("notice"), str) and bool(license_data["notice"].strip()),
            "Environment requires an explicit license classification and notice")
    scale = value.get("worldScale")
    require(isinstance(scale, dict), "Environment needs worldScale")
    pixels_per_unit = scale.get("pixelsPerUnit")
    require(pixels_per_unit == PRESENTATION_PROFILE["pixelsPerMeter"],
            "worldScale.pixelsPerUnit must be exactly 32 for the shared ground/XZ mapping")
    camera = value.get("camera")
    require(isinstance(camera, dict) and camera.get("projection") == "perspective" and
            camera.get("keepAspect") == "width", "Environment camera must use perspective KEEP_WIDTH")
    require(camera.get("fovDegrees") == PRESENTATION_PROFILE["fovDegrees"],
            "camera fovDegrees must match the canonical presentationProfile")
    require(camera.get("pitchDegrees") == PRESENTATION_PROFILE["pitchDegrees"],
            "camera pitchDegrees must match the canonical presentationProfile")
    sprite_tilt = _number(camera.get("spriteTiltDegrees"), "camera spriteTiltDegrees", 0, 30)
    require(abs(sprite_tilt - 8.0) <= 0.0001,
            "camera spriteTiltDegrees must be +8 (positive means tilt toward the fixed camera)")
    ground_distance = _number(camera.get("groundDistance"), "camera groundDistance", 2, 60)
    dolly = camera.get("dollyBounds")
    require(isinstance(dolly, list) and len(dolly) == 2, "camera dollyBounds must contain minimum and maximum")
    dolly_min = _number(dolly[0], "camera dollyBounds minimum", 2, 60)
    dolly_max = _number(dolly[1], "camera dollyBounds maximum", 2, 60)
    require(dolly_min <= ground_distance <= dolly_max and dolly_min < dolly_max,
            "camera groundDistance must lie inside ordered dollyBounds")
    _number(camera.get("smoothingSpeed"), "camera smoothingSpeed", 0.01, 20)
    near = _number(camera.get("near"), "camera near", 0.05, 1)
    far = _number(camera.get("far"), "camera far", 25, 500)
    require(far > near, "camera far must exceed near")
    movement = _rect(camera.get("movementBounds"), "camera movementBounds")

    footprints = value.get("groundFootprints")
    require(isinstance(footprints, list), "groundFootprints must be an array")
    footprint_ids: set[str] = set()
    for footprint in footprints:
        require(isinstance(footprint, dict), "Ground footprint must be an object")
        footprint_id = identifier(footprint.get("id"), "ground footprint ID")
        require(footprint_id not in footprint_ids, "Duplicate ground footprint ID")
        footprint_ids.add(footprint_id)
        _rect(footprint.get("rect"), "ground footprint rectangle", allow_negative_origin=True)

    navigation = value.get("navigationProfiles")
    require(isinstance(navigation, list), "navigationProfiles must be an array")
    navigation_ids: set[str] = set()
    for profile in navigation:
        require(isinstance(profile, dict), "Navigation profile must be an object")
        profile_id = identifier(profile.get("id"), "navigation profile ID")
        require(profile_id not in navigation_ids, "Duplicate navigation profile ID")
        navigation_ids.add(profile_id)
        require(all(type(profile.get(flag)) is bool for flag in ("movement", "waste", "decoration")),
                "Navigation profile flags must be explicit booleans")

    terrain = value.get("terrainChunks")
    require(isinstance(terrain, list) and 1 <= len(terrain) <= MAX_TERRAIN_CHUNKS,
            "Environment terrainChunks count is outside limits")
    terrain_ids: set[str] = set()
    referenced_sources: set[str] = set()
    for chunk in terrain:
        require(isinstance(chunk, dict), "Terrain chunk must be an object")
        chunk_id = identifier(chunk.get("id"), "terrain chunk ID")
        require(chunk_id not in terrain_ids, "Duplicate terrain chunk ID")
        terrain_ids.add(chunk_id)
        source_role = identifier(chunk.get("source"), "terrain source")
        referenced_sources.add(source_role)
        # Presentation terrain may extend beyond authoritative gameplay bounds
        # to keep fixed-axis perspective framing on painted ground.
        ground_rect = _rect(chunk.get("groundRect"), "terrain groundRect", allow_negative_origin=True)
        require(_rect_contains(movement, ground_rect) or _rect_contains(ground_rect, movement),
                "terrain groundRect must lie inside or fully cover camera movementBounds")
        _number(chunk.get("elevation", 0), "terrain elevation", -100, 100)
        subdivisions = integers(chunk.get("subdivisions"), 2, "terrain subdivisions", 1)
        require(max(subdivisions) <= 64, "Terrain subdivisions exceed limit")
        _alpha_depth(chunk.get("alphaMode", "opaque"), chunk.get("depthBehavior", "write"),
                     "Terrain chunk")
        if "sourceRegionPx" in chunk:
            x, y, width, height = integers(chunk["sourceRegionPx"], 4,
                                            "terrain sourceRegionPx")
            require(width > 0 and height > 0, "terrain sourceRegionPx needs positive size")
            if source_sizes is not None and source_role in source_sizes:
                source_width, source_height = source_sizes[source_role]
                require(x + width <= source_width and y + height <= source_height,
                        "terrain sourceRegionPx lies outside its source texture")
        if "textureBinding" in chunk:
            require(allow_compiled_bindings,
                    "terrain textureBinding is compiler-owned and cannot be authored")
            identifier(chunk["textureBinding"], "terrain textureBinding")

    planes = value.get("spritePlanes")
    require(isinstance(planes, list) and 1 <= len(planes) <= MAX_SPRITE_PLANES,
            "Environment spritePlanes count is outside limits")
    plane_ids: set[str] = set()
    for plane in planes:
        _plane(plane, "Sprite plane", "localPosition", source_sizes)
        plane_id = plane["id"]
        require(plane_id not in plane_ids, "Duplicate sprite plane ID")
        plane_ids.add(plane_id)
        referenced_sources.add(plane["source"])

    stack_ids: set[str] = set()
    stacks = value.get("planeStacks")
    require(isinstance(stacks, list) and 1 <= len(stacks) <= MAX_PLANE_STACKS,
            "Environment planeStacks count is outside limits")
    for stack in stacks:
        require(isinstance(stack, dict), "Plane stack must be an object")
        stack_id = identifier(stack.get("id"), "plane stack ID")
        require(stack_id not in stack_ids, "Duplicate plane stack ID")
        stack_ids.add(stack_id)
        stack_planes = stack.get("planes")
        require(isinstance(stack_planes, list) and stack_planes and len(set(stack_planes)) == len(stack_planes) and
                all(plane_id in plane_ids for plane_id in stack_planes), "Plane stack references invalid planes")
        require(stack.get("groundFootprint") in footprint_ids, "Plane stack needs a valid groundFootprint reference")
        require(stack.get("navigation") in navigation_ids, "Plane stack needs a valid navigation reference")
        root_plane = next(plane for plane in planes if plane["id"] == stack_planes[0])
        footprint = next(item["rect"] for item in footprints if item["id"] == stack["groundFootprint"])
        root_x = float(root_plane["localPosition"][0]) * pixels_per_unit
        root_y = float(root_plane["localPosition"][2]) * pixels_per_unit
        require(footprint[0] <= root_x <= footprint[0] + footprint[2] and
                footprint[1] <= root_y <= footprint[1] + footprint[3],
                "Plane stack root plane must be anchored inside its groundFootprint")

    ambient_ids: set[str] = set()
    ambient_planes = value.get("ambientPlanes", [])
    require(isinstance(ambient_planes, list) and len(ambient_planes) <= MAX_AMBIENT_PLANES,
            "Environment ambientPlanes count is outside limits")
    for ambient in ambient_planes:
        _plane(ambient, "Ambient plane", "position", source_sizes)
        require(ambient["id"] not in ambient_ids, "Duplicate ambient plane ID")
        ambient_ids.add(ambient["id"])
        require(ambient["alphaMode"] == "transparent" and ambient["depthBehavior"] == "prepass",
                "Ambient planes must declare transparent depth handling")
        _number(ambient.get("parallax", 1), "ambient parallax", 0, 4)
        referenced_sources.add(ambient["source"])

    viewpoints = value.get("reviewViewpoints")
    require(isinstance(viewpoints, list), "reviewViewpoints must be an array")
    viewpoint_ids: set[str] = set()
    for viewpoint in viewpoints:
        require(isinstance(viewpoint, dict), "Review viewpoint must be an object")
        viewpoint_id = identifier(viewpoint.get("id"), "review viewpoint ID")
        require(viewpoint_id not in viewpoint_ids, "Duplicate review viewpoint ID")
        viewpoint_ids.add(viewpoint_id)
        _vector(viewpoint.get("position"), 3, "review viewpoint position")
        _vector(viewpoint.get("lookAt"), 3, "review viewpoint lookAt")
    require(viewpoint_ids == {"center", "left", "right", "near", "far"},
            "Environment needs center/left/right/near/far review viewpoints")
    if source_roles is not None:
        require(referenced_sources <= source_roles, "Environment references missing source roles: " +
                ", ".join(sorted(referenced_sources - source_roles)))
    return {"terrainChunks": len(terrain), "spritePlanes": len(planes),
            "planeStacks": len(stacks), "ambientPlanes": len(ambient_planes)}


def validate_habitat(value: Any, environment: dict | None = None) -> dict:
    require(isinstance(value, dict), "Habitat must be an object")
    _binding(value.get("environment"), "Environment")
    grid = value.get("grid")
    require(isinstance(grid, dict) and grid == {"columns": 40, "rows": 48, "cellSize": 32},
            "Habitat grid must be exactly 40x48 cells at 32 units per cell")
    columns, rows = 40, 48
    blockers = value.get("blockers")
    require(isinstance(blockers, list) and len(blockers) <= 512, "Habitat blockers must be a bounded array")
    blocker_ids: set[str] = set()
    blocked: set[tuple[int, int]] = set()
    for blocker in blockers:
        require(isinstance(blocker, dict), "Habitat blocker must be an object")
        blocker_id = identifier(blocker.get("id"), "habitat blocker ID")
        require(blocker_id not in blocker_ids, "Duplicate habitat blocker ID")
        blocker_ids.add(blocker_id)
        x, y, width, height = integers(blocker.get("rect"), 4, "habitat blocker rectangle")
        require(width > 0 and height > 0 and x + width <= columns and y + height <= rows,
                "Habitat blocker lies outside grid")
        blocked.update((cell_x, cell_y) for cell_y in range(y, y + height) for cell_x in range(x, x + width))

    def cell(value_cell: Any, label: str) -> tuple[int, int]:
        x, y = integers(value_cell, 2, label)
        require(x < columns and y < rows, label + " lies outside grid")
        require((x, y) not in blocked, label + " is blocked")
        return x, y

    spawn = cell(value.get("spawn"), "Habitat spawn")
    anchors = value.get("wasteAnchors")
    require(isinstance(anchors, list) and len(anchors) == 3, "Habitat needs exactly three waste anchors")
    waste_anchors = [cell(anchor, "Waste anchor") for anchor in anchors]
    require(len(set(waste_anchors)) == 3, "Waste anchors must be unique")
    zones = value.get("decorationZones")
    require(isinstance(zones, list) and zones, "Habitat needs decoration zones")
    zone_ids: set[str] = set()
    for zone in zones:
        require(isinstance(zone, dict), "Decoration zone must be an object")
        zone_id = identifier(zone.get("id"), "decoration zone ID")
        require(zone_id not in zone_ids, "Duplicate decoration zone ID")
        zone_ids.add(zone_id)
        x, y, width, height = integers(zone.get("rect"), 4, "decoration zone rectangle")
        require(width > 0 and height > 0 and x + width <= columns and y + height <= rows,
                "Decoration zone lies outside grid")
        require(any((cx, cy) not in blocked for cy in range(y, y + height) for cx in range(x, x + width)),
                "Decoration zone has no usable cells")

    stack_records = {stack["id"]: stack for stack in environment.get("planeStacks", [])} if environment else None
    footprint_records = {footprint["id"]: footprint for footprint in environment.get("groundFootprints", [])} \
        if environment else None
    navigation_records = {profile["id"]: profile for profile in environment.get("navigationProfiles", [])} \
        if environment else None
    placement_ids: set[str] = set()
    placements = value.get("staticPlacements")
    require(isinstance(placements, list) and len(placements) <= MAX_HABITAT_PLACEMENTS,
            "staticPlacements must be a bounded array")
    for placement in placements:
        require(isinstance(placement, dict), "Static placement must be an object")
        placement_id = identifier(placement.get("id"), "static placement ID")
        require(placement_id not in placement_ids, "Duplicate static placement ID")
        placement_ids.add(placement_id)
        identifier(placement.get("planeStack"), "static placement planeStack")
        placement_x, placement_y = integers(placement.get("cell"), 2, "Static placement cell")
        require(placement_x < columns and placement_y < rows, "Static placement cell lies outside grid")
        turns = placement.get("rotationQuarterTurns", 0)
        require(type(turns) is int and turns == 0,
                "Static placement rotationQuarterTurns must be 0 for fixed-card environment v1")
        blocker_ref = placement.get("blocker")
        if blocker_ref is not None:
            require(blocker_ref in blocker_ids, "Static placement references a missing blocker")
        if stack_records is not None:
            require(placement["planeStack"] in stack_records, "Static placement references a missing environment plane stack")
            stack = stack_records[placement["planeStack"]]
            profile = navigation_records.get(stack["navigation"], {})
            require(not profile.get("movement", False) or blocker_ref in blocker_ids,
                    "Movement-blocking static placement needs an explicit habitat blocker")
            if blocker_ref is not None:
                footprint = footprint_records[stack["groundFootprint"]]["rect"]
                origin = ((placement_x + 0.5) * grid["cellSize"],
                          (placement_y + 0.5) * grid["cellSize"])
                visual_rect = _rotated_footprint(footprint, origin, turns * 90.0)
                blocker = next(record for record in blockers if record["id"] == blocker_ref)
                blocker_rect = [component * grid["cellSize"] for component in blocker["rect"]]
                require(_rect_contains(blocker_rect, visual_rect) and
                        all(abs(left - right) <= 0.01 for left, right in
                            zip(_rect_center(blocker_rect), _rect_center(visual_rect))),
                        "Static placement groundFootprint is not aligned with its habitat blocker")

    free = {(x, y) for y in range(rows) for x in range(columns) if (x, y) not in blocked}
    visited = {spawn}
    queue = deque([spawn])
    while queue:
        x, y = queue.popleft()
        for next_cell in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if next_cell in free and next_cell not in visited:
                visited.add(next_cell)
                queue.append(next_cell)
    require(set(waste_anchors) <= visited, "Waste anchors are unreachable from habitat spawn")
    require(visited == free, "Habitat contains disconnected free cells")
    return {"freeCells": len(free), "reachableCells": len(visited),
            "wasteAnchors": len(waste_anchors), "staticPlacements": len(placement_ids)}


def validate_arena_environment_placements(arena: dict, environment: dict) -> None:
    """Bind visual stack footprints exactly to arena collision authority."""
    stacks = {stack["id"]: stack for stack in environment["planeStacks"]}
    footprints = {footprint["id"]: footprint["rect"] for footprint in environment["groundFootprints"]}
    navigation = {profile["id"]: profile for profile in environment["navigationProfiles"]}
    obstacles = {obstacle["id"]: obstacle for obstacle in arena["obstacles"]}
    for placement in arena["presentation"]["staticPlacements"]:
        require(float(placement.get("rotationDegrees", 0)) == 0.0,
                "Arena presentation rotationDegrees must be 0 for fixed-card environment v1")
        require(placement["planeStack"] in stacks,
                "Arena presentation references a missing environment plane stack")
        stack = stacks[placement["planeStack"]]
        profile = navigation[stack["navigation"]]
        obstacle_id = placement.get("obstacle")
        require(not profile["movement"] or obstacle_id in obstacles,
                "Movement-blocking arena presentation needs an explicit arena obstacle")
        if obstacle_id is not None:
            require(obstacle_id in obstacles,
                    "Arena presentation placement references a missing obstacle")
            position = placement["groundPosition"]
            visual_rect = _rotated_footprint(footprints[stack["groundFootprint"]],
                                             (float(position[0]), float(position[1])),
                                             float(placement.get("rotationDegrees", 0)))
            obstacle_rect = [float(component) for component in obstacles[obstacle_id]["rect"]]
            require(_rect_equal(visual_rect, obstacle_rect),
                    "Arena placement groundFootprint must exactly align with its obstacle")


def validate_plan(plan: Any) -> None:
    require(isinstance(plan, dict), "Plan must be an object")
    require(plan.get("schemaVersion") == 1, "Unsupported source-plan version")
    identifier(plan.get("assetId"), "assetId")
    identifier(plan.get("revision"), "revision")
    require(plan.get("kind") in KINDS, "Unsupported asset kind")
    require(plan.get("provider") in PROVIDERS, "Unsupported provider")
    # Source plans are copied into immutable candidates for every kind. Keep
    # every promotable artifact free of host-specific paths, not just the
    # environment/habitat branches that first introduced this rule.
    require_portable_paths(plan, "Source plan")
    require(isinstance(plan.get("sources"), dict), "sources must be an object")
    require(isinstance(plan.get("keyposes", []), list), "keyposes must be an array")
    for role in plan.get("keyposes", []):
        identifier(role, "keypose role")
    require(len(set(plan.get("keyposes", []))) == len(plan.get("keyposes", [])), "Duplicate keypose roles")
    for role, source in plan["sources"].items():
        identifier(role, "source role")
        require(isinstance(source, dict) and set(source) == {"path", "sha256"}, "Malformed source binding")
        require(isinstance(source["path"], str) and source["path"], "Missing source path")
        require(isinstance(source["sha256"], str) and len(source["sha256"]) == 71 and
                source["sha256"].startswith("sha256:") and
                all(c in "0123456789abcdef" for c in source["sha256"][7:]), "Malformed source hash")
    validate_derived_images(plan)
    restriction = restricted_classification(source["sha256"] for source in plan["sources"].values())
    if restriction is not None:
        license_data = plan.get("environment", {}).get("license") if plan["kind"] == "environment" \
            else plan.get("license")
        require(isinstance(license_data, dict) and license_data.get("classification") == restriction,
                "Known DigimonUP source hashes require private-prototype-only license classification")
        if plan["kind"] == "environment" and plan.get("provenance", {}).get("kind") == "source-derived":
            environment = plan.get("environment", {})
            used_roles = {item.get("source") for item in environment.get("terrainChunks", [])}
            used_roles.update(item.get("source") for item in environment.get("spritePlanes", []))
            used_roles.update(item.get("source") for item in environment.get("ambientPlanes", []))
            undeclared = {role for role in used_roles if role in plan["sources"] and
                          plan["sources"][role]["sha256"] not in DIGIMONUP_ORIGINAL_HASHES and
                          role not in plan.get("derivedImages", {})}
            require(not undeclared,
                    "DigimonUP-derived environment outputs need machine-verifiable derivedImages: " +
                    ", ".join(sorted(undeclared)))
    if plan["kind"] == "animation":
        integers(plan.get("canvas"), 2, "canvas", 1)
        require(max(plan["canvas"]) <= 2048, "Frame canvas exceeds limit")
        facings = plan.get("requiredFacings", [])
        actions = plan.get("requiredActions", [])
        require(isinstance(facings, list) and all(f in FACINGS for f in facings) and
                len(set(facings)) == len(facings), "Invalid requiredFacings")
        require(isinstance(actions, list) and all(a in ACTIONS for a in actions), "Invalid requiredActions")
        require(all("keypose." + facing.lower() in plan.get("keyposes", []) for facing in facings),
                "Each required facing needs its own declared keypose gate")
        require(isinstance(plan.get("clips"), dict) and plan["clips"], "Animation needs clips")
        for action in actions:
            for facing in facings:
                require(action + "." + facing.lower() in plan["clips"],
                        "Missing directional clip: " + action + "." + facing.lower())
        for clip_id, clip in plan["clips"].items():
            identifier(clip_id, "clip ID")
            require(len(clip_id.split(".")) == 2, "Clip IDs must be action.variant")
            require(isinstance(clip, dict) and clip.get("kind") in ("loop", "one-shot", "hold", "transition"),
                    "Invalid clip kind")
            frames = clip.get("frames")
            require(isinstance(frames, list) and frames, "Clip needs frames")
            for frame in frames:
                require(isinstance(frame, dict), "Frame must be an object")
                identifier(frame.get("source"), "frame source")
                require(type(frame.get("durationMs")) is int and frame["durationMs"] > 0,
                        "Frame durations must be positive integers")
                point(frame.get("pivot"), "pivot")
                require(isinstance(frame.get("anchors"), dict) and frame["anchors"], "Frame needs anchors")
                for anchor in frame["anchors"].values():
                    point(anchor, "anchor")
                if "rect" in frame:
                    integers(frame["rect"], 4, "source rectangle")
                    require(min(frame["rect"][2:]) > 0, "Source rectangle must be positive")
            for event in clip.get("events", []):
                require(isinstance(event, dict) and type(event.get("frame")) is int and
                        0 <= event["frame"] < len(frames) and isinstance(event.get("name"), str) and
                        event["name"], "Invalid clip event")
        for target in plan.get("fallbacks", {}).values():
            require(target in plan["clips"], "Fallback references missing clip")
    elif plan["kind"] == "arena":
        validate_arena(plan.get("arena"))
    elif plan["kind"] == "tileset":
        validate_tileset(plan.get("tileset"))
    elif plan["kind"] == "environment":
        provenance = plan.get("provenance", {})
        require(isinstance(provenance, dict) and provenance.get("kind") in PROVENANCE_KINDS,
                "Environment provenance.kind must use a canonical classification")
        validate_environment(plan.get("environment"))
    elif plan["kind"] == "habitat":
        provenance = plan.get("provenance", {})
        require(isinstance(provenance, dict) and provenance.get("kind") in PROVENANCE_KINDS,
                "Habitat provenance.kind must use a canonical classification")
        validate_habitat(plan.get("habitat"))
    else:
        require(isinstance(plan.get("entries"), dict) and plan["entries"], "Atlas needs named entries")
        for name, entry in plan["entries"].items():
            identifier(name, "entry name")
            require(isinstance(entry, dict), "Atlas entry must be an object")
            identifier(entry.get("source"), "entry source")
            if "pivot" in entry:
                point(entry["pivot"], "atlas entry pivot")


def combat_collision(tile: dict, tile_size: list, projection: str) -> list:
    """Project the ONE authoritative ground footprint into a native tile polygon.

    A supplied collision array is not a second authority when combat exists.
    Projection math is presentation-only; combat keeps exact ground integers.
    """
    combat = tile.get("combat")
    if combat is None:
        require(not tile.get("collision"), "Collidable tiles need an explicit ground-unit combat footprint")
        return []
    require(isinstance(combat, dict), "combat footprint must be an object")
    cell = combat.get("cellSize")
    require(type(cell) is int and 1 <= cell <= 4096, "combat.cellSize must be a positive bounded integer")
    x, y, w, h = integers(combat.get("rect"), 4, "tile combat rectangle")
    require(w > 0 and h > 0 and x+w <= cell and y+h <= cell,
            "Tile combat footprint must fit its declared ground cell")
    require(all(type(combat.get(flag)) is bool for flag in
                ("movement", "projectile", "sight", "occlusion")), "Tile combat flags must be explicit")
    if not combat["movement"]:
        return []
    tile_w, tile_h = tile_size
    corners = [(x,y), (x+w,y), (x+w,y+h), (x,y+h)]
    if projection == "isometric":
        return [[[(px-py)*tile_w/(2*cell), (px+py-cell)*tile_h/(2*cell)] for px,py in corners]]
    return [[[px*tile_w/cell-tile_w/2, py*tile_h/cell-tile_h/2] for px,py in corners]]


def validate_tileset(value: Any, image_size: tuple[int, int] | None = None) -> None:
    require(isinstance(value, dict), "Missing TileSet data")
    require(value.get("projection") in ("square", "isometric"), "Invalid TileSet projection")
    tile_w, tile_h = integers(value.get("tileSize"), 2, "tileSize", 1)
    require(isinstance(value.get("tiles"), list) and value["tiles"], "TileSet needs explicit tile records")
    seen = set()
    for tile in value["tiles"]:
        require(isinstance(tile, dict), "Tile must be an object")
        x, y = integers(tile.get("atlas"), 2, "tile atlas coordinate")
        alternative = tile.get("alternative", 0)
        require(type(alternative) is int and 0 <= alternative < 4096, "Invalid alternative ID")
        key = (x, y, alternative)
        require(key not in seen, "Duplicate tile/alternative")
        seen.add(key)
        if image_size:
            require((x + 1) * tile_w <= image_size[0] and (y + 1) * tile_h <= image_size[1],
                    "Tile lies outside atlas")
        require(type(tile.get("probability", 1)) in (int, float) and tile.get("probability", 1) > 0,
                "Tile probability must be positive")
        collision = combat_collision(tile, value["tileSize"], value["projection"])
        for layer in ("collision", "navigation", "occlusion"):
            polygons = collision if layer == "collision" else tile.get(layer, [])
            require(isinstance(polygons, list), layer + " must be polygon arrays")
            for polygon in polygons:
                require(isinstance(polygon, list) and len(polygon) >= 3, "Polygon needs at least 3 vertices")
                for vertex in polygon:
                    require(isinstance(vertex, list) and len(vertex) == 2 and
                            all(type(c) in (int, float) and abs(c) <= 4096 for c in vertex), "Invalid polygon vertex")
                area = sum(polygon[i][0] * polygon[(i+1) % len(polygon)][1] -
                           polygon[(i+1) % len(polygon)][0] * polygon[i][1] for i in range(len(polygon)))
                require(area != 0, "Degenerate polygon")
        terrain_set = tile.get("terrainSet", -1)
        terrain = tile.get("terrain", -1)
        terrains = value.get("terrains", [])
        require(type(terrain_set) is int and -1 <= terrain_set < len(terrains), "Invalid terrain set")
        require(type(terrain) is int and terrain >= -1, "Invalid terrain")
        if terrain_set >= 0:
            require(terrain < len(terrains[terrain_set].get("terrains", [])), "Terrain index out of range")
        else:
            require(terrain == -1 and not tile.get("terrainPeering"), "Terrain requires a terrain set")
    require(all((x, y, 0) in seen for x, y, _ in seen), "Alternative tile requires base tile zero")


def validate_arena(arena: Any) -> dict:
    require(isinstance(arena, dict), "Arena must be an object")
    require(arena.get("projection") in ("square", "isometric"), "Invalid arena projection")
    ground = arena.get("ground")
    require(isinstance(ground, dict), "Arena needs ground dimensions")
    width, height, cell = [ground.get(key) for key in ("width", "height", "cellSize")]
    require(all(type(v) is int and v > 0 for v in (width, height, cell)), "Ground dimensions must be positive integers")
    require(80 <= width <= 4096 and 80 <= height <= 4096 and 8 <= cell <= 128 and
            width % cell == 0 and height % cell == 0 and width//cell * (height//cell) <= 16384,
            "Ground must use a bounded, whole-cell grid")
    radius = arena.get("maxBodyRadius")
    require(type(radius) is int and 0 < radius <= 64, "Invalid maxBodyRadius")
    obstacles = arena.get("obstacles")
    require(isinstance(obstacles, list) and len(obstacles) <= 512, "Invalid obstacles")
    seen = set()
    for obstacle in obstacles:
        require(isinstance(obstacle, dict), "Obstacle must be an object")
        obstacle_id = identifier(obstacle.get("id"), "obstacle ID")
        require(obstacle_id not in seen, "Duplicate obstacle ID")
        seen.add(obstacle_id)
        x, y, w, h = integers(obstacle.get("rect"), 4, "obstacle rectangle")
        require(w > 0 and h > 0 and x+w <= width and y+h <= height, "Obstacle outside ground")
        require(all(type(obstacle.get(flag)) is bool for flag in
                    ("movement", "projectile", "sight", "occlusion")), "Every obstacle flag must be explicit")

    def free(point_xy):
        x, y = point_xy
        if not (radius <= x <= width-radius and radius <= y <= height-radius):
            return False
        return not any(o["movement"] and o["rect"][0]-radius <= x <= o["rect"][0]+o["rect"][2]+radius and
                       o["rect"][1]-radius <= y <= o["rect"][1]+o["rect"][3]+radius for o in obstacles)

    def clear_segment(a, b):
        # Exact conservative slab test against body-expanded footprints; this
        # prevents thin barriers being missed between otherwise-free grid nodes.
        for obstacle in obstacles:
            if not obstacle["movement"]:
                continue
            x, y, w, h = obstacle["rect"]
            low, high = 0.0, 1.0
            for axis, minimum, maximum in ((0, x-radius, x+w+radius), (1, y-radius, y+h+radius)):
                delta = b[axis]-a[axis]
                if delta == 0:
                    if a[axis] < minimum or a[axis] > maximum:
                        low, high = 1.0, 0.0
                        break
                else:
                    first, second = sorted(((minimum-a[axis])/delta, (maximum-a[axis])/delta))
                    low, high = max(low, first), min(high, second)
            if low <= high:
                return False
        return True

    nodes = {(x+cell/2, y+cell/2) for y in range(0, height, cell) for x in range(0, width, cell)
             if free((x+cell/2, y+cell/2))}
    require(len(nodes) >= 25, "Arena has insufficient body-clear ground")
    spawns = arena.get("spawns")
    require(isinstance(spawns, dict) and set(spawns) == {"player", "opponent"}, "Arena needs two named spawns")
    starts = []
    for name in ("player", "opponent"):
        spawn = integers(spawns[name], 2, "spawn")
        require(free(spawn), "Spawn lacks body clearance: " + name)
        exits = [(spawn[0]+cell,spawn[1]), (spawn[0]-cell,spawn[1]),
                 (spawn[0],spawn[1]+cell), (spawn[0],spawn[1]-cell)]
        require(sum(free(nxt) and clear_segment(spawn, nxt) for nxt in exits) >= 3,
                "Spawn needs at least three body-clear cardinal exits: " + name)
        nearby = sorted(nodes, key=lambda n: ((n[0]-spawn[0])**2+(n[1]-spawn[1])**2, n))
        require(clear_segment(spawn, nearby[0]), "Spawn cannot enter navigation grid")
        starts.append(nearby[0])
    require(not all(abs(spawns["player"][i]-spawns["opponent"][i]) < 2*radius for i in (0, 1)),
            "Spawn bodies overlap")
    visited = {starts[0]}
    queue = deque(visited)
    while queue:
        x, y = queue.popleft()
        for nxt in ((x+cell, y), (x, y+cell), (x-cell, y), (x, y-cell)):
            if nxt in nodes and nxt not in visited and clear_segment((x, y), nxt):
                visited.add(nxt)
                queue.append(nxt)
    require(starts[1] in visited, "Spawns are disconnected")
    require(visited == nodes, "Arena contains disconnected body-clear islands")
    for start in starts:
        nearby = [n for n in visited if abs(n[0]-start[0]) + abs(n[1]-start[1]) <= 3*cell]
        require(len(nearby) >= 10, "Spawn has insufficient escape options")
    patches = sum(all((x+dx*cell, y+dy*cell) in visited for dx in (-1, 0, 1) for dy in (-1, 0, 1))
                  for x, y in visited)
    require(patches >= 4, "Arena lacks open 3x3 evasion patches")
    tiles = arena.get("tiles", [])
    require(isinstance(tiles, list), "tiles must be an array")
    require(not tiles or isinstance(arena.get("tileSet"), dict), "Placed tiles require a pinned TileSet")
    if "tileSet" in arena:
        identifier(arena["tileSet"].get("assetId"), "TileSet assetId")
        identifier(arena["tileSet"].get("revision"), "TileSet revision")
    for tile in tiles:
        x, y = integers(tile.get("cell"), 2, "tile cell")
        integers(tile.get("atlas"), 2, "tile atlas")
        require(x < width//cell and y < height//cell, "Placed tile outside arena")
        require(type(tile.get("alternative", 0)) is int and tile.get("alternative", 0) >= 0, "Invalid tile alternative")
    if "environment" in arena:
        _binding(arena["environment"], "Arena environment")
        presentation = arena.get("presentation")
        require(isinstance(presentation, dict) and isinstance(presentation.get("staticPlacements"), list) and
                len(presentation["staticPlacements"]) <= MAX_ARENA_PRESENTATION_PLACEMENTS,
                "Arena environment needs presentation.staticPlacements")
        placement_ids: set[str] = set()
        obstacle_ids = {obstacle["id"] for obstacle in obstacles}
        for placement in presentation["staticPlacements"]:
            require(isinstance(placement, dict), "Arena presentation placement must be an object")
            placement_id = identifier(placement.get("id"), "arena presentation placement ID")
            require(placement_id not in placement_ids, "Duplicate arena presentation placement ID")
            placement_ids.add(placement_id)
            identifier(placement.get("planeStack"), "arena presentation planeStack")
            x, y = integers(placement.get("groundPosition"), 2, "arena presentation groundPosition")
            require(x <= width and y <= height, "Arena presentation placement lies outside ground")
            _number(placement.get("rotationDegrees", 0), "arena presentation rotationDegrees", -360, 360)
            require(float(placement.get("rotationDegrees", 0)) == 0.0,
                    "Arena presentation rotationDegrees must be 0 for fixed-card environment v1")
            if "obstacle" in placement:
                require(placement["obstacle"] in obstacle_ids,
                        "Arena presentation placement references a missing obstacle")
    return {"bodyClearCells": len(nodes), "reachableCells": len(visited), "evasionPatches": patches,
            "validatedBodyRadius": radius}

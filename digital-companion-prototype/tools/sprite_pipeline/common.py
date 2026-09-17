"""Deterministic serialization and scoped, durable filesystem primitives.

Adapted from the companion web project's pinned-source compiler and PixelLab
adapter: never follow source symlinks, overwrite a revision, or retry a POST.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import stat
from typing import Any
from uuid import uuid4

MAX_BYTES = 16 * 1024 * 1024
SAFE_ID = re.compile(r"^[a-z0-9]+(?:[._-][a-z0-9]+)*$")


class PipelineError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise PipelineError(message)


def identifier(value: Any, label: str) -> str:
    require(isinstance(value, str) and len(value) <= 100 and bool(SAFE_ID.fullmatch(value)),
            label + " must be a lowercase identifier (letters, digits, '.', '_' or '-')")
    return value


def canonical(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False,
                       allow_nan=False) + "\n").encode("utf-8")


def digest(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def fingerprint(value: Any) -> str:
    return digest(canonical(value))


def safe_path(root: Path, path: Path) -> Path:
    """Resolve lexical scope, rejecting symlinks in every existing component."""
    root = root.absolute()
    path = path.absolute()
    require(".." not in path.parts, "Parent traversal is not permitted")
    try:
        path.relative_to(root)
    except ValueError:
        raise PipelineError("Path escapes allowed directory: " + str(root)) from None
    current = Path(path.anchor)
    for part in path.parts[1:]:
        current /= part
        require(not current.is_symlink(), "Symbolic links are not permitted: " + str(current))
    return path


def read_bytes(path: Path, limit: int = MAX_BYTES) -> bytes:
    safe_path(Path(path.anchor), path)
    fd = os.open(str(path), os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    with os.fdopen(fd, "rb") as stream:
        require(stat.S_ISREG(os.fstat(stream.fileno()).st_mode), "Expected a regular file")
        data = stream.read(limit + 1)
    require(len(data) <= limit, "File exceeds size limit: " + str(path))
    return data


def load_json(path: Path) -> Any:
    try:
        return json.loads(read_bytes(path), parse_constant=lambda _: (_ for _ in ()).throw(
            PipelineError("Non-finite JSON number")))
    except (ValueError, UnicodeDecodeError) as error:
        raise PipelineError("Invalid JSON: " + str(path)) from error


def sync_dir(path: Path) -> None:
    fd = os.open(str(path), os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def write_bytes(root: Path, path: Path, data: bytes, replace: bool = False) -> None:
    safe_path(root, path)
    path.parent.mkdir(parents=True, exist_ok=True)
    safe_path(root, path)
    if not replace:
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
        fd = os.open(str(path), flags, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
    else:
        temporary = path.with_name("." + path.name + "." + uuid4().hex + ".tmp")
        try:
            write_bytes(root, temporary, data)
            safe_path(root, path)
            os.replace(str(temporary), str(path))
        finally:
            if temporary.exists():
                temporary.unlink()
    sync_dir(path.parent)


def write_json(root: Path, path: Path, value: Any, replace: bool = False) -> None:
    write_bytes(root, path, canonical(value), replace)


def tree_hashes(directory: Path, payload_files=None) -> dict[str, str]:
    """Hash the complete payload, excluding only known PNG import sidecars.

    Godot may create ``atlas.png.import`` after review. Generated artwork is
    decoded from raw PNG bytes and embedded into reviewed native resources, so
    that editor-only import configuration cannot affect review/runtime output.
    Never extend this exception to arbitrary .import files or other extra files.
    Initial compilation supplies its known PNG names; later checks use the
    hash-bound candidate manifest. Symlinks are rejected even for sidecars.
    """
    if payload_files is None:
        metadata_path = directory / "candidate.json"
        metadata = load_json(metadata_path) if metadata_path.exists() else {}
        payload_files = metadata.get("files", {}) if isinstance(metadata, dict) else {}
    require(isinstance(payload_files, (dict, list, tuple, set)), "Invalid artifact payload file list")
    known_pngs = {name for name in payload_files
                  if isinstance(name, str) and name.endswith(".png")}
    result = {}
    for path in sorted(directory.rglob("*")):
        safe_path(directory, path)
        if path.is_dir():
            continue
        require(path.is_file(), "Expected a regular artifact file: " + str(path))
        name = path.relative_to(directory).as_posix()
        if name.endswith(".png.import") and name[:-7] in known_pngs:
            png_path = safe_path(directory, directory / name[:-7])
            if png_path.is_file():
                continue
        if path != directory / "candidate.json":
            result[name] = digest(read_bytes(path))
    return result

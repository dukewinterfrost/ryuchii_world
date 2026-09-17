"""Small real PixelLab REST adapter; a POST is never automatically retried.

Payloads verified against https://api.pixellab.ai/v2/openapi.json (2026-09-09).
Routes: /generate-image-v2, /animate-with-text-v3, /background-jobs/{job_id}.
Durable submission intent precedes POST, durable job ID precedes any GET.
"""

from __future__ import annotations

import base64
from io import BytesIO
import os
from pathlib import Path
import urllib.error
import urllib.parse
import urllib.request

from PIL import Image

from .common import (MAX_BYTES, PipelineError, canonical, digest, fingerprint,
                     identifier, load_json, read_bytes, require, write_bytes, write_json)

API = "https://api.pixellab.ai/v2"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise PipelineError("PixelLab redirect refused; credentials were not forwarded")


def request(method: str, route: str, payload=None):
    token = os.environ.get("PIXELLAB_API_TOKEN") or os.environ.get("PIXELLAB_API_KEY")
    require(bool(token), "Set PIXELLAB_API_TOKEN for PixelLab requests")
    headers = {"Authorization": "Bearer " + token, "Content-Type": "application/json"}
    req = urllib.request.Request(API + route, data=canonical(payload) if payload is not None else None,
                                 headers=headers, method=method)
    try:
        with urllib.request.build_opener(NoRedirect()).open(req, timeout=45) as response:
            raw = response.read(MAX_BYTES + 1)
        require(len(raw) <= MAX_BYTES, "PixelLab response exceeds limit")
        import json
        value = json.loads(raw)
        require(isinstance(value, dict), "Malformed PixelLab response")
        return value
    except urllib.error.HTTPError as error:
        raise PipelineError("PixelLab HTTP " + str(error.code) + "; response body omitted") from None
    except (OSError, ValueError):
        raise PipelineError("PixelLab request failed; provider details omitted; submission may be uncertain") from None


def inspect_png(raw: bytes, expected_size=None):
    require(len(raw) <= 4 * 1024 * 1024, "Provider image exceeds byte limit")
    try:
        with Image.open(BytesIO(raw)) as image:
            require(image.format == "PNG" and image.width * image.height <= 2048 * 2048,
                    "Provider image must be a bounded PNG")
            image.load()
            if expected_size:
                require(image.size == tuple(expected_size), "Provider dimensions do not match the request")
            return image.size
    except (OSError, ValueError):
        raise PipelineError("Provider returned an invalid PNG") from None


def prepare(plan, job, sources):
    """Only documented fields; local source bindings supply all image payloads."""
    require(isinstance(job, dict), "generation job must be an object")
    identifier(job.get("id"), "job ID")
    operation = job.get("operation", "generate-image-v2")
    require(operation in ("generate-image-v2", "animate-with-text-v3"), "Unsupported PixelLab operation")
    description = job.get("description")
    require(isinstance(description, str) and 0 < len(description) <= (1000 if operation == "animate-with-text-v3" else 2000),
            "Generation description is missing or too long")
    seed = job.get("seed", 1)
    require(type(seed) is int and seed > 0, "Generation seed must be a fixed positive integer")

    def image_object(role):
        require(role in sources, "Missing generation reference: " + str(role))
        raw = read_bytes(sources[role])
        size = inspect_png(raw)
        return {"type": "base64", "base64": base64.b64encode(raw).decode("ascii"), "format": "png"}, size

    if operation == "animate-with-text-v3":
        first, size = image_object(job.get("firstFrame"))
        require(max(size) <= 256, "Animation input exceeds 256 pixels")
        count = job.get("frameCount", 8)
        require(type(count) is int and 4 <= count <= 16 and count % 2 == 0, "frameCount must be even, 4–16")
        require(size[0]*size[1]*count <= 524288, "Animation pixel budget exceeded")
        payload = {"first_frame": first, "action": description, "frame_count": count,
                   "seed": seed, "no_background": True, "drift_threshold": 0, "enhance_prompt": False}
        if job.get("lastFrame"):
            last, last_size = image_object(job["lastFrame"])
            require(last_size == size, "Animation endpoints must have the same dimensions")
            payload["last_frame"] = last
    else:
        size = job.get("imageSize", plan.get("canvas", [128, 128]))
        require(isinstance(size, list) and len(size) == 2 and all(type(v) is int and 16 <= v <= 512 for v in size)
                and size[0]*size[1] <= 512*512, "Invalid PixelLab image size")
        payload = {"description": description, "image_size": {"width": size[0], "height": size[1]},
                   "seed": seed, "no_background": job.get("noBackground", True)}
        references = job.get("references", [])
        require(isinstance(references, list) and len(references) <= 4, "At most four reference images")
        if references:
            payload["reference_images"] = []
            for role in references:
                reference, dimensions = image_object(role)
                payload["reference_images"].append({"image": reference,
                                                    "size": {"width": dimensions[0], "height": dimensions[1]}})
    return operation, payload, size


def run_job(root: Path, directory: Path, binding: dict, operation: str, payload: dict,
            size, execute=False, allow_billable=False, resume=False, transport=request,
            source_plan_sha256=None):
    """One GET per invocation: bounded, resumable polling, no long hidden waits."""
    state_path = directory / "generation.json"
    bound = dict(binding, operation=operation, requestSha256=fingerprint(payload))
    if not execute and not resume:
        return {"dryRun": True, "billable": True, **bound, "sourcePlanSha256": source_plan_sha256,
                "requestFields": sorted(payload)}
    if resume:
        require(state_path.is_file(), "No recorded job to resume")
        state = load_json(state_path)
        recorded = state.get("binding")
        require(isinstance(recorded, dict), "Malformed recorded request binding")
        # The request hash already binds every transmitted source byte and API
        # parameter. Other jobs may finish/ingest while this paid job is pending.
        # Retain compatibility with early receipts that put provenance in binding.
        recorded_identity = {key: value for key, value in recorded.items() if key != "planSha256"}
        require(recorded_identity == bound, "Resume inputs do not match the recorded request")
        state.setdefault("sourcePlanSha256", recorded.get("planSha256", source_plan_sha256))
        require(state.get("jobId"), "Submission is uncertain; reconcile with PixelLab before creating another job")
        if state.get("status") == "completed":
            for item in state["outputs"]:
                require(digest(read_bytes(directory / item["path"])) == item["sha256"], "Generated output changed")
            return state
    else:
        require(execute and allow_billable, "Paid generation requires --execute and --allow-billable")
        require(not state_path.exists(), "Job already has a durable submission record; use --resume")
        state = {"schemaVersion": 1, "binding": bound, "sourcePlanSha256": source_plan_sha256,
                 "status": "submission-uncertain", "jobId": None}
        # Exclusive, fsynced intent closes the crash window before receiving ID.
        write_json(root, state_path, state)
        response = transport("POST", "/" + operation, payload)
        job_id = response.get("background_job_id")
        require(isinstance(job_id, str) and 0 < len(job_id) < 200, "PixelLab did not return a valid job ID; do not retry POST")
        state.update(jobId=job_id, status="processing")
        write_json(root, state_path, state, replace=True)
    response = transport("GET", "/background-jobs/" + urllib.parse.quote(state["jobId"], safe=""))
    status = response.get("status")
    require(status in ("processing", "pending", "queued", "completed", "failed"), "Unknown PixelLab job status")
    state["status"] = status
    if status == "completed":
        result = response.get("last_response") or {}
        images = result.get("images", [result.get("image")])
        require(isinstance(images, list) and 1 <= len(images) <= 64, "PixelLab returned invalid output count")
        outputs = []
        for index, value in enumerate(images):
            require(isinstance(value, dict), "Invalid provider image object")
            encoded = value.get("base64") or (value.get("image") or {}).get("base64")
            require(isinstance(encoded, str) and len(encoded) <= 6*1024*1024, "Missing/oversized provider image")
            if encoded.startswith("data:image/png;base64,"):
                encoded = encoded.split(",", 1)[1]
            try:
                raw = base64.b64decode(encoded, validate=True)
            except ValueError:
                raise PipelineError("Invalid provider base64") from None
            inspect_png(raw, size)
            path = directory / ("frame-%04d.png" % index)
            if path.exists():
                require(digest(read_bytes(path)) == digest(raw), "Previously downloaded provider output differs")
            else:
                write_bytes(root, path, raw)
            outputs.append({"path": path.name, "sha256": digest(raw)})
        state["outputs"] = outputs
        if operation == "animate-with-text-v3":
            state["requestedFrameCount"] = payload["frame_count"]
            state["actualFrameCount"] = len(outputs)
            state["frameCountMatches"] = len(outputs) == payload["frame_count"]
        state["humanApproval"] = "pending"
    write_json(root, state_path, state, replace=True)
    require(status != "failed", "PixelLab job failed; recorded receipt retained")
    return state

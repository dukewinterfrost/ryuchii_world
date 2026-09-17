# PixelLab operations

Verify the live [OpenAPI contract](https://api.pixellab.ai/v2/openapi.json) before adapting requests; the API identifies its version as `dev`. The [LLM index](https://api.pixellab.ai/v2/llms.txt) is another primary entry point. The following behavior was verified on 2026-09-13.

## Credentials and scope

Use an existing environment variable or configured local credential file. Standard names in the Digital Companion adapter are `PIXELLAB_API_TOKEN` and `PIXELLAB_API_KEY`. Never print or put the token in shell arguments. Send it only as the bearer credential to the intended official API host, refusing redirects that could forward it elsewhere.

`GET /balance` verifies access without generation and reports both USD credits and remaining subscription generations. A zero USD balance does not imply no capacity when subscription generations remain. Do not purchase or change a plan without a separate user request.

Measure a complete pilot before bulk requests. On this account's 2026-09-13 trial run, each unzoom reported 0.1 generations, background removal reported 1.0, and a four-frame 128px animation job reported 1.0. These are observed receipts, not guaranteed future prices; the balance endpoint ultimately reported zero after the concurrent batch that began with 18 remaining trial generations. Preserve original alpha where a deterministic pipeline can do so correctly, and account for opaque unzoom output before selecting that route. Do not assume preparation is free or infer per-frame pricing from a single job.

Animation authorization normally covers sending the approved sprite images and action prompts to the chosen provider. If an automatic review blocks a transfer, inspect the reason and the existing authorization. Evidence can include the user's provider choice, exact approved image set, and the concrete request fields. Do not bypass a rejection; if evidence does not resolve it, finish unaffected work and explain the specific blocked transfer when asking for approval.

## Native-resolution preparation

`POST /unzoom` accepts an image object and optional `quantize` (-1 preserves produced colors, 0 automatically chooses a palette, 2–256 requests a palette size). Input is at least 256×256 and at most 2048×2048 area. It detects uneven upscaled pixel grids. Output dimensions are inferred, not guaranteed to be suitable for animation.

**Unzoom returns an opaque image**, compositing alpha on white. Follow with `POST /remove-background` when transparency is needed. That request contains `image`, `image_size: {width,height}`, and optionally `background_removal_task: remove_simple_background`, a short foreground description in `text`, and a fixed seed. Its input edges are at most 400px in the observed contract.

Persist synchronous cleanup request hashes and completion receipts as well as animation receipts. A timeout can still leave a charged request; do not automatically rerun an uncertain POST. Inspect the native output before normalizing it into a game canvas.

## Animation

`POST /animate-with-text-v3` accepts:

```json
{
  "first_frame": {"type": "base64", "base64": "<in-memory PNG bytes>", "format": "png"},
  "last_frame": {"type": "base64", "base64": "<optional endpoint>", "format": "png"},
  "action": "A specific motion description, fixed camera and facing",
  "frame_count": 8,
  "seed": 913001,
  "no_background": true,
  "drift_threshold": 0,
  "enhance_prompt": false
}
```

Both endpoint images must have the same dimensions, at most 256×256. Frame count is even, from 4 through 16, with width × height × count ≤ 524,288. Four frames can suit subtle idle/guard loops; eight suits ordinary locomotion; complex actions may need more frames or explicit segments.

`drift_threshold: 0` requests color correction for every frame. Prompt enhancement is optional and has an extra provider charge; leave it disabled when the motion brief is already specific.

The POST returns `background_job_id`. Persist it and poll `GET /background-jobs/{id}` at a bounded interval (the documentation suggests 5–10 seconds). Completed frames are at `last_response.images`. The actual count must be read, not assumed. Preserve a mismatch as provider evidence; do not relabel duplicated frames to make it appear exact.

On 401, fix authentication. On 402, stop billable submissions and report capacity. On 429, preserve the rejection and reduce concurrency; do not confuse it with an accepted job. An uncertain POST without a job ID needs reconciliation. An accepted job with interrupted polling needs GET-only resume. Never silently switch providers or replace a failed AI animation with duplicated stills.

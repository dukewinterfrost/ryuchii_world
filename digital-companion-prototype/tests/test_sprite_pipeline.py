"""Offline contract tests. Synthetic art/approvals stay inside temporary roots."""

from copy import deepcopy
from contextlib import nullcontext
from io import BytesIO
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from sprite_pipeline.common import PipelineError, canonical, digest, load_json, tree_hashes, write_json
from sprite_pipeline.pipeline import Pipeline, template
from sprite_pipeline.sheet_template import create_sheet_template, make_plan
from sprite_pipeline.validation import combat_collision, validate_arena, validate_plan, validate_tileset


def png(size=(16, 16), color=(255, 120, 0, 255)):
    image = Image.new("RGBA", size, color)
    image.putpixel((0, 0), (0, 0, 0, 0))
    stream = BytesIO()
    image.save(stream, "PNG")
    return stream.getvalue()


def run_native_godot(command, **kwargs):
    """Keep focused native-test engine logs inside a disposable test directory."""
    with tempfile.TemporaryDirectory(prefix="companion-native-log-", dir="/tmp") as log_dir:
        return subprocess.run([command[0], "--log-file", str(Path(log_dir) / "godot.log"), *command[1:]], **kwargs)


class SpritePipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.pipeline = Pipeline(self.root)
        self.source = self.root / "input.png"
        self.source.write_bytes(png())

    def tearDown(self):
        self.temp.cleanup()

    def save_plan(self, plan):
        path = self.root / "assets-source" / plan["assetId"] / plan["revision"] / "source-plan.json"
        write_json(self.root, path, plan, replace=path.exists())
        return path

    def basic_plan(self, kind="atlas"):
        return self.save_plan(template("fixture", "v1", kind, "manual"))

    def animation_plan(self):
        plan = template("fixture", "v1", "animation", "manual")
        plan.update(canvas=[16, 16], requiredFacings=["N"], requiredActions=["idle"],
                    keyposes=["keypose.n"], clips={"idle.n": {"kind": "loop", "events": [{"frame":0,"name":"release"}],
                    "frames": [{"source":"idle.n.0000", "durationMs": 100, "pivot":{"x":.5,"y":.9},
                                "anchors":{"root":{"x":.5,"y":.9}}}]}})
        return self.save_plan(plan)

    def approve_keyposes(self, path):
        return self.pipeline.review(path=path, stage="keyposes", approve=True,
                                    reviewer="Test fixture only", notes="Synthetic approval inside temporary directory")

    def approve_final(self, candidate, real_native_probe=False):
        context = patch.object(self.pipeline, "_probe_native_resource", return_value=None) \
            if not real_native_probe else nullcontext()
        with context:
            result = self.pipeline.review(candidate=candidate, approve=True,
                                         reviewer="Test fixture only", notes="Synthetic approval inside temporary directory")
        return Path(result["receipt"])

    def promote_unit(self, candidate, receipt):
        with patch.object(self.pipeline, "_probe_native_resource", return_value=None):
            return self.pipeline.promote(candidate, receipt)

    def native_compile(self, path):
        exporter = self.root / "scripts" / "assets" / "export_resources.gd"
        exporter.parent.mkdir(parents=True, exist_ok=True)
        exporter.write_text("# Test double, not a real Godot resource export")
        def export(command, **kwargs):
            staging = Path(command[command.index("--candidate") + 1])
            self.assertIn("--asset-review", command)
            kind = load_json(staging / "candidate.json")["kind"]
            name = {"animation":"spriteframes.tres", "tileset":"tileset.tres", "arena":"arena.tres", "atlas":"atlasframes.tres"}[kind]
            (staging / name).write_text("[gd_resource type=\"Resource\" format=3]\n[resource]\n")
            return subprocess.CompletedProcess(command, 0, "ok", "")
        with patch("sprite_pipeline.pipeline.subprocess.run", side_effect=export):
            return Path(self.pipeline.compile(path)["candidate"])

    def test_new_preserves_existing_revision(self):
        self.pipeline.new("fixture", "v1", "atlas", "manual")
        with self.assertRaises(FileExistsError):
            self.pipeline.new("fixture", "v1", "atlas", "manual")

    def test_sheet_template_is_blank_rgba_and_rolls_to_next_page(self):
        result = create_sheet_template(self.pipeline, "fixture", "v1", "eating", 9, 140)
        self.assertEqual(len(result["sheets"]), 2)
        for sheet in result["sheets"]:
            with Image.open(sheet) as image:
                self.assertEqual(image.mode, "RGBA")
                self.assertEqual(image.size, (1024, 1024))
                self.assertIsNone(image.getchannel("A").getbbox())
        plan = load_json(Path(result["plan"]))
        self.assertEqual(plan["sheetLayout"]["rows"], ["N", "NE", "E", "SE", "S", "SW", "W", "NW"])
        last = plan["clips"]["eating.nw"]["frames"][8]
        self.assertEqual(last["source"], "sheet.eating.0001")
        self.assertEqual(last["rect"], [0, 896, 128, 128])
        self.assertEqual(last["durationMs"], 140)
        self.assertEqual(last["pivot"], {"x": 0.5, "y": 0.9375})
        with self.assertRaisesRegex(PipelineError, "exists"):
            create_sheet_template(self.pipeline, "fixture", "v1")

    def test_sheet_compiles_only_declared_cells_preserving_timing_and_anchors(self):
        plan = make_plan("fixture", "v1", "idle", 2, 110)
        plan["clips"]["idle.n"]["frames"][1]["durationMs"] = 230
        plan["clips"]["idle.n"]["frames"][1]["anchors"]["mouth"] = {"x": 0.25, "y": 0.4}
        path = self.save_plan(plan)
        sheet = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
        for row in range(8):
            for column in range(2):
                sheet.putpixel((column * 128 + 64, row * 128 + 119), (255, 160, 0, 255))
        sheet.save(self.source)
        self.pipeline.ingest(path, self.source, "sheet.idle.0000")
        for role in plan["keyposes"]:
            self.pipeline.ingest(path, self.source, role)
        self.approve_keyposes(path)
        candidate = Path(self.pipeline.compile(path, native=False)["candidate"])
        atlas = load_json(candidate / "atlas.json")
        self.assertEqual(len(atlas["frames"]), 16, "Six unused columns never enter playback")
        self.assertTrue(all(not frame["rotated"] and not frame["trimmed"] for frame in atlas["frames"].values()))
        clip = load_json(candidate / "animation-set.json")["clips"]["idle.n"]
        self.assertEqual([f["durationMs"] for f in clip["frames"]], [110, 230])
        self.assertEqual(clip["frames"][1]["anchors"], plan["clips"]["idle.n"]["frames"][1]["anchors"])
        self.assertEqual(clip["frames"][1]["pivot"], {"x": 0.5, "y": 0.9375})

    def test_sheet_declared_empty_cells_are_rejected_before_playback(self):
        plan = make_plan("fixture", "v1", "idle", 1)
        path = self.save_plan(plan)
        self.source.write_bytes(png(size=(1024, 1024), color=(0, 0, 0, 0)))
        self.pipeline.ingest(path, self.source, "sheet.idle.0000")
        for role in plan["keyposes"]:
            self.pipeline.ingest(path, self.source, role)
        self.approve_keyposes(path)
        with self.assertRaisesRegex(PipelineError, "Empty animation frame"):
            self.pipeline.compile(path, native=False)

    def test_ingest_hash_binding_and_no_role_overwrite(self):
        path = self.basic_plan()
        first = self.pipeline.ingest(path, self.source, "sprite")
        self.assertEqual(first["sha256"], digest(png()))
        self.pipeline.ingest(path, self.source, "sprite")
        self.source.write_bytes(png(color=(0, 1, 2, 255)))
        with self.assertRaisesRegex(PipelineError, "immutable"):
            self.pipeline.ingest(path, self.source, "sprite")

    def test_symlink_and_traversal_rejected(self):
        path = self.basic_plan()
        linked = self.root / "linked.png"
        linked.symlink_to(self.source)
        with self.assertRaises(PipelineError):
            self.pipeline.ingest(path, linked, "sprite")
        with self.assertRaises(PipelineError):
            self.pipeline.new("../escape", "v1", "atlas", "manual")
        value = load_json(path)
        value["sources"] = {"sprite":{"path":"../../../input.png", "sha256":digest(png())}}
        write_json(self.root, path, value, replace=True)
        with self.assertRaises(PipelineError):
            self.pipeline.compile(path, native=False)

    def test_compile_is_deterministic_and_preserves_pixels(self):
        path = self.basic_plan()
        self.pipeline.ingest(path, self.source, "sprite")
        first = self.pipeline.compile(path, native=False)
        second = self.pipeline.compile(path, native=False)
        self.assertEqual(first, second)
        atlas_path = Path(first["candidate"]) / "atlas.png"
        with Image.open(atlas_path) as image:
            self.assertEqual(image.getpixel((3, 3)), (255, 120, 0, 255))
            self.assertEqual(image.getpixel((2, 2)), (0, 0, 0, 0))
        manifest = load_json(Path(first["candidate"]) / "atlas.json")
        self.assertFalse(manifest["frames"]["sprite"]["trimmed"])

    def test_content_determinism_across_build_directories(self):
        path = self.basic_plan()
        self.pipeline.ingest(path, self.source, "sprite")
        candidate = Path(self.pipeline.compile(path, native=False)["candidate"])
        original = tree_hashes(candidate)
        candidate.rename(candidate.with_name("saved-copy"))
        rebuilt = Path(self.pipeline.compile(path, native=False)["candidate"])
        self.assertEqual(tree_hashes(rebuilt), original)

    def test_atlas_preserves_authored_foot_pivots(self):
        path = self.basic_plan()
        plan = load_json(path)
        plan["entries"]["sprite"]["pivot"] = {"x": 0.538, "y": 0.928}
        path = self.save_plan(plan)
        self.pipeline.ingest(path, self.source, "sprite")
        candidate = Path(self.pipeline.compile(path, native=False)["candidate"])
        atlas = load_json(candidate / "atlas.json")
        self.assertEqual(atlas["frames"]["sprite"]["pivot"], plan["entries"]["sprite"]["pivot"])
        for bad_pivot in ({"x": -0.1, "y": 0.5}, {"x": 0.5, "y": 1.1}, "feet"):
            plan["entries"]["sprite"]["pivot"] = bad_pivot
            with self.assertRaises(PipelineError):
                validate_plan(plan)

    def test_exact_tree_rejects_unlisted_and_nested_candidate_files(self):
        path = self.basic_plan()
        self.pipeline.ingest(path, self.source, "sprite")
        candidate = Path(self.pipeline.compile(path, native=False)["candidate"])
        (candidate / "nested").mkdir()
        (candidate / "nested" / "candidate.json").write_text("{}")
        with self.assertRaisesRegex(PipelineError, "file tree"):
            self.pipeline.validate(candidate)

    def test_only_known_png_import_sidecars_are_derived(self):
        path = self.basic_plan()
        self.pipeline.ingest(path, self.source, "sprite")
        candidate = self.native_compile(path)
        receipt = self.approve_final(candidate)
        original = tree_hashes(candidate)
        sidecar = candidate / "atlas.png.import"
        sidecar.write_text("[params]\nprocess/size_limit=8\n")
        self.assertEqual(tree_hashes(candidate), original)
        self.pipeline.validate(candidate)
        promoted = Path(self.promote_unit(candidate, receipt)["promoted"])
        self.assertFalse((promoted / sidecar.name).exists(), "Derived caches are not promoted payload")
        (promoted / sidecar.name).write_text("Different local editor settings")
        self.assertEqual(tree_hashes(promoted), original)
        self.promote_unit(candidate, receipt)
        for name in ("orphan.png.import", "atlas.json.import", "extra.import", ".gdignore", "extra.gd"):
            with self.subTest(name=name):
                extra = candidate / name
                extra.write_text("Unexpected file")
                with self.assertRaisesRegex(PipelineError, "file tree"):
                    self.pipeline.validate(candidate)
                extra.unlink()
        sidecar.unlink()
        sidecar.symlink_to(self.source)
        with self.assertRaisesRegex(PipelineError, "Symbolic links"):
            self.pipeline.validate(candidate)
        sidecar.unlink()
        for name in ("atlas.png", "atlas.json", "atlasframes.tres"):
            with self.subTest(payload=name):
                payload = candidate / name
                original_bytes = payload.read_bytes()
                payload.write_bytes(original_bytes + b"tampered")
                with self.assertRaisesRegex(PipelineError, "file tree"):
                    self.pipeline.validate(candidate)
                payload.write_bytes(original_bytes)
        sidecar.write_text("Cache")
        (candidate / "atlas.png").unlink()
        self.assertIn(sidecar.name, tree_hashes(candidate), "An orphaned formerly-known sidecar is not excluded")

    def test_initial_compilation_excludes_only_explicit_png_sidecars(self):
        folder = self.root / "staging"
        folder.mkdir()
        (folder / "atlas.png").write_bytes(png())
        (folder / "atlas.png.import").write_text("Editor cache created during compilation")
        (folder / "other.png.import").write_text("Unrelated file")
        hashes = tree_hashes(folder, payload_files=["atlas.png"])
        self.assertEqual(set(hashes), {"atlas.png", "other.png.import"})

    def test_keypose_gate_and_metadata_preservation(self):
        path = self.animation_plan()
        self.pipeline.ingest(path, self.source, "keypose.n")
        with self.assertRaisesRegex(PipelineError, "Approve keyposes"):
            self.pipeline.compile(path, native=False)
        self.approve_keyposes(path)
        self.pipeline.ingest(path, self.source, "idle.n.0000")
        candidate = Path(self.pipeline.compile(path, native=False)["candidate"])
        clip = load_json(candidate / "animation-set.json")["clips"]["idle.n"]
        self.assertEqual(clip["frames"][0]["durationMs"], 100)
        self.assertEqual(clip["frames"][0]["pivot"], {"x":.5,"y":.9})
        self.assertEqual(clip["events"], [{"frame":0,"name":"release"}])
        self.assertEqual(clip["frames"][0]["atlasFrame"], "idle.n.f0000")
        self.assertEqual(clip["qualityProfile"], "pending-human-review")

    def test_stale_pose_approval_after_spec_change(self):
        path = self.animation_plan()
        self.pipeline.ingest(path, self.source, "keypose.n")
        self.approve_keyposes(path)
        plan = load_json(path)
        plan["canvas"] = [32, 32]
        write_json(self.root, path, plan, replace=True)
        with self.assertRaisesRegex(PipelineError, "stale"):
            self.pipeline.compile(path, native=False)

    def test_missing_facing_and_bad_event_rejected(self):
        plan = load_json(self.animation_plan())
        plan["requiredFacings"].append("NE")
        plan["keyposes"].append("keypose.ne")
        with self.assertRaisesRegex(PipelineError, "Missing directional"):
            validate_plan(plan)
        plan["requiredFacings"] = ["N"]
        plan["clips"]["idle.n"]["events"][0]["frame"] = 3
        with self.assertRaisesRegex(PipelineError, "Invalid clip event"):
            validate_plan(plan)

    def test_bad_canvas_and_empty_frame_rejected(self):
        path = self.animation_plan()
        self.pipeline.ingest(path, self.source, "keypose.n")
        self.approve_keyposes(path)
        self.source.write_bytes(png(size=(32, 32)))
        self.pipeline.ingest(path, self.source, "idle.n.0000")
        with self.assertRaisesRegex(PipelineError, "fixed canvas"):
            self.pipeline.compile(path, native=False)

    def test_promotion_requires_native_and_final_review(self):
        path = self.basic_plan()
        self.pipeline.ingest(path, self.source, "sprite")
        offline = Path(self.pipeline.compile(path, native=False)["candidate"])
        receipt = self.approve_final(offline)
        with self.assertRaisesRegex(PipelineError, "Native resources"):
            self.promote_unit(offline, receipt)
        candidate = self.native_compile(path)
        with self.assertRaisesRegex(PipelineError, "different content"):
            self.promote_unit(candidate, receipt)
        receipt = self.approve_final(candidate)
        first = self.promote_unit(candidate, receipt)
        self.assertEqual(self.promote_unit(candidate, receipt), first)
        catalog = load_json(self.root / "assets" / "runtime-catalog.json")
        self.assertEqual(catalog["assets"]["fixture"]["revision"], "v1")
        self.assertTrue((self.root / catalog["assets"]["fixture"]["review"]).is_file())
        self.assertEqual(tree_hashes(Path(first["promoted"])), tree_hashes(candidate))

    def test_stale_source_rejects_final_promotion(self):
        path = self.basic_plan()
        self.pipeline.ingest(path, self.source, "sprite")
        candidate = self.native_compile(path)
        receipt = self.approve_final(candidate)
        plan = load_json(path)
        plan["generation"]["brief"] = "Changed identity"
        write_json(self.root, path, plan, replace=True)
        with self.assertRaisesRegex(PipelineError, "Source plan changed"):
            self.promote_unit(candidate, receipt)

    def test_final_review_without_approve_never_mints_receipt(self):
        path = self.basic_plan()
        self.pipeline.ingest(path, self.source, "sprite")
        candidate = Path(self.pipeline.compile(path, native=False)["candidate"])
        result = self.pipeline.review(candidate=candidate, no_launch=True)
        self.assertIn("pending", result["approval"])
        self.assertFalse(list(candidate.parent.glob("*.final-review.json")))

    def test_codex_generate_dry_run_has_no_network_or_writes(self):
        path = self.basic_plan()
        plan = load_json(path)
        plan["provider"] = "codex-imagegen"
        write_json(self.root, path, plan, replace=True)
        before = tree_hashes(self.root)
        result = self.pipeline.generate(path)
        self.assertTrue(result["dryRun"])
        self.assertEqual(tree_hashes(self.root), before)

    def pixellab_plan(self, animation=False):
        path = self.animation_plan() if animation else self.basic_plan()
        plan = load_json(path)
        plan["provider"] = "pixellab"
        job = {"id":"job-1", "stage":"keyposes", "operation":"generate-image-v2",
               "description":"A test sprite", "imageSize":[16,16], "seed": 42}
        if animation:
            job.update(stage="final", operation="animate-with-text-v3", firstFrame="keypose.n",
                       lastFrame="keypose.n", frameCount=4)
        plan["generation"]["jobs"] = [job]
        write_json(self.root, path, plan, replace=True)
        return path

    def test_pixellab_dry_run_zero_network_and_write(self):
        path = self.pixellab_plan()
        before = tree_hashes(self.root)
        with patch("sprite_pipeline.pixellab.request", side_effect=AssertionError("Unexpected network")):
            result = self.pipeline.generate(path)
        self.assertTrue(result["dryRun"])
        self.assertEqual(tree_hashes(self.root), before)

    def test_pixellab_requires_both_billing_flags(self):
        path = self.pixellab_plan()
        with self.assertRaisesRegex(PipelineError, "allow-billable"):
            self.pipeline.generate(path, execute=True)
        self.assertFalse((self.root / "work").exists())

    def test_pixellab_single_post_durable_id_then_get_only_resume(self):
        path = self.pixellab_plan()
        calls = []
        def transport(method, route, payload=None):
            calls.append(method)
            receipt = self.root / "work/sprites/fixture/v1/jobs/job-1/generation.json"
            if method == "POST":
                self.assertEqual(load_json(receipt)["status"], "submission-uncertain")
                self.assertEqual(payload["image_size"], {"width":16,"height":16})
                return {"background_job_id":"abc/def"}
            self.assertEqual(load_json(receipt)["jobId"], "abc/def")
            self.assertEqual(route, "/background-jobs/abc%2Fdef")
            return {"status":"processing"}
        self.pipeline.generate(path, execute=True, allow_billable=True, transport=transport)
        self.pipeline.generate(path, resume=True, transport=transport)
        self.assertEqual(calls, ["POST", "GET", "GET"])
        with self.assertRaisesRegex(PipelineError, "durable submission"):
            self.pipeline.generate(path, execute=True, allow_billable=True, transport=transport)
        self.assertEqual(calls.count("POST"), 1)

    def test_uncertain_post_never_retried(self):
        path = self.pixellab_plan()
        def transport(*args):
            raise PipelineError("uncertain transport")
        with self.assertRaises(PipelineError):
            self.pipeline.generate(path, execute=True, allow_billable=True, transport=transport)
        with self.assertRaisesRegex(PipelineError, "uncertain"):
            self.pipeline.generate(path, resume=True, transport=transport)
        with self.assertRaisesRegex(PipelineError, "durable submission"):
            self.pipeline.generate(path, execute=True, allow_billable=True, transport=transport)

    def test_pixellab_resume_survives_unrelated_source_ingestion(self):
        path = self.pixellab_plan()
        initial_plan_hash = digest(path.read_bytes())
        calls = []
        def transport(method, *args):
            calls.append(method)
            return {"background_job_id":"pending-job"} if method == "POST" else {"status":"processing"}
        submitted = self.pipeline.generate(path, execute=True, allow_billable=True, transport=transport)
        self.pipeline.ingest(path, self.source, "unrelated-completed-frame")
        resumed = self.pipeline.generate(path, resume=True, transport=transport)
        self.assertEqual(calls, ["POST", "GET", "GET"])
        self.assertEqual(resumed["binding"], submitted["binding"])
        self.assertNotIn("planSha256", resumed["binding"])
        self.assertEqual(resumed["sourcePlanSha256"], initial_plan_hash)
        self.assertNotEqual(initial_plan_hash, digest(path.read_bytes()))

    def test_pixellab_resume_rejects_changed_request_reference_bytes(self):
        path = self.pixellab_plan()
        self.pipeline.ingest(path, self.source, "reference-original")
        plan = load_json(path)
        plan["generation"]["jobs"][0]["references"] = ["reference-original"]
        write_json(self.root, path, plan, replace=True)
        calls = []
        def transport(method, *args):
            calls.append(method)
            return {"background_job_id":"pending-reference-job"} if method == "POST" else {"status":"processing"}
        self.pipeline.generate(path, execute=True, allow_billable=True, transport=transport)
        self.source.write_bytes(png(color=(1, 2, 3, 255)))
        self.pipeline.ingest(path, self.source, "reference-new")
        plan = load_json(path)
        plan["generation"]["jobs"][0]["references"] = ["reference-new"]
        write_json(self.root, path, plan, replace=True)
        with self.assertRaisesRegex(PipelineError, "inputs do not match"):
            self.pipeline.generate(path, resume=True, transport=transport)
        self.assertEqual(calls, ["POST", "GET"])

    def test_pixellab_resume_accepts_legacy_plan_provenance_binding(self):
        path = self.pixellab_plan()
        initial_plan_hash = digest(path.read_bytes())
        def transport(method, *args):
            return {"background_job_id":"legacy-job"} if method == "POST" else {"status":"processing"}
        self.pipeline.generate(path, execute=True, allow_billable=True, transport=transport)
        receipt = self.root / "work/sprites/fixture/v1/jobs/job-1/generation.json"
        legacy = load_json(receipt)
        legacy["binding"]["planSha256"] = legacy.pop("sourcePlanSha256")
        write_json(self.root, receipt, legacy, replace=True)
        self.pipeline.ingest(path, self.source, "unrelated-completed-frame")
        resumed = self.pipeline.generate(path, resume=True, transport=transport)
        self.assertEqual(resumed["sourcePlanSha256"], initial_plan_hash)

    def test_pixellab_completed_bytes_preserved_without_approval(self):
        path = self.pixellab_plan()
        def transport(method, *args):
            if method == "POST":
                return {"background_job_id":"test"}
            return {"status":"completed", "last_response":{"images":[{"base64":base64.b64encode(png()).decode()}]}}
        result = self.pipeline.generate(path, execute=True, allow_billable=True, transport=transport)
        self.assertEqual(result["humanApproval"], "pending")
        output = self.root / "work/sprites/fixture/v1/jobs/job-1/frame-0000.png"
        self.assertEqual(output.read_bytes(), png())
        self.pipeline.generate(path, resume=True, transport=lambda *args: self.fail("completed job must not repoll"))
        self.assertFalse((self.root / "assets/runtime-catalog.json").exists())

    def test_pixellab_wrong_dimensions_rejected(self):
        path = self.pixellab_plan()
        def transport(method, *args):
            if method == "POST":
                return {"background_job_id":"test"}
            return {"status":"completed", "last_response":{"image":{"base64":base64.b64encode(png((32,32))).decode()}}}
        with self.assertRaisesRegex(PipelineError, "dimensions"):
            self.pipeline.generate(path, execute=True, allow_billable=True, transport=transport)

    def test_pixellab_animation_payload_and_keypose_gate(self):
        path = self.pixellab_plan(animation=True)
        self.pipeline.ingest(path, self.source, "keypose.n")
        with self.assertRaisesRegex(PipelineError, "Approve keyposes"):
            self.pipeline.generate(path)
        self.approve_keyposes(path)
        def transport(method, route, payload=None):
            if method == "POST":
                self.assertEqual(route, "/animate-with-text-v3")
                self.assertEqual(payload["first_frame"], payload["last_frame"])
                self.assertEqual(payload["drift_threshold"], 0)
                self.assertFalse(payload["enhance_prompt"])
                return {"background_job_id":"anim"}
            return {"status":"processing"}
        self.pipeline.generate(path, execute=True, allow_billable=True, transport=transport)

    def test_arena_square_isometric_and_independent_obstacle_flags(self):
        arena = template("arena", "v1", "arena", "manual")["arena"]
        first = validate_arena(arena)
        arena["projection"] = "isometric"
        self.assertEqual(validate_arena(arena), first)
        arena["obstacles"] = [{"id":"canopy", "rect":[200,0,100,480], "movement":False,
                                "projectile":False,"sight":False,"occlusion":True}]
        self.assertEqual(validate_arena(arena), first)
        arena["obstacles"][0]["movement"] = True
        with self.assertRaisesRegex(PipelineError, "disconnected"):
            validate_arena(arena)

    def test_arena_spawn_overlap_and_thin_barriers_rejected(self):
        arena = template("arena", "v1", "arena", "manual")["arena"]
        arena["spawns"]["opponent"] = arena["spawns"]["player"][:]
        with self.assertRaisesRegex(PipelineError, "overlap"):
            validate_arena(arena)
        arena["spawns"]["opponent"] = [540, 240]
        arena["obstacles"] = [{"id":"wall", "rect":[320,0,1,480], "movement":True,
                               "projectile":True,"sight":True,"occlusion":True}]
        with self.assertRaisesRegex(PipelineError, "disconnected"):
            validate_arena(arena)

    def test_arena_diagonal_box_overlap_and_half_cell_centers(self):
        arena = template("arena", "v1", "arena", "manual")["arena"]
        arena["spawns"]["opponent"] = [125, 265]
        with self.assertRaisesRegex(PipelineError, "overlap"):
            validate_arena(arena)
        arena["ground"] = {"width": 360, "height": 540, "cellSize": 9}
        arena["spawns"] = {"player":[80,160],"opponent":[280,380]}
        result = validate_arena(arena)
        self.assertGreater(result["bodyClearCells"], 0)

    def test_tileset_alternatives_and_required_combat_metadata(self):
        value = template("tiles", "v1", "tileset", "manual")["tileset"]
        value["tiles"][0]["alternative"] = 1
        with self.assertRaisesRegex(PipelineError, "base tile"):
            validate_tileset(value)
        value["tiles"][0]["alternative"] = 0
        value["tiles"][0]["collision"] = [[[-8,-8],[8,-8],[8,8],[-8,8]]]
        with self.assertRaisesRegex(PipelineError, "combat footprint"):
            validate_tileset(value)

    def test_placed_collision_tile_derives_shared_ground_obstacle(self):
        plan = template("tiles", "v1", "tileset", "manual")
        plan["tileset"]["tileSize"] = [16,16]
        tile = plan["tileset"]["tiles"][0]
        tile["collision"] = [[[-8,-8],[8,-8],[8,8],[-8,8]]]
        tile["combat"] = {"cellSize":20,"rect":[0,0,20,20],"movement":True,"projectile":True,"sight":False,"occlusion":True}
        path = self.save_plan(plan)
        self.pipeline.ingest(path, self.source, "sample")
        self.approve_keyposes(path)
        self.pipeline.ingest(path, self.source, "texture")
        tiles_candidate = self.native_compile(path)
        self.promote_unit(tiles_candidate, self.approve_final(tiles_candidate))
        arena = template("arena", "v1", "arena", "manual")
        arena["arena"]["tileSet"] = {"assetId":"tiles","revision":"v1"}
        arena["arena"]["tiles"] = [{"cell":[15,12],"atlas":[0,0],"alternative":0}]
        candidate = Path(self.pipeline.compile(self.save_plan(arena), native=False)["candidate"])
        compiled = load_json(candidate / "arena.json")
        self.assertEqual(compiled["obstacles"][0]["rect"], [300,240,20,20])
        self.assertTrue(compiled["obstacles"][0]["movement"])
        self.assertFalse(compiled["obstacles"][0]["sight"])
        self.assertTrue(compiled["tileSet"]["contentSha256"].startswith("sha256:"))
        mismatched = deepcopy(arena)
        mismatched["assetId"] = "arena-wrong-cell"
        mismatched["arena"]["ground"]["cellSize"] = 40
        mismatched["arena"]["tiles"][0]["cell"] = [7, 6]
        with self.assertRaisesRegex(PipelineError, "cellSize differs"):
            self.pipeline.compile(self.save_plan(mismatched), native=False)

    def test_shared_canonical_tile_collision_corpus(self):
        cases = load_json(Path(__file__).resolve().parent / "fixtures/tilesets/combat-collision-cases.json")
        for case in cases:
            with self.subTest(case=case["name"]):
                manifest = case["manifest"]
                if case["expectedValid"]:
                    validate_tileset(manifest)
                    self.assertEqual(combat_collision(manifest["tiles"][0], manifest["tileSize"], manifest["projection"]),
                                     case["expectedCollision"])
                else:
                    with self.assertRaises(PipelineError):
                        validate_tileset(manifest)

    def test_compiler_replaces_conflicting_collision_with_ground_authority(self):
        cases = load_json(Path(__file__).resolve().parent / "fixtures/tilesets/combat-collision-cases.json")
        for index in (0, 1, 2, 3):
            case = cases[index]
            plan = template("canonical-%d" % index, "v1", "tileset", "manual")
            plan["tileset"] = case["manifest"]
            self.source.write_bytes(png(tuple(plan["tileset"]["tileSize"])))
            path = self.save_plan(plan)
            self.pipeline.ingest(path, self.source, "sample")
            self.approve_keyposes(path)
            self.pipeline.ingest(path, self.source, "texture")
            candidate = Path(self.pipeline.compile(path, native=False)["candidate"])
            output = load_json(candidate / "tileset.json")
            self.assertEqual(output["tiles"][0]["collision"], case["expectedCollision"])

    def test_candidate_templates_are_well_formed_but_not_approved(self):
        project = Path(__file__).resolve().parents[1]
        # Actual authored assets can gain human approval. Only these starter
        # templates promise empty/unapproved input; do not classify every future
        # source revision as a template just because its directory depth matches.
        for relative in ("agumon/combat-v1", "forest-arena/forest-v1", "creature-template/v1"):
            path = project / "assets-source" / relative / "source-plan.json"
            plan = load_json(path)
            validate_plan(plan)
            if plan["assetId"] == "forest-arena":
                # A concept sample is not approved background/runtime artwork.
                self.assertEqual(set(plan["sources"]), {"sample"})
                source = plan["sources"]["sample"]
                self.assertEqual(digest((path.parent / source["path"]).read_bytes()), source["sha256"])
                self.assertNotIn(plan["backgroundSource"], plan["sources"])
            else:
                self.assertEqual(plan["sources"], {})
            self.assertFalse((path.parent / "keypose-review.json").exists())

    def test_shared_runtime_arena_corpus(self):
        cases = load_json(Path(__file__).resolve().parent / "fixtures/arenas/shared-arena-cases.json")
        for case in cases:
            with self.subTest(case=case["name"]):
                if case["expectedValid"]:
                    validate_arena(case["arena"])
                else:
                    with self.assertRaises(PipelineError):
                        validate_arena(case["arena"])

    @unittest.skipUnless(os.environ.get("SPRITE_NATIVE_TESTS") == "1", "Set SPRITE_NATIVE_TESTS=1 for installed Godot integration")
    def test_real_editor_import_preserves_review_promotion_and_pinned_dependency(self):
        # An isolated project proves actual import settings change imported PNGs,
        # without touching the user's real catalog, imports, saves, or approvals.
        project = Path(__file__).resolve().parents[1]
        shutil.copytree(project / "assets" / "balance", self.root / "assets" / "balance", dirs_exist_ok=True)
        shutil.copytree(project / "scripts", self.root / "scripts")
        shutil.copytree(project / "scenes", self.root / "scenes")
        shutil.copytree(project / "shaders", self.root / "shaders")
        shutil.copy2(project / "project.godot", self.root / "project.godot")
        # The care renderer preloads this texture. Supply synthetic pixels so
        # full-project parse remains valid without copying private runtime art.
        (self.root / "assets/habitat").mkdir(parents=True)
        (self.root / "assets/habitat/verdant-field.png").write_bytes(png())
        (self.root / "assets/enclosure").mkdir(parents=True)
        for texture in ("digi_potty.png", "campfire.png", "pond.png", "flame-loop.png"):
            (self.root / "assets/enclosure" / texture).write_bytes(png())
        (self.root / "tests").mkdir()
        shutil.copy2(project / "tests/asset_import_test_runner.gd", self.root / "tests/asset_import_test_runner.gd")

        def editor_import():
            result = run_native_godot([self.pipeline.godot, "--headless", "--path", str(self.root),
                                     "--import", "--", "--test-mode"],
                                    capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn("SCRIPT ERROR", result.stderr)

        editor_import()  # Register global script classes before native export.
        compiled = []
        for kind in ("atlas", "animation", "tileset", "arena"):
            plan = template("import-" + kind, "v1", kind, "manual")
            if kind == "animation":
                small = load_json(self.animation_plan())
                plan.update(canvas=small["canvas"], requiredFacings=small["requiredFacings"],
                            requiredActions=small["requiredActions"], keyposes=small["keyposes"], clips=small["clips"])
            elif kind == "tileset":
                plan["tileset"]["tileSize"] = [16, 16]
            elif kind == "arena":
                plan["backgroundSource"] = "background"
                plan["arena"]["tileSet"] = {"assetId":"import-tileset", "revision":"v1"}
                plan["arena"]["tiles"] = [{"cell":[15,12], "atlas":[0,0], "alternative":0}]
            path = self.save_plan(plan)
            for role in plan["keyposes"]:
                self.pipeline.ingest(path, self.source, role)
            if plan["keyposes"]:
                self.approve_keyposes(path)
            for role in {"atlas":["sprite"], "animation":["idle.n.0000"], "tileset":["texture"], "arena":["background"]}[kind]:
                self.pipeline.ingest(path, self.source, role)
            candidate = Path(self.pipeline.compile(path)["candidate"])
            receipt = self.approve_final(candidate, real_native_probe=True)
            promoted = Path(self.pipeline.promote(candidate, receipt)["promoted"])
            compiled.append((candidate, receipt, promoted, tree_hashes(candidate)))
        editor_import()
        for candidate, receipt, promoted, before in compiled:
            for folder in (candidate, promoted):
                png_name = "background.png" if load_json(folder / "candidate.json")["kind"] == "arena" else "atlas.png"
                sidecar = folder / (png_name + ".import")
                self.assertTrue(sidecar.is_file(), "Real Godot import must reproduce its sidecar")
                self.assertEqual(tree_hashes(folder), before)
                self.pipeline.validate(folder, require_native=True)
                settings = sidecar.read_text()
                self.assertIn("process/size_limit=0", settings)
                sidecar.write_text(settings.replace("process/size_limit=0", "process/size_limit=8"))
                # Godot's filesystem cache uses second-granularity timestamps.
                # Fast tests must not hide settings edits in the same scan second.
                info = sidecar.stat()
                os.utime(sidecar, ns=(info.st_atime_ns, info.st_mtime_ns + 2_000_000_000))
            self.pipeline.promote(candidate, receipt)
        editor_import()  # Reimport with deliberately different editor-only pixels.
        for candidate, receipt, promoted, before in compiled:
            for folder in (candidate, promoted):
                self.assertEqual(tree_hashes(folder), before)
                self.pipeline.validate(folder, require_native=True)
                result = run_native_godot([self.pipeline.godot, "--headless", "--path", str(self.root),
                                         "--script", "res://tests/asset_import_test_runner.gd", "--",
                                         "--asset-review", "--candidate", str(folder)],
                                        capture_output=True, text=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("Imported PNG differs; reviewed native and raw payload pixels agree", result.stdout)
                exported = run_native_godot([self.pipeline.godot, "--headless", "--path", str(self.root),
                                           "--script", "res://scripts/assets/export_resources.gd", "--",
                                           "--asset-review", "--candidate", str(folder)],
                                          capture_output=True, text=True, timeout=60)
                self.assertEqual(exported.returncode, 0, exported.stdout + exported.stderr)
                self.assertEqual(tree_hashes(folder), before, "Re-export ignores mutated PNG import settings")
            self.pipeline.promote(candidate, receipt)
        # Fresh arena compilation must also accept the imported pinned TileSet.
        arena = template("post-import-arena", "v1", "arena", "manual")
        arena["arena"]["tileSet"] = {"assetId":"import-tileset", "revision":"v1"}
        arena["arena"]["tiles"] = [{"cell":[15,12], "atlas":[0,0], "alternative":0}]
        self.pipeline.compile(self.save_plan(arena), native=False)

    @unittest.skipUnless(os.environ.get("SPRITE_NATIVE_TESTS") == "1", "Set SPRITE_NATIVE_TESTS=1 for installed Godot integration")
    def test_native_godot_export_all_kinds_and_deterministic_rebuild(self):
        project = Path(__file__).resolve().parents[1]
        exporter = self.root / "scripts/assets/export_resources.gd"
        exporter.parent.mkdir(parents=True, exist_ok=True)
        exporter.write_text("# Existence marker; real exporter is invoked in the actual project")
        real_run = subprocess.run
        def export(command, **kwargs):
            actual_command = command[:]
            actual_command[actual_command.index("--path") + 1] = str(project)
            return real_run(actual_command, **kwargs)
        for kind in ("atlas", "animation", "tileset", "arena"):
            plan = template("native-" + kind, "v1", kind, "manual")
            # Regression: textual raw RGBA for large atlases exceeded 16 MiB.
            self.source.write_bytes(png((1254, 1254)) if kind == "atlas" else png())
            if kind == "animation":
                small = load_json(self.animation_plan())
                plan.update(canvas=small["canvas"], requiredFacings=small["requiredFacings"],
                            requiredActions=small["requiredActions"], keyposes=small["keyposes"], clips=small["clips"])
            elif kind == "tileset":
                plan["tileset"]["tileSize"] = [16, 16]
            path = self.save_plan(plan)
            for role in plan["keyposes"]:
                self.pipeline.ingest(path, self.source, role)
            if plan["keyposes"]:
                self.approve_keyposes(path)
            for role in {"atlas":["sprite"], "animation":["idle.n.0000"], "tileset":["texture"], "arena":[]}[kind]:
                self.pipeline.ingest(path, self.source, role)
            with patch("sprite_pipeline.pipeline.subprocess.run", side_effect=export):
                result = self.pipeline.compile(path)
            candidate = Path(result["candidate"])
            first = tree_hashes(candidate)
            candidate.rename(candidate.with_name("original-native"))
            with patch("sprite_pipeline.pipeline.subprocess.run", side_effect=export):
                self.pipeline.compile(path)
            self.assertEqual(tree_hashes(candidate), first, kind + " native export should be byte deterministic")
            self.assertTrue(result["nativeResources"])


if __name__ == "__main__":
    unittest.main()

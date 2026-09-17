"""Five-region source, layout, fixture, and review-evidence checks."""

from pathlib import Path
import json
import sys
import unittest

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from sprite_pipeline.common import digest, fingerprint, load_json, read_bytes, tree_hashes  # noqa: E402
from sprite_pipeline.pipeline import Pipeline  # noqa: E402
from sprite_pipeline.restricted_sources import DIGIMONUP_ORIGINAL_HASHES  # noqa: E402
from sprite_pipeline.validation import (  # noqa: E402
    PRESENTATION_PROFILE,
    validate_arena,
    validate_arena_environment_placements,
    validate_environment,
    validate_habitat,
    validate_plan,
)
from check_restricted_environment_distribution import check as distribution_errors  # noqa: E402


EXPECTED = {
    "green-shade": ("canopy-clearing", "rootbound-glade"),
    "shellfish-beach": ("tidepool-camp", "breaker-cove"),
    "toy-maze": ("wind-up-plaza", "clockwork-maze"),
    "mechatropolis": ("service-deck", "reactor-causeway"),
    "nephelis-abyss": ("cloudfall-sanctuary", "rift-platform"),
}


class FiveRegionContentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.index = load_json(ROOT / "tests/fixtures/regions/index.json")

    def test_inventory_hashes_all_fifteen_private_sources(self):
        inventory = load_json(ROOT / "assets-source/environments/SOURCE_INVENTORY.json")
        self.assertEqual(inventory["kind"], "environment-source-inventory")
        self.assertEqual(len(inventory["sources"]), 15)
        self.assertTrue(all(record["licenseClassification"] == "private-prototype-only"
                            and record["distributionStatus"] == "not-cleared"
                            for record in inventory["sources"]))
        self.assertTrue(all(record["sha256"] in DIGIMONUP_ORIGINAL_HASHES
                            for record in inventory["sources"]))
        self.assertFalse(any(Path(record["sourceRelativePath"]).is_absolute()
                             for record in inventory["sources"]))

    def test_three_third_layer_authority_hashes_are_original_not_derivative(self):
        expected = {
            "sha256:5a9c24f75e729743710ea2c39bf23a8c4c8bd2d3d2196004794da1983ffb054e",
            "sha256:7fabc01d3071c247fd9564775c450315f2dfb1709e611d5a1969a201deb8bf0f",
            "sha256:2d28b4768a817d9a762e20d4c5c5bd59597f12177ab37681937c2ab90373741d",
        }
        self.assertTrue(expected <= DIGIMONUP_ORIGINAL_HASHES)

    def test_index_has_five_stable_regions_aliases_and_contextual_encounters(self):
        self.assertEqual(self.index["status"], "pending-human-review")
        self.assertEqual(self.index["licenseClassification"], "private-prototype-only")
        self.assertEqual(set(self.index["regions"]), set(EXPECTED))
        self.assertEqual(self.index["aliases"], {"forest": "green-shade", "forest-arena": "green-shade"})
        expected_encounters = {f"encounter.{region}.{arena}" for region, (_, arena) in EXPECTED.items()}
        self.assertEqual(set(self.index["encounters"]), expected_encounters)
        signed = {
            "revision": self.index["revision"],
            "licenseClassification": self.index["licenseClassification"],
            "regions": self.index["regions"],
            "encounters": self.index["encounters"],
        }
        self.assertEqual(self.index["aggregateFingerprint"], fingerprint(signed))

    def test_environment_plans_and_raw_dev_packages_are_reproducible(self):
        pipeline = Pipeline(ROOT)
        for region, (home, arena) in EXPECTED.items():
            with self.subTest(region=region):
                record = self.index["regions"][region]
                plan_path = ROOT / "assets-source/environments" / region / self.index["revision"] / "source-plan.json"
                plan, _sources = pipeline.plan(plan_path)
                self.assertEqual(plan["assetId"], "environment-" + region)
                self.assertEqual(plan["environment"]["presentationProfile"], PRESENTATION_PROFILE)
                self.assertEqual(plan["environment"]["license"]["classification"], "private-prototype-only")
                fixture = ROOT / record["environment"]["path"]
                metadata = load_json(fixture / "candidate.json")
                manifest = load_json(fixture / "environment.json")
                self.assertTrue(metadata["devFixture"])
                self.assertTrue(metadata["nativeResources"])
                self.assertLess((fixture / "environment.tres").stat().st_size, 2 * 1024 * 1024)
                self.assertEqual(metadata["nativeDependencies"], {
                    relative: digest(read_bytes(fixture / relative))
                    for relative in sorted(manifest["textures"].values())
                })
                self.assertEqual(tree_hashes(fixture), metadata["files"])
                expected_hash = fingerprint({key: value for key, value in metadata.items()
                                             if key not in ("sourcePlan", "contentSha256")})
                self.assertEqual(metadata["contentSha256"], expected_hash)
                self.assertEqual(record["environment"]["contentSha256"], expected_hash)
                self.assertEqual(manifest["presentationProfile"], PRESENTATION_PROFILE)
                self.assertEqual(manifest["camera"]["movementBounds"], [0, 0, 1280, 1536])
                self.assertEqual(manifest["camera"]["dollyBounds"], [2, 60])
                self.assertEqual(validate_environment(manifest, set(manifest["textures"]),
                                                      allow_compiled_bindings=True)["planeStacks"], 1)
                self.assertGreaterEqual(len(manifest["planeStacks"][0]["planes"]), 3)
                self.assertTrue(all(plane["rotationDegrees"][1] == 0 for plane in manifest["spritePlanes"]))
                self.assertTrue(all(plane["depthBehavior"] == "write" for plane in manifest["spritePlanes"]))
                self.assertTrue(all(plane["depthBehavior"] == "prepass" and
                                    isinstance(plane["renderPriority"], int)
                                    for plane in manifest["ambientPlanes"]))
                self.assertTrue(all(plane.get("edgePolicy") in
                                    ("camera-safe-rear-band", "natural-alpha-silhouette")
                                    for plane in manifest["ambientPlanes"]))
                self.assertNotIn("placeholder", manifest.get("developmentStatus", "").lower())
                self.assertTrue(all("placeholder" not in plane.get("authoringStatus", "").lower()
                                    for plane in manifest["spritePlanes"]))
                if region != "green-shade":
                    self.assertEqual(set(plan["derivedImages"]),
                                     {"feature_facade", "feature_interior", "feature_roof"})
                    self.assertEqual({item["recipe"]["parameters"]["profile"]
                                      for item in plan["derivedImages"].values()},
                                     {"source-component-depth-cards-v1"})
                    self.assertEqual(len({plan["sources"][plane["source"]]["sha256"]
                                          for plane in plan["environment"]["spritePlanes"]}), 3)
                self.assertEqual(record["homeId"], home)
                self.assertEqual(record["arenaId"], arena)

    def test_habitats_are_connected_40_by_48_and_persist_static_props(self):
        for region, (home, _arena) in EXPECTED.items():
            with self.subTest(region=region):
                record = self.index["regions"][region]
                environment = load_json(ROOT / record["environment"]["path"] / "environment.json")
                habitat = load_json(ROOT / record["habitat"]["path"])
                self.assertEqual(habitat["assetId"], "habitat-" + home)
                self.assertEqual(habitat["grid"], {"columns": 40, "rows": 48, "cellSize": 32})
                result = validate_habitat(habitat, environment)
                self.assertEqual(result["freeCells"], result["reachableCells"])
                self.assertEqual(result["wasteAnchors"], 3)
                self.assertTrue(all(placement.get("persistent") is True
                                    for placement in habitat["staticPlacements"]))
                self.assertEqual(habitat["environment"], {
                    "assetId": record["environment"]["assetId"],
                    "revision": record["environment"]["revision"],
                    "contentSha256": record["environment"]["contentSha256"],
                })

    def test_arenas_are_connected_30_by_36_and_geometry_matches_art(self):
        for region, (_home, arena_id) in EXPECTED.items():
            with self.subTest(region=region):
                record = self.index["regions"][region]
                environment = load_json(ROOT / record["environment"]["path"] / "environment.json")
                arena = load_json(ROOT / record["arena"]["path"])
                self.assertEqual(arena["assetId"], "arena-" + arena_id)
                self.assertEqual(arena["ground"], {"width": 960, "height": 1152, "cellSize": 32})
                result = validate_arena(arena)
                self.assertEqual(result["bodyClearCells"], result["reachableCells"])
                self.assertGreaterEqual(result["evasionPatches"], 4)
                validate_arena_environment_placements(arena, environment)
                self.assertTrue(all(placement["rotationDegrees"] == 0
                                    for placement in arena["presentation"]["staticPlacements"]))
                self.assertEqual(arena["environment"]["contentSha256"],
                                 record["environment"]["contentSha256"])

    def test_review_packages_are_isolated_hash_bound_and_unapproved(self):
        catalog_path = ROOT / "assets/runtime-catalog.json"
        catalog_assets = load_json(catalog_path).get("assets", {}) if catalog_path.is_file() else {}
        for region, record in self.index["regions"].items():
            with self.subTest(region=region):
                self.assertNotIn(record["environment"]["assetId"], catalog_assets)
                for kind in ("habitat", "arena"):
                    package = ROOT / record[kind]["reviewPackage"]
                    metadata = load_json(package / "candidate.json")
                    self.assertTrue(metadata["devFixture"])
                    self.assertEqual(metadata["environmentPackage"], "environment")
                    self.assertEqual(metadata["environmentContentSha256"],
                                     record["environment"]["contentSha256"])
                    self.assertEqual(tree_hashes(package), metadata["files"])
                    self.assertEqual(load_json(package / (kind + "-review.json"))["status"],
                                     "pending-human-review")
                    self.assertFalse(list(package.glob("*.final-review.json")))

    def test_hash_bound_native_capture_matrix_and_benchmarks(self):
        for region, record in self.index["regions"].items():
            with self.subTest(region=region):
                capture = record["review"]["captures"]
                self.assertEqual(capture["status"], "captured-pending-human-review")
                evidence_path = ROOT / "tests/fixtures/regions" / region / "review/evidence.json"
                evidence = load_json(evidence_path)
                self.assertEqual(capture["evidenceSha256"], digest(read_bytes(evidence_path)))
                self.assertEqual(evidence["environmentContentSha256"], record["environment"]["contentSha256"])
                self.assertEqual(evidence["reviewerBuildSha256"], capture["reviewerBuildSha256"])
                self.assertEqual(evidence["presentationProfile"], PRESENTATION_PROFILE)
                self.assertIn("region_environment_capture_runner.gd", evidence["renderCommand"])
                self.assertEqual(set(evidence["targets"]), {"360x640", "390x844", "430x932"})
                for size_key, expected_size in {"360x640": (360, 640), "390x844": (390, 844),
                                                "430x932": (430, 932)}.items():
                    target = evidence["targets"][size_key]
                    folder = ROOT / "tests/fixtures/regions" / region / "review" / size_key
                    self.assertEqual(set(target["viewpoints"]), {"center", "left", "right", "near", "far"})
                    self.assertEqual(set(target["shimmerSweep"]), {"000", "025", "050", "075", "100"})
                    self.assertEqual(target["shimmerAnalysis"]["sampleCount"], 5)
                    images = {}
                    for name, image_record in target["viewpoints"].items():
                        image = Image.open(folder / image_record["file"]).convert("RGB")
                        self.assertEqual(image.size, expected_size)
                        self.assertIsNotNone(image.getbbox())
                        self.assertTrue(image_record["actorBounds"]["behind"]["fullyVisible"])
                        self.assertTrue(image_record["actorBounds"]["front"]["fullyVisible"])
                        images[name] = image
                    self.assertIsNotNone(ImageChops.difference(images["left"], images["right"]).getbbox())
                    self.assertIsNotNone(ImageChops.difference(images["near"], images["far"]).getbbox())
                    self.assertEqual(set(target["samples"]),
                                     {"behindActor", "frontActor", "opaqueVfx", "translucentVfx"})
                    performance = target["performance"]
                    self.assertGreaterEqual(performance["sampleFrames"], 120)
                    self.assertNotEqual(performance["displayServer"], "headless")
                    self.assertGreaterEqual(performance["averageFrameMs"], 0)
                    self.assertGreaterEqual(performance["maximumFrameMs"], performance["averageFrameMs"])
                    self.assertGreater(performance["maximumDrawCalls"], 0)
                    self.assertGreater(performance["maximumTextureMemoryBytes"], 0)
                qa = load_json(ROOT / "tests/fixtures/regions" / region / "review/automated-qa.json")
                expected_status = "fail" if region == "nephelis-abyss" else "pass"
                self.assertEqual(qa["automatedStatus"], expected_status)
                if expected_status == "pass":
                    self.assertTrue(all(qa["checks"].values()))
                else:
                    self.assertFalse(qa["checks"]["noOpaqueCardBoundary"])
                    self.assertTrue(qa["artBlockers"])
                self.assertEqual(qa["humanReviewStatus"], "pending-human-review")
                self.assertEqual(qa["environmentContentSha256"], record["environment"]["contentSha256"])
                self.assertEqual(qa["reviewerBuildSha256"], evidence["reviewerBuildSha256"])

    def test_private_prototype_distribution_guard(self):
        self.assertEqual(distribution_errors(), [])


if __name__ == "__main__":
    unittest.main()

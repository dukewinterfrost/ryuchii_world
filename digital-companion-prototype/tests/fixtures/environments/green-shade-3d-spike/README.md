# Green Shade 3D spike fixture

This folder is a deterministic, non-promoted test/development fixture emitted
directly by `Pipeline.compile_environment()` from
`assets-source/environments/green-shade/spike/source-plan.json`. Calling the
environment emitter directly keeps the technical spike runnable without
inventing a keypose approval receipt or bypassing the production promotion
gate. It is not an approved asset candidate and must never be copied into the
promoted catalog.

Rebuild and verify the fixture without creating an approval receipt:

```sh
.venv-sprites/bin/python assets-source/environments/green-shade/spike/build-dev-fixture.py
.venv-sprites/bin/python assets-source/environments/green-shade/spike/build-dev-fixture.py --check
```

`fixture.json` binds the source-plan bytes, compiler version, source hashes,
every runtime payload, aggregate content hash, and complete fixture fingerprint.

The single `terrain.green-shade-ground.png` payload is an exact bounded crop of
the walkable cobblestone area in the immutable Green Shade Ground source. It is
applied to one subdivided horizontal mesh, so there is no internal terrain-card
seam. The vertical cliff remains in `ground.png` and is used only by the upright
rear-cliff card. The `tree_*` payloads are deterministic `256x256`
target-density reductions. Their padded masks form a closed lobed canopy, a
trunk/interior card, and a curved facade/root card with broad natural overlap;
the plan binds their parent, script, recipe, and outputs by SHA-256.

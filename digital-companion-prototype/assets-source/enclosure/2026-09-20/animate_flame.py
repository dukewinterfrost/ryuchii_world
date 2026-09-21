"""Small fire-only loop; static base is never sent for animation."""
import importlib.util,json
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
p=ROOT/'design-workshop/animation-review/2026-09-13-v1/animate.py'
s=importlib.util.spec_from_file_location('existing_pipeline',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);m.credentials()
job={'id':'flame-loop','operation':'animate-with-text-v3','firstFrame':'flame','lastFrame':'flame','frameCount':4,'seed':920200,'description':'A tiny seamless four-frame campfire flame flicker loop. Only the upper yellow-orange flame tongues gently bend and rise. Keep the bottom of the fire anchored in exactly the same place. Fixed camera, no movement across canvas, no logs, smoke, sparks or new objects. Preserve this pixel-art palette and outline. End at the starting flame shape.'}
(HERE/'flame-loop-prompt.json').write_text(json.dumps(job,indent=2))
op,payload,size=m.pixellab.prepare({'canvas':[64,64]},job,{'flame':HERE/'jobs/flame/frame-0000.png'})
d=HERE/'jobs/flame-loop';exists=(d/'generation.json').exists()
r=m.pixellab.run_job(HERE,d,{'assetId':'flame','revision':'2026-09-20','job':'flame-loop'},op,payload,size,execute=not exists,allow_billable=True,resume=exists)
print(json.dumps(r))

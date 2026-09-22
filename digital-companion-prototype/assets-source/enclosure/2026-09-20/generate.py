"""Authorized enclosure stills. Durable jobs; reruns only GET accepted jobs."""
import importlib.util, json, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]
p=ROOT/'design-workshop/animation-review/2026-09-13-v1/animate.py'
s=importlib.util.spec_from_file_location('existing_pipeline',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
HERE=Path(__file__).resolve().parent
STYLE='Original cozy monster-raising woodland builder game prop, crisp native pixel art, restrained warm earthy palette, dark colored outlines, readable chunky forms, elevated front three-quarter view showing the top and front, orthographic camera, centered isolated complete object with transparent background, no text, no characters, no ground tile, no cast shadow outside object. '
JOBS={
'digi_potty':('A small inviting mint-green ceramic training potty with a low wooden privacy back, rounded bowl, wooden step in front and tiny leaf motif. Two by two tile footprint. Front access must read clearly.',[128,128]),
'campfire':('An unlit cooking campfire base: low ring of chunky gray stones surrounding crossed brown logs and dark embers, a short wooden cooking spit with an empty horizontal bar. NO flames, NO smoke, NO glow. Two by two tile footprint; keep central flame area clear. Static reusable base.',[128,128]),
'pond':('A shallow small oval turquoise bathing pond bordered by smooth rounded stones and a few reeds, clear shallow entry at the front, calm cool water with sparse highlights. Four by three tile footprint. Low profile with entire water surface visible.',[160,128]),
'flame':('One small compact yellow-orange campfire flame with red base, three pointed tongues, NO logs, NO stones, NO smoke, NO stand. A detached fire overlay, centered, anchored at bottom center with generous transparent margins.',[64,64])}
m.credentials()
key=sys.argv[1]
prompt,size=JOBS[key]
job={'id':key,'description':STYLE+prompt,'imageSize':size,'seed':920100+list(JOBS).index(key),'noBackground':True}
(HERE/(key+'-prompt.json')).write_text(json.dumps(job,indent=2))
op,payload,size=m.pixellab.prepare({'canvas':size},job,{})
d=HERE/'jobs'/key
receipt=d/'generation.json'
result=m.pixellab.run_job(HERE,d,{'assetId':key,'revision':'2026-09-20','job':key},op,payload,size,execute=not receipt.exists(),allow_billable=True,resume=receipt.exists())
print(json.dumps(result))

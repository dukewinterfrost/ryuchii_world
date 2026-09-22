"""Deterministic source-sheet extraction; original art is never overwritten.

The selected slime rows exclude every grab/walk pose with leg-like appendages.
Source strips are a visibly documented fallback, not claimed PixelLab output.
"""
from pathlib import Path
import json, hashlib, colorsys
from collections import deque, Counter
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets-source/mobs/2026-09-21'
REVISION = 'source-2026-09-21'

def digest(path): return 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()

def crop_sprite(sheet, box, palette='base'):
    crop = sheet.crop(box).convert('RGBA')
    width,height=crop.size
    # Remove the source sheet's flat cell matte only when connected to an edge.
    bg=Counter(crop.convert("RGB").getdata()).most_common(1)[0][0]
    queue=deque([(x,0) for x in range(width)]+[(x,height-1) for x in range(width)]+[(0,y) for y in range(height)]+[(width-1,y) for y in range(height)])
    seen=set()
    while queue:
        x,y=queue.popleft()
        if not (0<=x<width and 0<=y<height) or (x,y) in seen: continue
        seen.add((x,y));r,g,b,a=crop.getpixel((x,y))
        if max(abs(r-bg[0]),abs(g-bg[1]),abs(b-bg[2])) > 42: continue
        crop.putpixel((x,y),(0,0,0,0));queue.extend([(x-1,y),(x+1,y),(x,y-1),(x,y+1)])
    # Cell dividers and neighbouring matte fragments are separate from the
    # creature. Keep the largest 8-connected foreground component.
    remaining={(x,y) for y in range(height) for x in range(width) if crop.getpixel((x,y))[3]}
    components=[]
    while remaining:
        component=set(); queue=deque([remaining.pop()])
        while queue:
            point=queue.popleft();component.add(point)
            for dx in (-1,0,1):
                for dy in (-1,0,1):
                    neighbour=(point[0]+dx,point[1]+dy)
                    if neighbour in remaining:remaining.remove(neighbour);queue.append(neighbour)
        components.append(component)
    keep=max(components,key=len) if components else set()
    for y in range(height):
        for x in range(width):
            if (x,y) not in keep:crop.putpixel((x,y),(0,0,0,0))
    if palette!='base':
        for y in range(height):
            for x in range(width):
                r,g,b,a=crop.getpixel((x,y))
                if not a: continue
                h,s,v=colorsys.rgb_to_hsv(r/255,g/255,b/255)
                if .32<h<.62 and s>.18:
                    h,s=(.64,s) if palette=='blue' else (.78,s) if palette=='purple' else (0,0)
                    r,g,b=(round(c*255) for c in colorsys.hsv_to_rgb(h,s,v))
                    crop.putpixel((x,y),(r,g,b,a))
    canvas=Image.new('RGBA',(128,128))
    # Stable cell registration across the whole clip; no per-frame recentering.
    crop=crop.resize((width*2,height*2),Image.Resampling.NEAREST)
    canvas.alpha_composite(crop,((128-width*2)//2,120-height*2))
    return canvas

def row(y,count=8,x=3):
    start=round((x-3)/50)
    return [(round((start+i)*50.4)+3,y,round((start+i)*50.4)+48,y+44) for i in range(count)]

def build():
    SOURCE.mkdir(parents=True,exist_ok=True)
    inputs=SOURCE/'inputs';inputs.mkdir(exist_ok=True)
    configs=[('slime_basic','slime','base'),('slime_metal','slime','metal'),('slime_spitter','slime','blue'),('fairy_healer','fairy','base'),('fairy_striker','fairy','purple')]
    provenance={'fileKey':'syQM2pShfeCTfXms0HmzTB','sources':{},'variants':{},'slimeAnatomy':'legless; grab rows excluded','generatedMotionApproval':'pending'}
    preview=Image.new('RGB',(640,256),'#23342f');draw=ImageDraw.Draw(preview)
    for vi,(species,family,palette) in enumerate(configs):
        path=SOURCE/'sources'/f'{family}-original.png';sheet=Image.open(path)
        provenance['sources'][family]={'nodeId':'161:541' if family=='slime' else '167:544','sha256':digest(path)}
        clips={
            'idle':row(144,8),
            'move':row(254,8) if family=='slime' else row(144,8,505),
            'basic_attack':row(660,7),
            'special_attack':row(719,6),
            'guard':row(254,3,605),
            'evade':row(254,8),
            'hit':row(312,6,505),
            'defeat':row(998,9),
        }
        target=ROOT/'assets/companions'/species;target.mkdir(parents=True,exist_ok=True)
        frames={};manifest={};images=[]
        for action,boxes in clips.items():
            entries=[]
            for index,box in enumerate(boxes):
                sprite=crop_sprite(sheet,box,palette)
                key=f'{species}.{action}.{index}'
                i=len(images);images.append(sprite)
                frames[key]={'frame':{'x':(i%8)*128,'y':(i//8)*128,'w':128,'h':128},'rotated':False}
                entries.append({'atlasFrame':key,'durationMs':160 if action=='idle' else 100,'pivot':{'x':.5,'y':.9375},'anchors':{'root':{'x':.5,'y':.9375}}})
                if index==0:
                    sprite.save(inputs/f'{species}-{action}.png')
                    if action=='idle':preview.paste(sprite,(vi*128,25),sprite)
            manifest[action+'.default']={'semanticAction':action,'kind':'loop' if action in ['idle','move','guard'] else 'one-shot','frames':entries}
        atlas=Image.new('RGBA',(1024,((len(images)+7)//8)*128))
        for i,sprite in enumerate(images):atlas.alpha_composite(sprite,((i%8)*128,(i//8)*128))
        atlas.save(target/'atlas.png')
        (target/'atlas.json').write_text(json.dumps({'frames':frames,'meta':{'image':'atlas.png','size':{'w':atlas.width,'h':atlas.height}}},indent=2))
        (target/'animation-set.json').write_text(json.dumps({'schemaVersion':1,'subjectId':species,'assetId':species,'revision':REVISION,'status':'source-derived-fallback','provenance':{'kind':'source-derived','referenceHashes':[digest(path)],'note':'Original Figma sheet poses; PixelLab replacements await motion review.'},'motionProfile':{'morphology':'legless' if family=='slime' else 'winged','locomotion':'hopping' if family=='slime' else 'flying','rootPolicy':'in-place','facing':'right'},'fallbacks':{},'clips':manifest},indent=2))
        provenance['variants'][species]={'palette':palette,'clips':clips,'atlasSha256':digest(target/'atlas.png')}
        draw.text((vi*128+5,5),species,fill='white')
    preview.save(SOURCE/'source-preview.png')
    (SOURCE/'source-manifest.json').write_text(json.dumps(provenance,indent=2))

if __name__=='__main__':build()

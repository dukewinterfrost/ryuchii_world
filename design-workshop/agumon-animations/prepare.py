from pathlib import Path
from PIL import Image
import json, hashlib
OUT=Path(__file__).parent.resolve()
WEB=Path('/Users/johncohrn/Documents/ChatGPT/Tomagachi Web App')
UP=Path('/Users/johncohrn/Documents/Digimon/Digimon Up Assets/Texture2D')
clips=[]
def saveclip(key,title,frames,durations,group,source,status,notes,events=None):
    frames=[f.convert('RGBA') for f in frames]
    size=max(max(f.size) for f in frames)
    norm=[]
    for f in frames:
        canvas=Image.new('RGBA',(size,size));canvas.alpha_composite(f,((size-f.width)//2,size-f.height));norm.append(canvas)
    strip=Image.new('RGBA',(size*len(norm),size))
    for i,f in enumerate(norm): strip.alpha_composite(f,(size*i,0))
    sp=OUT/(key+'-strip.png'); strip.save(sp)
    gif=[]
    for f in norm:
        bg=Image.new('RGBA',f.size,'#F5EFE2');bg.alpha_composite(f)
        gif.append(bg.convert('RGB').resize((256,256),Image.Resampling.NEAREST))
    gif_durations=[];elapsed=0;previous=0
    for d in durations:
        elapsed+=d;rounded=round(elapsed/10)*10;gif_durations.append(rounded-previous);previous=rounded
    gp=OUT/(key+'-preview.gif');gif[0].save(gp,save_all=True,append_images=gif[1:],duration=gif_durations,loop=0,disposal=2,optimize=False)
    clips.append(dict(key=key,title=title,n=len(frames),cell=size,durations=durations,totalMs=sum(durations),group=group,source=str(source),status=status,notes=notes,events=events or [],strip=str(sp),gif=str(gp),hashes=[hashlib.sha256(f.tobytes()).hexdigest() for f in norm]))

def manifest(folder,group,prefix,names,status,notes):
    d=json.loads((folder/'animation-set.json').read_text()); a=json.loads((folder/'atlas.json').read_text());im=Image.open(folder/'atlas.png')
    for k,c in d['clips'].items():
        ims=[]
        for f in c['frames']:
            entry=a['frames'][f['atlasFrame']];r=entry['frame'];crop=im.crop((r['x'],r['y'],r['x']+r['w'],r['y']+r['h'])).convert('RGBA')
            original=Image.new('RGBA',(entry['sourceSize']['w'],entry['sourceSize']['h']));original.alpha_composite(crop,(entry['spriteSourceSize']['x'],entry['spriteSourceSize']['y']));ims.append(original)
        saveclip(prefix+k.split('.')[0],names[k],ims,[f['durationMs'] for f in c['frames']],group,folder,status,notes[k],c.get('events'))
latest=WEB/'assets-source/companions/agumon/mvp/2026-08-27.001'
manifest(latest,'current','current-',{'idle.default':'Idle','move.default':'Walk','eat.default':'Eat','pepper-breath.default':'Pepper Breath'},'CANDIDATE · 27 AUG 2026',{
'idle.default':'Also present in Godot revision 26 Aug. Loops in place.',
'move.default':'Also present in Godot revision 26 Aug. Host controls travel across the field.',
'eat.default':'Also present in Godot revision 26 Aug. Same frames as the cleanup draft; art review remains open.',
'pepper-breath.default':'Newest attack candidate; not present in the current Godot atlas. Character pose sequence; projectile source is in column 3.'})
manifest(WEB/'public/assets/promoted/digital-companion/agumon/animation-set/2026-08-21.001','archive','early-',{'idle.default':'Earlier idle','eat.default':'Earlier eat'},'EARLIER SET · 21 AUG 2026',{'idle.default':'Earlier generated identity treatment; retained for comparison.','eat.default':'Earlier eight-frame eating treatment; retained for comparison.'})
p=WEB/'work/animation-generation/agumon/eat/2026-08-25.002/pixellab-v3'
ap=Image.open(p/'animation.apng');ds=[]
for i in range(ap.n_frames): ap.seek(i);ds.append(int(ap.info.get('duration',100)))
fs=[Image.open(f) for f in sorted(p.glob('frame-*.png'))]
if len(ds)!=len(fs): raise ValueError((ds,len(fs)))
saveclip('pixellab-eat','PixelLab eating experiment',fs,ds,'archive',p,'RAW EXPERIMENT · 25 AUG 2026','Source metadata marks this candidate invalid. Motion comparison only; cleanup version appears as Eat in column 1.')
legacy=Image.open(WEB/'public/assets/companions/agumon.png')
for name,seq,ms in [('idle',[6,7,6,7],400),('roam',[6,7,6,7],1000/6),('happy',[7,6,7,6],1000/7)]:
    fs=[legacy.crop(((i%4)*96,(i//4)*96,(i%4+1)*96,(i//4+1)*96)) for i in seq]
    saveclip('legacy-'+name,'Legacy '+name.title(),fs,[round(ms)]*4,'legacy',WEB/'public/assets/companions/agumon.png','ORIGINAL WEB FALLBACK',f'Runtime order {seq}. '+('Plays twice per happy reaction.' if name=='happy' else 'Looping two-pose animation.')+' Timing comes from HabitatScene.tsx; GIF preview rounds to 10 ms.')
p=UP/'Fx_Agumon_Attack_Projectile.png';im=Image.open(p)
fs=[im.crop(((i%3)*80,(i//3)*80,(i%3+1)*80,(i//3+1)*80)) for i in range(9)]
saveclip('projectile','Pepper Breath projectile',fs,[80]*9,'source',p,'DIGIMON UP · 9-FRAME EFFECT','Frame order and 80 ms timing come from the 27 Aug source plan. Review preview loops this effect independently.')
raw=[]
for fn,title,note in [
('Agumon.png','Agumon · original atlas','Packed poses and effects. Original frame boundaries and animation timing were not included in the downloaded texture.'),
('Agumon_Adventure.png','Agumon Adventure · alternate atlas','Alternate packed pose/effect set. Preserve as source reference; no inferred clip order.'),
('Eat_Agumon.png','Eating · parts atlas','Mouths, food, body parts and props for assembly. This is a parts texture, not a timed animation strip.'),
('Fx_Agumon_Attack_Projectile_Hit.png','Pepper Breath · impact texture','Downloaded impact effect sheet. Original timing was not found.'),
]:
    p=UP/fn; im=Image.open(p)
    raw.append(dict(key='source-'+p.stem,title=title,path=str(p),width=im.width,height=im.height,notes=note))
# Earlier still studies, preserved as studies rather than invented animation sequences.
for rel,title,key in [('work/animation-generation/agumon/eat/2026-08-23.001/key-pose-contact-sheet.png','Eating · key pose study','keyposes'),('work/animation-generation/agumon/eat/2026-08-24.001/pixellab/bite-contact/contact-sheet-x1.png','Bite contact · four candidates','bite-candidates')]:
    p=WEB/rel;im=Image.open(p);raw.append(dict(key=key,title=title,path=str(p),width=im.width,height=im.height,notes='Earlier still-pose experiment. No animation timing is assigned.'))
(OUT/'inventory.json').write_text(json.dumps(dict(clips=clips,raw=raw),indent=2))
print(json.dumps({'clips':[(c['key'],c['n'],c['totalMs']) for c in clips],'raw':[(r['key'],r['width'],r['height']) for r in raw]},indent=2))

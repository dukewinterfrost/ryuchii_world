"""Lossless sheet packing; never repaints generated pixels."""
import hashlib,json
from pathlib import Path
from PIL import Image,ImageDraw
H=Path(__file__).resolve().parent
out=H/'review';out.mkdir(exist_ok=True)
for kind in ['digi_potty','campfire','pond','flame']:
 files=sorted((H/'jobs'/kind).glob('frame-*.png'))
 sheet=Image.new('RGBA',(4*180,((len(files)+3)//4)*170),(29,48,40,255));d=ImageDraw.Draw(sheet)
 for i,p in enumerate(files):
  im=Image.open(p).convert('RGBA');x=(i%4)*180;y=(i//4)*170
  sheet.alpha_composite(im,(x+(180-im.width)//2,y+20));d.text((x+12,y+150),f'{kind} / variant {i+1}',fill='white')
 sheet.save(out/(kind+'-variants.png'))
frames=[Image.open(H/'jobs/flame-loop'/f'frame-{i:04d}.png').convert('RGBA') for i in range(4)]
sheet=Image.new('RGBA',(256,64));
for i,im in enumerate(frames):sheet.paste(im,(i*64,0))
sheet.save(out/'flame-loop.png')
sheet.save(H.parents[2]/'assets/enclosure/flame-loop.png')
frames[0].save(out/'flame-loop.gif',save_all=True,append_images=frames[1:],duration=125,loop=0,disposal=2)
record={'provider':'PixelLab','sourceDate':'2026-09-20','figmaFile':'syQM2pShfeCTfXms0HmzTB','figmaPage':'156:150','selectedStills':{},'flame':{'requestedFrames':4,'returnedFrames':5,'selectedFrames':[0,1,2,3],'omittedFrame':4,'reason':'Frame 4 is byte-identical to frame 0, the supplied loop endpoint.','fps':8,'canvas':[64,64],'atlas':[256,64]},'status':'Agent visually inspected prototype art; not a user final-art approval.'}
for kind in ['digi_potty','campfire','pond','flame']:
 p=H/'jobs'/kind/'frame-0000.png';record['selectedStills'][kind]={'source':str(p.relative_to(H)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
(H/'delivery.json').write_text(json.dumps(record,indent=2))

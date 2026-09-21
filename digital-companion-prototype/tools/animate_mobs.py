"""Resumable PixelLab jobs for the source-sheet mob batch. No automatic purchases."""
from pathlib import Path
import argparse,base64,json,os,shlex,stat,sys,subprocess,tempfile
from sprite_pipeline import pixellab
from sprite_pipeline.common import digest,write_json

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets-source/mobs/2026-09-21'
ACTIONS={
 'idle':'A subtle breathing squash and stretch in place, returning to the original pose.',
 'move':'One small body hop forward in place and land, squashing on landing; return to the initial pose.',
 'basic_attack':'Anticipate by compressing the body, lunge the entire body to the right to bump, then recover to neutral.',
 'special_attack':'Compress, lean right and open the mouth to cast a ranged attack; return to neutral. No projectile or detached effects.',
 'guard':'Compress into a sturdy rounded defensive pose, briefly hold, then relax.',
 'evade':'A quick small sideways body slide in place, then settle back at the original root.',
 'hit':'One brief recoil backwards from a hit, then recover without changing anatomy.',
 'defeat':'Slowly collapse into a low motionless puddle. Finish collapsed; do not stand up.',
}

def transport(method,route,payload=None):
 # Use curl with normal TLS verification enabled and
 # disallow redirects. Bearer credentials travel through stdin, never argv.
 if not route.startswith('/') or '\n' in route:raise ValueError('Invalid API route')
 token=os.environ.get('PIXELLAB_API_TOKEN') or os.environ['PIXELLAB_API_KEY']
 options='header = '+json.dumps('Authorization: Bearer '+token)+'\nheader = "Content-Type: application/json"\n'
 args=['curl','--silent','--show-error','--max-time','45','--config','-','--request',method,'--write-out','\n%{http_code}','https://api.pixellab.ai/v2'+route]
 temporary=None
 try:
  if payload is not None:
   with tempfile.NamedTemporaryFile(mode='w',delete=False) as f:json.dump(payload,f);temporary=f.name
   args.extend(['--data-binary','@'+temporary])
  result=subprocess.run(args,input=options,capture_output=True,text=True)
  if result.returncode:raise RuntimeError('PixelLab transport failed; resume recorded job before any new submission')
  body,code=result.stdout.rsplit('\n',1)
  if code!='200':raise RuntimeError('PixelLab HTTP '+code+'; no automatic resubmission')
  return json.loads(body)
 finally:
  if temporary:Path(temporary).unlink(missing_ok=True)

def credentials():
 if os.environ.get('PIXELLAB_API_TOKEN') or os.environ.get('PIXELLAB_API_KEY'):return
 p=Path(os.environ.get('PIXELLAB_CREDENTIAL_FILE',str(ROOT.parent.parent/'Tomagachi Web App/.env.pixellab.local')))
 info=p.lstat()
 if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode)!=0o600:raise RuntimeError('Credential file must be regular and mode 0600')
 for line in p.read_text().splitlines():
  k,sep,v=line.removeprefix('export ').partition('=')
  if sep and k.strip() in ['PIXELLAB_API_TOKEN','PIXELLAB_API_KEY']:
   words=shlex.split(v,comments=True)
   if len(words)==1:os.environ[k.strip()]=words[0]

def run(species,action):
 directory=SOURCE/'jobs'/f'{species}-{action}'
 source=directory/'source.png' if (directory/'source.png').exists() else SOURCE/'inputs'/f'{species}-idle.png'
 image={'type':'base64','base64':base64.b64encode(source.read_bytes()).decode(),'format':'png'}
 if species.startswith('slime'):
  anatomy='One single legless gelatinous slime body. NO legs, NO feet, NO toes, NO shoes, NO arms, NO hands, NO walking limbs at any frame. Keep its simple rounded silhouette, eyes, mouth and original palette.'
  motion=ACTIONS[action]
 else:
  anatomy='One small winged fairy, preserving her face, dress, hair, two arms, two legs and two wings exactly. She hovers in place.'
  motion={ 'move':'Flutter the wings and hover forward in place, returning to the starting root.', 'basic_attack':'Wind up and strike right with one arm, then recover.', 'special_attack':'Raise both hands to cast a support spell, then lower them. No detached effects or symbols.', 'defeat':'Droop the wings and descend into a defeated resting pose, remaining still.'}.get(action,ACTIONS[action])
 prompt=f'{anatomy} {motion} Fixed camera, fixed scale, transparent background, no text, no emote symbols, crisp pixel art. Keep the original root registration.'
 payload={'first_frame':image,'action':prompt,'frame_count':8,'seed':92126,'no_background':True,'drift_threshold':0,'enhance_prompt':False}
 if action in ['idle','move','guard']:payload['last_frame']=image
 directory=SOURCE/'jobs'/f'{species}-{action}'
 directory.mkdir(parents=True,exist_ok=True)
 if not (directory/'prompt.json').exists():write_json(SOURCE,directory/'prompt.json',{'species':species,'action':action,'prompt':prompt,'sourceSha256':digest(source.read_bytes()),'motionApproval':'pending'},replace=True)
 receipt=directory/'generation.json'
 result=pixellab.run_job(SOURCE,directory,{'species':species,'action':action},'animate-with-text-v3',payload,[128,128],execute=not receipt.exists(),allow_billable=True,resume=receipt.exists(),transport=transport)
 print(json.dumps({'job':directory.name,'status':result['status'],'jobId':result.get('jobId'),'frames':result.get('actualFrameCount')}),flush=True)

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('species',choices=['slime_basic','slime_metal','slime_spitter','fairy_healer','fairy_striker']);p.add_argument('action',choices=list(ACTIONS));a=p.parse_args()
 credentials();run(a.species,a.action)

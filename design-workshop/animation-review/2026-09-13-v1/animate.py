"""Figma-approved sprite animation run; reuse the project PixelLab adapter."""
from pathlib import Path
import argparse, base64, hashlib, io, json, os, shlex, stat, sys, concurrent.futures
from datetime import datetime, timezone

HERE = Path(__file__).resolve().parent
WORKSPACE = HERE.parents[2]
PROJECT = WORKSPACE / 'digital-companion-prototype'
sys.path.insert(0, str(PROJECT / 'tools'))
from sprite_pipeline import pixellab
from sprite_pipeline.common import PipelineError, canonical, digest, fingerprint, write_json, write_bytes
from PIL import Image

KEYFRAMES = WORKSPACE / 'design-workshop/keyframe-review/2026-09-12-v1'

def image_payload(path):
    return {'type': 'base64', 'base64': base64.b64encode(path.read_bytes()).decode(), 'format': 'png'}

def sync_image(step, route, payload):
    receipt = step.with_suffix('.json')
    output = step.with_suffix('.png')
    request_hash = fingerprint(payload)
    if receipt.exists():
        state = json.loads(receipt.read_text())
        if state.get('requestSha256') != request_hash:
            raise PipelineError('Prepared input changed: ' + str(step))
        if state.get('status') != 'completed':
            raise PipelineError('Uncertain existing cleanup request; reconcile before resubmission: ' + str(step))
        if digest(output.read_bytes()) != state['outputSha256']:
            raise PipelineError('Prepared output changed')
        return output
    state = {'route': route, 'requestSha256': request_hash, 'status': 'submission-uncertain'}
    write_json(HERE, receipt, state)
    result = pixellab.request('POST', route, payload)
    encoded = result['image']['base64'].split(',')[-1]
    raw = base64.b64decode(encoded, validate=True)
    size = pixellab.inspect_png(raw)
    write_bytes(HERE, output, raw)
    state.update(status='completed', outputSha256=digest(raw), size=size, usage=result.get('usage'),
                 zoomFactorDetected=result.get('zoom_factor_detected'))
    write_json(HERE, receipt, state, replace=True)
    return output

def prepare(key):
    approval = json.loads((HERE / 'keyframe-approval.json').read_text())
    if approval['decision'] != 'approved' or key not in approval['sources']:
        raise PipelineError('Keyframe approval missing')
    source = KEYFRAMES / (key + '.png')
    if digest(source.read_bytes()) != approval['sources'][key]:
        raise PipelineError('Approved keyframe changed')
    normalized = HERE/'inputs'/(key+'.png')
    normalized_receipt = normalized.with_suffix('.json')
    if normalized.exists() and normalized_receipt.exists():
        state = json.loads(normalized_receipt.read_text())
        if digest(normalized.read_bytes()) != state['outputSha256']:
            raise PipelineError('Normalized input changed: '+key)
        if digest((HERE/'prepared'/key/'transparent.png').read_bytes()) != state['sourceSha256']:
            raise PipelineError('Prepared input changed: '+key)
        print(json.dumps({'key':key,'status':'already-prepared'}),flush=True)
        return
    directory = HERE / 'prepared' / key
    unzoom = sync_image(directory / 'unzoom', '/unzoom', {'image': image_payload(source), 'quantize': 0})
    with Image.open(unzoom) as image:
        width, height = image.size
    if max(width,height) > 400:
        raise PipelineError('Unzoom did not recover a usable native grid')
    result = sync_image(directory / 'transparent', '/remove-background', {
        'image': image_payload(unzoom), 'image_size': {'width':width,'height':height},
        'background_removal_task':'remove_simple_background',
        'text':'The single pixel art ' + key.split('-')[0] + ' creature, including every dark outline, claw, eye and ear.', 'seed': 913})
    with Image.open(result) as image:
        if image.mode != 'RGBA' or image.getextrema()[-1][0] != 0:
            raise PipelineError('Cleanup did not produce transparent sprite')
        print(json.dumps({'key':key,'nativeSize':image.size,'bbox':image.getbbox(),'prepared':str(result)}),flush=True)

def initialize():
    manifest = json.loads((KEYFRAMES / 'manifest.json').read_text())
    approval = {'decision':'approved','reviewer':'John','reviewedAt':datetime.now(timezone.utc).isoformat(),
        'evidence':"These are looking good, run them through the animation machine, and either create, or update the 'sprite generator workflow' skill (or whatever similar",
        'scope':'18 keyframes approved for animation generation; generated animations remain candidates for review.',
        'figma':manifest['figma'], 'sources':{a['key']:digest(Path(a['path']).read_bytes()) for a in manifest['assets']}}
    write_json(HERE,HERE/'keyframe-approval.json',approval)
    print(json.dumps({'approvedKeyframes':len(approval['sources'])}))

def normalize(key):
    species=key.split('-')[0]
    source=HERE/'prepared'/key/'transparent.png'
    neutral=HERE/'prepared'/(species+'-idle')/'transparent.png'
    base=Image.open(neutral).convert('RGBA').resize((128,128),Image.Resampling.NEAREST)
    shift=120-base.getbbox()[3]
    image=Image.open(source).convert('RGBA').resize((128,128),Image.Resampling.NEAREST)
    original_bbox=image.getbbox()
    if original_bbox is None or original_bbox[3]+shift>128 or original_bbox[1]+shift<0:
        raise PipelineError('Pose would clip under the fixed species registration: '+key)
    output=Image.new('RGBA',(128,128),(0,0,0,0))
    output.alpha_composite(image,(0,shift))
    path=HERE/'inputs'/(key+'.png')
    buffer=io.BytesIO();output.save(buffer,format='PNG');raw=buffer.getvalue()
    if path.exists():
        if digest(path.read_bytes())!=digest(raw):raise PipelineError('Normalized input changed')
    else:write_bytes(HERE,path,raw)
    receipt=HERE/'inputs'/(key+'.json')
    value={'sourceSha256':digest(source.read_bytes()),'outputSha256':digest(raw),'canvas':[128,128],
        'resample':'nearest','speciesOffset':[0,shift],'root':[64,120],'bbox':output.getbbox(),
        'registration':'One fixed translation from the species idle; no per-pose recentering.'}
    if not receipt.exists():write_json(HERE,receipt,value)
    print(json.dumps({'key':key,'input':str(path),'bbox':output.getbbox(),'offset':shift}),flush=True)

def pilot(resume=False):
    source=HERE/'inputs/agumon-idle.png'
    job={'id':'idle.e','operation':'animate-with-text-v3','firstFrame':'idle','lastFrame':'idle','frameCount':4,'seed':913001,
         'description':'A seamless subtle idle breathing loop. The orange Agumon dinosaur gently breathes, chest rising and falling with a tiny relaxed arm and tail movement, and blinks once. Remain standing on the same spot facing right. Fixed camera, fixed scale, preserve the exact head, green eye, orange palette and ivory claws. Both feet stay planted. No walking, turning, objects, fire, shadows, background or motion lines. End exactly in the starting pose.'}
    operation,payload,size=pixellab.prepare({'canvas':[128,128]},job,{'idle':source})
    state=pixellab.run_job(HERE,HERE/'jobs/agumon-idle',{'assetId':'agumon','revision':'2026-09-13-v1','job':'idle.e'},operation,payload,size,
        execute=not resume,allow_billable=not resume,resume=resume,
        source_plan_sha256=digest((HERE/'keyframe-approval.json').read_bytes()))
    print(json.dumps(state),flush=True)

def credentials():
    if os.environ.get('PIXELLAB_API_TOKEN') or os.environ.get('PIXELLAB_API_KEY'):
        return
    path = Path('/Users/johncohrn/Documents/ChatGPT/Tomagachi Web App/.env.pixellab.local')
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600:
        raise PipelineError('PixelLab credential file must be a regular file with mode 0600')
    for line in path.read_text().splitlines():
        if line.strip().startswith('export '):
            line = line.strip()[7:]
        key, sep, val = line.partition('=')
        if sep and key.strip() in ('PIXELLAB_API_TOKEN', 'PIXELLAB_API_KEY'):
            parts = shlex.split(val, comments=True)
            if len(parts) == 1 and parts[0]:
                os.environ[key.strip()] = parts[0]
    if not (os.environ.get('PIXELLAB_API_TOKEN') or os.environ.get('PIXELLAB_API_KEY')):
        raise PipelineError('No PixelLab token found in the configured credential file')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['auth','init','prepare','normalize','pilot'])
    parser.add_argument('--key', action='append')
    parser.add_argument('--all',action='store_true')
    parser.add_argument('--resume',action='store_true')
    args = parser.parse_args()
    if args.command == 'init':
        return initialize()
    keys=list(json.loads((HERE/'keyframe-approval.json').read_text())['sources']) if args.all else args.key or []
    if args.command == 'normalize':
        for key in keys: normalize(key)
        return
    credentials()
    if args.command == 'auth':
        result = pixellab.request('GET', '/balance')
        write_json(HERE, HERE / 'balance-before.json', result)
        print(json.dumps({'authenticated': True, 'credits': result.get('credits'), 'subscription': result.get('subscription')}))
    elif args.command == 'prepare':
        # Stop on the first error; never eagerly submit the entire paid batch.
        for key in keys: prepare(key)
    elif args.command == 'pilot':
        pilot(args.resume)

if __name__ == '__main__':
    try:
        main()
    except (PipelineError, OSError, ValueError) as error:
        print(type(error).__name__ + ': ' + str(error), file=sys.stderr)
        raise SystemExit(1)

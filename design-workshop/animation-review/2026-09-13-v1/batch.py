"""Resumable animation queue and offline review packaging; no POST during plan/check/package."""
from pathlib import Path
import argparse, base64, io, json
from PIL import Image
import animate as a

HERE = a.HERE
PLAN = HERE/'animation-plan.json'
PILOT_PROMPT = 'A seamless subtle idle breathing loop. The orange Agumon dinosaur gently breathes, chest rising and falling with a tiny relaxed arm and tail movement, and blinks once. Remain standing on the same spot facing right. Fixed camera, fixed scale, preserve the exact head, green eye, orange palette and ivory claws. Both feet stay planted. No walking, turning, objects, fire, shadows, background or motion lines. End exactly in the starting pose.'
IDENTITY = {
    'agumon':'orange Agumon dinosaur with green eyes and ivory claws',
    'botamon':'small black fuzzy Botamon with yellow eyes and two short pointed ears',
    'koromon':'pink round Koromon with long ear-like appendages and red eyes',
}
MOTIONS = {
    'idle':'gently breathe and blink once',
    'move':'perform one small hop cycle in place, squash before takeoff and settle on landing',
    'happy':'bounce with delight into the supplied happy pose',
    'eat':'lean toward the supplied eating pose and take a small contented bite',
    'basic-attack':'anticipate then lunge into the supplied claw-strike pose',
    'pepper-breath':'brace, inhale and open the mouth into the supplied Pepper Breath release pose',
    'guard':'hold the defensive guard stance with subtle breathing',
    'evade':'make a quick evasive lean into the supplied dodge pose',
    'hit':'recoil from an impact into the supplied hit-reaction pose',
    'defeat':'lose balance and settle into the supplied defeated pose',
}

def save(path, value):
    a.write_json(HERE,path,value,replace=path.exists())

def build():
    approval=json.loads((HERE/'keyframe-approval.json').read_text())
    if approval['decision']!='approved':raise a.PipelineError('Keyframe approval missing')
    keys=list(approval['sources'])
    jobs=[];clips=[]
    for key in keys:
        species,action=key.split('-',1)
        loop=action in ('idle','move','guard')
        frames={'idle':4,'move':8,'guard':4,'evade':4,'hit':4,'pepper-breath':8,'defeat':8}.get(action,6)
        ms={'idle':200,'move':110,'guard':180,'happy':90,'eat':90,'basic-attack':60,'pepper-breath':70,'evade':60,'hit':80,'defeat':120}[action]
        parts=['loop'] if loop else ['out'] if action=='defeat' else ['out','back']
        segments=[]
        for part in parts:
            pilot=key=='agumon-idle'
            jobkey=key if pilot else key+'-'+part
            motion=MOTIONS[action]
            if key=='agumon-move':motion='perform a complete in-place walk cycle with alternating planted feet and a small tail counter-swing'
            first=key if loop or part=='back' else species+'-idle'
            last=species+'-idle' if part=='back' else key
            if part=='back':motion='recover smoothly from the supplied action pose into the supplied relaxed idle pose'
            text=f'Animate the {IDENTITY[species]}: {motion}. '
            text+='Start at the first reference and finish exactly at the last reference. '
            if loop:text+='Make a seamless complete cycle. '
            if action=='defeat':text+='Remain defeated at the end; do not recover. '
            text+='Fixed camera, right-facing view, fixed character scale and ground registration. Preserve the reference anatomy, silhouette, eyes, outlines and palette. Keep all appendages intact. Transparent background. No camera motion, turning, added props, text, particles, fire, projectile or scene effects.'
            job={'id':'idle.e' if pilot else action.replace('-','_')+'.e.'+part,
                'operation':'animate-with-text-v3','firstFrame':first,'lastFrame':last,
                'frameCount':frames,'seed':913001 if pilot else 914000+len(jobs),
                'description':PILOT_PROMPT if pilot else text}
            jobs.append({'key':jobkey,'clip':key,'species':species,'job':job})
            segments.append(jobkey)
        clips.append({'key':key,'character':species,'action':{'basic-attack':'basic_attack','pepper-breath':'special_attack'}.get(action,action),
            'facing':'E','loop':loop,'frameDurationMs':ms,'segments':segments,'motionApproval':'pending'})
    plan={'schemaVersion':1,'revision':'2026-09-13-v1','provider':'PixelLab','canvas':[128,128],'root':[64,120],
        'approvalSha256':a.digest((HERE/'keyframe-approval.json').read_bytes()),
        'inputSha256':{k:a.digest((HERE/'inputs'/(k+'.png')).read_bytes()) for k in keys},
        'clips':clips,'jobs':jobs,'note':'Prepared requests; unsubmitted jobs have consumed no animation credits. Keyframe approval is not motion approval.'}
    if PLAN.exists() and a.fingerprint(json.loads(PLAN.read_text()))!=a.fingerprint(plan):
        raise a.PipelineError('Existing plan differs; preserve it and create a new revision')
    if not PLAN.exists():save(PLAN,plan)
    return plan

def load():
    plan=json.loads(PLAN.read_text())
    refinements=HERE/'animation-refinements.json'
    if refinements.exists():
        replacements=json.loads(refinements.read_text())['replacements']
        for index,item in enumerate(plan['jobs']):
            if item['key'] in replacements:
                replacement=replacements[item['key']]
                plan['jobs'][index]=replacement['item']
                for clip in plan['clips']:
                    clip['segments']=[replacement['item']['key'] if key==item['key'] else key for key in clip['segments']]
    if a.digest((HERE/'keyframe-approval.json').read_bytes())!=plan['approvalSha256']:
        raise a.PipelineError('Approval record changed')
    approval=json.loads((HERE/'keyframe-approval.json').read_text())
    for key,expected in plan['inputSha256'].items():
        if a.digest((HERE/'inputs'/(key+'.png')).read_bytes())!=expected:
            raise a.PipelineError('Input changed: '+key)
        if a.digest((a.KEYFRAMES/(key+'.png')).read_bytes())!=approval['sources'][key]:
            raise a.PipelineError('Approved source changed: '+key)
    return plan

def payload(item):
    job=item['job']
    sources={key:HERE/'inputs'/(key+'.png') for key in (job['firstFrame'],job['lastFrame'])}
    return a.pixellab.prepare({'canvas':[128,128]},job,sources)

def binding(item):
    return {'assetId':item['species'],'revision':'2026-09-13-v1','job':item['job']['id']}

def state_for(item,plan):
    operation,data,size=payload(item)
    directory=HERE/'jobs'/item['key']
    path=directory/'generation.json'
    if not path.exists():return {'status':'not-submitted'}
    state=json.loads(path.read_text())
    expected=dict(binding(item),operation=operation,requestSha256=a.fingerprint(data))
    if state['binding']!=expected:raise a.PipelineError('Recorded job inputs changed: '+item['key'])
    if state['sourcePlanSha256']!=plan['approvalSha256']:raise a.PipelineError('Job approval differs')
    if state['status']=='completed':
        for output in state['outputs']:
            if a.digest((directory/output['path']).read_bytes())!=output['sha256']:
                raise a.PipelineError('Generated frame changed')
    return state

def check(plan):
    statuses={item['key']:state_for(item,plan)['status'] for item in plan['jobs']}
    summary={'clips':len(plan['clips']),'jobs':len(plan['jobs']),
        'completedClips':sum(all(statuses[s]=='completed' for s in c['segments']) for c in plan['clips']),
        'completedJobs':sum(s=='completed' for s in statuses.values()),
        'unsubmittedJobs':sum(s=='not-submitted' for s in statuses.values()),'jobsByStatus':statuses}
    save(HERE/'status.json',summary)
    print(json.dumps(summary),flush=True)
    return summary

def run(plan, execute, allow_billable, limit):
    if not execute or not allow_billable:raise a.PipelineError('New generation requires --execute --allow-billable')
    a.credentials();advanced=0
    for item in plan['jobs']:
        state=state_for(item,plan)
        if state['status']=='completed':continue
        if state['status'] in ('failed','submission-uncertain'):
            raise a.PipelineError('Reconcile existing job before continuing: '+item['key'])
        resume=state['status']!='not-submitted'
        if not resume:
            balance=a.pixellab.request('GET','/balance');save(HERE/'balance-latest.json',balance)
            credits=balance.get('credits') or {}
            usd=credits.get('usd');trial=(balance.get('subscription') or {}).get('generations')
            # Interpret only the observed API schema. Unknown balances require inspection.
            if usd is None or trial is None:raise a.PipelineError('Inspect changed balance schema before submission')
            if float(usd)<=0 and float(trial)<=0:raise a.PipelineError('PixelLab balance is zero; no job submitted')
        operation,data,size=payload(item)
        state=a.pixellab.run_job(HERE,HERE/'jobs'/item['key'],binding(item),operation,data,size,
            execute=not resume,allow_billable=not resume,resume=resume,source_plan_sha256=plan['approvalSha256'])
        print(json.dumps({'key':item['key'],'status':state['status'],'jobId':state.get('jobId')}),flush=True)
        advanced+=1
        if state['status']!='completed' or advanced>=limit:break
    check(plan)

def package(plan):
    out=HERE/'review';out.mkdir(exist_ok=True)
    selection_path=HERE/'frame-selection.json'
    selection=json.loads(selection_path.read_text()) if selection_path.exists() else {}
    curation_path=HERE/'clip-selections.json'
    curations=json.loads(curation_path.read_text()) if curation_path.exists() else {}
    def read_frame(segment,output):
        source=HERE/'jobs'/segment/output['path'];key=str(source.relative_to(HERE))
        if key in selection:
            chosen=selection[key]
            if chosen['sourceSha256']!=output['sha256']:raise a.PipelineError('Extraction source changed')
            source=HERE/chosen['selectedPath']
            if a.digest(source.read_bytes())!=chosen['selectedSha256']:raise a.PipelineError('Extracted frame changed')
        return Image.open(source).convert('RGBA')
    items={i['key']:i for i in plan['jobs']};cards=[]
    for clip in plan['clips']:
        states=[state_for(items[s],plan) for s in clip['segments']]
        ready=all(s['status']=='completed' for s in states)
        frames=[];raw_count=0;removed=0
        if ready:
            if clip['key'] in curations:
                curation=curations[clip['key']];source_jobs={}
                for chosen in curation['frames']:
                    segment=chosen['job']
                    if segment not in source_jobs:
                        state=json.loads((HERE/'jobs'/segment/'generation.json').read_text())
                        if state['status']!='completed' or state['sourcePlanSha256']!=plan['approvalSha256']:
                            raise a.PipelineError('Curated source is not a completed approved-source job')
                        source_jobs[segment]=state
                    output=source_jobs[segment]['outputs'][chosen['index']]
                    if output['sha256']!=chosen['sha256'] or a.digest((HERE/'jobs'/segment/output['path']).read_bytes())!=chosen['sha256']:
                        raise a.PipelineError('Curated source frame changed')
                    frames.append(read_frame(segment,output))
                raw_count=sum(len(s['outputs']) for s in source_jobs.values())
            else:
                for segment,state in zip(clip['segments'],states):
                    segment_frames=[read_frame(segment,o) for o in state['outputs']]
                    raw_count+=len(segment_frames)
                    if frames and segment_frames and frames[-1].tobytes()==segment_frames[0].tobytes():
                        segment_frames=segment_frames[1:];removed+=1
                    frames.extend(segment_frames)
            strip=Image.new('RGBA',(128*len(frames),128));data=[]
            frame_dir=out/'frames'/clip['key'];frame_dir.mkdir(parents=True,exist_ok=True)
            frame_exports=[]
            for i,frame in enumerate(frames):
                strip.paste(frame,(128*i,0));buf=io.BytesIO();frame.save(buf,format='PNG')
                raw=buf.getvalue();data.append('data:image/png;base64,'+base64.b64encode(raw).decode())
                name='frame-%04d.png'%i;(frame_dir/name).write_bytes(raw)
                frame_exports.append({'index':i,'durationMs':clip['frameDurationMs'],'path':str((frame_dir/name).relative_to(out)),
                    'sha256':a.digest(raw)})
            for old_frame in frame_dir.glob('frame-*.png'):
                if int(old_frame.stem.split('-')[-1])>=len(frames):old_frame.unlink()
            strip.save(out/(clip['key']+'-strip.png'))
            columns=min(6,len(frames));rows=(len(frames)+columns-1)//columns
            sheet=Image.new('RGBA',(128*columns,128*rows))
            for i,frame in enumerate(frames):sheet.paste(frame,(128*(i%columns),128*(i//columns)))
            sheet.save(out/(clip['key']+'-sheet.png'))
            gif_frames=[]
            for frame in frames:
                bg=Image.new('RGB',(128,128),'#f5efe2');bg.paste(frame,mask=frame.getchannel('A'))
                gif_frames.append(bg.resize((512,512),Image.Resampling.NEAREST))
            opts={'loop':0} if clip['loop'] else {}
            gif_frames[0].save(out/(clip['key']+'.gif'),save_all=True,append_images=gif_frames[1:],
                duration=clip['frameDurationMs'],disposal=2,optimize=False,**opts)
            save(out/(clip['key']+'.json'),dict(clip,actualFrameCount=len(frames),rawFrameCount=raw_count,
                removedIdenticalSegmentSeams=removed,totalDurationMs=len(frames)*clip['frameDurationMs'],
                sheetColumns=columns,sheetRows=rows,
                curation=curations.get(clip['key']),frames=frame_exports))
        else:
            data=['data:image/png;base64,'+base64.b64encode((HERE/'inputs'/(clip['key']+'.png')).read_bytes()).decode()]
        notes_path=HERE/'review-notes.json'
        notes=json.loads(notes_path.read_text()) if notes_path.exists() else {}
        cards.append(dict(clip,ready=ready,images=data,actualFrameCount=len(frames),reviewNote=notes.get(clip['key'],''),
            approvedImage='data:image/png;base64,'+base64.b64encode((HERE/'inputs'/(clip['key']+'.png')).read_bytes()).decode()))
    cards.sort(key=lambda card:(not card['ready'],card['character'],card['key']))
    template=(HERE/'review-template.html').read_text()
    (out/'index.html').write_text(template.replace('__DATA__',json.dumps(cards)))
    check(plan)
    print(json.dumps({'review':str(out/'index.html')}))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['plan','check','run','package'])
    parser.add_argument('--execute',action='store_true');parser.add_argument('--allow-billable',action='store_true')
    parser.add_argument('--limit',type=int,default=1,help='Maximum jobs advanced per invocation (default 1)')
    args=parser.parse_args()
    try:
        plan=build() if args.command=='plan' else load()
        if args.command in ('plan','check'):check(plan)
        elif args.command=='run':run(plan,args.execute,args.allow_billable,max(1,args.limit))
        else:package(plan)
    except (a.PipelineError,OSError,ValueError) as error:
        print(type(error).__name__+': '+str(error),flush=True);raise SystemExit(1)

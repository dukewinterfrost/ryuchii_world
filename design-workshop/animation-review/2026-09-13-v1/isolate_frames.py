"""Separate detached overhead effect pixels from reviewed character frames.

This is source-pixel extraction: no drawing, interpolation, recentering or body edits.
Original provider frames remain unchanged. Only explicitly selected job keys are used.
"""
from pathlib import Path
from PIL import Image
import argparse,io,json
import batch as b

def components(image):
    alpha=image.getchannel('A');pixels=alpha.load()
    remaining={(x,y) for y in range(image.height) for x in range(image.width) if pixels[x,y]>0}
    groups=[]
    while remaining:
        seed=next(iter(remaining));remaining.remove(seed);group={seed};stack=[seed]
        while stack:
            x,y=stack.pop()
            for dx,dy in ((-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)):
                point=(x+dx,y+dy)
                if point in remaining:remaining.remove(point);group.add(point);stack.append(point)
        groups.append(group)
    return sorted(groups,key=len,reverse=True)

def bounds(group):
    return [min(x for x,y in group),min(y for x,y in group),max(x for x,y in group)+1,max(y for x,y in group)+1]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--job',action='append',required=True)
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args();plan=b.load();selection_path=b.HERE/'frame-selection.json'
    selection=json.loads(selection_path.read_text()) if selection_path.exists() else {}
    report=[]
    for job in args.job:
        item=next((i for i in plan['jobs'] if i['key']==job),None)
        if item is None:raise b.a.PipelineError('Unknown job '+job)
        state=b.state_for(item,plan)
        if state['status']!='completed':raise b.a.PipelineError('Job is not complete '+job)
        for frame in state['outputs']:
            source=b.HERE/'jobs'/job/frame['path'];im=Image.open(source).convert('RGBA');groups=components(im)
            main_box=bounds(groups[0]);detached=[g for g in groups[1:] if bounds(g)[3]<main_box[1]-1]
            if not detached:continue
            removed=set().union(*detached)
            record={'source':str(source.relative_to(b.HERE)),'sourceSha256':frame['sha256'],
                'method':'retain-character-source-pixels-v1','connectivity':8,'alphaThreshold':1,
                'characterComponentBox':main_box,'removedComponentBoxes':[bounds(g) for g in detached],
                'removedPixels':len(removed),'reason':'Visually reviewed detached overhead symbols; preserve every character pixel and its position.'}
            if args.apply:
                output=im.copy()
                for point in removed:output.putpixel(point,(0,0,0,0))
                # The entire character component and all other pixels must remain exact.
                for y in range(128):
                    for x in range(128):
                        if (x,y) not in removed:assert output.getpixel((x,y))==im.getpixel((x,y))
                target=b.HERE/'isolated'/job/frame['path'];buf=io.BytesIO();output.save(buf,format='PNG');raw=buf.getvalue()
                if target.exists():
                    if b.a.digest(target.read_bytes())!=b.a.digest(raw):raise b.a.PipelineError('Existing extraction differs')
                else:b.a.write_bytes(b.HERE,target,raw)
                record.update(selectedPath=str(target.relative_to(b.HERE)),selectedSha256=b.a.digest(raw))
                selection[record['source']]=record
            report.append(record)
    if args.apply:b.save(selection_path,selection)
    print(json.dumps({'applied':args.apply,'frames':report}),flush=True)

if __name__=='__main__':main()

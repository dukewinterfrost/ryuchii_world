"""Run the approved queue with two in-flight jobs and durable GET-only recovery."""
import argparse, json, time
import batch as b

def capacity():
    balance=b.a.pixellab.request('GET','/balance')
    b.save(b.HERE/'balance-latest.json',balance)
    usd=(balance.get('credits') or {}).get('usd')
    generations=(balance.get('subscription') or {}).get('generations')
    if usd is None or generations is None:
        raise b.a.PipelineError('Inspect changed balance schema before submission')
    if float(usd)<=0 and float(generations)<=0:
        raise b.a.PipelineError('PixelLab balance is zero; no new job submitted')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute',action='store_true')
    parser.add_argument('--allow-billable',action='store_true')
    parser.add_argument('--job',action='append',help='Optional exact job keys; default entire plan')
    args=parser.parse_args()
    if not args.execute or not args.allow_billable:
        raise b.a.PipelineError('Use --execute --allow-billable for the approved generation run')
    plan=b.load();b.a.credentials()
    jobs=[i for i in plan['jobs'] if not args.job or i['key'] in args.job]
    if args.job and {i['key'] for i in jobs}!=set(args.job):raise b.a.PipelineError('Unknown job key')
    last={};started=time.monotonic()
    while True:
        states={item['key']:b.state_for(item,plan) for item in jobs}
        uncertain=[key for key,s in states.items() if s['status'] in ('failed','submission-uncertain')]
        if uncertain:raise b.a.PipelineError('Reconcile existing receipts: '+', '.join(uncertain))
        active=[i for i in jobs if states[i['key']]['status'] not in ('completed','not-submitted')]
        pending=[i for i in jobs if states[i['key']]['status']=='not-submitted']
        if not active and not pending:break
        selected=active+pending[:max(0,2-len(active))]
        for item in selected:
            previous=states[item['key']]
            resume=previous['status']!='not-submitted'
            if not resume:capacity()
            directory=b.HERE/'jobs'/item['key']
            def transport(method,route,payload=None):
                response=b.a.pixellab.request(method,route,payload)
                if method=='GET' and response.get('status')=='completed':
                    b.save(directory/'usage.json',{'jobUsage':response.get('usage'),
                        'resultUsage':(response.get('last_response') or {}).get('usage')})
                return response
            operation,payload,size=b.payload(item)
            state=b.a.pixellab.run_job(b.HERE,directory,b.binding(item),operation,payload,size,
                execute=not resume,allow_billable=not resume,resume=resume,
                source_plan_sha256=plan['approvalSha256'],transport=transport)
            if state['status']!=last.get(item['key']):
                print(json.dumps({'job':item['key'],'status':state['status'],'jobId':state.get('jobId'),
                    'actualFrames':state.get('actualFrameCount')}),flush=True)
                last[item['key']]=state['status']
        if time.monotonic()-started>3600:
            raise b.a.PipelineError('Bounded run ended; accepted job IDs are saved for resume')
        time.sleep(10)
    b.check(plan)

if __name__=='__main__':
    try:main()
    except (b.a.PipelineError,OSError,ValueError) as error:
        print(type(error).__name__+': '+str(error),flush=True);raise SystemExit(1)

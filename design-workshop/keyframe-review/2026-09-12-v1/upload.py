from pathlib import Path
import json, sys, urllib.request, mimetypes, concurrent.futures
p=Path(__file__).parent
batch=json.loads((p/(sys.argv[1] if len(sys.argv)>1 else 'upload-batch.json')).read_text())
def one(u):
 req=urllib.request.Request(u['submitUrl'],data=Path(u['path']).read_bytes(),headers={'Content-Type':mimetypes.guess_type(u['path'])[0]},method='POST')
 try:
  with urllib.request.urlopen(req,timeout=60) as r: result=json.loads(r.read())
  out={'nodeId':u['nodeId'],'path':u['path'],'result':result}
 except Exception as e: out={'nodeId':u['nodeId'],'error':str(e)}
 (p/('upload-'+u['nodeId'].replace(':','-')+'.json')).write_text(json.dumps(out))
 return out
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
 for r in pool.map(one,batch['uploads']): print(json.dumps(r))

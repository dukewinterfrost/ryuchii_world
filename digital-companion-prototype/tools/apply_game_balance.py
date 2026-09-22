"""Read the canonical XLSX without requiring Excel or third-party Python packages.

Validate in Python and the actual Godot content loader, then replace one bundle
atomically. A failed import never changes the last valid game configuration.
"""
from pathlib import Path
import argparse,copy,json,math,os,re,subprocess,tempfile,zipfile
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
NS={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
REL='{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id'

def read_xlsx(path):
 with zipfile.ZipFile(path) as z:
  strings=[]
  if 'xl/sharedStrings.xml' in z.namelist():
   strings=[''.join(n.itertext()) for n in ET.fromstring(z.read('xl/sharedStrings.xml')).findall('s:si',NS)]
  rels={r.attrib['Id']:r.attrib['Target'].lstrip('/') for r in ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))}
  output={}
  for sheet in ET.fromstring(z.read('xl/workbook.xml')).findall('s:sheets/s:sheet',NS):
   target=rels[sheet.attrib[REL]]
   if not target.startswith('xl/'):target='xl/'+target
   rows=[]
   for row in ET.fromstring(z.read(target)).findall('s:sheetData/s:row',NS):
    cells={}
    for cell in row.findall('s:c',NS):
     ref=cell.attrib['r'];col=0
     for c in re.match('[A-Z]+',ref)[0]:col=col*26+ord(c)-64
     if cell.find('s:f',NS) is not None:raise ValueError(f'{sheet.attrib["name"]} {ref}: enter a value, not a formula')
     kind=cell.attrib.get('t');text=cell.findtext('s:v','',NS)
     value=strings[int(text)] if kind=='s' else ''.join(cell.find('s:is',NS).itertext()) if kind=='inlineStr' else text
     if kind=='b':value=text=='1'
     elif kind not in ['s','inlineStr','str'] and text:
      try:value=float(text);value=int(value) if value.is_integer() else value
      except ValueError:raise ValueError(f'{sheet.attrib["name"]} {ref}: invalid number')
     if value!='':cells[col-1]=value
    if cells:rows.append((int(row.attrib['r']),cells))
   output[sheet.attrib['name']]=rows
  return output

def leaf_get(root,path):
 for key in path:root=root[int(key)] if isinstance(root,list) else root[key]
 return root

def leaf_set(root,path,value):
 parent=leaf_get(root,path[:-1]);key=int(path[-1]) if isinstance(parent,list) else path[-1];parent[key]=value

def import_workbook(path):
 schema=json.loads((ROOT/'assets/balance/workbook-schema.json').read_text())
 sheets=read_xlsx(path);bundle=copy.deepcopy(schema['structure']);bundle['tables']={}
 for table,definition in schema['tables'].items():
  sheet=definition['sheet'];columns=definition['columns'];rows=sheets.get(sheet,[])
  if not rows or [rows[0][1].get(i) for i in range(len(columns))]!=columns:raise ValueError(f'{sheet} row 1: missing or changed columns')
  seen=set();result=[]
  for number,cells in rows[1:]:
   record={col:cells.get(i,'') for i,col in enumerate(columns)}
   if not record['id'] or record['id'] in seen:raise ValueError(f'{sheet} row {number} column id: missing or duplicate ID')
   seen.add(record['id'])
   for col in definition['numeric']:
    val=record[col]
    if isinstance(val,bool) or not isinstance(val,(int,float)) or not math.isfinite(val):raise ValueError(f'{sheet} row {number} column {col}: expected a finite number')
   result.append(record)
  bundle['tables'][table]=result
 found=set()
 for sheet in schema['settingSheets']:
  for number,cells in sheets.get(sheet,[])[1:]:
   key=cells.get(0,'');value=cells.get(2,'');meta=schema['settings'].get(key)
   if not meta or key in found:raise ValueError(f'{sheet} row {number} column key: unknown or duplicate setting')
   found.add(key)
   if meta['type']=='number':
    if isinstance(value,bool) or not isinstance(value,(int,float)) or not math.isfinite(value) or not meta['min']<=value<=meta['max'] or (meta['integer'] and int(value)!=value):raise ValueError(f'{sheet} row {number} column value: expected {"integer" if meta["integer"] else "number"} in {meta["min"]}–{meta["max"]}')
   elif meta['type']=='boolean':
    if str(value).lower() not in ['true','false']:raise ValueError(f'{sheet} row {number}: expected true or false')
    value=str(value).lower()=='true'
   elif not isinstance(value,str) or not value:raise ValueError(f'{sheet} row {number}: expected text')
   leaf_set(bundle['settings'],key.split('/'),value)
 if found!=set(schema['settings']):raise ValueError('Missing settings: '+', '.join(sorted(set(schema['settings'])-found)))
 settings=bundle['settings']
 for prefix in ['food','care.wish']:
  base=settings[prefix+'.wait_base' if prefix=='food' else 'care.wish_wait_base']
  jitter=settings[prefix+'.wait_jitter' if prefix=='food' else 'care.wish_wait_jitter']
  if base+jitter>420:raise ValueError('Care wait base plus jitter must not exceed 420 seconds')
 if any(food not in ['sweet_potato','pizza','shrimp','pudding','rice_ball','strawberry','drumstick','steak','cake'] for food in settings['food.favorites'].values()):raise ValueError('Unknown favorite food')
 for species,rules in settings['game_definitions.EVOLUTIONS'].items():
  for rule in rules:
   if rule['target'] not in ['botamon','koromon','agumon'] or rule['target']==species:raise ValueError('Evolution target must be another supported companion species')
   if rule['stage']!={'botamon':'Baby','koromon':'In-Training','agumon':'Rookie'}[rule['target']]:raise ValueError('Evolution stage must match the target species')
   if any(a not in ['feed','play','chat','clean','pet','praise','scold'] for a in rule['required_actions']):raise ValueError('Unknown evolution care action')
 for stat,training in settings['game_definitions.TRAINING'].items():
  if training['gain']!=int(training['gain']) or training['cap']!=int(training['cap']) or training['cap']<settings['player.initial_stats'][stat]:raise ValueError('Training gains and caps must be integers; caps must cover starting stats')
 creatures={r['id']:r for r in bundle['tables']['creatures']};moves={r['id']:r for r in bundle['tables']['moves']}
 for i,c in enumerate(creatures.values(),2):
  for key in ['hp','mp','offense','defense','speed','brains']:
   value=c[key];maximum=9999 if key in ['hp','mp'] else 999
   if value< (1 if key=='hp' else 0) or value>maximum or value!=int(value):raise ValueError(f'Creatures row {i} column {key}: invalid stat')
  if not re.fullmatch(r'[a-z][a-z0-9_]*',str(c['id'])) or not str(c['name']).strip() or len(str(c['name']))>64:raise ValueError(f'Creatures row {i}: invalid ID or name')
  if c['basic_move'] not in moves or moves[c['basic_move']]['kind']!='melee' or moves[c['basic_move']]['mp_cost']!=0:raise ValueError(f'Creatures row {i}: basic_move must be free melee')
  loadout=str(c['moves']).split('|')
  if len(loadout)!=3 or len(set(loadout))!=3:raise ValueError(f'Creatures row {i} column moves: exactly three distinct moves required')
  for move in loadout:
   if move not in moves or c['id'] not in str(moves[move]['species']).split('|') or str(moves[move]['equippable']).lower()!='true':raise ValueError(f'Creatures row {i} column moves: unavailable move {move}')
  if c['nature'] not in {r['id'] for r in bundle['tables']['natures']}:raise ValueError(f'Creatures row {i} column nature: unknown nature')
 if not any(c.startswith('slime') for c in creatures):raise ValueError('The mixed encounter pool requires a slime')
 if [e['id'] for e in bundle['tables']['encounters']]!=['first_slime','three_slimes','slimes_and_healer','mixed_groups']:raise ValueError('Keep the four encounter IDs and order unchanged')
 for i,e in enumerate(bundle['tables']['encounters'],2):
  members=str(e['members']).split('|')
  if len(members)!=(1 if i==2 else 3) or any(m not in creatures for m in members) or sum(m.startswith('fairy') for m in members)>1:raise ValueError(f'Encounters row {i} column members: require valid group size and at most one fairy')
 return bundle

def validate_godot(bundle):
 godot=os.environ.get('GODOT_PATH','/Applications/Godot.app/Contents/MacOS/Godot')
 with tempfile.NamedTemporaryFile(mode='w',suffix='.json',delete=False) as f:json.dump(bundle,f);candidate=f.name
 try:
  run=subprocess.run([godot,'--headless','--path',str(ROOT),'--script','res://tools/validate_game_balance.gd','--','--test-mode',candidate],capture_output=True,text=True,timeout=45)
  if run.returncode or 'BALANCE_VALID' not in run.stdout or 'SCRIPT ERROR' in run.stderr:raise ValueError('Godot validation failed:\n'+run.stdout+run.stderr)
 finally:Path(candidate).unlink(missing_ok=True)

def apply(path,check=False):
 bundle=import_workbook(path);validate_godot(bundle)
 if not check:
  destination=ROOT/'assets/balance/game-balance.json'
  with tempfile.NamedTemporaryFile(mode='w',dir=destination.parent,suffix='.tmp',delete=False) as f:
   json.dump(bundle,f,indent=2);f.write('\n');f.flush();os.fsync(f.fileno());temporary=f.name
  os.replace(temporary,destination)
 print('Validated game balance.' if check else 'Applied game balance. Restart the game or reload the sandbox for a fresh battle.')
 return bundle

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('workbook',nargs='?',type=Path,default=ROOT/'Game Balance.xlsx');parser.add_argument('--check',action='store_true');args=parser.parse_args()
 try:apply(args.workbook,args.check)
 except (ValueError,OSError,KeyError,zipfile.BadZipFile,subprocess.TimeoutExpired) as error:parser.exit(1,str(error)+'\nNo balance changes were applied.\n')

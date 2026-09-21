import fs from 'node:fs/promises';
import path from 'node:path';
import {Workbook,SpreadsheetFile} from '@oai/artifact-tool';
const root=path.resolve(import.meta.dirname,'../..');
const source=JSON.parse(await fs.readFile(path.join(root,'assets/balance/game-balance.json'),'utf8'));
const wb=Workbook.create();
const schema={structure:structuredClone(source),tables:{},settings:{},settingSheets:['Care','Training','Progression','Economy','Player']};
schema.structure.tables={};
const intro=wb.worksheets.add('Start here');intro.showGridLines=false;
intro.getRange('B2').values=[['Game balance']];intro.getRange('B2').format.font={name:'Arial',size:16,bold:true};
const notes=[['Edit the values in the content tables and the yellow Value cells.'],['Save this workbook, then double-click Apply Game Balance.command.'],['Restart the game, or reload the sandbox to start a fresh battle.'],['Existing battles and replays retain their original balance.'],['Keep IDs unchanged. Move lists use | between three move IDs.'],['New enemies need art and content validation through $mob-creator.'],['Slimes remain legless in every source and generated frame.'],['Source: existing game balance and the approved September 21 mob plan.'],['New mob numbers are starting values for playtesting.']];
intro.getRange('B4').write(notes);intro.getRange('B4:B12').format.font={name:'Arial',size:11};intro.getRange('B4:B12').format.rowHeight=25;intro.getRange('B:B').format.columnWidth=100;
function column(n){let s='';for(n++;n;n=Math.floor((n-1)/26))s=String.fromCharCode(65+(n-1)%26)+s;return s;}
function makeTable(name,headers,rows){
 const sheet=wb.worksheets.add(name);sheet.showGridLines=false;
 const area=`A1:${column(headers.length-1)}${rows.length+1}`;
 sheet.getRange(area).values=[headers,...rows];sheet.getRange(area).format.font={name:'Arial',size:11,color:'#25352E'};
 sheet.getRange(area).format.rowHeight=25;
 sheet.getRange(`A1:${column(headers.length-1)}1`).format={fill:'#234B3E',font:{name:'Arial',size:11,bold:true,color:'#FFFFFF'},rowHeight:40,wrapText:true};
 sheet.tables.add(area,true,name.replaceAll(' ','')+'Table');
 sheet.freezePanes.freezeRows(1);sheet.freezePanes.freezeColumns(1);
 sheet.getRange(area).format.columnWidth=20;
 sheet.getRange(`A1:A${rows.length+1}`).format.columnWidth=25;
 return sheet;
}
const names={creatures:'Creatures',moves:'Moves',encounters:'Encounters',items:'Items',natures:'AI',tuning:'Combat tuning'};
for(const key of ['creatures','moves','encounters','items','natures','tuning']){
 const records=source.tables[key],headers=Object.keys(records[0]);
 const convert=v=>typeof v==='string'&&v!==''&&Number.isFinite(Number(v))?Number(v):v;
 const rows=records.map(r=>headers.map(h=>convert(r[h])));
 const sheet=makeTable(names[key],headers,rows);
 const numeric=headers.filter((h,i)=>rows.every(r=>typeof r[i]==='number'));
 schema.tables[key]={sheet:names[key],columns:headers,numeric};
 for(let i=0;i<headers.length;i++){
  const h=headers[i],range=sheet.getRange(`${column(i)}2:${column(i)}${rows.length+1}`);
  if(numeric.includes(h))range.setNumberFormat(h.includes('percent')||h==='damage_variance'?'0%':rows.every(r=>Number.isInteger(r[i]))?'0':'0.00');
  if(h==='kind')range.dataValidation={rule:{type:'list',values:['melee','projectile','rush','heal','barrier']}};
  if(h==='target')range.dataValidation={rule:{type:'list',values:['enemy','self','ally_slime']}};
  if(['equippable','movement_while_casting','opening_tackle'].includes(h))range.dataValidation={rule:{type:'list',values:['true','false']}};
  if(h==='nature')range.dataValidation={rule:{type:'list',values:source.tables.natures.map(r=>r.id)}};
  if(['species','moves','members'].includes(h))sheet.getRange(`${column(i)}1:${column(i)}${rows.length+1}`).format.columnWidth=62;
 }
}
const groups=Object.fromEntries(schema.settingSheets.map(n=>[n,[]]));
function flatten(value,parts){
 if(value && typeof value==='object'){
  for(const [key,v] of Object.entries(value))flatten(v,[...parts,key]);return;
 }
 const key=parts.join('/');
 // Building collision geometry remains an immutable schema field.
 if(parts[0]==='game_definitions.DECOR' && parts[2]!=='cost')return;
 const group=/EVOLUTIONS/.test(key)?'Progression':/training|TRAINING/.test(key)?'Training':/player\./.test(key)?'Player':/inventory|enclosure|building|DECOR|rewards|WIN_ITEM/.test(key)?'Economy':'Care';
 const numeric=typeof value==='number';
 let min=numeric&&value<0?-100:0,max=100000;
 if(/SECONDS|seconds_per|sleep_need_seconds/.test(key))min=.033333;
 if(/SLEEP_SECONDS/.test(key))max=3600;
 if(/wait_jitter/.test(key))max=180;
 if(/care.initial/.test(key)){min=parts[1]==='weight'?1:0;max=parts[1]==='weight'?99:100;}
 if(/cooking_.*cost/.test(key))min=1;
 if(/social_repeat_multiplier/.test(key))max=1;
 if(/initial_wait|wait_base/.test(key))max=/wait_base/.test(key)?240:420;
 if(/SICK_CHANCE|TIRED|SLEEPY|FULLNESS|threshold|min_bond|fatigue|happiness|discipline/.test(key)&&!(/seconds|SECONDS|wait/.test(key)))max=100;
 if(/\/cap$/.test(key))max=/\/(hp|mp)\//.test(key)?9999:999;
 if(/player.initial_stats/.test(key)){min=parts[1]==='hp'?1:0;max=['hp','mp'].includes(parts[1])?9999:999;}
 const integer=numeric&&(/TRAINING\/|WIN_ITEM|inventory|rewards.*points|cooking|wait_jitter|player.initial_stats/.test(key)||Number.isInteger(value)&&!(/SECONDS|duration|cooldown|gain|recovery|percent|multiplier|seconds|wait/.test(key)));
 schema.settings[key]={type:numeric?'number':typeof value==='boolean'?'boolean':'text',min,max,integer};
 let parent=schema.structure.settings;for(const p of parts.slice(0,-1))parent=parent[p];parent[parts.at(-1)]=null;
 const label=key.replaceAll('/',' · ').replaceAll('_',' ').replaceAll('game definitions.','').toLowerCase();
 const unit=/seconds|SECONDS|duration|cooldown|wait|active_seconds/.test(key)?'seconds':/multiplier/.test(key)?'multiplier':numeric?'points / count':'text';
 groups[group].push([key,label,value,unit,numeric?`${min} to ${max}`:'Keep stable IDs and references']);
}
for(const [key,value] of Object.entries(source.settings))flatten(value,[key]);
for(const [name,rows] of Object.entries(groups)){
 const sheet=makeTable(name,['key','Setting','Value','Unit','Allowed range'],rows);
 sheet.getRange(`A1:A${rows.length+1}`).format.columnWidth=62;
 sheet.getRange(`B1:B${rows.length+1}`).format.columnWidth=65;
 sheet.getRange(`C2:C${rows.length+1}`).format.fill='#FFF2CC';
 sheet.getRange(`C2:C${rows.length+1}`).setNumberFormat('0.00');
 for(let i=0;i<rows.length;i++){const meta=schema.settings[rows[i][0]];if(meta.type==='number')sheet.getRange(`C${i+2}`).dataValidation={rule:{type:meta.integer?'whole':'decimal',operator:'between',formula1:meta.min,formula2:meta.max}};}
}
wb.recalculate();
const output=path.join(root,'outputs/mob-balance');await fs.mkdir(output,{recursive:true});
for(const name of ['Start here',...Object.values(names),...schema.settingSheets]){
 const image=await wb.render({sheetName:name,range:name==='Start here'?'B2:B12':name==='Creatures'?'A1:J6':schema.settingSheets.includes(name)?'B1:E12':'A1:F9',scale:1,format:'png'});
 await fs.writeFile(path.join(output,`${name}.png`),new Uint8Array(await image.arrayBuffer()));
}
const file=await SpreadsheetFile.exportXlsx(wb);await file.save(path.join(output,'Game Balance.xlsx'));
await fs.writeFile(path.join(root,'assets/balance/workbook-schema.json'),JSON.stringify(schema,null,2)+'\n');
console.log((await wb.inspect({kind:'sheet',include:'id,name',maxChars:2000})).ndjson);
console.log('Workbook and previews exported.');

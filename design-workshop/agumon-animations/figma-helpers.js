const createdNodeIds=[],mutatedNodeIds=[];
const [variables,styles]=await Promise.all([figma.variables.getLocalVariablesAsync(),figma.getLocalTextStylesAsync()]);
await Promise.all(styles.map(s=>figma.loadFontAsync(s.fontName)));
const vm=Object.fromEntries(variables.map(v=>[v.name,v]));
const sm=Object.fromEntries(styles.map(s=>[s.name.split(' / ')[1],s]));
function color(name){let v=vm['color/'+name],value=Object.values(v.valuesByMode)[0];while(value.type==='VARIABLE_ALIAS'){v=variables.find(t=>t.id===value.id);value=Object.values(v.valuesByMode)[0];}return figma.variables.setBoundVariableForPaint({type:'SOLID',color:{r:value.r,g:value.g,b:value.b}},'color',vm['color/'+name]);}
function track(n){createdNodeIds.push(n.id);return n;}
function space(n,key,value){n[key]=value;if(vm['space/'+value])n.setBoundVariable(key,vm['space/'+value]);}
function panel(parent,name,width,bg='paper',gap=16,pad=24,direction='VERTICAL'){
const n=track(figma.createAutoLayout(direction));n.name=name;n.fills=bg?[color(bg)]:[];n.resize(width,1);n.layoutSizingHorizontal='FIXED';n.layoutSizingVertical='HUG';space(n,'itemSpacing',gap);for(const k of ['paddingLeft','paddingRight','paddingTop','paddingBottom'])space(n,k,pad);parent.appendChild(n);return n;
}
async function label(parent,value,style='Body',width=1000,ink='ink',size){const n=track(figma.createText());n.name=value.slice(0,70);await n.setTextStyleIdAsync(sm[style].id);n.characters=value;if(size)n.fontSize=size;n.textAutoResize='HEIGHT';n.resize(width,n.height);n.layoutSizingHorizontal='FIXED';n.fills=[color(ink)];parent.appendChild(n);return n;}
function imageRect(parent,name,w,h){const r=track(figma.createRectangle());r.name=name;r.resize(w,h);r.fills=[];parent.appendChild(r);return r;}

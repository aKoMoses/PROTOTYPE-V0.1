// Read source GLBs, compare their actual data and build the animation review index.
// node tools/analyze_mecha_animations.mjs "C:/path/model.glb" [output-directory]
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import http from 'node:http';
const source = process.argv[2];
if (!source) throw Error('Supply the new GLB path.');
const destination = path.resolve(process.argv[3] || 'outputs/mecha-animation-review');
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
function load(file) {
  const buffer = fs.readFileSync(file);
  if (buffer.readUInt32LE(0) !== 0x46546c67 || buffer.readUInt32LE(4) !== 2 || buffer.readUInt32LE(8) !== buffer.length) throw Error('Invalid GLB 2.0');
  let document, binary;
  for (let offset = 12; offset < buffer.length;) {
    const length = buffer.readUInt32LE(offset), type = buffer.readUInt32LE(offset + 4);
    const chunk = buffer.subarray(offset + 8, offset + 8 + length);
    if (type === 0x4e4f534a) document = JSON.parse(chunk.toString('utf8'));
    if (type === 0x004e4942) binary = chunk;
    offset += 8 + length;
  }
  const cache = new Map();
  function accessor(index) {
    if (cache.has(index)) return cache.get(index);
    const item = document.accessors[index], view = document.bufferViews[item.bufferView];
    if (item.sparse) throw Error('Sparse accessor requires a separate decoder');
    const width = {SCALAR:1,VEC2:2,VEC3:3,VEC4:4,MAT4:16}[item.type];
    const size = {5120:1,5121:1,5122:2,5123:2,5125:4,5126:4}[item.componentType];
    const read = {5120:'readInt8',5121:'readUInt8',5122:'readInt16LE',5123:'readUInt16LE',5125:'readUInt32LE',5126:'readFloatLE'}[item.componentType];
    const start = (view.byteOffset || 0) + (item.byteOffset || 0), stride = view.byteStride || width * size;
    const rows = Array.from({length:item.count}, (_, i) => Array.from({length:width}, (_, k) => binary[read](start + i * stride + k * size)));
    if (rows.some(row => row.some(x => !Number.isFinite(x)))) throw Error(`Nonfinite accessor ${index}`);
    cache.set(index, rows); return rows;
  }
  const fingerprint = value => hash(JSON.stringify(value));
  function animationFingerprint(animation) {
    return fingerprint(animation.channels.map(channel => {
      const sampler = animation.samplers[channel.sampler];
      return [document.nodes[channel.target.node].name, channel.target.path, sampler.interpolation || 'LINEAR', accessor(sampler.input), accessor(sampler.output)];
    }).sort((a,b) => `${a[0]}/${a[1]}`.localeCompare(`${b[0]}/${b[1]}`)));
  }
  const rigFingerprint = fingerprint({nodes:document.nodes.map(({name,children,translation,rotation,scale,matrix,skin,mesh})=>({name,children,translation,rotation,scale,matrix,skin,mesh})),skins:document.skins.map(s=>({joints:s.joints,skeleton:s.skeleton,inverseBindMatrices:accessor(s.inverseBindMatrices)}))});
  const meshFingerprint = fingerprint(document.meshes.map(mesh => mesh.primitives.map(p => ({material:p.material,mode:p.mode,indices:p.indices === undefined ? null : accessor(p.indices),attributes:Object.fromEntries(Object.entries(p.attributes).map(([name,index])=>[name,accessor(index)]))}))));
  const imageFingerprint = fingerprint((document.images || []).map(im => im.bufferView === undefined ? im.uri : hash(binary.subarray(document.bufferViews[im.bufferView].byteOffset || 0,(document.bufferViews[im.bufferView].byteOffset || 0) + document.bufferViews[im.bufferView].byteLength))));
  return {document,accessor,animationFingerprint,rigFingerprint,meshFingerprint,imageFingerprint,bytes:buffer.length};
}
const current = load('art/player_mecha_animated.glb'), incoming = load(source);
const oldAnimations = new Map(current.document.animations.map(a=>[a.name,a]));
const length = (model,a) => Math.max(...a.samplers.map(s=>model.accessor(s.input).at(-1)[0]));
const round = x => Math.round(x*10000)/10000;
const angle = (a,b) => 2*Math.acos(Math.min(1,Math.abs(a.reduce((s,x,i)=>s+x*b[i],0)/(Math.hypot(...a)*Math.hypot(...b)))))*180/Math.PI;
const groups = [
  ['Priorité : présence', ['idle','standing_relax','look_around','wait','scratch','fold_arms','turn','warm_up']],
  ['Priorité : impacts', ['hit_to_body_01','hit_to_body_02','hit_to_head','hit_to_side','hit_to_stomach','fall']],
  ['Priorité : manches', ['greet_01','greet_02','greet_03','greet_04','agree','bow','cheer','defeat_02','defeat_03','frustrated_01','frustrated_02','depressed','wave_goodbye_01','wave_goodbye_02']],
  ['Combat à adapter', ['box_01','box_02','box_03','slash','chop','cast_a_spell','fire','pitch_baseball','football_catch','front_kick_01','front_kick_02']],
  ['Déplacement à adapter', ['walk','run','run_upstairs','jump','jump_down','climb','dive','flip','flee_01','flee_02','surf']],
];
const animations = incoming.document.animations.map((a,index)=> {
  let maxEndpointRotation = 0, maxEndpointTranslation = 0, constantChannels = 0;
  const movingBones = new Set(), rootMotion = [], interpolations = new Set();
  for (const c of a.channels) {
    const s = a.samplers[c.sampler], rows = incoming.accessor(s.output), times = incoming.accessor(s.input);
    const bone = incoming.document.nodes[c.target.node].name;
    const changed = rows.some(row=>row.some((x,i)=>Math.abs(x-rows[0][i])>1e-6));
    if (changed) movingBones.add(bone); else constantChannels++;
    for(let i=1;i<times.length;i++) if(times[i][0] <= times[i-1][0]) throw Error(`Invalid timeline ${a.name}`);
    interpolations.add(s.interpolation || 'LINEAR');
    if(c.target.path==='rotation') maxEndpointRotation=Math.max(maxEndpointRotation,angle(rows[0],rows.at(-1)));
    if(c.target.path==='translation') maxEndpointTranslation=Math.max(maxEndpointTranslation,Math.hypot(...rows.at(-1).map((x,i)=>x-rows[0][i])));
    if (/Hips$|Pelvis$|Root$/i.test(bone) && c.target.path==='translation') {
      const min = [0,1,2].map(i=>Math.min(...rows.map(r=>r[i]))), max=[0,1,2].map(i=>Math.max(...rows.map(r=>r[i])));
      rootMotion.push({bone,start:rows[0].map(round),end:rows.at(-1).map(round),delta:rows.at(-1).map((x,i)=>round(x-rows[0][i])),range:max.map((x,i)=>round(x-min[i]))});
    }
  }
  const group = groups.find(([,names])=>names.includes(a.name))?.[0] || 'Expressif / contexte spécifique';
  return {name:a.name,index,duration:round(length(incoming,a)),group,channels:a.channels.length,constantChannels,movingBones:movingBones.size,interpolations:[...interpolations],rootMotion,maxEndpointRotationDegrees:round(maxEndpointRotation),maxEndpointTranslation:round(maxEndpointTranslation),existing:oldAnimations.has(a.name),identicalToExisting:oldAnimations.has(a.name) ? incoming.animationFingerprint(a)===current.animationFingerprint(oldAnimations.get(a.name)) : null,sheet:`sheet-${String(Math.floor(index/6)+1).padStart(2,'0')}.png`,row:index%6};
});
const meshDifferences = [];
for (let i=0; i<incoming.document.meshes.length; i++) {
  const left=current.document.meshes[i],right=incoming.document.meshes[i];
  for(let p=0;p<right.primitives.length;p++) {
    const a=left.primitives[p],b=right.primitives[p];
    for(const [name,index] of Object.entries(b.attributes)) {
      const old=current.accessor(a.attributes[name]),next=incoming.accessor(index);
      let different=0,maxDelta=0;
      next.forEach((row,r)=>row.forEach((x,c)=>{const delta=Math.abs(x-old[r]?.[c]);if(delta>0)different++;maxDelta=Math.max(maxDelta,delta);}));
      if(different)meshDifferences.push({mesh:i,attribute:name,different,maxDelta});
    }
  }
}
const duplicateMap = new Map();
for(const animation of incoming.document.animations) {
  const signature=incoming.animationFingerprint(animation);
  if(!duplicateMap.has(signature))duplicateMap.set(signature,[]);
  duplicateMap.get(signature).push(animation.name);
}
const report = {
  sourceName:path.basename(source),sourceBytes:incoming.bytes,currentBytes:current.bytes,
  incomingAnimationCount:animations.length,currentAnimationCount:oldAnimations.size,newAnimationCount:animations.filter(a=>!a.existing).length,
  totalDurationSeconds:round(animations.reduce((s,a)=>s+a.duration,0)),joints:incoming.document.skins[0].joints.length,meshes:incoming.document.meshes.length,
  compatibility:{sameRig:current.rigFingerprint===incoming.rigFingerprint,sameMeshData:current.meshFingerprint===incoming.meshFingerprint,sameEmbeddedImages:current.imageFingerprint===incoming.imageFingerprint,missingExistingAnimations:[...oldAnimations.keys()].filter(name=>!animations.some(a=>a.name===name)),sharedAnimationDataIdentical:animations.filter(a=>a.existing).every(a=>a.identicalToExisting)},
  meshDifferences,identicalClipGroups:[...duplicateMap.values()].filter(names=>names.length>1),
  measurements:'Raw GLB units and local joint endpoints; no Godot gameplay scaling. Endpoint rotation is a screening metric, not proof of a seamless loop. Captures at 5%, 35%, 65% and 95%, horizontal hips travel removed for display only.',
  animations
};
fs.mkdirSync(destination,{recursive:true});
fs.writeFileSync(path.join(destination,'report.json'),JSON.stringify(report,null,2)+'\n');
const template=fs.readFileSync('tools/mecha_animation_review.html','utf8');
fs.writeFileSync(path.join(destination,'review.html'),template.replace('__REPORT_JSON__',JSON.stringify(report).replaceAll('<','\\u003c')));
fs.copyFileSync('tools/review_mecha_animations.gd',path.join(destination,'review_mecha_animations.gd'));
console.log(JSON.stringify({...report,animations:undefined},null,2));
if(process.argv.includes('--serve')) {
  const server=http.createServer((request,response)=>{
    const requested=decodeURIComponent(new URL(request.url,'http://localhost').pathname);
    const file=path.resolve(destination,'.'+(requested==='/'?'/review.html':requested));
    if(!file.startsWith(destination+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){response.writeHead(404);response.end('Not found');return;}
    response.setHeader('Content-Type',({'.html':'text/html; charset=utf-8','.json':'application/json','.png':'image/png'})[path.extname(file)]||'text/plain; charset=utf-8');
    fs.createReadStream(file).pipe(response);
  });
  server.listen(8768,'127.0.0.1',()=>console.log('MECHA_REVIEW_URL: http://127.0.0.1:8768/review.html'));
}

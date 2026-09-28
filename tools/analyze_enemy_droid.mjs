// Read-only source GLB diagnostics. Run: node tools/analyze_enemy_droid.mjs
// No Godot import cache or source asset is modified.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const radToDeg = 180 / Math.PI;
const dot = (a, b) => a.reduce((sum, value, i) => sum + value * b[i], 0);
const norm = a => Math.sqrt(dot(a, a));
const normalized = a => a.map(value => value / norm(a));
const add = (a, b) => a.map((value, i) => value + b[i]);
const subtract = (a, b) => a.map((value, i) => value - b[i]);
const scale = (a, k) => a.map(value => value * k);
const qAngle = (a, b) => 2 * Math.acos(Math.min(1, Math.abs(dot(normalized(a), normalized(b))))) * radToDeg;
function multiply(a, b) {
  const [x, y, z, w] = a, [X, Y, Z, W] = b;
  return [w*X+x*W+y*Z-z*Y, w*Y-x*Z+y*W+z*X, w*Z+x*Y-y*X+z*W, w*W-x*X-y*Y-z*Z];
}
function rotate(q, v) {
  return multiply(multiply(q, [...v, 0]), [-q[0], -q[1], -q[2], q[3]]).slice(0, 3);
}
function slerp(a, b, fraction) {
  a = normalized(a); b = normalized(b);
  let cosine = dot(a, b);
  if (cosine < 0) { b = scale(b, -1); cosine = -cosine; }
  if (cosine > 0.9995) return normalized(add(scale(a, 1 - fraction), scale(b, fraction)));
  const angle = Math.acos(Math.min(1, cosine));
  return add(scale(a, Math.sin((1-fraction)*angle)/Math.sin(angle)), scale(b, Math.sin(fraction*angle)/Math.sin(angle)));
}

function loadGlb(relativePath) {
  const buffer = fs.readFileSync(path.isAbsolute(relativePath) ? relativePath : path.join(root, relativePath));
  if (buffer.readUInt32LE(0) !== 0x46546c67 || buffer.readUInt32LE(4) !== 2) throw Error('Expected glTF 2.0 binary');
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
    const width = {SCALAR:1,VEC2:2,VEC3:3,VEC4:4,MAT4:16}[item.type];
    const size = {5120:1,5121:1,5122:2,5123:2,5125:4,5126:4}[item.componentType];
    const read = {5120:'readInt8',5121:'readUInt8',5122:'readInt16LE',5123:'readUInt16LE',5125:'readUInt32LE',5126:'readFloatLE'}[item.componentType];
    const start = (view.byteOffset || 0) + (item.byteOffset || 0), stride = view.byteStride || width * size;
    const data = Array.from({length:item.count}, (_, i) => Array.from({length:width}, (_, k) => binary[read](start + i * stride + k * size)));
    cache.set(index, data); return data;
  }
  const parents = new Map();
  document.nodes.forEach((node, index) => (node.children || []).forEach(child => parents.set(child, index)));
  function channels(animation) {
    return new Map(animation.channels.map(channel => {
      const sampler = animation.samplers[channel.sampler];
      return [`${channel.target.node}/${channel.target.path}`, {times:accessor(sampler.input).map(t => t[0]), values:accessor(sampler.output), interpolation:sampler.interpolation || 'LINEAR'}];
    }));
  }
  function sample(tracks, node, property, time) {
    const track = tracks.get(`${node}/${property}`);
    if (!track) return document.nodes[node][property] || (property === 'rotation' ? [0,0,0,1] : property === 'scale' ? [1,1,1] : [0,0,0]);
    if (time <= track.times[0]) return track.values[0];
    let i = 1;
    while (i < track.times.length && track.times[i] < time) ++i;
    if (i === track.times.length) return track.values.at(-1);
    if (track.interpolation === 'STEP') return track.values[i - 1];
    if (track.interpolation !== 'LINEAR') throw Error(`Unsupported interpolation: ${track.interpolation}`);
    const fraction = (time - track.times[i - 1])/(track.times[i] - track.times[i - 1]);
    return property === 'rotation' ? slerp(track.values[i - 1], track.values[i], fraction) : add(scale(track.values[i - 1], 1-fraction), scale(track.values[i], fraction));
  }
  function pose(tracks, time) {
    const poses = new Map();
    function global(index) {
      if (poses.has(index)) return poses.get(index);
      const p = sample(tracks, index, 'translation', time), q = sample(tracks, index, 'rotation', time), s = sample(tracks, index, 'scale', time);
      let result = {p,q,s};
      if (parents.has(index)) {
        const parent = global(parents.get(index));
        result = {p:add(parent.p, rotate(parent.q, p.map((v, i) => v * parent.s[i]))),q:multiply(parent.q,q),s:s.map((v,i) => v * parent.s[i])};
      }
      poses.set(index, result); return result;
    }
    document.nodes.forEach((_, i) => global(i)); return poses;
  }
  return {document, accessor, channels, sample, pose};
}

const source = process.argv[2] || 'C:/Users/Ben/Downloads/humanoid+combat+robot+3d+model (1).glb';
const model = loadGlb(source), g = model.document;
const indexOf = name => g.nodes.findIndex(n => n.name?.split(':').at(-1) === name);
const nameOf = i => g.nodes[i]?.name;
const parents = new Map();
g.nodes.forEach((n,i) => (n.children || []).forEach(c => parents.set(c,i)));
const hips = indexOf('Hips'), right = indexOf('RightHand'), left = indexOf('LeftHand');
const cross = (a,b) => [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]];
const rounded = value => JSON.parse(JSON.stringify(value, (_,v) => typeof v === 'number' ? Math.round(v*1e6)/1e6 : v));
const range = values => ({min:[0,1,2].map(k=>Math.min(...values.map(v=>v[k]))),max:[0,1,2].map(k=>Math.max(...values.map(v=>v[k])))});
const transformPoint = (p,q,s,v) => add(p,rotate(q,v.map((x,i)=>x*s[i])));
const applyMatrix = (m,v) => [0,1,2].map(i=>m[i]*v[0]+m[i+4]*v[1]+m[i+8]*v[2]+m[i+12]);
function direction(pose) {
  // Anatomical left-to-right cross up: front inferred from hip arrangement.
  const r=pose.get(indexOf('RightUpLeg')).p, l=pose.get(indexOf('LeftUpLeg')).p;
  const axis=subtract(r,l); axis[1]=0;
  return normalized(cross([0,1,0], axis));
}
function poseSummary(pose) {
  const picked=['Hips','Spine2','Head','RightArm','RightForeArm','RightHand','LeftArm','LeftForeArm','LeftHand','RightFoot','LeftFoot'];
  return {anatomicalForward:direction(pose), joints:Object.fromEntries(picked.map(name=>[name,{position:pose.get(indexOf(name)).p,rotation:pose.get(indexOf(name)).q}]))};
}
function skinnedBounds(pose) {
  const all=[];
  for (const node of g.nodes) {
    if(node.mesh===undefined) continue;
    const skin=g.skins[node.skin], bind=model.accessor(skin.inverseBindMatrices);
    for(const primitive of g.meshes[node.mesh].primitives) {
      const positions=model.accessor(primitive.attributes.POSITION), joints=model.accessor(primitive.attributes.JOINTS_0), weights=model.accessor(primitive.attributes.WEIGHTS_0);
      positions.forEach((position,vi)=>{
        let out=[0,0,0];
        for(let c=0;c<4;c++) {
          if(weights[vi][c]===0)continue;
          const ji=joints[vi][c], jp=pose.get(skin.joints[ji]);
          const point=transformPoint(jp.p,jp.q,jp.s,applyMatrix(bind[ji],position));
          out=add(out,scale(point,weights[vi][c]));
        }
        all.push(out);
      });
    }
  }
  return range(all);
}
const rest=model.pose(new Map(),0);
const report={source,format:'glTF 2.0 binary',generator:g.asset.generator,units:'source GLTF scene units; normally metres',notes:['glTF animations do not encode a standard looping flag. Playback loop modes must be selected in Godot, not inferred as authored metadata.','All rotation interpolation is quaternion slerp; sampling is at 60 Hz plus exact endpoint.','Anatomical forward is inferred from the hip arrangement; final visual orientation must also be verified in Godot.'],sceneRoots:g.scenes[g.scene||0].nodes.map(nameOf),skinCount:g.skins.length,skins:g.skins.map(s=>({name:s.name,jointCount:s.joints.length,root:nameOf(hips)})),bones:g.skins[0].joints.map((i,skinJointIndex)=>({skinJointIndex,nodeIndex:i,name:nameOf(i),parent:nameOf(parents.get(i)),children:(g.nodes[i].children||[]).map(nameOf),restLocal:{translation:g.nodes[i].translation||[0,0,0],rotation:g.nodes[i].rotation||[0,0,0,1],scale:g.nodes[i].scale||[1,1,1]}})),meshes:{count:g.meshes.length,vertexCount:g.meshes.reduce((sum,m)=>sum+m.primitives.reduce((s,p)=>s+g.accessors[p.attributes.POSITION].count,0),0),bindBounds:range(g.meshes.flatMap(m=>m.primitives.flatMap(p=>[g.accessors[p.attributes.POSITION].min,g.accessors[p.attributes.POSITION].max]))),restSkinnedBounds:skinnedBounds(rest)},rest:poseSummary(rest),animations:[]};
for(const animation of g.animations) {
  const tracks=model.channels(animation);
  const duration=Math.max(...animation.samplers.flatMap(s=>model.accessor(s.input).map(t=>t[0])));
  const times=Array.from({length:Math.ceil(duration*60)+1},(_,i)=>Math.min(i/60,duration));
  const localPositions=times.map(t=>model.sample(tracks,hips,'translation',t));
  const globalPoses=times.map(t=>model.pose(tracks,t));
  const globalPositions=globalPoses.map(p=>p.get(hips).p);
  const endpointDelta=subtract(globalPositions.at(-1),globalPositions[0]);
  const horizontalPathLength=globalPositions.slice(1).reduce((sum,p,i)=>sum+Math.hypot(p[0]-globalPositions[i][0],p[2]-globalPositions[i][2]),0);
  const significantTracks=[...tracks.entries()].filter(([key,t])=>key.endsWith('/translation')).map(([key,t])=>({node:nameOf(Number(key.split('/')[0])),range:range(t.values),delta:subtract(t.values.at(-1),t.values[0])})).filter(t=>norm(subtract(t.range.max,t.range.min))>1e-4);
  const firstPose=globalPoses[0],lastPose=globalPoses.at(-1);
  const joints=g.skins[0].joints;
  const item={name:animation.name,duration,channelCount:animation.channels.length,loop:'unspecified in glTF',interpolations:[...new Set(animation.samplers.map(s=>s.interpolation||'LINEAR'))],extras:animation.extras||null,root:{node:nameOf(hips),start:globalPositions[0],end:globalPositions.at(-1),delta:endpointDelta,localRange:range(localPositions),worldRange:range(globalPositions),horizontalPathLength,netHorizontalSpeed:Math.hypot(endpointDelta[0],endpointDelta[2])/duration},significantTranslationTracks:significantTracks,orientation:{startForward:direction(firstPose),endForward:direction(lastPose),hipsQuaternionStart:firstPose.get(hips).q,hipsQuaternionEnd:lastPose.get(hips).q,startToEndDegrees:qAngle(firstPose.get(hips).q,lastPose.get(hips).q)},loopSeam:{maximumJointRotationDeltaDegrees:Math.max(...joints.map(i=>qAngle(model.sample(tracks,i,'rotation',0),model.sample(tracks,i,'rotation',duration)))),hipsPositionDelta:norm(endpointDelta)},samples:[0,0.25,0.5,0.75,1].map(f=>({time:f*duration,...poseSummary(model.pose(tracks,f*duration))}))};
  item.loopSeam.worstJoints=joints.map(i=>({name:nameOf(i),degrees:qAngle(model.sample(tracks,i,'rotation',0),model.sample(tracks,i,'rotation',duration))})).sort((a,b)=>b.degrees-a.degrees).slice(0,5);
  if(['idle','run','walk','fire','fall'].includes(animation.name))item.skinnedBounds=[0,.5,1].map(f=>({time:f*duration,...skinnedBounds(model.pose(tracks,f*duration))}));
  if(animation.name==='fire') {
    const upper=['Spine','Spine1','Spine2','RightShoulder','RightArm','RightForeArm','RightHand','LeftShoulder','LeftArm','LeftForeArm','LeftHand','Neck','Head'].map(indexOf);
    item.aimCandidates=times.filter(t=>t>=.05&&t<=duration-.05).map(t=>{
      const velocities=upper.map(i=>qAngle(model.sample(tracks,i,'rotation',t-.05),model.sample(tracks,i,'rotation',t+.05))/.1);
      const a=model.pose(tracks,t-.05),b=model.pose(tracks,t+.05),p=model.pose(tracks,t);
      return {time:t,rmsLocalDegreesPerSecond:Math.sqrt(velocities.reduce((s,v)=>s+v*v,0)/velocities.length),maxLocalDegreesPerSecond:Math.max(...velocities),rightHandSpeed:norm(subtract(a.get(right).p,b.get(right).p))/.1,rightHand:p.get(right),leftHand:p.get(left),hips:p.get(hips),forward:direction(p)};
    }).sort((a,b)=>a.rmsLocalDegreesPerSecond-b.rmsLocalDegreesPerSecond).slice(0,12);
    item.handTimeline=Array.from({length:Math.floor(duration*10)+1},(_,i)=>{const t=i/10,p=model.pose(tracks,t);return {time:t,rightHand:p.get(right),leftHand:p.get(left),hips:p.get(hips)};});
    item.upperBodyAngularRange=upper.map(i=>{
      const qs=times.map(t=>model.sample(tracks,i,'rotation',t));
      let diameter=0;
      for(let a=0;a<qs.length;a++)for(let b=a+1;b<qs.length;b++)diameter=Math.max(diameter,qAngle(qs[a],qs[b]));
      return {name:nameOf(i),maxPairwiseDegrees:diameter};
    });
    item.handMotion={rightRange:range(globalPoses.map(p=>p.get(right).p)),leftRange:range(globalPoses.map(p=>p.get(left).p)),rightMaximumGlobalRotationFromStartDegrees:Math.max(...globalPoses.map(p=>qAngle(p.get(right).q,firstPose.get(right).q)))};
  }
  if(animation.name==='run') {
    const lower=['Hips','LeftUpLeg','LeftLeg','LeftFoot','RightUpLeg','RightLeg','RightFoot'].map(indexOf);
    const candidates=[];
    for(let start=0;start<=.3;start+=1/24)for(let end=duration;end>=.8;end-=1/24) {
      if(end-start<.8)continue;
      const ds=lower.map(i=>qAngle(model.sample(tracks,i,'rotation',start),model.sample(tracks,i,'rotation',end)));
      candidates.push({start,end,length:end-start,maxJointDelta:Math.max(...ds),rmsJointDelta:Math.sqrt(ds.reduce((s,d)=>s+d*d,0)/ds.length),hipsYDelta:model.sample(tracks,hips,'translation',end)[1]-model.sample(tracks,hips,'translation',start)[1]});
    }
    item.loopCropCandidates=candidates.sort((a,b)=>a.rmsJointDelta-b.rmsJointDelta).slice(0,6);
  }
  report.animations.push(item);
}
fs.mkdirSync(path.join(root,'docs'),{recursive:true});
fs.writeFileSync(path.join(root,'docs/enemy_droid_source_audit.json'),JSON.stringify(rounded(report),null,2)+'\n');
console.log(JSON.stringify(rounded({meshes:report.meshes,restForward:report.rest.anatomicalForward,animations:report.animations.map(a=>({name:a.name,duration:a.duration,root:a.root,orientation:a.orientation,loopSeam:a.loopSeam})),aimCandidates:report.animations.find(a=>a.name==='fire').aimCandidates.slice(0,3)}),null,2));

// Read-only GLB diagnostics. Run: node tools/analyze_aim_pose.mjs
// No Godot import cache or source asset is modified.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outputOption = process.argv.find(arg => arg.startsWith('--json-output='));
const sampleOption = process.argv.find(arg => arg.startsWith('--sample='));
const report = {};
function emit(label, value) {
  report[label.replace(/:$/, '')] = typeof value === 'string' && /^[\[{]/.test(value) ? JSON.parse(value) : value ?? true;
  console.log(label, value ?? '');
}
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
  const buffer = fs.readFileSync(path.join(root, relativePath));
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

const model = loadGlb('art/player_mecha_animated.glb');
const animations = model.document.animations || [];
const animationNames = animations.map(a => ({name:a.name, duration:Math.max(...a.samplers.flatMap(s => model.accessor(s.input).map(v => v[0]))),channels:a.channels.length}));
emit('Animations:', JSON.stringify(animationNames, null, 2));
emit('Skeleton joints:', model.document.skins?.[0]?.joints.length);
const fire = animations.find(a => a.name.toLowerCase() === 'fire');
const idle = animations.find(a => a.name.toLowerCase() === 'idle');
if (!fire || !idle) throw Error('fire/idle not found');
const fireTracks = model.channels(fire), idleTracks = model.channels(idle);
const sourceDuration = animationNames.find(a => a.name === fire.name).duration;
const wanted = ['Spine','Spine1','Spine2','RightShoulder','RightArm','RightForeArm','RightHand','LeftShoulder','LeftArm','LeftForeArm','LeftHand','Neck','Head'];
const joints = wanted.map(name => ({name,index:model.document.nodes.findIndex(node => node.name?.split(':').at(-1) === name)})).filter(j => j.index >= 0);
const samples = Array.from({length:Math.round(sourceDuration*60)+1}, (_, i) => i/60);
// Each candidate is evaluated with an equal, centred 100 ms window, excluding
// boundaries: clamped endpoints would spuriously appear more stable.
const halfWindow = 0.05;
const scores = samples.filter(t => t >= halfWindow && t <= sourceDuration-halfWindow).map(time => {
  const velocities = joints.map(j => qAngle(model.sample(fireTracks,j.index,'rotation',time-halfWindow),model.sample(fireTracks,j.index,'rotation',time+halfWindow))/(2*halfWindow));
  return {time, rmsDegreesPerSecond:Math.sqrt(velocities.reduce((s,x) => s+x*x,0)/velocities.length), maxDegreesPerSecond:Math.max(...velocities)};
}).sort((a,b) => a.rmsDegreesPerSecond-b.rmsDegreesPerSecond || a.time-b.time);
const selectedTime = sampleOption ? Number(sampleOption.slice('--sample='.length)) : scores[0].time;
if (!Number.isFinite(selectedTime) || selectedTime < 0 || selectedTime > sourceDuration) throw Error('Sample time must be within fire duration');
emit('Stable frame metric:', 'RMS local angular velocity, thirteen upper-body joints, centred 100 ms window, 60 Hz candidates.');
emit('Best candidates:', JSON.stringify(scores.slice(0, 10),null,2));
emit('Measured sample:', JSON.stringify({time:selectedTime,frameAt60Hz:Math.round(selectedTime*60),source:sampleOption ? 'Explicit sample for comparison with imported Godot clip' : 'Raw GLB minimum',note:'Godot import optimization can shift the minimum; raw data are measured here.'}));
const hipsIndex = model.document.nodes.findIndex(node => node.name?.split(':').at(-1) === 'Hips');
emit('Hips rotation relative to idle start:', JSON.stringify(['idle','fire','run','walk'].map(name => {
  const animation = animations.find(a => a.name === name), tracks=model.channels(animation);
  const length=animationNames.find(a => a.name===name).duration;
  const base=model.sample(idleTracks,hipsIndex,'rotation',0);
  const rotations=Array.from({length:Math.ceil(length*60)+1},(_,i)=>model.sample(tracks,hipsIndex,'rotation',Math.min(i/60,length)));
  return {name,startDegrees:qAngle(base,rotations[0]),maxDegrees:Math.max(...rotations.map(q=>qAngle(base,q)))};
}),null,2));
emit('Joint differences:', JSON.stringify(joints.map(j => {
  const rotations = samples.map(time => model.sample(fireTracks,j.index,'rotation',time));
  const translations = samples.map(time => model.sample(fireTracks,j.index,'translation',time));
  let diameter = 0;
  for (let a=0; a<rotations.length; ++a) for (let b=a+1; b<rotations.length; ++b) diameter = Math.max(diameter,qAngle(rotations[a],rotations[b]));
  return {bone:j.name,fireMaxPairwiseDegrees:diameter,idleStartToFireStartDegrees:qAngle(model.sample(idleTracks,j.index,'rotation',0),rotations[0]),idleStartToSelectedDegrees:qAngle(model.sample(idleTracks,j.index,'rotation',0),model.sample(fireTracks,j.index,'rotation',selectedTime)),fireMaxTranslationFromStart:Math.max(...translations.map(p=>norm(subtract(p,translations[0]))))};
}),null,2));
const firePose = model.pose(fireTracks,selectedTime), idlePose = model.pose(idleTracks,0);
// Production's ModelAxisCorrection is yaw PI with uniform scale 2.0.
const toGameplay = p => [-p[0]*2,p[1]*2,-p[2]*2];
emit('Hands in gameplay model space:', JSON.stringify(joints.filter(j => /Hand|Arm|Shoulder/.test(j.name)).map(j => ({name:j.name,fire:toGameplay(firePose.get(j.index).p),idle:toGameplay(idlePose.get(j.index).p),worldRotationChangeDegrees:qAngle(firePose.get(j.index).q,idlePose.get(j.index).q)})),null,2));
const left = joints.find(j => j.name === 'LeftHand');
const shoulder = joints.find(j => j.name === 'LeftArm');
const elbow = joints.find(j => j.name === 'LeftForeArm');
const grip = [0.58,0.93+0.06,-0.42-0.48];
const leftPos = toGameplay(firePose.get(left.index).p), shoulderPos=toGameplay(firePose.get(shoulder.index).p), elbowPos=toGameplay(firePose.get(elbow.index).p);
emit('Pre-fix fixed profile and LeftHandGrip (source fire pose, no runtime compensation):', JSON.stringify({grip,leftHand:leftPos,distance:norm(subtract(grip,leftPos)),shoulderDistance:norm(subtract(grip,shoulderPos)),upperArmLength:norm(subtract(elbowPos,shoulderPos)),forearmLength:norm(subtract(leftPos,elbowPos))},null,2));
const gun=loadGlb('art/player_heavy_blaster.glb');
emit('Weapon nodes:',JSON.stringify(gun.document.nodes.map(n => ({name:n.name,translation:n.translation,rotation:n.rotation,scale:n.scale,mesh:n.mesh})),null,2));
emit('Weapon mesh bounds:',JSON.stringify(gun.document.meshes.map(mesh => ({name:mesh.name,primitives:mesh.primitives.map(p => {const a=gun.document.accessors[p.attributes.POSITION];return {min:a.min,max:a.max};})})),null,2));
if (outputOption) {
  const destination = path.resolve(root, outputOption.slice('--json-output='.length));
  fs.mkdirSync(path.dirname(destination), {recursive:true});
  fs.writeFileSync(destination, JSON.stringify(report, null, 2) + '\n');
}

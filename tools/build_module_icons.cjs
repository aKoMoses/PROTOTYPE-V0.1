// Hand-drawn vector assets: the same worn ivory / copper / dark steel as Pelto.
// Existing Pelto Smash, Fulguro Punch, Projector and Eclipse remain the references.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..', 'art', 'icons');
const defs = `<defs>
<linearGradient id="plate" x2="1" y2="1"><stop stop-color="#fff0c7"/><stop offset=".48" stop-color="#d8be8e"/><stop offset="1" stop-color="#89755a"/></linearGradient>
<linearGradient id="rust" x2="1" y2="1"><stop stop-color="#eaa457"/><stop offset=".5" stop-color="#b55c32"/><stop offset="1" stop-color="#663d2a"/></linearGradient>
<linearGradient id="steel" x2="1" y2="1"><stop stop-color="#607174"/><stop offset=".5" stop-color="#293a40"/><stop offset="1" stop-color="#142126"/></linearGradient>
<linearGradient id="energy" x2="0" y2="1"><stop stop-color="#dcffff"/><stop offset=".5" stop-color="#69e5e0"/><stop offset="1" stop-color="#318a9d"/></linearGradient>
</defs>`;
const p = (d, fill='plate', width=6) => `<path d="${d}" fill="${fill.startsWith('#') ? fill : `url(#${fill})`}" stroke="#172126" stroke-width="${width}" stroke-linejoin="round"/>`;
const line = (d, color='#8de8dc', width=4) => `<path d="${d}" fill="none" stroke="${color}" stroke-width="${width}" stroke-linecap="round" stroke-linejoin="round"/>`;
const circle = (x,y,r,fill='plate',width=5) => `<circle cx="${x}" cy="${y}" r="${r}" fill="${fill.startsWith('#') ? fill : `url(#${fill})`}" stroke="#172126" stroke-width="${width}"/>`;
const bolts = (...pairs) => pairs.map(([x,y]) => circle(x,y,4,'#172126',0)+line(`m${x-2} ${y-1} 4 2`,'#dfbe88',1.5)).join('');
const scratches = d => line(d,'#806849',2);
const icons = {};

// Javelin: unmistakable three-pronged electrical lance, thicker at mobile size.
icons.javelin = p('m61 213 24 13 82-127-20-13Z','steel') + p('m55 203 37 21-9 16-37-22Z','rust') + p('m94 156 22 13 45-72-20-12Z') + p('m120 109 13-25 24-1 23-19-3-36-15 20-14 8 2-25-10-13-18 44-23 15-5 28Z','steel') + p('m113 97 14-12 29 5 9 17-16 15-29-7Z','rust') + line('m131 88 5-24 13-30m12 56 19-22 7-29m-33 42-11-13 10-28','#8de8dc',7) + line('m72 199 43-65','#fff0c7',4) + line('m189 111 16-12m-91-60 4-15m76 19 13-8','#d8be8e',3) + bolts([125,103],[150,107],[70,215]) + scratches('m107 146 8-12m-42 71 12 6');

// Wall: the two emitter posts and their translucent magnetic barrier.
icons['magnetic-field'] = p('m33 176 31-27 127 1 31 29-6 39H42Z','steel') + p('m37 180 29-20 120 1 28 19-12 23H49Z') + p('m43 159-4-103 15-20 26 2 8 20-2 97-18 15Z') + p('m174 158-3-103 17-17 25 2 8 20-5 103-20 10Z') + p('m80 70q42-27 96 1v87q-48-22-92-1Z','energy',4) + line('M87 85q42-21 82 0m-81 20q39-19 80 0m-80 22q38-15 78 0','#dcffff',3) + p('m86 178 82 1-2 17-78-1Z','steel',4) + line('m100 186 50 1','#8de8dc',5) + p('m50 58 9-11 12 3-1 94-12 7Z','rust',4) + p('m186 59 9-10 14 3-3 100-13 6Z','rust',4) + bolts([56,174],[195,174],[47,194],[200,197]) + scratches('m46 72 7-5m132 166 17 1m54 188 11 1') + line('M31 118H17m220-1h-12','#8de8dc',4);

// Static Shield: a plated forearm guard with a bright hexagonal field.
icons['static-shield'] = p('m169 73 40 14 15 37-5 57-41 23-21-29Z','steel') + p('m191 91 16 6 9 29-5 44-23 10-4-16 16-8 3-27-14-11Z') + p('m78 34 70 1 40 41 1 96-40 44-75-2-37-44 2-91Z') + p('m80 55 61-1 31 33-1 74-34 32-54-2-28-34 1-69Z','rust',5) + p('m88 70 43 1 28 29-1 51-30 26-44-2-23-27 1-50Z','steel',5) + p('m94 82 34 1 20 23-1 37-21 21-28-1-21-24 1-37Z','energy',4) + line('m103 96 19 1 11 15-1 23-12 14-18-1-11-15v-22Z','#dcffff',3) + bolts([80,46],[143,48],[51,90],[52,162],[78,203],[144,203],[174,95],[174,163]) + scratches('m62 70 8-10m88 187 13 1m-5-130 11 1m48 70 4 15');

// Two boot thrusters, no thin silhouettes that disappear inside a 50px button.
icons['pyro-boots'] = p('m52 48 53-13 16 34-12 68 27 18-9 32-79-4-17-18 15-44Z','steel') + p('m64 49 34-5 10 27-11 63-44 8 7-47Z') + p('m52 141 49-10 29 26-10 20-64-4-15-14Z','rust') + p('m148 57 46-10 13 33-14 73 31 15-7 24-69 4-24-22 19-45Z','steel') + p('m157 60 29-5 9 27-13 65-32 6 2-52Z') + p('m150 149 36-7 29 28-5 16-57 2-19-16Z','rust') + p('m49 191 12 22 11-19 12 42-25-8-16 9-9-24Z','#ed7730',3) + p('m150 197 14 19 11-20 12 37-24 9-22-14Z','#ed7730',3) + p('m57 194 9 16 5-9 6 26-17-7Z','#ffe4a5',2) + p('m159 200 10 20 6-15 4 25-15-3Z','#ffe4a5',2) + line('m64 72 27-5m63 14 23-4','#8de8dc',5) + bolts([62,152],[114,159],[148,164],[204,175]) + scratches('M78 54l4 9M83 52l6 12M76 112l11-2M77 155l14-2M72 170l12 1');

// Injector: mechanical ampoule with a visible green reservoir and needle.
icons['bio-injector'] = p('m68 29 54 7-7 34-56-8Z','steel') + p('m39 63 90 12-3 19-91-13Z') + p('m57 93 57 5 31 87-37 32-36-38Z','steel') + p('m64 100 32 3 31 78-22 14-17-18Z','energy',5) + p('m55 113-15 9 31 73 18 5 3-21Z','rust',4) + p('m106 103 18-6 33 78-11 14-14-8Z') + p('m96 205 15-10 14 11-19 20Z','rust',4) + line('m110 218 14 22','#d8be8e',6) + line('m77 123 10 1m-5 17 10 1m-5 17 10 1','#dcffff',4) + p('m87 41 17 2-4 15-16-2Z','#8de8dc',2) + line('m179 51 1 26m-14-13h28','#8de8dc',6) + circle(180,64,30,'steel',4) + line('m179 49 1 29m-14-15h28','#8de8dc',6) + bolts([51,77],[111,85],[148,176]) + scratches('m70 33 12 2m-31 35 13 2m54 111 5 9');

// Last stand: broken but still-lit robot core with a vivid warning burst.
icons.baroud = p('m83 43 53-11 49 37 2 77-40 44-67-4-37-42 4-71Z','steel') + p('m78 54 43-12 45 29-4 60-29 26-54-13-19-35Z') + p('m89 95 41-11 24 22-5 34-27 20-34-18-4-25Z','rust',5) + p('m104 108 18-4 13 13-3 15-16 10-13-13Z','energy',3) + p('m78 152 31 2-8 25-26-3Z','rust',4) + p('m138 140 21-11 6 32-28 19-20-4 13-20Z','rust',4) + line('m130 50-12 29 18 13-15 20','#172126',6) + line('m56 103 12-9m8-19 11-5m70 20 12 9','#806849',3) + p('m50 187-29 8 13-32-17-5 34-14m136 47 14-28 18 18 14-5-4 33m-30 121 35-9 16 12-18 10 16 19-36-7Z','#e7a04c',4) + line('m83 211 6 17m36-27 15 20m-89-8-9 6','#e7a04c',4) + bolts([82,64],[153,76],[69,129],[151,150]);

// Omnivamp: an armoured heart, feeding inward, contrasting with the reactor.
icons.omnivamp = p('M128 214 54 147Q26 114 53 75q28-29 64 3l11 12 12-12q32-33 61-2 27 29-2 63Z','steel',7) + p('M128 193 68 141q-22-27-3-48 23-20 53 11l10 14 12-14q27-31 48-8 19 23-1 43Z','rust',5) + p('m107 120 35-5 16 22-29 32-27-20Z','energy',4) + line('m111 136 8-1 7 12 10-18 11 9','#dcffff',4) + p('m25 45 11 40 16-12 18 34 13-7-17-33 17-4Z') + p('m228 47-13 40-14-12-19 33-13-7 16-32-16-6Z') + line('m94 217 18 10m31-8-12 15','#8de8dc',4) + bolts([70,93],[182,97],[128,190]) + scratches('m80 112 8 6m89 12 9 7m-26 52 9 8');

// Rocket basket: four clear rockets in a salvaged mechanical launcher.
icons['rocket-basket'] = p('m37 141 182-1 10 30-16 55-170-1-17-48Z','steel',7) + p('m42 166 168-1 8 15-17 31-150-1-17-27Z','rust',5) + p('m49 143 150-1-3 25-143 1Z') + [0,1,2,3].map((i)=>{const x=48+i*43;const top=40+[16,0,-9,9][i];return p(`m${x} 142 1 ${top-142} 14-25 14 25 1 ${142-top}Z`,'steel',5)+p(`m${x+2} ${top} 13-24 13 24-1 57-24 1Z`,'plate',4)+line(`m${x+6} ${top+27} 18-1`,'#8de8dc',6)+p(`m${x+3} 121-7 20 14-3m${x+23} 121 7 19-14-2Z`,'rust',3);}).join('') + p('m93 182 30-7 28 8-5 22-44 1Z','steel',3) + line('m110 190 20-1','#8de8dc',6) + bolts([50,181],[198,181],[69,212],[181,211]) + scratches('m55 151 22-1m87 0 15-1m-7 46 12 1');

// Counter: a shield turns an incoming strike back outwards.
icons.counter = p('m70 48 53-20 55 22-4 90q-8 37-52 64-44-21-56-60Z','steel',7) + p('m78 67 43-19 42 21-2 65q-6 27-37 51-34-17-43-49Z') + p('m94 78 27-9 26 13-2 46-24 26-26-25Z','rust',4) + line('m51 126-30-9 13-11-19-13','#e6b977',7) + line('M116 109q61-45 107-1m-23-24 25 25-35 10','#172126',17) + line('M116 109q61-45 107-1m-23-24 25 25-35 10','#8de8dc',8) + line('m122 167-1-22','#8de8dc',5) + bolts([83,68],[154,72],[122,182]) + scratches('m91 108 5 9m47 16 4 12');

// Auxiliary reactor: robust octagonal housing, luminous lightning core.
icons['auxiliary-reactor'] = p('m87 31 77 1 51 51v84l-51 53-77-1-48-49-1-85Z','steel',7) + p('m92 43 65 1 43 43-1 73-43 44-61-1-41-43V88Z') + p('m94 68 57 1 29 28-1 56-29 29-54-1-28-29 1-55Z','rust',5) + p('m101 80 44 1 24 23-1 42-23 24-43-1-24-23 1-43Z','steel',4) + p('m133 83-31 45 25-3-11 36 35-49-25 4Z','energy',3) + p('m14 110 26-2v27l-26-1Zm198-2 27 1-1 26-26-1Z','rust',4) + line('m90 57 63 1m-67 134 62 1','#fff0c7',3) + bolts([56,87],[60,165],[189,87],[188,164]) + scratches('m96 50 12 1m49 119 5 6m20-1 5-6');

// Tracker: a mechanical eye in a bracket reticle; three hit indicators.
icons.tracker = line('M48 73V40h35m90 0h35v33m0 102v32h-35m-90 0H48v-32','#172126',14) + line('M48 73V40h35m90 0h35v33m0 102v32h-35m-90 0H48v-32','#d8be8e',7) + p('m28 123 43-41 56-21 57 23 42 39-46 40-55 20-56-22Z','steel',7) + p('m45 123 36-28 46-15 49 16 34 27-37 28-48 15-48-16Z') + circle(126,121,42,'rust',5) + circle(126,121,30,'steel',4) + circle(126,121,22,'energy',3) + circle(126,121,10,'#172126',0) + line('m121 105 9-3','#dcffff',4) + [0,1,2].map(i=>circle(105+i*22,217,5,'energy',2)).join('') + bolts([57,122],[196,121]) + scratches('m68 107 9-8m91 39 9 6');

// Alternator: a split dynamo with two distinct opposing copper arrows.
icons.alternator = line('M43 86Q67 22 137 26q50 1 74 46m-7-37 10 41-40-8M215 171q-29 62-96 61-49-1-76-45m8 35-12-41 41 8','#172126',18) + line('M43 86Q67 22 137 26q50 1 74 46m-7-37 10 41-40-8M215 171q-29 62-96 61-49-1-76-45m8 35-12-41 41 8','#d8be8e',9) + p('m86 76 74-1 23 30-6 57-29 26-61-1-22-26 1-54Z','steel',6) + p('m89 82 37-1-1 98-32-1-22-21 1-54Z') + p('m130 81 25 1 21 27-6 48-25 24-18-1Z','rust',4) + p('m138 88-38 48 27-3-10 38 37-47-27 4Z','energy',3) + bolts([87,97],[158,104],[88,160],[157,161]) + scratches('m82 123 10-5m47 18 11-7');

// Inertia: a weighted armoured fist with horizontal momentum streaks.
icons.inertia = line('M24 91h43M15 116h38m-30 24h32m-12 25h30','#172126',11) + line('M24 91h43M15 116h38m-30 24h32m-12 25h30','#8de8dc',5) + p('m79 88 34-32 44-7 50 30 17 61-39 47-64-4-31-35Z','steel',7) + p('m95 82 18-25 23-4 7 32-24 14Zm45-29 26 2 9 30-23 14Zm32 7 23 9 12 23-27 10Z') + p('m90 105 51-20 47 23-9 45-47 15-32-24Z','rust',5) + p('m125 104 36 2 15 17-24 13-27-12Z') + p('m115 169 65-12 15 27-30 31-40-14Z','steel',5) + line('m134 184 32-10','#8de8dc',6) + bolts([112,113],[169,129],[150,195]) + scratches('m104 71 8 4m42-13 8 5m-37 64 9-5m-4 30 10-4');

for (const [name, body] of Object.entries(icons)) {
  fs.writeFileSync(path.join(root, `${name}.svg`), `<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">\n${defs}\n${body}\n</svg>\n`);
}
console.log(`Built ${Object.keys(icons).length} module icons.`);

// Pre-import the dimmed variants: never loop over pixels on a phone's cast frame.
const modules = [...Object.keys(icons), 'fulguro-punch', 'pelto-smash', 'projector', 'permutation', 'eclipse'];
fs.mkdirSync(path.join(root, 'cooldown'), { recursive: true });
for (const name of modules) {
  const svg = fs.readFileSync(path.join(root, `${name}.svg`), 'utf8');
  const grey = svg.replace(/#[0-9a-f]{6}\b/gi, color => {
    const value = parseInt(color.slice(1), 16);
    const luminance = Math.round(((value >> 16) & 255) * 0.2126 + ((value >> 8) & 255) * 0.7152 + (value & 255) * 0.0722);
    return '#' + luminance.toString(16).padStart(2, '0').repeat(3);
  });
  fs.writeFileSync(path.join(root, 'cooldown', `${name}.svg`), grey);
}
console.log(`Built ${modules.length} pre-imported cooldown variants.`);

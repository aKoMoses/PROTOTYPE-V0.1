// Targeted regressions for the combat presentation pass. Saves are isolated.
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const repo = path.resolve(__dirname, '..');
const engine = process.env.GODOT_CONSOLE || [
  'C:/RomainOpen/perso/Godot_4.7.2/Godot_v4.7.2-stable_win64_console.exe',
  'C:/Users/Ben/Desktop/Prototype 0/Godot_v4.7.2-stable_win64_console.exe',
].find(candidate => fs.existsSync(candidate));
if (!engine || !fs.existsSync(engine)) throw new Error('Set GODOT_CONSOLE to the absolute Godot 4.7.2 console executable path.');
const destination = path.join(repo, 'outputs', 'combat-presence', 'checks');
const selected = process.argv.slice(2);
const suites = selected.length ? selected : [
  'test_combat_presence', 'test_vfx', 'test_vfx_materials', 'test_combat_polish',
  'test_combat_signatures', 'test_game_sfx', 'test_comfort_settings',
  'test_player_visual_rig', 'test_player_aim_core', 'test_shotgun_contact',
  'test_shotgun_reload', 'test_gameplay_fluidity', 'test_hud_layout',
  'test_hud_editor_safety', 'test_industrial_menus', 'test_game_flow',
  'test_visibility', 'test_bush_gameplay', 'test_training_ground',
  'test_mode_pause_reliability', 'test_network_combat', 'test_survival',
];
fs.mkdirSync(destination, { recursive: true });
async function run(suite) {
  return new Promise(resolve => {
    const log = [];
    const child = spawn(engine, ['--headless', '--path', repo, '--script', `res://tools/${suite}.gd`, '--max-fps', '60'], {
      cwd: repo, windowsHide: true,
      env: { ...process.env, APPDATA: path.join(repo, '.godot', 'combat-presence-checks', suite) },
    });
    let timedOut = false;
    const timeout = setTimeout(() => { timedOut = true; child.kill(); }, 180000);
    child.stdout.on('data', chunk => log.push(chunk));
    child.stderr.on('data', chunk => log.push(chunk));
    child.on('error', error => log.push(Buffer.from(String(error))));
    child.on('close', code => {
      clearTimeout(timeout);
      const text = Buffer.concat(log).toString('utf8');
      fs.writeFileSync(path.join(destination, suite + '.log'), text);
      const scriptErrors = text.split(/\r?\n/).filter(line => /SCRIPT ERROR:|Parse Error:|^ERROR:|Assertion failed/.test(line) && !line.includes('Failed to read the root certificate store'));
      const result = { suite, code, timedOut, scriptErrors, summaries: text.split(/\r?\n/).filter(line => /PASS|FAIL|checks|TEST:|TESTS:/.test(line)).slice(-4) };
      console.log(`${suite}: ${code === 0 && !timedOut && !scriptErrors.length ? 'PASS' : 'FAIL'} ${result.summaries.join(' | ')}`);
      resolve(result);
    });
  });
}
(async () => {
  const reportPath = path.join(destination, 'report.json');
  const results = selected.length && fs.existsSync(reportPath) ? JSON.parse(fs.readFileSync(reportPath, 'utf8')) : [];
  for (const suite of suites) {
    const result = await run(suite);
    const existing = results.findIndex(entry => entry.suite === suite);
    if (existing >= 0) results[existing] = result;
    else results.push(result);
    fs.writeFileSync(reportPath, JSON.stringify(results, null, 2));
  }
  const failures = results.filter(result => result.code !== 0 || result.timedOut || result.scriptErrors.length);
  console.log(`COMBAT REGRESSIONS: ${results.length - failures.length}/${results.length} passed`);
  process.exitCode = failures.length ? 1 : 0;
})();

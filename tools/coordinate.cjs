#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { createHash } = require('node:crypto');
const readline = require('node:readline/promises');
const SITE = 'https://prototype-zero-site.vercel.app';
const LABELS = { active: 'en cours', local: 'terminé localement, non publié', interrupted: 'interrompu', published: 'publié', cancelled: 'abandonné' };
function root(cwd = process.cwd()) {
  return execFileSync('git', ['rev-parse', '--show-toplevel'], { cwd, encoding: 'utf8', windowsHide: true }).trim();
}
function files(repo, session) {
  return { config: path.join(repo, '.codex', 'coordination.local.json'), state: path.join(repo, '.codex', 'coordination-state', `${createHash('sha256').update(session).digest('hex')}.json`) };
}
function read(file) { try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return {}; } }
function write(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temp, JSON.stringify(value, null, 2), { mode: 0o600 });
  fs.renameSync(temp, file);
}
async function request(config, body, timeout = 6000) {
  if (body && body.action !== 'pair' && !config.token) throw new Error('Coordination non activée. Lance node tools/coordinate.cjs setup.');
  const response = await fetch(`${config.site || SITE}/api/developments`, {
    method: body ? 'POST' : 'GET', signal: AbortSignal.timeout(timeout),
    headers: { 'Content-Type': 'application/json', ...(config.token ? { Authorization: `Bearer ${config.token}` } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {})
  });
  const result = await response.json();
  if (!response.ok) {
    const messages = { duplicate: 'Cette modification est déjà réservée ou terminée localement. Consulte le site et coordonne-toi avant de continuer.', session_busy: 'Cette conversation a déjà un travail actif. Termine-le avant de changer de sujet.', expired: 'La réservation a expiré. Consulte le tableau et réserve à nouveau avant toute modification.', ownership: 'Cette réservation appartient à une autre conversation.' };
    throw new Error(`${messages[result.error] || result.error || `HTTP ${response.status}`}${result.conflicting ? ` Référence : ${result.conflicting}.` : ''}`);
  }
  return result;
}
function compact(records) {
  const now = Date.now();
  const selected = records.filter(r => r.status !== 'published' || r.updatedAt > now - 14 * 86400000)
    .sort((a, b) => (a.status === 'published') - (b.status === 'published') || b.updatedAt - a.updatedAt);
  const lines = selected.slice(0, 6).map(r => `${r.actor} · ${LABELS[r.status]} · ${r.title.slice(0, 80)}${r.commit ? ` (${r.commit.slice(0, 7)})` : ''}`);
  return `${lines.join('\n') || 'Aucun travail déclaré.'}${selected.length > 6 ? `\n+ ${selected.length - 6} autres sur le site.` : ''}`.slice(0, 850);
}
const SHELL_TOOLS = /^(Bash|exec_command|shell|shell_command)$/;
const GIT_PREFIX = "git(?:\\.exe)?(?:\\s+(?:--no-pager|-C\\s+(?:\"[^\"]+\"|'[^']+'|[^\\s;]+)))*\\s+";
const GIT_DELIVERY = new RegExp(`^${GIT_PREFIX}(?:add|commit|push)\\b`, 'i');
const READ_COMMAND = new RegExp(`^(?:${GIT_PREFIX}(?:status|diff|log|show|rev-parse|ls-files|ls-remote|remote\\s+-v)\\b|rg\\b|Get-(?:Content|ChildItem|Item|Location|Command)\\b|Test-Path\\b|pwd\\b|ls\\b|cat\\b|head\\b|tail\\b)`, 'i');
function shellStatements(command) {
  const statements = [];
  let quote = '', current = '';
  for (let i = 0; i < command.length; i++) {
    const ch = command[i], next = command[i + 1];
    // Ambiguous escaping/interpolation stays on the guarded editing path.
    if (ch === '`' || ch === '\0' || (ch === '$' && next === '(' && quote !== "'")) return null;
    if (quote) {
      current += ch;
      if (ch === '\\' && next === quote) return null;
      if (ch === quote) {
        if (next === quote) { current += next; i++; } else quote = '';
      }
      continue;
    }
    if (ch === '"' || ch === "'") { quote = ch; current += ch; continue; }
    if (ch === ';' || ch === '\n' || ch === '\r' || (ch === '&' && next === '&')) {
      if (current.trim()) statements.push(current.trim());
      current = ''; if (ch === '&') i++; continue;
    }
    if ('|<>&(){}'.includes(ch)) return null;
    current += ch;
  }
  if (quote) return null;
  if (current.trim()) statements.push(current.trim());
  return statements.length ? statements : null;
}
function readCommand(command) {
  // Only the coordination entrypoint is exempt. Arbitrary Node/Python/shell code needs a claim.
  if (/^(?:&\s*)?(?:node|"[^"]*node(?:\.exe)?")\s+["']?(?:[^\r\n"';|&]+[\/])?tools[\/]coordinate\.cjs["']?\s+(?:claim|context|catalog|status|finish|cancel|setup|heartbeat)\b[^\r\n;|&<>]*$/.test(command)) return true;
  return !/--output\b|\b(?:Set-Content|Add-Content|Out-File|Remove-Item|Move-Item|Copy-Item|New-Item|Invoke-Expression)\b/i.test(command) && READ_COMMAND.test(command);
}
function isReadOnly(payload) {
  const name = payload.tool_name || '';
  if (/^(apply_patch|Edit|Write)$/.test(name)) return false;
  if (!SHELL_TOOLS.test(name)) return true;
  const statements = shellStatements(String(payload.tool_input?.command || payload.tool_input?.cmd || '').trim());
  return Boolean(statements && statements.every(readCommand));
}
function isPublicationOnly(payload) {
  if (!SHELL_TOOLS.test(payload.tool_name || '')) return false;
  const statements = shellStatements(String(payload.tool_input?.command || payload.tool_input?.cmd || '').trim());
  return Boolean(statements && statements.some(command => GIT_DELIVERY.test(command)) &&
    statements.every(command => GIT_DELIVERY.test(command) || readCommand(command)));
}
async function touch(config, state, session, action = 'heartbeat', timeout, extras = {}) {
  if (!state.record) throw new Error('Réserve cette modification avant d’écrire : node tools/coordinate.cjs claim --title "Modification précise" --topic "sujet-precis" --sectors "secteur" --files "scripts/fichier.gd"');
  return request(config, { ...extras, action, id: state.record.id, leaseToken: state.record.leaseToken, session }, timeout);
}
async function hook(payload, repo = root(payload.cwd)) {
  const session = payload.session_id;
  if (!session || !/^[a-zA-Z0-9_-]{8,100}$/.test(session)) throw new Error('Identifiant de conversation manquant.');
  const local = files(repo, session), config = read(local.config), state = read(local.state);
  const event = payload.hook_event_name;
  if (event === 'UserPromptSubmit' || event === 'SessionStart') {
    let context;
    try { context = compact((await request(config)).developments); }
    catch { context = 'Tableau indisponible : relis-le avant de modifier le projet.'; }
    return { hookSpecificOutput: { hookEventName: event, additionalContext: `Coordination Prototype 0 (session ${session}).\n${context}\n${config.actor ? `Identité : ${config.actor}.` : 'Activation requise : node tools/coordinate.cjs setup.'}\nAvant le premier changement, consulte AGENTS.md puis réserve avec node tools/coordinate.cjs claim --session ${session}. Questions et lecture : aucune réservation. Site : ${SITE}/repartition.html#developpements` } };
  }
  if (event === 'PreToolUse') {
    if (isReadOnly(payload)) return null;
    try {
      // Staging/committing/pushing verified work checks ownership without reopening editing.
      // Every command in a shell batch must be a delivery step or a permitted read.
      const result = await touch(config, state, session, isPublicationOnly(payload) ? 'check' : 'heartbeat');
      write(local.state, { ...state, record: result.record });
      return null;
    } catch (error) {
      return { hookSpecificOutput: { hookEventName: event, permissionDecision: 'deny', permissionDecisionReason: `${error.message} Session : ${session}.` } };
    }
  }
  if (event === 'Interrupt' || event === 'SessionEnd') {
    if (state.record?.status === 'active') {
      const result = await touch(config, state, session, 'interrupt', 1800);
      write(local.state, { ...state, record: result.record });
    }
  }
  // Stop is deliberately not "finished": the next user prompt can continue the same work.
  return null;
}
function options(args) {
  const result = {};
  for (let i = 0; i < args.length; i += 2) {
    if (!args[i].startsWith('--') || args[i + 1] === undefined) throw new Error('Options attendues : --nom valeur.');
    result[args[i].slice(2)] = args[i + 1];
  }
  return result;
}
async function main() {
  const command = process.argv[2] || 'status';
  if (command === 'hook') {
    await runHook();
    return;
  }
  const repo = root(), opts = options(process.argv.slice(3));
  const session = opts.session || process.env.CODEX_THREAD_ID;
  const local = files(repo, session || 'installation'), config = read(local.config);
  if (command === 'setup') {
    const terminal = readline.createInterface({ input: process.stdin, output: process.stdout });
    try {
      const actor = opts.actor || (await terminal.question('Ton pseudo (akomoses / morepudding) : ')).trim().toLowerCase();
      // Use stdin or a local ignored file, never a command argument that could enter history.
      const code = opts['code-file'] ? fs.readFileSync(opts['code-file'], 'utf8').trim().replace(/^SECTORS_EDIT_CODE=/, '').replace(/^['"]|['"]$/g, '') : (await terminal.question('Code d’édition de la répartition : ')).trim();
      const paired = await request({}, { action: 'pair', actor, code });
      write(local.config, { site: SITE, actor: paired.actor, token: paired.token });
      console.log(`Coordination activée pour ${paired.actor}. Dans Codex, approuve ensuite les hooks du projet avec /hooks, puis ouvre une nouvelle conversation. Aucun secret à committer.`);
    } finally { terminal.close(); }
    return;
  }
  if (command === 'context' || command === 'status') {
    console.log(compact((await request(config)).developments)); return;
  }
  if (command === 'catalog') {
    const response = await fetch(`${SITE}/api/sectors`, { signal: AbortSignal.timeout(6000) });
    if (!response.ok) throw new Error('Secteurs indisponibles.');
    console.log((await response.json()).sectors.filter(s => !s.archived).map(s => `${s.id} : ${s.title}`).join('\n')); return;
  }
  if (!session || !/^[a-zA-Z0-9_-]{8,100}$/.test(session)) throw new Error('Utilise --session avec l’identifiant donné par le hook (ou CODEX_THREAD_ID).');
  const state = read(local.state);
  if (command === 'claim') {
    const result = await request(config, { action: 'claim', session, title: opts.title, topic: opts.topic,
      sectors: (opts.sectors || '').split(',').filter(Boolean), files: (opts.files || '').split(',').filter(Boolean),
      baseCommit: execFileSync('git', ['rev-parse', 'HEAD'], { cwd: repo, encoding: 'utf8', windowsHide: true }).trim() });
    write(local.state, { record: result.record });
    console.log(`Réservé : ${result.record.title}\nRéférence de commit : Prototype-Work: ${result.record.id}`);
    for (const warning of result.warnings || []) console.log(`À vérifier : ${warning.actor} · ${LABELS[warning.status]} · ${warning.title} (${warning.id})`);
    return;
  }
  if (!['finish', 'cancel', 'heartbeat'].includes(command)) throw new Error('Commandes : setup, context, catalog, claim, heartbeat, finish, cancel, status.');
  const result = await touch(config, state, session, command, undefined, command === 'finish' ? { summary: opts.summary || state.record?.title } : {});
  write(local.state, { ...state, record: result.record });
  console.log(`${LABELS[result.record.status]} : ${result.record.title}\nPrototype-Work: ${result.record.id}`);
}
async function runHook() {
  try {
    const chunks = []; for await (const chunk of process.stdin) chunks.push(chunk);
    const result = await hook(JSON.parse(Buffer.concat(chunks).toString('utf8')));
    if (result) process.stdout.write(JSON.stringify(result));
  } catch (error) { process.stderr.write(`Coordination : ${error.message}\n`); process.exitCode = 2; }
}
if (require.main === module) main().catch(error => {
  if (process.argv[2] === 'hook') {
    // A hook must fail closed for guarded writes, including malformed input/network failures.
    process.stderr.write(`Coordination : ${error.message}\n`); process.exitCode = 2;
  } else { console.error(error.message); process.exitCode = 1; }
});
module.exports = { compact, isReadOnly, isPublicationOnly, hook, files, request, runHook };

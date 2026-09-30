const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const { execFile, execFileSync } = require('node:child_process');
const { promisify } = require('node:util');
const { compact, isReadOnly, isPublicationOnly, hook, files } = require('./coordinate.cjs');
test('reads need no claim; shell writes and patches do; only coordination commands are exempt', () => {
  const shell = command => ({ tool_name: 'Bash', tool_input: { command } });
  assert.ok(isReadOnly(shell('git status --short; Get-Content AGENTS.md')));
  assert.ok(isReadOnly(shell('node tools/coordinate.cjs claim --title "Corriger la visée"')));
  for (const command of ['node -e "require(\'fs\').writeFileSync(\'test\',\'x\')"', 'git status; Set-Content test x', 'git status && Set-Content test x', 'Get-Content test > other', 'git commit -m test', 'node tools/coordinate.cjs status; Remove-Item test']) assert.equal(isReadOnly(shell(command)), false);
  assert.equal(isReadOnly({ tool_name: 'apply_patch', tool_input: {} }), false);
});
test('staging, commits and pushes are delivery, including batches and quoted paths', () => {
  const shell = command => ({ tool_name: 'Bash', tool_input: { command } });
  for (const command of ['git add -- tools/coordinate.cjs', 'git commit -m "Sujet; avec ponctuation"', 'git push origin main', 'git add -- file.gd; git diff --cached --check; git commit -m "Fix"; git push origin main', 'git add -- "file; name.gd" && git status --short && git commit -m "Fix"', 'git -C "C:\\Game Project" add -- file.gd\ngit -C "C:\\Game Project" diff --cached --check']) {
    assert.equal(isPublicationOnly(shell(command)), true, command);
  }
  for (const command of ['git status', 'git add -- file.gd; Set-Content file.gd changed', 'git add -- file.gd && node -e "write()"', 'git add -- file.gd | node -e "write()"', 'git reset --hard', 'git add -- "$(Set-Content file.gd changed)"', 'git add -- file.gd; git checkout -- file.gd']) {
    assert.equal(isPublicationOnly(shell(command)), false, command);
  }
});
test('context is bounded and prioritizes unfinished work over published history', () => {
  const records = Array.from({ length: 40 }, (_, index) => ({ actor: 'akomoses', status: index === 39 ? 'local' : 'published', title: 'x'.repeat(120), updatedAt: Date.now(), commit: 'a'.repeat(40) }));
  const text = compact(records);
  assert.ok(text.length <= 850);
  assert.match(text.split('\n')[0], /terminé localement/);
  assert.match(text, /autres sur le site/);
});

test('the CLI reports a resumed reservation and saves its new lease under the existing id', async () => {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'prototype-coordination-resume-cli-'));
  const session = 'resume-cli-test-session', local = files(repo, session);
  const id = 'bdcf58da-7c52-4f4d-ab8e-e19a6701e3a7';
  const record = { id, title: 'Préparer les sons des pièges', status: 'active', leaseToken: 'fresh-test-lease' };
  let seen;
  const server = http.createServer(async (req, res) => {
    let raw = ''; for await (const chunk of req) raw += chunk;
    seen = JSON.parse(raw);
    assert.equal(req.headers.authorization, 'Bearer private-test-token');
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ record, resumed: true, warnings: [] }));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    execFileSync('git', ['init', '--quiet'], { cwd: repo, windowsHide: true });
    execFileSync('git', ['-c', 'user.name=Coordination Test', '-c', 'user.email=coordination@example.invalid', 'commit', '--quiet', '--allow-empty', '-m', 'Fixture'], { cwd: repo, windowsHide: true });
    fs.mkdirSync(path.dirname(local.config), { recursive: true });
    fs.writeFileSync(local.config, JSON.stringify({ actor: 'morepudding', token: 'private-test-token', site: `http://127.0.0.1:${server.address().port}` }));
    fs.mkdirSync(path.dirname(local.state), { recursive: true });
    fs.writeFileSync(local.state, JSON.stringify({ record: { ...record, status: 'local', leaseToken: 'previous-test-lease' } }));
    const { stdout } = await promisify(execFile)(process.execPath, [path.join(__dirname, 'coordinate.cjs'), 'claim', '--session', session,
      '--title', record.title, '--topic', 'audio-pieges-duel', '--sectors', 'effets-sonores', '--files', 'audio-lab/arena-traps'], { cwd: repo, windowsHide: true });
    assert.match(stdout, /^Repris : Préparer les sons des pièges/);
    assert.ok(stdout.includes(`Prototype-Work: ${id}`));
    assert.ok(!stdout.includes('test-token') && !stdout.includes('test-lease'));
    assert.deepEqual(JSON.parse(fs.readFileSync(local.state, 'utf8')).record, record);
    assert.equal(seen.action, 'claim');
    assert.equal(seen.session, session);
    assert.deepEqual(seen.files, ['audio-lab/arena-traps']);
    assert.match(seen.baseCommit, /^[a-f0-9]{40}$/);
    assert.deepEqual(Object.keys(seen).sort(), ['action', 'baseCommit', 'files', 'sectors', 'session', 'title', 'topic']);
  } finally {
    await new Promise(resolve => server.close(resolve));
    assert.equal(path.dirname(path.resolve(repo)), path.resolve(os.tmpdir()));
    fs.rmSync(repo, { recursive: true, force: true });
  }
});
test('finished local or published work can be staged without enabling file edits or bypassing outages', async () => {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'prototype-coordination-finished-'));
  const session = 'finished-test-session', local = files(repo, session);
  let status = 'local', unavailable = false, seen = [];
  const server = http.createServer(async (req, res) => {
    let raw = ''; for await (const chunk of req) raw += chunk;
    const body = JSON.parse(raw); seen.push(body);
    res.setHeader('Content-Type', 'application/json');
    if (unavailable) { res.writeHead(503); res.end(JSON.stringify({ error: 'Indisponible' })); return; }
    if (body.action === 'heartbeat' || !['local', 'published'].includes(status)) { res.writeHead(409); res.end(JSON.stringify({ error: 'expired' })); return; }
    res.end(JSON.stringify({ record: { id: 'finished-work', status, leaseToken: 'finished-lease' } }));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    fs.mkdirSync(path.dirname(local.config), { recursive: true });
    fs.writeFileSync(local.config, JSON.stringify({ actor: 'morepudding', token: 'private-token', site: `http://127.0.0.1:${server.address().port}` }));
    fs.mkdirSync(path.dirname(local.state), { recursive: true });
    fs.writeFileSync(local.state, JSON.stringify({ record: { id: 'finished-work', status, leaseToken: 'finished-lease' } }));
    const payload = { session_id: session, hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: { command: 'git add -- file.gd; git diff --cached --check; git commit -m "Fix"; git push origin main' } };
    for (status of ['local', 'published']) {
      assert.equal(await hook(payload, repo), null);
      assert.equal(seen.at(-1).action, 'check');
      assert.equal((await hook({ ...payload, tool_name: 'apply_patch' }, repo)).hookSpecificOutput.permissionDecision, 'deny');
      assert.equal((await hook({ ...payload, tool_input: { command: 'git add -- file.gd; Set-Content file.gd changed' } }, repo)).hookSpecificOutput.permissionDecision, 'deny');
    }
    status = 'interrupted';
    assert.equal((await hook(payload, repo)).hookSpecificOutput.permissionDecision, 'deny');
    status = 'local'; unavailable = true;
    assert.equal((await hook(payload, repo)).hookSpecificOutput.permissionDecision, 'deny');
  } finally {
    await new Promise(resolve => server.close(resolve));
    fs.rmSync(repo, { recursive: true, force: true });
  }
});
test('hook denies an unreserved patch, renews a claim, and fails closed during an outage', async () => {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'prototype-coordination-'));
  const session = 'hook-test-session';
  const local = files(repo, session);
  let seen = [], unavailable = false;
  const server = http.createServer(async (req, res) => {
    let raw = ''; for await (const chunk of req) raw += chunk;
    if (raw) seen.push(JSON.parse(raw));
    res.setHeader('Content-Type', 'application/json');
    if (unavailable) { res.writeHead(503); res.end(JSON.stringify({ error: 'Indisponible' })); return; }
    res.end(JSON.stringify(req.method === 'GET' ? { developments: [] } : { record: { id: 'test-work', status: seen.at(-1).action === 'interrupt' ? 'interrupted' : 'active', leaseToken: 'test-lease' } }));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    fs.mkdirSync(path.dirname(local.config), { recursive: true });
    fs.writeFileSync(local.config, JSON.stringify({ actor: 'morepudding', token: 'private-token', site: `http://127.0.0.1:${server.address().port}` }));
    const payload = { session_id: session, hook_event_name: 'PreToolUse', tool_name: 'apply_patch', tool_input: {} };
    assert.equal((await hook(payload, repo)).hookSpecificOutput.permissionDecision, 'deny');
    fs.mkdirSync(path.dirname(local.state), { recursive: true });
    fs.writeFileSync(local.state, JSON.stringify({ record: { id: 'test-work', status: 'active', leaseToken: 'test-lease' } }));
    assert.equal(await hook(payload, repo), null);
    assert.equal(seen.at(-1).action, 'heartbeat');
    assert.equal(await hook({ ...payload, tool_name: 'Bash', tool_input: { command: 'git commit -m "Publish verified work"' } }, repo), null);
    assert.equal(seen.at(-1).action, 'check');
    const prompt = 'RAW PRIVATE PROMPT MUST NOT BE SENT';
    assert.match((await hook({ session_id: session, hook_event_name: 'UserPromptSubmit', prompt }, repo)).hookSpecificOutput.additionalContext, /Aucun travail/);
    assert.ok(!JSON.stringify(seen).includes(prompt));
    assert.equal(await hook({ session_id: session, hook_event_name: 'Stop' }, repo), null);
    await hook({ session_id: session, hook_event_name: 'Interrupt' }, repo);
    assert.equal(seen.at(-1).action, 'interrupt');
    unavailable = true;
    assert.equal((await hook(payload, repo)).hookSpecificOutput.permissionDecision, 'deny');
  } finally {
    await new Promise(resolve => server.close(resolve));
    fs.rmSync(repo, { recursive: true, force: true });
  }
});

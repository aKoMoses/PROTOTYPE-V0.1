const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const { compact, isReadOnly, hook, files } = require('./coordinate.cjs');
test('reads need no claim; shell writes and patches do; only coordination commands are exempt', () => {
  const shell = command => ({ tool_name: 'Bash', tool_input: { command } });
  assert.ok(isReadOnly(shell('git status --short; Get-Content AGENTS.md')));
  assert.ok(isReadOnly(shell('node tools/coordinate.cjs claim --title "Corriger la visée"')));
  for (const command of ['node -e "require(\'fs\').writeFileSync(\'test\',\'x\')"', 'git status; Set-Content test x', 'Get-Content test > other', 'git commit -m test', 'node tools/coordinate.cjs status; Remove-Item test']) assert.equal(isReadOnly(shell(command)), false);
  assert.equal(isReadOnly({ tool_name: 'apply_patch', tool_input: {} }), false);
});
test('context is bounded and prioritizes unfinished work over published history', () => {
  const records = Array.from({ length: 40 }, (_, index) => ({ actor: 'akomoses', status: index === 39 ? 'local' : 'published', title: 'x'.repeat(120), updatedAt: Date.now(), commit: 'a'.repeat(40) }));
  const text = compact(records);
  assert.ok(text.length <= 850);
  assert.match(text.split('\n')[0], /terminé localement/);
  assert.match(text, /autres sur le site/);
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

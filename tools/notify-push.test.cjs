const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { buildPush, scopeReferences } = require('./notify-push.cjs');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

test('summarizes a push in three sentences and links to its pull confirmation', () => {
  const sha = 'a'.repeat(40);
  const result = buildPush({
    after: sha, sender: { login: 'morepudding' },
    head_commit: { timestamp: '2026-09-26T12:00:00Z' },
    compare: 'https://github.com/aKoMoses/PROTOTYPE-V0.1/compare/old...new',
    commits: [{ message: 'Add a new arena', added: ['scenes/arena.tscn'], modified: ['scripts/game_flow.gd'], removed: [] }]
  });
  assert.equal(result.record.author, 'BotteroRomain');
  assert.equal(result.record.summary.match(/\./g).length, 3);
  assert.match(result.content, new RegExp(`patchs\\.html#push-${sha}`));
  assert.match(result.record.summary, /les scènes, le gameplay/);
});

test('uses Git diff paths when the push event omits file lists', () => {
  const result = buildPush({
    after: 'b'.repeat(40), sender: { login: 'aKoMoses' },
    commits: [{ message: 'Tune combat', added: [], modified: [], removed: [] }]
  }, ['scripts/combat_state.gd']);
  assert.match(result.record.summary, /le gameplay/);
});

test('only explicit work trailers from pushed commits confirm publication', () => {
  const id = randomUUID(), sha = 'c'.repeat(40);
  const result = buildPush({ after: sha, sender: { login: 'morepudding' }, commits: [
    { id: sha, message: `Install coordination\n\nPrototype-Work: ${id}` },
    { id: 'd'.repeat(40), message: 'Another change without a work reference' },
    { id: 'fake', message: `Prototype-Work: ${randomUUID()}` }
  ] });
  assert.deepEqual(result.record.workReferences, [{ id, commit: sha }]);
});

test('a resumed work reference must come from a commit after its Git base and carry its current cycle', () => {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'prototype-notify-resumed-'));
  const id = randomUUID(), legacy = randomUUID();
  const git = args => execFileSync('git', args, { cwd: repo, encoding: 'utf8', windowsHide: true }).trim();
  const commit = title => {
    git(['-c', 'user.name=Coordination Test', '-c', 'user.email=coordination@example.invalid', 'commit', '--quiet', '--allow-empty', '-m', title]);
    return git(['rev-parse', 'HEAD']);
  };
  try {
    git(['init', '--quiet']);
    const old = commit('First completion');
    const base = commit('Reopen from this base');
    const next = commit('Complete the resumed work');
    const isAncestor = (ancestor, child) => {
      try { git(['merge-base', '--is-ancestor', ancestor, child]); return true; }
      catch (error) { if (error.status === 1) return false; throw error; }
    };
    const refs = [{ id, commit: old }, { id, commit: base }, { id, commit: next }, { id: legacy, commit: old }];
    const work = { id, resumedAt: 1780000000000, publicationBaseCommit: base };
    assert.deepEqual(scopeReferences(refs, [work], isAncestor), [{ id, commit: next, resumedAt: work.resumedAt }, { id: legacy, commit: old }]);
    assert.deepEqual(scopeReferences(refs.slice(0, 3), [{ ...work, publicationBaseCommit: undefined }], isAncestor), []);
    assert.deepEqual(scopeReferences(refs.slice(0, 3), [work], () => { throw new Error('Git base unavailable'); }), []);
  } finally {
    assert.equal(path.dirname(path.resolve(repo)), path.resolve(os.tmpdir()));
    fs.rmSync(repo, { recursive: true, force: true });
  }
});

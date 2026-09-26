const test = require('node:test');
const assert = require('node:assert/strict');
const { buildPush } = require('./notify-push.cjs');

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

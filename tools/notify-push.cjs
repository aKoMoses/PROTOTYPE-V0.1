const fs = require('node:fs');
const { execFileSync } = require('node:child_process');

const SITE_URL = 'https://prototype-zero-site.vercel.app';
const AUTHORS = { morepudding: 'BotteroRomain', BotteroRomain: 'BotteroRomain', aKoMoses: 'aKoMoses' };

function clean(value, limit = 120) {
  return String(value || '').split('\n')[0].replace(/[.!?*_`~|<>@\r]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, limit);
}

function fileAreas(commits, fallbackPaths = []) {
  const paths = [...fallbackPaths, ...commits.flatMap(commit => [...(commit.added || []), ...(commit.modified || []), ...(commit.removed || [])])];
  const areas = new Set();
  for (const path of paths) {
    if (path.startsWith('scenes/')) areas.add('les scènes');
    else if (path.startsWith('scripts/')) areas.add('le gameplay');
    else if (path.startsWith('art/')) areas.add('les éléments visuels et sonores');
    else if (path.startsWith('captures/')) areas.add('les captures');
    else if (path.startsWith('tools/')) areas.add('les outils de test');
    else if (path.startsWith('.github/')) areas.add('l’automatisation');
    else areas.add('la configuration du projet');
  }
  return [...areas].slice(0, 3).join(', ') || 'le projet';
}

function buildPush(event, fallbackPaths = []) {
  const author = AUTHORS[event.sender?.login] || AUTHORS[event.pusher?.name];
  if (!author) throw new Error('Unknown game contributor');
  const commits = event.commits || [];
  const titles = commits.map(commit => clean(commit.message)).filter(Boolean);
  const count = commits.length;
  const summary = [
    `${author} a publié ${count} commit${count > 1 ? 's' : ''} sur la branche principale.`,
    titles.length ? `Les changements annoncés sont « ${titles.slice(0, 3).join(' », « ')} »${titles.length > 3 ? ' et d’autres' : ''}.` : 'Le détail des commits n’est pas disponible.',
    `Les fichiers touchés concernent ${fileAreas(commits, fallbackPaths)}.`
  ].join(' ');
  const commit = event.after;
  const record = {
    commit, author,
    date: new Date(event.head_commit?.timestamp || Date.now()).toISOString().slice(0, 10),
    title: titles.at(-1) || 'Nouveau push du jeu',
    summary,
    changes: titles.slice(0, 10),
    source: event.compare || event.head_commit?.url
  };
  record.workReferences = commits.flatMap(commit => [...String(commit.message || '').matchAll(/^Prototype-Work:\s*([a-f0-9-]{36})\s*$/gm)]
    .map(match => ({ id: match[1], commit: commit.id }))).filter(ref => /^[a-f0-9]{40}$/i.test(ref.commit));
  const content = `🎮 **Nouveau push de ${author}**\n${summary}\n[Voir le push et confirmer mon pull](${SITE_URL}/patchs.html#push-${commit})`;
  return { record, content };
}

async function main() {
  const webhook = process.env.DISCORD_WEBHOOK_URL;
  const secret = process.env.GAME_PUSH_SECRET;
  if (!webhook || !secret) throw new Error('Discord or site push secret is not configured');
  const event = JSON.parse(fs.readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  let changedPaths = [];
  try {
    changedPaths = execFileSync('git', ['diff', '--name-only', event.before, event.after], { encoding: 'utf8' }).trim().split(/\r?\n/).filter(Boolean);
  } catch (_) { /* Commit metadata remains usable if this diff is unavailable. */ }
  const { record, content } = buildPush(event, changedPaths);
  // Reconcile unfinished records against recent main history, including a missed notification.
  // This is a bounded Git read, with no model call and no scan of the entire history.
  try {
    const current = await fetch(`${SITE_URL}/api/developments`, { signal: AbortSignal.timeout(6000) });
    if (!current.ok) throw new Error('Coordination history unavailable');
    const developments = (await current.json()).developments;
    const pending = new Set(developments.filter(work => work.status !== 'published').map(work => work.id));
    const log = execFileSync('git', ['log', '-100', '--format=%H%x00%B%x00', event.after], { encoding: 'utf8' });
    const parts = log.split('\0');
    for (let i = 0; i + 1 < parts.length; i += 2) {
      const commit = parts[i].trim();
      if (!/^[a-f0-9]{40}$/i.test(commit)) continue;
      for (const match of parts[i + 1].matchAll(/^Prototype-Work:\s*([a-f0-9-]{36})\s*$/gm)) {
        if (pending.has(match[1])) record.workReferences.push({ id: match[1], commit });
      }
    }
    record.workReferences = scopeReferences(record.workReferences, developments, commitIsAncestor);
    record.workReferences = [...new Map(record.workReferences.map(ref => [`${ref.id}:${ref.commit}`, ref])).values()].slice(0, 100);
  } catch (_) { /* Event commit metadata still covers ordinary pushes. */ }
  const saved = await fetch(`${SITE_URL}/api/game-pushes`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${secret}` },
    body: JSON.stringify(record)
  });
  if (!saved.ok) throw new Error(`Site returned ${saved.status}`);
  const sent = await fetch(webhook, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ content, allowed_mentions: { parse: [] } })
  });
  if (!sent.ok) throw new Error(`Discord returned ${sent.status}`);
  console.log(`Announced game push ${record.commit.slice(0, 7)}.`);
}

function commitIsAncestor(base, commit) {
  try {
    execFileSync('git', ['merge-base', '--is-ancestor', base, commit], { stdio: 'ignore', windowsHide: true });
    return true;
  } catch (error) {
    if (error.status === 1) return false;
    throw error;
  }
}

function scopeReferences(refs, developments, isAncestor) {
  const workById = new Map(developments.map(work => [work.id, work]));
  return refs.flatMap(ref => {
    const work = workById.get(ref.id);
    if (!work?.resumedAt) return [ref];
    const base = work.publicationBaseCommit;
    if (!/^[a-f0-9]{40}$/i.test(base || '') || ref.commit === base) return [];
    try {
      return isAncestor(base, ref.commit) ? [{ ...ref, resumedAt: work.resumedAt }] : [];
    } catch (_) { return []; } // An unavailable base cannot prove publication of resumed work.
  });
}

if (require.main === module) main().catch(error => { console.error(error); process.exitCode = 1; });
module.exports.buildPush = buildPush;
module.exports.scopeReferences = scopeReferences;

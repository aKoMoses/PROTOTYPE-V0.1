const fs = require('node:fs');

const webhook = process.env.DISCORD_WEBHOOK_URL;
if (!webhook) {
  console.log('Discord webhook not configured; push notification skipped.');
  process.exit(0);
}

const event = JSON.parse(fs.readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
const commits = event.commits || [];
const author = String(event.pusher?.name || 'Quelqu’un').replace(/[\r\n*_`~|<>@]/g, '').slice(0, 60);
const lines = commits.slice(0, 5).map(commit => {
  const title = String(commit.message || '').split('\n')[0].replace(/[\r\n*_`~|<>@]/g, '').slice(0, 100);
  return `• ${title} ([${commit.id.slice(0, 7)}](${commit.url}))`;
});
if (commits.length > 5) lines.push(`• … et ${commits.length - 5} autres commits`);
const content = `🎮 **${author} a poussé du nouveau code sur le jeu**\n${lines.join('\n') || 'Nouveau commit disponible.'}\n${event.compare || event.repository?.html_url}`;

fetch(webhook, {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ content, allowed_mentions: { parse: [] } })
}).then(response => {
  if (!response.ok) throw new Error(`Discord returned ${response.status}`);
  console.log(`Announced ${commits.length} commits.`);
}).catch(error => { console.error(error); process.exitCode = 1; });

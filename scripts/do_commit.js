const { execSync } = require('child_process');
const fs = require('fs');

try {
  execSync('git config core.safecrlf false');
  execSync('git config core.autocrlf false');
  execSync('git config user.name "Antigravity Dev"');
  execSync('git config user.email "dev@antigravity.local"');
  fs.rmSync('scripts/do_commit.js', { force: true });
  execSync('git add -A');
  const commitOutput = execSync('git commit -m "feat: support Antigravity 2.4.x family (2.4.2) and sync app.asar.unpacked backup"').toString();
  fs.writeFileSync('git_commit_success.txt', commitOutput, 'utf8');
} catch (err) {
  const msg = (err.stdout ? err.stdout.toString() : '') + (err.stderr ? err.stderr.toString() : err.message);
  fs.writeFileSync('git_commit_success.txt', msg, 'utf8');
}

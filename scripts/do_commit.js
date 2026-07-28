const { execSync } = require('child_process');
const fs = require('fs');

let log = '';
try {
  log += execSync('git config user.name "Antigravity Dev"').toString();
  log += execSync('git config user.email "dev@antigravity.local"').toString();
  log += execSync('git add -A').toString();
  try {
    log += execSync('git commit -m "feat: support Antigravity 2.4.x family (2.4.2) and sync app.asar.unpacked backup"').toString();
  } catch (e) {
    log += (e.stdout ? e.stdout.toString() : '') + (e.stderr ? e.stderr.toString() : '');
  }
} catch (err) {
  log += err.message;
}

fs.writeFileSync('git_result.txt', log, 'utf8');

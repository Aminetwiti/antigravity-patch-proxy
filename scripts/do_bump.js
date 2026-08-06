const fs = require('fs');
const { execSync } = require('child_process');

const gitBin = 'C:\\Program Files\\Git\\cmd\\git.exe';
const env = {
  ...process.env,
  GIT_AUTHOR_NAME: 'Amine Twiti',
  GIT_AUTHOR_EMAIL: 'amine@example.com',
  GIT_COMMITTER_NAME: 'Amine Twiti',
  GIT_COMMITTER_EMAIL: 'amine@example.com',
};

let log = '';
try {
  log += 'STAGING:\n' + execSync(`"${gitBin}" add package.json ag-doctor/package.json ag-doctor-ui/package.json README.md AGENTS.md agents/AGENTS.md`, { encoding: 'utf8', env }) + '\n';
  log += 'COMMIT:\n' + execSync(`"${gitBin}" commit -m "chore(release): bump version to 3.0.2"`, { encoding: 'utf8', env }) + '\n';
  log += 'TAG:\n' + execSync(`"${gitBin}" tag v3.0.2`, { encoding: 'utf8', env }) + '\n';
  log += 'PUSH BRANCH:\n' + execSync(`"${gitBin}" push origin main`, { encoding: 'utf8', env }) + '\n';
  log += 'PUSH TAG:\n' + execSync(`"${gitBin}" push origin v3.0.2`, { encoding: 'utf8', env }) + '\n';
} catch (e) {
  log += 'ERR:\n' + (e.stdout || '') + '\nSTDERR:\n' + (e.stderr || '') + '\nMSG:\n' + e.message;
}

fs.writeFileSync('c:\\Users\\amine\\Downloads\\antigravity-add-model-main\\antigravity-add-model-main\\bump_log.txt', log, 'utf8');

const fs = require('fs');
const text = fs.readFileSync('dist/renderer/app.js', 'utf8');
const lines = text.split(/\r?\n/);
// Find every line that contains navigate( outside of comments
for (let i = 0; i < lines.length; i++) {
  const ln = i + 1;
  const line = lines[i];
  if (/navigate\s*\(/.test(line) && !line.trim().startsWith('//') && !line.trim().startsWith('*')) {
    console.log(`${ln}: ${line.trim()}`);
  }
}
const fs = require('fs');
const text = fs.readFileSync('dist/renderer/app.js', 'utf8');
const lines = text.split(/\r?\n/);

// Show all references for each var with the actual source line
const vars = ['logsStreaming', 'loadInfo', 'settingsConfigSkeleton'];
vars.forEach(v => {
  console.log(`\n=== ${v} ===`);
  const re = new RegExp(`\\b${v}\\b`);
  for (let i = 0; i < lines.length; i++) {
    if (re.test(lines[i])) {
      console.log(`${i + 1}: ${lines[i].trim()}`);
    }
  }
});
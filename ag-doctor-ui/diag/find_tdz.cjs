const fs = require('fs');
const text = fs.readFileSync('dist/renderer/app.js', 'utf8');
const lines = text.split(/\r?\n/);
const declLine = {};
// Find declaration lines for each TDZ var
const vars = ['logsStreaming', 'loadInfo', 'settingsConfigSkeleton'];
vars.forEach(v => {
  const declRe = new RegExp(`^\\s*(let|const)\\s+${v}\\b`);
  for (let i = 0; i < lines.length; i++) {
    if (declRe.test(lines[i])) {
      declLine[v] = i + 1; // 1-indexed
      break;
    }
  }
});
console.log('Declaration lines:', declLine);
// Find all usages and report any before declaration
vars.forEach(v => {
  const re = new RegExp(`\\b${v}\\b`);
  console.log(`\n=== ${v} (declared at line ${declLine[v]}) ===`);
  for (let i = 0; i < lines.length; i++) {
    if (re.test(lines[i]) && !new RegExp(`^\\s*(let|const)\\s+${v}\\b`).test(lines[i])) {
      const ln = i + 1;
      if (ln < declLine[v]) {
        console.log(`  ⚠️  USAGE BEFORE DECL line ${ln}: ${lines[i].trim()}`);
      }
    }
  }
});
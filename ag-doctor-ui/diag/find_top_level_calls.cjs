const fs = require('fs');
const text = fs.readFileSync('dist/renderer/app.js', 'utf8');
const lines = text.split(/\r?\n/);

// Track brace depth. Lines at depth 0 are top-level.
let depth = 0;
const topLevel = [];
for (let i = 0; i < lines.length; i++) {
  const ln = i + 1;
  const line = lines[i];
  const before = depth;
  for (const c of line) {
    if (c === '{') depth++;
    else if (c === '}') depth--;
  }
  if (before === 0 && depth === 0) {
    // This line didn't change brace depth (or balanced it)
    if (/^\s*(void\s+)?(loadInfo|loadAntigravityStatus|loadLogs|loadMitmStatus|loadSettings|loadPatchStatus|loadModels|runDoctor|navigate|startLogStream|stopLogStream|flushLogs|scheduleLogsFlush|setTheme|memo)\s*\(/.test(line)) {
      topLevel.push({ln, line: line.trim()});
    }
  }
}
console.log('Top-level invocations of suspect functions:');
topLevel.forEach(t => console.log(`  ${t.ln}: ${t.line}`));
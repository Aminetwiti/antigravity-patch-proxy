const fs = require('fs');
const text = fs.readFileSync('dist/renderer/features.js', 'utf8');
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
    if (/^\s*(void\s+)?[A-Za-z_$][A-Za-z0-9_$]*\s*\(/.test(line) && !line.trim().startsWith('//') && !line.trim().startsWith('*')) {
      topLevel.push({ln, line: line.trim()});
    }
  }
}
console.log('Top-level invocations in features.js:');
topLevel.forEach(t => console.log(`  ${t.ln}: ${t.line}`));
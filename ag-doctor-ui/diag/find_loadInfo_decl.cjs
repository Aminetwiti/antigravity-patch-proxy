const fs = require('fs');
const text = fs.readFileSync('dist/renderer/app.js', 'utf8');
const lines = text.split(/\r?\n/);
// Find all const loadInfo declarations and ALL references
const decls = [];
const refs = [];
for (let i = 0; i < lines.length; i++) {
  const ln = i + 1;
  const line = lines[i];
  if (/^\s*const\s+loadInfo\s*=/.test(line)) decls.push({ln, line: line.trim()});
  if (/\bloadInfo\b/.test(line)) refs.push({ln, line: line.trim()});
}
console.log('Declarations of loadInfo:');
decls.forEach(d => console.log(`  ${d.ln}: ${d.line}`));
console.log('\nReferences (top-level only, not inside function bodies):');
// Very rough heuristic: top-level = no leading whitespace OR after a `;` at end of line
// Just show all references for now
refs.forEach(r => console.log(`  ${r.ln}: ${r.line}`));
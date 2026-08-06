const fs = require('fs');
const m = fs.readFileSync('dist/main.js', 'utf8');
const lines = m.split('\n');
let count = 0;
lines.forEach((line, i) => {
  if (line.includes('proxy-runner') || line.includes('child_process') || line.includes('spawn(') || line.includes('fork(') || line.includes('exec(')) {
    console.log((i+1) + ': ' + line.trim().slice(0, 200));
    count++;
  }
});
console.log('TOTAL_REFS:', count);

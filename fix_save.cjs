const fs = require('fs');
const p = 'src/preload.ts';
let s = fs.readFileSync(p, 'utf8');
const bad = "            externalModelName: model.id,\r\n      }\r\n    });\r\n  };";
const good = "            externalModelName: model.id,\r\n            allowUnauthorized: apiConfig.allowUnauthorized,\r\n            inputModalities: model.inputModalities || ['text'],\r\n          });\r\n        }\r\n\r\n        // Success - reload models and close\r\n        closeModalAndCleanup();\r\n      } catch (err) {\r\n        fetchStatus.textContent = 'Error: ' + (err as Error).message;\r\n        fetchStatus.style.color = '#ef4444';\r\n        saveBtn.disabled = false;\r\n        saveBtn.textContent = 'Add Selected Models';\r\n      }\r\n    });\r\n  };";
if (s.includes(bad)) {
  s = s.replace(bad, good);
  fs.writeFileSync(p, s);
  console.log('FIXED');
} else {
  console.log('NOT FOUND');
}

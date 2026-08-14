const fs = require('fs');
const file = 'c:/Users/amine/Downloads/antigravity-add-model-main/antigravity-add-model-main/remote/mobile/lib/features/settings/settings_screen.dart';
let content = fs.readFileSync(file, 'utf8');

content = content.replace(/bool _mcpAllowlistStrict[\s\S]*?String _executionPolicy = 'request-review';\s*/m, '');
content = content.replace(/_mcpAllowlistStrict = \(s\['mcpAllowlistStrict'\] as bool\?\) \?\? true;[\s\S]*?_executionPolicy = \(s\['executionPolicy'\] as String\?\) \?\? 'request-review';\s*/m, '');
fs.writeFileSync(file, content);
console.log('Fixed');

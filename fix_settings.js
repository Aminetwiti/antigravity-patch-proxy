const fs = require('fs');
const path = require('path');

const file = 'c:/Users/amine/Downloads/antigravity-add-model-main/antigravity-add-model-main/remote/mobile/lib/features/settings/settings_screen.dart';
let content = fs.readFileSync(file, 'utf8');

// Remove _isGeminiEnterprise, _geTier, _inferenceRegion, _mcpAllowlistStrict, _executionPolicy
content = content.replace(/bool _isGeminiEnterprise = true;\n\s*String _geTier = 'GE-Plus';\n\s*String _inferenceRegion = 'UE \(Europe\)';\n\s*bool _mcpAllowlistStrict = true;\n\s*String _executionPolicy = 'request-review';\n\s*/, '');
content = content.replace(/_isGeminiEnterprise = \(s\['isGeminiEnterprise'\] as bool\?\) \?\? true;\n\s*_geTier = \(s\['geTier'\] as String\?\) \?\? 'GE-Plus';\n\s*_inferenceRegion = \(s\['inferenceRegion'\] as String\?\) \?\? 'UE \(Europe\)';\n\s*_mcpAllowlistStrict = \(s\['mcpAllowlistStrict'\] as bool\?\) \?\? true;\n\s*_executionPolicy = \(s\['executionPolicy'\] as String\?\) \?\? 'request-review';\n\s*/, '');

// Fetch branches
content = content.replace(/bool _toolNotifications = true;\n\s*bool _diagnosticsBusy = false;/, 
ool _toolNotifications = true;
  bool _diagnosticsBusy = false;
  List<String> _branches = [];
  bool _isLoadingBranches = false;);

content = content.replace(/_fetchCustomModels\(\);\n\s*_applyApprovalTimeoutToDaemon\(\);/,
_fetchCustomModels();
    _applyApprovalTimeoutToDaemon();
    _fetchBranches(););

const fetchBranchesFunc = 
  Future<void> _fetchBranches() async {
    if (widget.api == null) return;
    setState(() => _isLoadingBranches = true);
    try {
      final branches = await widget.api!.listGitBranches();
      if (mounted) {
        setState(() {
          _branches = branches;
          if (!_branches.contains(_activeBranch) && _branches.isNotEmpty) {
            _activeBranch = _branches.first;
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch branches: \');
    } finally {
      if (mounted) setState(() => _isLoadingBranches = false);
    }
  }
;
content = content.replace(/Future<void> _fetchCustomModels/, fetchBranchesFunc + '\n  Future<void> _fetchCustomModels');

// Replace UI sections
const enterpriseRegex = /const _SectionTitle\(title: 'GEMINI ENTERPRISE & COMPLIANCE'\);[\s\S]*?const _SectionTitle\(title: 'POLITIQUES D\\'ADMINISTRATION D\\'ENTREPRISE'\);[\s\S]*?const Divider\(\),/m;
content = content.replace(enterpriseRegex, const _SectionTitle(title: 'WORKSPACE & BRANCH'),
          const SizedBox(height: 8),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [);

// Replace GitWorktreeSelector usage
content = content.replace(/GitWorktreeSelector\(\s*currentBranch: _activeBranch,\s*branches: const \['main', 'feature\/remote-v2', 'fix\/websocket-reconnect'\],\s*onBranchSelected: \(b\) async \{/,
_isLoadingBranches 
                    ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                    : GitWorktreeSelector(
                    currentBranch: _activeBranch,
                    branches: _branches.isEmpty ? ['main'] : _branches,
                    onBranchSelected: (b) async {);

fs.writeFileSync(file, content);
console.log('Fixed settings_screen.dart');

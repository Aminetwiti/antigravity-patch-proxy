import 'package:flutter/material.dart';
import '../../core/protocol/daemon_api.dart';
import '../../theme/app_colors.dart';

/// Écran Colosseum Battle Arena : Duel multi-modèles et arbitrage de branches.
class BattleArenaScreen extends StatefulWidget {
  final DaemonApi api;
  final String workspaceUri;

  const BattleArenaScreen({
    super.key,
    required this.api,
    required this.workspaceUri,
  });

  @override
  State<BattleArenaScreen> createState() => _BattleArenaScreenState();
}

class _BattleArenaScreenState extends State<BattleArenaScreen> {
  final _promptController = TextEditingController();
  bool _isRunning = false;
  String _modelA = 'claude-3-7-sonnet';
  String _modelB = 'gemini-2-5-pro';
  Map<String, dynamic>? _battleDiff;
  String? _winningArm;
  String? _statusMessage;

  final List<Map<String, dynamic>> _availableModels = [
    {'uid': 'claude-3-7-sonnet', 'enum': 312, 'name': 'Claude 3.7 Sonnet', 'badge': 'Anthropic'},
    {'uid': 'gemini-2-5-pro', 'enum': 246, 'name': 'Gemini 2.5 Pro', 'badge': 'Google'},
    {'uid': 'gpt-4o', 'enum': 101, 'name': 'GPT-4o', 'badge': 'OpenAI'},
    {'uid': 'deepseek-r1', 'enum': 405, 'name': 'DeepSeek R1', 'badge': 'Reasoning'},
  ];

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _startBattle() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer un prompt pour le duel.')),
      );
      return;
    }

    setState(() {
      _isRunning = true;
      _statusMessage = 'Initialisation des worktrees éphémères...';
    });

    try {
      final selectedA = _availableModels.firstWhere((m) => m['uid'] == _modelA);
      final selectedB = _availableModels.firstWhere((m) => m['uid'] == _modelB);

      await widget.api.startBattleMode(
        widget.workspaceUri,
        prompt,
        modelUIDA: selectedA['uid'] as String?,
        modelEnumA: selectedA['enum'] as int?,
        modelUIDB: selectedB['uid'] as String?,
        modelEnumB: selectedB['enum'] as int?,
      );

      setState(() {
        _statusMessage = 'Génération simultanée en cours sur Arm A et Arm B...';
      });

      // Rafraîchir le diff comparatif
      await _refreshDiff();
    } catch (e) {
      setState(() {
        _isRunning = false;
        _statusMessage = 'Erreur: $e';
      });
    }
  }

  Future<void> _refreshDiff() async {
    try {
      final diff = await widget.api.getBattleDiff(widget.workspaceUri);
      setState(() {
        _battleDiff = diff;
      });
    } catch (_) {}
  }

  Future<void> _eliminateArm(String armId) async {
    try {
      await widget.api.eliminateBattleArm(armId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Branche $armId éliminée')),
      );
      await _refreshDiff();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Échec élimination: $e')),
      );
    }
  }

  Future<void> _concludeBattle(String winningArm, int strategy) async {
    try {
      await widget.api.endBattleMode(winningArm, mergeStrategy: strategy);
      if (!mounted) return;
      setState(() {
        _isRunning = false;
        _winningArm = winningArm;
        _statusMessage = 'Victoire validée pour $winningArm via SafeMerge.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.positive,
          content: Text('Fusion appliquée avec succès dans la branche principale !'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur arbitrage: $e')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceRaised,
        title: const Text('Colosseum Battle Arena ⚔️', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (_isRunning)
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.accentBlue),
              onPressed: _refreshDiff,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sélecteurs de modèles
            Row(
              children: [
                Expanded(
                  child: _buildModelSelector(
                    title: 'Arm A (Modèle 1)',
                    selectedUID: _modelA,
                    color: AppColors.providerAnthropic,
                    onChanged: (uid) => setState(() => _modelA = uid),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('VS', style: TextStyle(color: AppColors.codeGold, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: _buildModelSelector(
                    title: 'Arm B (Modèle 2)',
                    selectedUID: _modelB,
                    color: AppColors.providerGoogle,
                    onChanged: (uid) => setState(() => _modelB = uid),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Saisie du prompt
            TextField(
              controller: _promptController,
              maxLines: 3,
              style: const TextStyle(color: AppColors.inkPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Entrez la tâche à mettre en compétition (ex: Refactor du tokenizer en zéro-allocation)...',
                hintStyle: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
                filled: true,
                fillColor: AppColors.surfaceInput,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),

            // Bouton de lancement
            ElevatedButton.icon(
              onPressed: _isRunning ? null : _startBattle,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentBlue,
                foregroundColor: AppColors.onAccent,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.flash_on, size: 18),
              label: Text(_isRunning ? 'Combat en cours...' : 'Lancer le Duel Multi-Modèles'),
            ),

            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Text(_statusMessage!, style: const TextStyle(color: AppColors.inkSecondary, fontSize: 12)),
              ),
            ],

            const SizedBox(height: 20),
            // Actions d'arbitrage
            if (_isRunning) ...[
              const Text('Arbitrage & SafeMerge', style: TextStyle(color: AppColors.inkPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger)),
                      onPressed: () => _eliminateArm('arm_a'),
                      child: const Text('Éliminer Arm A', style: TextStyle(color: AppColors.danger, fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger)),
                      onPressed: () => _eliminateArm('arm_b'),
                      child: const Text('Éliminer Arm B', style: TextStyle(color: AppColors.danger, fontSize: 11)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.positive),
                      onPressed: () => _concludeBattle('arm_a', 2), // 2 = SAFE_MERGE
                      child: const Text('Gagnant : Arm A (SafeMerge)', style: TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.positive),
                      onPressed: () => _concludeBattle('arm_b', 2), // 2 = SAFE_MERGE
                      child: const Text('Gagnant : Arm B (SafeMerge)', style: TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ],

            if (_battleDiff != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceInput,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Diff Comparatif Live', style: TextStyle(color: AppColors.codeGold, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('${_battleDiff!}', style: const TextStyle(color: AppColors.inkPrimary, fontSize: 11, fontFamily: 'monospace')),
                  ],
                ),
              ),
            ],

            if (_winningArm != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.positive.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.positive),
                ),
                child: Text('Victoire validée : $_winningArm', style: const TextStyle(color: AppColors.positive, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModelSelector({
    required String title,
    required String selectedUID,
    required Color color,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(100)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          DropdownButton<String>(
            value: selectedUID,
            isExpanded: true,
            dropdownColor: AppColors.surfaceRaised,
            underline: const SizedBox(),
            items: _availableModels.map((m) {
              return DropdownMenuItem<String>(
                value: m['uid'] as String,
                child: Text(m['name'] as String, style: const TextStyle(color: AppColors.inkPrimary, fontSize: 12)),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) onChanged(val);
            },
          ),
        ],
      ),
    );
  }
}

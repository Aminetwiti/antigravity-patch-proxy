import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/core/protocol/daemon_api.dart';
import 'package:mobile/services/settings_store.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/widgets/app_toast.dart';

/// Section Models (Antigravity IDE 1:1)
/// Permet de sélectionner le modèle par défaut, le niveau de réflexion (Reasoning Effort)
/// et d'activer le fallback automatique.
class ModelsSettingsSection extends StatefulWidget {
  final DaemonApi? api;
  final String currentDefaultModel;
  final ValueChanged<String>? onDefaultModelChanged;

  const ModelsSettingsSection({
    super.key,
    this.api,
    this.currentDefaultModel = 'Gemini 3.7 Flash Medium',
    this.onDefaultModelChanged,
  });

  @override
  State<ModelsSettingsSection> createState() => _ModelsSettingsSectionState();
}

class _ModelsSettingsSectionState extends State<ModelsSettingsSection> {
  late String _selectedModel;
  String _reasoningEffort = 'medium'; // off, low, medium, high
  bool _autoFallback = true;
  bool _isLoadingModels = false;

  final List<String> _models = [
    'Gemini 3.7 Flash Medium',
    'Gemini 3.6 Flash Medium',
    'Gemini 3.5 Flash Medium',
    'Gemini 3.1 Pro Low',
    'Claude Sonnet 4.6 (Thinking)',
    'Claude Opus 4.6 (Thinking)',
    'Claude 3.7 Sonnet',
    'GPT-4o',
    'GPT-OSS 120B (Medium)',
    'DeepSeek R1',
  ];

  @override
  void initState() {
    super.initState();
    _selectedModel = widget.currentDefaultModel;
    _loadSettings();
    _fetchDaemonModels();
  }

  Future<void> _loadSettings() async {
    final s = await SettingsStore.load();
    if (mounted) {
      setState(() {
        _reasoningEffort = (s['reasoningEffort'] as String?) ?? 'medium';
        _autoFallback = (s['autoFallback'] as bool?) ?? true;
      });
    }
  }

  Future<void> _fetchDaemonModels() async {
    if (widget.api == null) return;
    setState(() => _isLoadingModels = true);
    try {
      final res = await widget.api!.listModels();
      if (mounted && res['models'] is List) {
        final list = List<dynamic>.from(res['models'] as List);
        for (final m in list) {
          final name = (m is Map ? (m['displayName'] ?? m['name']) : m.toString()) as String;
          if (name.isNotEmpty && !_models.contains(name)) {
            _models.add(name);
          }
        }
        setState(() => _isLoadingModels = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingModels = false);
    }
  }

  void _onModelSelected(String model) {
    setState(() => _selectedModel = model);
    HapticFeedback.selectionClick();
    SettingsStore.save({'defaultModel': model});
    widget.onDefaultModelChanged?.call(model);
    if (widget.api != null) {
      widget.api!.sendCommand('/model $model');
    }
    AppToast.show(context, message: 'Modèle par défaut : $model', icon: Icons.smart_toy_outlined);
  }

  void _onReasoningChanged(String effort) {
    setState(() => _reasoningEffort = effort);
    HapticFeedback.selectionClick();
    SettingsStore.save({'reasoningEffort': effort});
    AppToast.show(context, message: 'Reasoning Effort : ${effort.toUpperCase()}', icon: Icons.psychology_outlined);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Models',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Configure default models, reasoning effort (thinking budget), and custom endpoints.',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // ── DEFAULT MODEL
          Text(
            'Default Model',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),

          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141619) : scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isDark ? const Color(0xFF26282E) : scheme.outlineVariant,
                width: 1,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: _models.contains(_selectedModel) ? _selectedModel : _models.first,
                  dropdownColor: isDark ? const Color(0xFF1B1D22) : scheme.surfaceContainer,
                  style: TextStyle(fontSize: 13.5, color: scheme.onSurface, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    labelText: 'Modèle actif',
                    labelStyle: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    prefixIcon: Icon(Icons.smart_toy_outlined, size: 18, color: scheme.primary),
                  ),
                  items: _models.map((m) {
                    final isThinking = m.contains('Thinking') || m.contains('R1') || m.contains('Pro');
                    return DropdownMenuItem(
                      value: m,
                      child: Row(
                        children: [
                          Text(m),
                          if (isThinking) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'THINKING',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.primary,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) _onModelSelected(val);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── REASONING EFFORT / THINKING BUDGET
          Text(
            'Reasoning Effort (Thinking Budget)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),

          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141619) : scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isDark ? const Color(0xFF26282E) : scheme.outlineVariant,
                width: 1,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Définit l\'allocation de calcul allouée à la réflexion étape par étape avant de produire une réponse.',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _buildEffortPill('off', 'Off', Icons.block_outlined, scheme),
                    const SizedBox(width: 8),
                    _buildEffortPill('low', 'Low (1k)', Icons.battery_1_bar_outlined, scheme),
                    const SizedBox(width: 8),
                    _buildEffortPill('medium', 'Medium (8k)', Icons.battery_5_bar_outlined, scheme),
                    const SizedBox(width: 8),
                    _buildEffortPill('high', 'High (32k)', Icons.battery_charging_full_outlined, scheme),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── AUTO FALLBACK
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141619) : scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isDark ? const Color(0xFF26282E) : scheme.outlineVariant,
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Auto Fallback on Rate Limit (429)',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: scheme.onSurface),
              ),
              subtitle: Text(
                'Bascule automatiquement sur un modèle secondaire si le quota du modèle principal est saturé.',
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
              value: _autoFallback,
              activeColor: const Color(0xFF007AFF),
              onChanged: (val) {
                setState(() => _autoFallback = val);
                SettingsStore.save({'autoFallback': val});
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildEffortPill(String key, String label, IconData icon, ColorScheme scheme) {
    final isSelected = _reasoningEffort == key;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: InkWell(
        onTap: () => _onReasoningChanged(key),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF007AFF).withValues(alpha: 0.15)
                : (isDark ? const Color(0xFF1B1D22) : scheme.surfaceContainerHigh),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: isSelected ? const Color(0xFF007AFF) : (isDark ? const Color(0xFF2C2F36) : scheme.outlineVariant),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 16, color: isSelected ? const Color(0xFF007AFF) : scheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? const Color(0xFF007AFF) : scheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

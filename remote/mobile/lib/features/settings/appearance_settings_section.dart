import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/settings_store.dart';
import 'package:mobile/theme/app_colors.dart';

/// Préférences d'apparence : mode clair/sombre + style de l'interface chat.
/// Le theme mode est persisté (SettingsStore) et remonté à l'app (changement
/// immédiat du ThemeMode).
class AppearanceSettingsSection extends StatefulWidget {
  const AppearanceSettingsSection({
    super.key,
    required this.initialIndex,
    required this.onThemeModeChanged,
  });

  final int initialIndex;
  final ValueChanged<int> onThemeModeChanged;

  @override
  State<AppearanceSettingsSection> createState() => _AppearanceSettingsSectionState();
}

class _AppearanceSettingsSectionState extends State<AppearanceSettingsSection> {
  late int _themeModeIndex = widget.initialIndex;
  bool _compactBubbles = false;
  bool _monospaceCode = true;

  void _setThemeMode(int index) {
    setState(() => _themeModeIndex = index);
    widget.onThemeModeChanged(index);
    SettingsStore.save({'themeMode': index});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Theme mode : système / clair / sombre
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Theme Mode',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Système, clair ou sombre — appliqué immédiatement.',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildToggleBtn(0, Icons.monitor_outlined, 'Système'),
                      _buildToggleBtn(1, Icons.light_mode_outlined, 'Clair'),
                      _buildToggleBtn(2, Icons.dark_mode_outlined, 'Sombre'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // ── Style de l'interface (bulles, code, compaction)
        Text(
          'Style de l’interface',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                title: Text(
                  'Bulles compactes',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                ),
                subtitle: Text(
                  'Réduire l’espacement vertical des messages',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                value: _compactBubbles,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: (v) => setState(() => _compactBubbles = v),
              ),
              const Divider(height: 1),
              SwitchListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                title: Text(
                  'Code monospace',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                ),
                subtitle: Text(
                  'Afficher les blocs de code en police à chasse fixe',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                value: _monospaceCode,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: (v) => setState(() => _monospaceCode = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggleBtn(int index, IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = _themeModeIndex == index;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        _setThemeMode(index);
      },
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? scheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: isSelected ? Border.all(color: scheme.outlineVariant, width: 1) : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

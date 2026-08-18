import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/core/notifications/approval_notifier.dart';
import 'package:mobile/core/protocol/daemon_api.dart';
import 'package:mobile/services/settings_store.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/widgets/app_toast.dart';

/// Section General (Antigravity IDE 1:1)
/// Gère l'autonomie de l'agent, le timeout d'auto-refus et les notifications.
class GeneralSettingsSection extends StatefulWidget {
  final DaemonApi? api;
  final ApprovalNotifier? notifier;

  const GeneralSettingsSection({
    super.key,
    this.api,
    this.notifier,
  });

  @override
  State<GeneralSettingsSection> createState() => _GeneralSettingsSectionState();
}

class _GeneralSettingsSectionState extends State<GeneralSettingsSection> {
  static const int _defaultApprovalTimeoutMinutes = 5;
  late TextEditingController _timeoutController;
  int _timeoutMinutes = _defaultApprovalTimeoutMinutes;
  bool _timeoutSaved = false;

  bool _toolNotifications = true;
  bool _autoAcceptEnabled = false;
  String _autoAcceptMode = 'readonly'; // readonly | full

  @override
  void initState() {
    super.initState();
    _timeoutController = TextEditingController(text: '$_timeoutMinutes');
    _loadSettings();
  }

  @override
  void dispose() {
    _timeoutController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final s = await SettingsStore.load();
    if (mounted) {
      setState(() {
        _timeoutMinutes = (s['approvalTimeoutMinutes'] as int?) ?? _defaultApprovalTimeoutMinutes;
        _timeoutController.text = '$_timeoutMinutes';
        _toolNotifications = (s['toolNotifications'] as bool?) ?? true;
        _autoAcceptEnabled = (s['autoAcceptEnabled'] as bool?) ?? false;
        _autoAcceptMode = (s['autoAcceptMode'] as String?) ?? 'readonly';
      });
      widget.notifier?.setEnabled(_toolNotifications);
    }
  }

  Future<void> _applyTimeout() async {
    final val = int.tryParse(_timeoutController.text.trim()) ?? _defaultApprovalTimeoutMinutes;
    final clamped = val.clamp(0, 1440);
    setState(() {
      _timeoutMinutes = clamped;
      _timeoutController.text = '$clamped';
      _timeoutSaved = true;
    });
    HapticFeedback.selectionClick();
    await SettingsStore.save({'approvalTimeoutMinutes': clamped});
    if (widget.api != null) {
      widget.api!.sendApprovalTimeout(clamped);
    }
    if (mounted) {
      AppToast.show(
        context,
        message: clamped == 0 ? 'Auto-refus désactivé.' : 'Délai d\'auto-refus : $clamped min.',
        icon: Icons.timer_outlined,
      );
    }
  }

  Future<void> _toggleAutoAccept(bool val) async {
    setState(() => _autoAcceptEnabled = val);
    HapticFeedback.selectionClick();
    await SettingsStore.save({'autoAcceptEnabled': val, 'autoAcceptMode': _autoAcceptMode});
    if (widget.api != null) {
      widget.api!.sendAutoAccept(enabled: val, mode: _autoAcceptMode);
    }
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
            'General',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Manage agent autonomy, tool approval timeouts, and push notifications.',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Autonomy Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141619) : scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isDark ? const Color(0xFF26282E) : scheme.outlineVariant,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Autonomie & Approbations d\'outils',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Auto-approuver les actions en lecture seule',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: scheme.onSurface),
                  ),
                  subtitle: Text(
                    _autoAcceptMode == 'full'
                        ? 'Accès total : toutes les commandes et écritures passent automatiquement.'
                        : 'Lecture seule : fichiers et recherches passent sans confirmation.',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
                  value: _autoAcceptEnabled,
                  activeColor: const Color(0xFF007AFF),
                  onChanged: _toggleAutoAccept,
                ),
                const Divider(height: 20, thickness: 0.5),
                // Timeout
                Text(
                  'Délai d\'auto-refus des approbations (minutes)',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _timeoutController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(fontSize: 13, color: scheme.onSurface),
                        decoration: InputDecoration(
                          hintText: '$_defaultApprovalTimeoutMinutes',
                          suffixIcon: Icon(Icons.timer_outlined, size: 18, color: scheme.onSurfaceVariant),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onChanged: (_) => setState(() => _timeoutSaved = false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Appliquer au daemon',
                      icon: Icon(
                        _timeoutSaved ? Icons.check_circle : Icons.check,
                        color: _timeoutSaved ? const Color(0xFF007AFF) : scheme.onSurfaceVariant,
                      ),
                      onPressed: _applyTimeout,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '0 = pas de timeout (attend indéfiniment). Défaut : 5 min.',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Notifications Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141619) : scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isDark ? const Color(0xFF26282E) : scheme.outlineVariant,
                width: 1,
              ),
            ),
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Notifications Push (Approbations)',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: scheme.onSurface),
              ),
              subtitle: Text(
                'Alerte sonore et vibration lorsqu\'une commande shell requiert votre accord.',
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
              value: _toolNotifications,
              activeColor: const Color(0xFF007AFF),
              onChanged: (val) {
                setState(() => _toolNotifications = val);
                SettingsStore.save({'toolNotifications': val});
                widget.notifier?.setEnabled(val);
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/env_config.dart';
import '../../core/notifications/approval_notifier.dart';
import '../../core/protocol/daemon_api.dart';
import '../../core/protocol/model_catalog.dart';
import '../../services/settings_store.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/conflict_dialog.dart';
import '../workspace/git_worktree_selector.dart';
import 'appearance_settings_section.dart';
import 'profile_settings_section.dart';
import 'package:mobile/theme/app_colors.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.initialSettings = const {},
    this.onThemeModeChanged,
    this.onDaemonSaved,
    this.api,
    this.notifier,
    this.httpClient,
  });

  final Map<String, dynamic> initialSettings;
  final ValueChanged<int>? onThemeModeChanged;
  final ValueChanged<Map<String, dynamic>>? onDaemonSaved;
  final DaemonApi? api;
  final ApprovalNotifier? notifier;
  final http.Client? httpClient;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _csrfController;
  bool _useSsl = EnvConfig.useSsl;
  bool _toolNotifications = true;
  bool _diagnosticsBusy = false;
  List<String> _branches = [];
  bool _isLoadingBranches = false;
  String _selectedDefaultModel = 'Gemini 3.7 Flash Medium';
  // Délai d'auto-refus des approbations d'outils (0 = désactivé). Valeur par
  // défaut alignée sur le daemon (5 min) ; persisté et poussé au daemon via
  // le message WS set_approval_timeout (minutes).
  static const int _defaultApprovalTimeoutMinutes = 5;
  late TextEditingController _approvalTimeoutController;
  int _approvalTimeoutMinutes = _defaultApprovalTimeoutMinutes;
  bool _approvalTimeoutSaved = false;
  // Auto-approbation des actions read-only (lectures/recherches) : toggle
  // poussé au daemon via le message WS set_auto_accept. Désactivé par défaut
  // (toute action non read-only reste soumise à approbation).
  bool _autoAcceptEnabled = false;
  String _autoAcceptMode = 'readonly';
  bool _mcpAllowlistStrict = true;
  bool _isGeminiEnterprise = true;
  // Appareils pairés (3.4, admin) : liste brute des sessions renvoyée par
  // admin.list_devices (deviceId, name, ip, admin, allowedProjects...).
  List<Map<String, dynamic>> _devices = [];
  bool _devicesLoading = false;
  bool _devicesError = false;
  final List<String> _models = [
    'Gemini 3.7 Flash Medium',
    'Gemini 3.6 Flash Medium',
    'Gemini 3.5 Flash Medium',
    'Gemini 3.1 Pro Low',
    'Claude Sonnet 4.6 (Thinking)',
    'Claude Opus 4.6 (Thinking)',
    'GPT-OSS 120B (Medium)',
    'GPT-4o',
    'Claude 3.7 Sonnet',
    'DeepSeek R1',
  ];

  String _activeBranch = 'main';

  @override
  void initState() {
    super.initState();
    final s = widget.initialSettings;
    _activeBranch = (s['activeBranch'] as String?) ?? 'main';
    _hostController = TextEditingController(
      text: (s['host'] as String?)?.trim().isNotEmpty == true
          ? (s['host'] as String).trim()
          : EnvConfig.daemonHost,
    );
    _portController = TextEditingController(
      text: ((s['port'] as int?) ?? EnvConfig.daemonPort).toString(),
    );
    _csrfController = TextEditingController(text: (s['csrf'] as String?) ?? '');
    _useSsl = (s['ssl'] as bool?) ?? EnvConfig.useSsl;
    _selectedDefaultModel =
        (s['defaultModel'] as String?) ?? 'Gemini 3.7 Flash Medium';
    if (!_models.contains(_selectedDefaultModel)) {
      _models.insert(0, _selectedDefaultModel);
    }
    _toolNotifications = (s['toolNotifications'] as bool?) ?? true;
    _approvalTimeoutMinutes =
        (s['approvalTimeoutMinutes'] as int?) ?? _defaultApprovalTimeoutMinutes;
    _approvalTimeoutController =
        TextEditingController(text: '$_approvalTimeoutMinutes');
    _autoAcceptEnabled = (s['autoAcceptEnabled'] as bool?) ?? false;
    _autoAcceptMode = (s['autoAcceptMode'] as String?) ?? 'readonly';
    // Applique le réglage persisté dès l'ouverture (le notifier est un
    // singleton : il faut re-synchroniser son état global).
    widget.notifier?.setEnabled(_toolNotifications);
    _fetchCustomModels();
    _applyApprovalTimeoutToDaemon();
    _fetchBranches();
    _fetchDevices();
  }

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
      debugPrint('Failed to fetch branches: $e');
    } finally {
      if (mounted) setState(() => _isLoadingBranches = false);
    }
  }

  Future<void> _fetchCustomModels() async {
    if (widget.api != null) {
      final models = await ModelCatalog.fetchCustomModels(widget.api);
      if (mounted && models.isNotEmpty) {
        setState(() {
          for (final m in models) {
            if (!_models.contains(m.displayName)) {
              _models.add(m.displayName);
            }
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _csrfController.dispose();
    _approvalTimeoutController.dispose();
    super.dispose();
  }

  /// Charge la liste des appareils pairés (3.4, admin.list_devices). Best-effort :
  /// sans daemon connecté ou sans droit admin, on affiche un état vide/erreur
  /// discret au lieu de faire planter l'écran de réglages.
  Future<void> _fetchDevices() async {
    if (widget.api == null) return;
    setState(() {
      _devicesLoading = true;
      _devicesError = false;
    });
    try {
      final devices = await widget.api!.listDevices();
      if (mounted) {
        setState(() {
          _devices = devices;
          _devicesLoading = false;
        });
      }
    } catch (e) {
      debugPrint('listDevices failed: ');
      if (mounted) {
        setState(() {
          _devicesError = true;
          _devicesLoading = false;
        });
      }
    }
  }

  /// Révoque un appareil pairé (3.4, admin.revoke_device) après confirmation.
  /// Sur succès, on retire l'appareil de la liste locale (le daemon broadcast
  /// aussi devices_updated, mais on ne l'écoute pas ici).
  Future<void> _revokeDevice(Map<String, dynamic> device) async {
    final deviceId = device['deviceId']?.toString() ?? '';
    final name = device['name']?.toString() ?? deviceId;
    if (deviceId.isEmpty || widget.api == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Révoquer cet appareil ?'),
        content: Text(
          '« $name » perdra immédiatement l\'accès au daemon. '
          'Cette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Révoquer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final ok = await widget.api!.revokeDevice(deviceId);
      if (!mounted) return;
      if (ok) {
        setState(() => _devices.removeWhere((d) => d['deviceId'] == deviceId));
        AppToast.show(
          context,
          message: 'Appareil « $name » révoqué.',
          icon: Icons.devices_other_outlined,
        );
      } else {
        AppToast.show(
          context,
          message: 'Appareil introuvable (déjà révoqué ?).',
          type: ToastType.warning,
        );
        _fetchDevices();
      }
    } catch (e) {
      debugPrint('revokeDevice failed: $e');
      if (mounted) {
        AppToast.show(
          context,
          message: 'Échec de la révocation (droits admin requis).',
          type: ToastType.error,
        );
      }
    }
  }

  /// Persiste le délai d'auto-refus et l'applique au daemon (set_approval_timeout).
  Future<void> _applyApprovalTimeoutToDaemon() async {
    final minutes = int.tryParse(_approvalTimeoutController.text.trim());
    if (minutes == null || minutes < 0) return;
    setState(() {
      _approvalTimeoutMinutes = minutes;
      _approvalTimeoutSaved = true;
    });
    await SettingsStore.save({'approvalTimeoutMinutes': minutes});
    // Envoi non bloquant : sans daemon connecté, le RPC expire silencieusement.
    try {
      await widget.api?.sendWithResult('set_approval_timeout', {
        'data': {'minutes': minutes},
      });
    } catch (_) {}
  }

  /// URL ws(s)://host:port du daemon — source unique pour l'export de
  /// diagnostics et toute future connexion directe.
  Uri _daemonUri() {
    final scheme = _useSsl ? 'https' : 'http';
    final host = _hostController.text.trim().isEmpty
        ? EnvConfig.daemonHost
        : _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? EnvConfig.daemonPort;
    return Uri(scheme: scheme, host: host, port: port);
  }

  /// Persiste la config bridge + prévient le main screen (reconnexion).
  Future<void> _saveDaemonConfig() async {
    final portText = _portController.text.trim();
    final port = int.tryParse(portText);
    if (portText.isNotEmpty && (port == null || port < 1 || port > 65535)) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Le port doit être un nombre valide entre 1 et 65535.',
          icon: Icons.error_outline,
          type: ToastType.error,
        );
      }
      return;
    }

    final config = {
      'host': _hostController.text.trim(),
      if (port != null) 'port': port,
      'ssl': _useSsl,
      'csrf': _csrfController.text.trim(),
    };
    await SettingsStore.save(config);
    widget.onDaemonSaved?.call(config);
    if (!mounted) return;
    AppToast.show(
      context,
      message: 'Connexion Daemon enregistrée !',
      icon: Icons.check_circle_outline,
      type: ToastType.success,
    );
  }

  /// Persiste le modèle par défaut choisi.
  Future<void> _setDefaultModel(String model) async {
    setState(() => _selectedDefaultModel = model);
    await SettingsStore.save({'defaultModel': model});
    // Le daemon connaît la commande /model : on l'applique si connecté.
    try {
      await widget.api?.sendCommand('/model $model');
    } catch (_) {}
  }

  /// GET /health/diagnostic → export JSON (logs + state) → partage.
  Future<void> _downloadDiagnostics() async {
    setState(() => _diagnosticsBusy = true);
    try {
      final client = widget.httpClient ?? http.Client();
      final response = await client
          .get(_daemonUri().replace(path: '/health/diagnostic'))
          .timeout(const Duration(seconds: 10));
      final file = File(
        '${(await getApplicationDocumentsDirectory()).path}/diagnostics_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(jsonDecode(response.body)),
      );
      await Share.shareXFiles([XFile(file.path)]);
      if (!mounted) return;
      AppToast.show(
        context,
        message: 'Paquet de diagnostic exporté avec succès !',
        icon: Icons.file_download_done,
        type: ToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: 'Export impossible : $e',
        icon: Icons.error_outline,
        type: ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _diagnosticsBusy = false);
    }
  }

  Widget _buildAdaptivePair(BuildContext context, Widget child1, Widget child2) {
    final isCompact = MediaQuery.sizeOf(context).width < 500;
    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child1,
          const SizedBox(height: 12),
          child2,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: child1),
        const SizedBox(width: 12),
        Expanded(child: child2),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Paramètres'),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── USER PROFILE (éditable)
          const _SectionTitle(title: 'PROFILE'),
          ProfileSettingsSection(
            initialName: (widget.initialSettings['displayName'] as String?) ?? 'Amine Developer',
            initialRole: (widget.initialSettings['role'] as String?) ?? 'Remote Host Controller',
            initialStatus: (widget.initialSettings['status'] as String?) ?? 'Online',
          ),

          const SizedBox(height: 20),

          // ── WORKSPACE & BRANCH
          const _SectionTitle(title: 'WORKSPACE & BRANCH'),
          const SizedBox(height: 8),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _isLoadingBranches
                    ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                    : GitWorktreeSelector(
                    currentBranch: _activeBranch,
                    branches: _branches.isEmpty ? ['main'] : _branches,
                    onBranchSelected: (b) async {
                      final oldBranch = _activeBranch;
                      setState(() => _activeBranch = b);
                      try {
                        await widget.api?.sendCommand('/checkout $b');
                        await SettingsStore.save({'activeBranch': b});
                        if (context.mounted) {
                          AppToast.show(
                            context,
                            message: 'Branche active : $b',
                            icon: Icons.alt_route,
                            type: ToastType.success,
                          );
                        }
                      } catch (e) {
                        setState(() => _activeBranch = oldBranch);
                        final errMsg = e.toString().toLowerCase();
                        if (context.mounted) {
                          if (errMsg.contains('conflict') || errMsg.contains('uncommitted') || errMsg.contains('merge') || errMsg.contains('please commit')) {
                            final force = await ConflictDialog.show(
                              context,
                              title: 'Conflit Git détecté',
                              message: 'Le changement vers la branche "$b" a échoué car vous avez des modifications non commitées qui seraient écrasées.',
                              conflictDetails: e.toString(),
                              primaryButtonText: 'Forcer (perte locale)',
                            );
                            if (force == true && widget.api != null) {
                              try {
                                await widget.api!.sendCommand('/checkout -f $b');
                                setState(() => _activeBranch = b);
                                await SettingsStore.save({'activeBranch': b});
                                if (context.mounted) {
                                  AppToast.show(context, message: 'Branche forcée : $b', type: ToastType.success);
                                }
                              } catch (e2) {
                                if (context.mounted) {
                                  AppToast.show(context, message: 'Échec du checkout forcé.', type: ToastType.error);
                                }
                              }
                            }
                          } else {
                             AppToast.show(context, message: 'Erreur lors du checkout.', type: ToastType.error);
                          }
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── GESTION DE PROJET
          const _SectionTitle(title: 'PARAMÈTRES ET SUPPRESSION DU PROJET'),
          const SizedBox(height: 8),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Zone Dangereuse',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Supprimer définitivement ce projet et toutes ses conversations associées.',
                    style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: Theme.of(ctx).colorScheme.surfaceContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            side: BorderSide(color: Theme.of(ctx).colorScheme.outlineVariant),
                          ),
                          title: const Text('Supprimer définitivement le projet ?'),
                          content: const Text(
                            'Cette action supprimera le projet ainsi que toutes ses conversations actives et archivées.\n\nCette action est irréversible.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Annuler'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                              onPressed: () async {
                                Navigator.of(ctx).pop();
                                if (widget.api != null) {
                                  try {
                                    await widget.api!.sendCommand('/clear');
                                  } catch (_) {}
                                }
                                if (context.mounted) {
                                  AppToast.show(
                                    context,
                                    message: 'Projet et conversations réinitialisés avec succès.',
                                    icon: Icons.delete_sweep_outlined,
                                    type: ToastType.warning,
                                  );
                                }
                              },
                              child: const Text('Supprimer définitivement'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: Icon(Icons.delete_forever_outlined, size: 16, color: Theme.of(context).colorScheme.error),
                    label: Text('Supprimer le projet', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── DAEMON CONNECTION SETTINGS
          const _SectionTitle(title: 'DAEMON BRIDGE CONNECTION'),
          const SizedBox(height: 8),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Daemon Host IP / Domain',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _hostController,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: 'e.g. 192.168.1.50 or tunnel.domain.com',
                      prefixIcon: Icon(Icons.lan_outlined, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _buildAdaptivePair(
                    context,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Port',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _portController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: EnvConfig.daemonPort.toString(),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SSL / TLS (WSS)',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 6),
                        SwitchListTile(
                          value: _useSsl,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) => setState(() => _useSsl = val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  Text('CSRF Security Token',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _csrfController,
                    obscureText: true,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.key_outlined, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saveDaemonConfig,
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: const Text('Enregistrer la configuration'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── PREFERENCES & MODEL SETTINGS
          const _SectionTitle(title: 'PREFERENCES & AI MODEL'),
          const SizedBox(height: 8),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Modèle par défaut',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _selectedDefaultModel,
                    dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.smart_toy_outlined, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    items: _models
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) _setDefaultModel(val);
                    },
                  ),
                  const SizedBox(height: 12),

                  Text('Délai d\'auto-refus des approbations (minutes)',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('settings-approval-timeout-field'),
                          controller: _approvalTimeoutController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: '$_defaultApprovalTimeoutMinutes',
                            suffixIcon: Icon(Icons.timer_outlined, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Appliquer le délai au daemon',
                        icon: Icon(
                          _approvalTimeoutSaved ? Icons.check_circle_outline : Icons.check,
                          size: 20,
                          color: _approvalTimeoutSaved
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        onPressed: _applyApprovalTimeoutToDaemon,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '0 = désactiver l\'auto-refus (le daemon attendra indéfiniment). Défaut : 5 min.',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),

                  SwitchListTile(
                    title: Text(
                      'Notifications Push (Tool Approvals)',
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    subtitle: Text(
                      'Recevoir une alerte sonore quand une commande requiert votre accord',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    value: _toolNotifications,
                    activeColor: Theme.of(context).colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setState(() => _toolNotifications = val);
                      SettingsStore.save({'toolNotifications': val});
                      widget.notifier?.setEnabled(val);
                    },
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    title: Text(
                      'Auto-approuver les actions en lecture seule',
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    subtitle: Text(
                      _autoAcceptMode == 'full'
                          ? 'Accès total : toutes les commandes et écritures passent automatiquement (sauf questions interactives).'
                          : 'Lecture seule : fichiers et recherches passent sans confirmation. Écritures et commandes requièrent accord.',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    value: _autoAcceptEnabled,
                    activeColor: Theme.of(context).colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) async {
                      setState(() => _autoAcceptEnabled = val);
                      await SettingsStore.save({'autoAcceptEnabled': val, 'autoAcceptMode': _autoAcceptMode});
                      try {
                        await widget.api?.setAutoAccept(enabled: val, mode: _autoAcceptMode);
                      } catch (_) {}
                    },
                  ),
                  if (_autoAcceptEnabled) ...[
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'readonly',
                          label: Text('Lecture seule', style: TextStyle(fontSize: 12)),
                          icon: Icon(Icons.visibility_outlined, size: 14),
                        ),
                        ButtonSegment(
                          value: 'full',
                          label: Text('Accès total', style: TextStyle(fontSize: 12)),
                          icon: Icon(Icons.flash_on_outlined, size: 14),
                        ),
                      ],
                      selected: {_autoAcceptMode},
                      onSelectionChanged: (newSelection) async {
                        final newMode = newSelection.first;
                        setState(() => _autoAcceptMode = newMode);
                        await SettingsStore.save({'autoAcceptMode': newMode});
                        try {
                          await widget.api?.setAutoAccept(enabled: _autoAcceptEnabled, mode: newMode);
                        } catch (_) {}
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── ENTERPRISE & ADMINISTRATION
          const _SectionTitle(title: 'ENTERPRISE & ADMINISTRATION'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: Text(
                      'Gemini Enterprise Tier',
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    subtitle: Text(
                      'Activer les fonctionnalités d\'entreprise et quotas étendus',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    value: _isGeminiEnterprise,
                    activeColor: Theme.of(context).colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setState(() => _isGeminiEnterprise = val);
                      SettingsStore.save({'isGeminiEnterprise': val});
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: Text(
                      'Liste d\'autorisation MCP stricte',
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    subtitle: Text(
                      'Restreindre l\'accès aux serveurs MCP explicitement approuvés',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    value: _mcpAllowlistStrict,
                    activeColor: Theme.of(context).colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setState(() => _mcpAllowlistStrict = val);
                      SettingsStore.save({'mcpAllowlistStrict': val});
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── PAIRED DEVICES (3.4, admin)
          const _SectionTitle(title: 'APPAREILS PAIRÉS'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Appareils connectés au daemon',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Actualiser',
                        icon: const Icon(Icons.refresh, size: 18),
                        onPressed: _devicesLoading ? null : _fetchDevices,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (_devicesLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (_devicesError)
                    Text(
                      'Liste indisponible (daemon déconnecté ou droits admin requis).',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  else if (_devices.isEmpty)
                    Text(
                      'Aucun autre appareil pairé. Le premier appareil appairé est administrateur.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    ..._devices.map(
                      (d) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.smartphone_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          d['name']?.toString() ?? 'Appareil',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          [
                            if (d['ip']?.toString().isNotEmpty == true)
                              d['ip'].toString(),
                            if (d['admin'] == true) 'admin',
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Révoquer l\'accès',
                          icon: Icon(
                            Icons.link_off_outlined,
                            size: 18,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          onPressed: () => _revokeDevice(d),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── APPEARANCE
          const _SectionTitle(title: 'APPEARANCE'),
          const SizedBox(height: 8),
          AppearanceSettingsSection(
            initialIndex: ((widget.initialSettings['themeMode'] as int?) ?? 0)
                .clamp(0, 2),
            initialCompactBubbles: (widget.initialSettings['compactBubbles'] as bool?) ?? false,
            initialMonospaceCode: (widget.initialSettings['monospaceCode'] as bool?) ?? true,
            onThemeModeChanged: widget.onThemeModeChanged ?? (_) {},
          ),

          const SizedBox(height: 20),

          // ── ABOUT & VERSION
          const _SectionTitle(title: 'SYSTEM & DIAGNOSTICS'),
          const SizedBox(height: 8),

          Card(
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  leading: Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  title: Text('Version de l\'application', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                  trailing: Text('v1.0.0 (Build 42)', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
                const Divider(),
                ListTile(
                  dense: true,
                  enabled: !_diagnosticsBusy,
                  leading: _diagnosticsBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.download_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary),
                  title: Text(
                    'Télécharger les diagnostics',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'Exporter les journaux d\'exécution et l\'état de l\'agent (.json)',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onTap: _downloadDiagnostics,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final displayTitle = title == 'AGENT' ? 'GÉNÉRAL' : title;
    return Semantics(
      header: true,
      label: displayTitle,
      child: Text(
        displayTitle,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

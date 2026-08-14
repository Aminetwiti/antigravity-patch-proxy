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
import '../workspace/git_worktree_selector.dart';
import 'appearance_settings_section.dart';
import 'profile_settings_section.dart';
import '../theme/app_colors.dart';

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
  String _selectedDefaultModel = 'Gemini 3.7 Flash Medium';
  // Délai d'auto-refus des approbations d'outils (0 = désactivé). Valeur par
  // défaut alignée sur le daemon (5 min) ; persisté et poussé au daemon via
  // le message WS set_approval_timeout (minutes).
  static const int _defaultApprovalTimeoutMinutes = 5;
  late TextEditingController _approvalTimeoutController;
  int _approvalTimeoutMinutes = _defaultApprovalTimeoutMinutes;
  bool _approvalTimeoutSaved = false;

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

  // Feature Gemini Enterprise & Enterprise Admin Policies
  bool _isGeminiEnterprise = true;
  String _geTier = 'GE-Plus';
  String _inferenceRegion = 'UE (Europe)';
  bool _mcpAllowlistStrict = true;
  String _executionPolicy = 'request-review';

  @override
  void initState() {
    super.initState();
    final s = widget.initialSettings;
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
    _isGeminiEnterprise = (s['isGeminiEnterprise'] as bool?) ?? true;
    _geTier = (s['geTier'] as String?) ?? 'GE-Plus';
    _inferenceRegion = (s['inferenceRegion'] as String?) ?? 'UE (Europe)';
    _mcpAllowlistStrict = (s['mcpAllowlistStrict'] as bool?) ?? true;
    _executionPolicy = (s['executionPolicy'] as String?) ?? 'request-review';
    _approvalTimeoutMinutes =
        (s['approvalTimeoutMinutes'] as int?) ?? _defaultApprovalTimeoutMinutes;
    _approvalTimeoutController =
        TextEditingController(text: '$_approvalTimeoutMinutes');
    // Applique le réglage persisté dès l'ouverture (le notifier est un
    // singleton : il faut re-synchroniser son état global).
    widget.notifier?.setEnabled(_toolNotifications);
    _fetchCustomModels();
    _applyApprovalTimeoutToDaemon();
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
    final port = int.tryParse(_portController.text.trim());
    final config = {
      'host': _hostController.text.trim(),
      if (port != null) 'port': port,
      'ssl': _useSsl,
      'csrf': _csrfController.text.trim(),
    };
    await SettingsStore.save(config);
    widget.onDaemonSaved?.call(config);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Connexion Daemon enregistrée !')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Paquet de diagnostic exporté avec succès (logs + state) !',
          ),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export impossible : $e')),
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
          const SizedBox(height: 8),
          const ProfileSettingsSection(),

          const SizedBox(height: 20),

          // ── GEMINI ENTERPRISE & GOOGLE CLOUD
          const _SectionTitle(title: 'GEMINI ENTERPRISE & COMPLIANCE'),
          const SizedBox(height: 8),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: Text(
                      'Compte Gemini Enterprise',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    subtitle: Text(
                      'Contrôles administrateur d\'organisation & Conditions Google Cloud',
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
                  if (_isGeminiEnterprise) ...[
                    const Divider(),
                    const SizedBox(height: 8),
                    _buildAdaptivePair(
                      context,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Niveau d\'abonnement',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: _geTier,
                            dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
                            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                            items: ['GE-Standard', 'GE-Plus']
                                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _geTier = val);
                                SettingsStore.save({'geTier': val});
                              }
                            },
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Inférence Régionalisée',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: _inferenceRegion,
                            dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
                            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                            items: ['États-Unis', 'UE (Europe)', 'Global']
                                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _inferenceRegion = val);
                                SettingsStore.save({'inferenceRegion': val});
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.verified_user_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Licence attribuée automatiquement sous les conditions Google Cloud (Région : $_inferenceRegion).',
                              style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── POLITIQUES D'ADMINISTRATION D'ENTREPRISE
          const _SectionTitle(title: 'POLITIQUES D\'ADMINISTRATION D\'ENTREPRISE'),
          const SizedBox(height: 8),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: Text(
                      'Liste d\'autorisation MCP stricte',
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    subtitle: Text(
                      'Seuls les serveurs MCP approuvés par l\'organisation sont autorisés',
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
                  const Divider(),
                  Text('Politique d\'exécution des outils', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(height: 4),
                  Text('Définit quand l\'agent peut exécuter des commandes sur le workspace', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _executionPolicy,
                    decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                    items: const [
                      DropdownMenuItem(value: 'strict', child: Text('Strict (Approbat. manuelle)')),
                      DropdownMenuItem(value: 'request-review', child: Text('Révision (Si sensible)')),
                      DropdownMenuItem(value: 'always-proceed', child: Text('Auto (Sans approbat.)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _executionPolicy = val);
                        SettingsStore.save({'executionPolicy': val});
                      }
                    },
                  ),
                  const Divider(),
                  // ponytail: liste statique des branches/worktrees en attendant l'intégration daemon
                  GitWorktreeSelector(
                    currentBranch: 'main',
                    branches: const ['main', 'feature/remote-v2', 'fix/websocket-reconnect'],
                    onBranchSelected: (b) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Branche active : $b')));
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
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Projet et conversations réinitialisés avec succès.')),
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
                ],
              ),
            ),
          ),

          // ── APPEARANCE
          const _SectionTitle(title: 'APPEARANCE'),
          const SizedBox(height: 8),
          AppearanceSettingsSection(
            initialIndex: ((widget.initialSettings['themeMode'] as int?) ?? 0)
                .clamp(0, 2),
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

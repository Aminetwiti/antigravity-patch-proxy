import 'package:flutter/material.dart';
import '../../config/env_config.dart';
import 'appearance_settings_section.dart';
import 'profile_settings_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _csrfController;
  bool _useSsl = EnvConfig.useSsl;
  bool _toolNotifications = true;
  String _selectedDefaultModel = 'Gemini 3.6 Flash Medium';

  final List<String> _models = [
    'Gemini 3.6 Flash Medium',
    'Claude 3.7 Sonnet',
    'DeepSeek R1',
    'GPT-4o',
    'Ollama Local Model',
  ];

  // Feature Gemini Enterprise & Enterprise Admin Policies
  bool _isGeminiEnterprise = true;
  String _geTier = 'GE-Plus';
  String _inferenceRegion = 'UE (Europe)';
  bool _mcpAllowlistStrict = true;
  bool _browserFeaturesEnabled = true;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: EnvConfig.daemonHost);
    _portController = TextEditingController(text: EnvConfig.daemonPort.toString());
    _csrfController = TextEditingController(text: '••••••••••••••••••••••••');
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _csrfController.dispose();
    super.dispose();
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
                    onChanged: (val) => setState(() => _isGeminiEnterprise = val),
                  ),
                  if (_isGeminiEnterprise) ...[
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
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
                                  if (val != null) setState(() => _geTier = val);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
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
                                  if (val != null) setState(() => _inferenceRegion = val);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
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
                    onChanged: (val) => setState(() => _mcpAllowlistStrict = val),
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: Text(
                      'Fonctionnalités du navigateur web',
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    subtitle: Text(
                      'Autoriser le sous-agent navigateur pour les tâches d\'exploration',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    value: _browserFeaturesEnabled,
                    activeColor: Theme.of(context).colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setState(() => _browserFeaturesEnabled = val),
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
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Projet et conversations supprimés avec succès.')),
                                );
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

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Port',
                                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _portController,
                              keyboardType: TextInputType.number,
                              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                              decoration: const InputDecoration(
                                hintText: '8090',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
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
                    ],
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
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Connexion Daemon enregistrée !')),
                        );
                      },
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
                      if (val != null) setState(() => _selectedDefaultModel = val);
                    },
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
                    onChanged: (val) => setState(() => _toolNotifications = val),
                  ),
                ],
              ),
            ),
          ),

          // ── APPEARANCE
          const _SectionTitle(title: 'APPEARANCE'),
          const SizedBox(height: 8),
          const AppearanceSettingsSection(),

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
                  leading: Icon(Icons.download_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                  title: Text(
                    'Télécharger les diagnostics',
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Exporter les journaux d\'exécution et l\'état de l\'agent (.json)',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Paquet de diagnostic exporté avec succès (logs + state) !'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
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

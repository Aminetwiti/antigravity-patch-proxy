import 'package:flutter/material.dart';
import '../../config/env_config.dart';
import '../../theme/app_colors.dart';

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
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        title: const Text('Settings & Profile'),
        backgroundColor: AppColors.surfaceRaised,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── USER PROFILE CARD
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.accentBlue,
                    child: const Text(
                      'A',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Amine Developer',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Remote Host Controller • PC Linked',
                          style: TextStyle(fontSize: 12, color: AppColors.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.positive.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.positive,
                      ),
                    ),
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
                  const Text('Daemon Host IP / Domain',
                      style: TextStyle(fontSize: 12, color: AppColors.inkSecondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _hostController,
                    style: const TextStyle(fontSize: 13, color: AppColors.inkPrimary),
                    decoration: const InputDecoration(
                      hintText: 'e.g. 192.168.1.50 or tunnel.domain.com',
                      prefixIcon: Icon(Icons.lan_outlined, size: 18, color: AppColors.inkMuted),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Port',
                                style: TextStyle(fontSize: 12, color: AppColors.inkSecondary)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _portController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 13, color: AppColors.inkPrimary),
                              decoration: const InputDecoration(
                                hintText: '8080',
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
                            const Text('SSL / TLS (WSS)',
                                style: TextStyle(fontSize: 12, color: AppColors.inkSecondary)),
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

                  const Text('CSRF Security Token',
                      style: TextStyle(fontSize: 12, color: AppColors.inkSecondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _csrfController,
                    obscureText: true,
                    style: const TextStyle(fontSize: 13, color: AppColors.inkPrimary),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.key_outlined, size: 18, color: AppColors.inkMuted),
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
                  const Text('Modèle par défaut',
                      style: TextStyle(fontSize: 12, color: AppColors.inkSecondary)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _selectedDefaultModel,
                    dropdownColor: AppColors.surfaceRaised,
                    style: const TextStyle(fontSize: 13, color: AppColors.inkPrimary),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.smart_toy_outlined, size: 18, color: AppColors.inkMuted),
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
                    title: const Text(
                      'Notifications Push (Tool Approvals)',
                      style: TextStyle(fontSize: 13, color: AppColors.inkPrimary),
                    ),
                    subtitle: const Text(
                      'Recevoir une alerte sonore quand une commande requiert votre accord',
                      style: TextStyle(fontSize: 11, color: AppColors.inkMuted),
                    ),
                    value: _toolNotifications,
                    activeColor: AppColors.accentBlue,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setState(() => _toolNotifications = val),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── ABOUT & VERSION
          const _SectionTitle(title: 'SYSTEM & DIAGNOSTICS'),
          const SizedBox(height: 8),

          Card(
            child: Column(
              children: const [
                ListTile(
                  dense: true,
                  leading: Icon(Icons.info_outline, size: 18, color: AppColors.inkSecondary),
                  title: Text('Version de l\'application', style: TextStyle(fontSize: 13, color: AppColors.inkPrimary)),
                  trailing: Text('v1.0.0 (Build 42)', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                ),
                Divider(color: AppColors.borderSubtle),
                ListTile(
                  dense: true,
                  leading: Icon(Icons.terminal_outlined, size: 18, color: AppColors.inkSecondary),
                  title: Text('Protocole ConnectRPC / gRPC-Web', style: TextStyle(fontSize: 13, color: AppColors.inkPrimary)),
                  trailing: Text('Active (v1)', style: TextStyle(fontSize: 12, color: AppColors.positive)),
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
    return Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.inkSecondary,
        letterSpacing: 0.8,
      ),
    );
  }
}

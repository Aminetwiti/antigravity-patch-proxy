import 'package:flutter/material.dart';
import '../../config/env_config.dart';
import '../../theme/app_colors.dart';
import 'qr_scanner_screen.dart';

class DiscoveryScreen extends StatefulWidget {
  final Future<bool> Function(String host, int port, String csrfToken)? onConnect;

  const DiscoveryScreen({super.key, this.onConnect});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final TextEditingController _hostController =
      TextEditingController(text: EnvConfig.daemonHost);
  final TextEditingController _portController =
      TextEditingController(text: EnvConfig.daemonPort.toString());
  final TextEditingController _csrfController = TextEditingController();

  bool _isConnecting = false;
  String? _errorMessage;
  String? _successMessage;

  final List<String> _discoveredHosts = [];

  // Lancement du scanner QR
  Future<void> _startScan() async {
    final scannedCode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (scannedCode != null && scannedCode.isNotEmpty) {
      // Ex: wss://abcd.trycloudflare.com/ws?token=mysecret
      final uri = Uri.tryParse(scannedCode);
      if (uri != null) {
        final host = '${uri.scheme}://${uri.host}${uri.path}';
        final port = uri.port > 0 ? uri.port : (uri.scheme == 'wss' || uri.scheme == 'https' ? 443 : 80);
        final token = uri.queryParameters['token'] ?? '';

        setState(() {
          _hostController.text = host;
          _portController.text = port.toString();
          _csrfController.text = token;
        });

        // Auto-connect
        _connect();
      }
    }
  }

  Future<void> _connect() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    if (host.isEmpty || port == null) {
      setState(() => _errorMessage = 'Veuillez saisir un hôte et un port valides.');
      return;
    }
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
      _successMessage = null;
    });
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final ok = widget.onConnect == null || await widget.onConnect!(host, port, _csrfController.text.trim());
    if (!mounted) return;
    setState(() {
      _isConnecting = false;
      if (ok) {
        _successMessage = 'Appairé avec succès : $host:$port';
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.of(context).pop(true);
        });
      } else {
        _errorMessage = 'Connexion refusée. Vérifiez le port et le token CSRF.';
      }
    });
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
        title: Text('Discover Daemons', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Intro Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.accentBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.podcasts, color: AppColors.accentBlue, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Découvrir le Daemon Bridge',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Scannez votre réseau local ou saisissez manuellement l\'adresse du PC hôte.',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Scan QR Code Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _startScan,
              icon: Icon(Icons.qr_code_scanner, size: 16, color: Theme.of(context).colorScheme.primary),
              label: Text(
                'Scanner le QR Code',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.accentBlue),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          if (_discoveredHosts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'RÉSEAU LOCAL (mDNS)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Card(
              child: Column(
                children: _discoveredHosts.map((host) {
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.computer, size: 18, color: AppColors.positive),
                    title: Text(host, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                    subtitle: Text('Daemon Bridge détecté', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    trailing: Icon(Icons.chevron_right, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    onTap: () {
                      _hostController.text = host;
                    },
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),

          // ── Manual Entry Section
          Text(
            'CONNEXION MANUELLE',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hôte PC / Domaine', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _hostController,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.lan_outlined, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      hintText: '192.168.1.50',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Port Daemon', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.numbers, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      hintText: '8090',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Token Auth (optionnel)', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, size: 16, color: Theme.of(context).colorScheme.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_errorMessage!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (_successMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.positive.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, size: 16, color: AppColors.positive),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_successMessage!, style: const TextStyle(fontSize: 12, color: AppColors.positive)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isConnecting ? null : _connect,
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _isConnecting
                            ? const SizedBox(key: ValueKey('loading'), width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.link, key: ValueKey('link'), size: 16),
                      ),
                      label: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          _isConnecting ? 'Connexion…' : 'Appairer & Connecter',
                          key: ValueKey<bool>(_isConnecting),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          const _SectionHeader(title: 'AGENTS PERSONNALISÉS'),
          const SizedBox(height: 8),

          _CustomAgentManager(),
        ],
      ),
    );
  }
}

class _CustomAgentManager extends StatefulWidget {
  @override
  State<_CustomAgentManager> createState() => _CustomAgentManagerState();
}

class _CustomAgentManagerState extends State<_CustomAgentManager> {
  final List<Map<String, dynamic>> _customAgents = [
    {'id': 'ca1', 'name': 'Code Reviewer Agent', 'active': true},
    {'id': 'ca2', 'name': 'Refactoring Specialist', 'active': false},
    {'id': 'ca3', 'name': 'Doc Generator', 'active': true},
  ];

  @override
  Widget build(BuildContext context) {
    if (_customAgents.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Aucun agent personnalisé configuré.',
            style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          for (int i = 0; i < _customAgents.length; i++) ...[
            if (i > 0) const Divider(),
            ListTile(
              dense: true,
              leading: Icon(
                Icons.smart_toy_outlined,
                size: 18,
                color: _customAgents[i]['active'] ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              title: Text(
                _customAgents[i]['name'],
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _customAgents[i]['active'] ? 'Activé' : 'Désactivé',
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: _customAgents[i]['active'],
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (val) => setState(() => _customAgents[i]['active'] = val),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    tooltip: 'Supprimer l\'agent',
                    onPressed: () {
                      final name = _customAgents[i]['name'];
                      setState(() => _customAgents.removeAt(i));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Agent "$name" supprimé.')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.8,
      ),
    );
  }
}

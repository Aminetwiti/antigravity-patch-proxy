import 'package:flutter/material.dart';
import '../../config/env_config.dart';
import '../../theme/app_colors.dart';

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

  bool _isScanning = false;
  bool _isConnecting = false;
  String? _errorMessage;
  String? _successMessage;

  List<String> _discoveredHosts = [];

  // ponytail: mock scan for demo — replace with real UDP/port scanner against Daemon
  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() {
      _isScanning = false;
      _discoveredHosts = ['192.168.1.50', '192.168.1.42', '10.0.2.2'];
    });
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
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        title: const Text('Appairage Daemon'),
        backgroundColor: AppColors.surfaceRaised,
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
                      children: const [
                        Text(
                          'Découvrir le Daemon Bridge',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.inkPrimary),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Scannez votre réseau local ou saisissez manuellement l\'adresse du PC hôte.',
                          style: TextStyle(fontSize: 12, color: AppColors.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Scan Network Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isScanning ? null : _startScan,
              icon: _isScanning
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentBlue),
                    )
                  : const Icon(Icons.radar, size: 16, color: AppColors.accentBlue),
              label: Text(
                _isScanning ? 'Scan en cours…' : 'Scanner le réseau local',
                style: const TextStyle(fontSize: 13, color: AppColors.inkPrimary),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.accentBlue),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          if (_discoveredHosts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: _discoveredHosts.map((host) {
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.computer, size: 18, color: AppColors.positive),
                    title: Text(host, style: const TextStyle(fontSize: 13, color: AppColors.inkPrimary)),
                    subtitle: const Text('Daemon Bridge détecté', style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
                    trailing: const Icon(Icons.chevron_right, size: 16, color: AppColors.inkMuted),
                    onTap: () {
                      _hostController.text = host;
                    },
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 20),
          const Divider(color: AppColors.borderSubtle),
          const SizedBox(height: 16),

          // ── Manual Entry Section
          const Text(
            'CONNEXION MANUELLE',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkSecondary, letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Hôte PC / Domaine', style: TextStyle(fontSize: 12, color: AppColors.inkSecondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _hostController,
                    style: const TextStyle(fontSize: 13, color: AppColors.inkPrimary),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.lan_outlined, size: 18, color: AppColors.inkMuted),
                      hintText: '192.168.1.50',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Port Daemon', style: TextStyle(fontSize: 12, color: AppColors.inkSecondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 13, color: AppColors.inkPrimary),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.numbers, size: 18, color: AppColors.inkMuted),
                      hintText: '8080',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Token CSRF (optionnel)', style: TextStyle(fontSize: 12, color: AppColors.inkSecondary)),
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

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_errorMessage!, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
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
                      icon: _isConnecting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.link, size: 16),
                      label: Text(_isConnecting ? 'Connexion…' : 'Appairer & Connecter'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

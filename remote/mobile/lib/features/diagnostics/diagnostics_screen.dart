import 'package:flutter/material.dart';
import '../../core/protocol/daemon_api.dart';
import '../../theme/app_colors.dart';

/// Écran de diagnostic & profiling FlightRecorder (runtime/trace Go).
class DiagnosticsScreen extends StatefulWidget {
  final DaemonApi api;

  const DiagnosticsScreen({super.key, required this.api});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  bool _isDumping = false;
  Map<String, dynamic>? _lastTraceResult;
  String? _statusMessage;

  Future<void> _dumpTrace() async {
    setState(() {
      _isDumping = true;
      _statusMessage = 'Extraction de la trace d\'exécution runtime/trace...';
    });

    try {
      final res = await widget.api.dumpFlightRecorder();
      if (!mounted) return;
      setState(() {
        _isDumping = false;
        _lastTraceResult = res;
        _statusMessage = 'Trace extraite avec succès (${res['size'] ?? 0} octets)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDumping = false;
        _statusMessage = 'Échec extraction trace: $e';
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceRaised,
        title: const Text('Diagnostics & Profiling 📊', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // FlightRecorder Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderStrong),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.monitor_heart, color: AppColors.positive, size: 20),
                      SizedBox(width: 8),
                      Text('Go FlightRecorder Engine', style: TextStyle(color: AppColors.inkPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Capture en direct les goroutines, syscalls, contention des mutex et allocations heap du Language Server Go.',
                    style: TextStyle(color: AppColors.inkSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _isDumping ? null : _dumpTrace,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.buttonBackground,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.download, size: 16),
                    label: Text(_isDumping ? 'Extraction en cours...' : 'Extraire un Dump FlightRecorder (.trace)'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_statusMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceInput,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Text(
                  _statusMessage!,
                  style: const TextStyle(color: AppColors.inkPrimary, fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_lastTraceResult != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceInput,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.positive),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Détails de la Trace Go Profiling', style: TextStyle(color: AppColors.positive, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('Taille: ${_lastTraceResult!['size'] ?? 0} octets | Statut: ${_lastTraceResult!['status'] ?? 'ok'}', style: const TextStyle(color: AppColors.inkPrimary, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],



            // Section Métriques Système
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Métriques d\'Exécution', style: TextStyle(color: AppColors.inkPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 12),
                  _buildMetricRow('Statut Language Server', 'Connecté (Hub :62103)', AppColors.positive),
                  const Divider(color: AppColors.borderSubtle),
                  _buildMetricRow('Protocole Wire', 'ConnectRPC / gRPC-Web', AppColors.info),
                  const Divider(color: AppColors.borderSubtle),
                  _buildMetricRow('Framing Protobuf', 'Manuel Zéro-Allocation', AppColors.codeGold),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
          Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'daemon_api.dart';

/// Represents a model entry in the Antigravity 2.0 dropdown catalog.
class AntigravityModel {
  final String id;
  final String displayName;
  final String? tag; // e.g. 'Fast'
  final String? effort; // e.g. 'Medium', 'Low', 'High', '(Thinking)'
  final bool isThinking;
  final bool isCustom;
  final int? latencyMs;
  final String? status; // 'online', 'degraded', 'offline'

  const AntigravityModel({
    required this.id,
    required this.displayName,
    this.tag,
    this.effort,
    this.isThinking = false,
    this.isCustom = false,
    this.latencyMs,
    this.status,
  });

  /// Short display title for the compact button in the input bar.
  String get shortName {
    if (isCustom) {
      return displayName;
    }
    // E.g. "Gemini 3.7 Flash", "Claude Sonnet 4.6", "GPT-OSS 120B"
    final parts = displayName.split(' ');
    if (displayName.startsWith('Claude') || displayName.startsWith('GPT')) {
      return parts.take(3).join(' ');
    }
    return parts.take(3).join(' ');
  }

  /// Full formatted label for custom models (e.g. "441ms • deepseek-v4-flash")
  String get customLabel {
    if (latencyMs != null) {
      return '${latencyMs}ms • $displayName';
    }
    return displayName;
  }
}

/// Quota usage statistics for Antigravity model families.
class ModelUsageStats {
  final int geminiWeeklyPercent;
  final int geminiFiveHourPercent;
  final int claudeGptWeeklyPercent;
  final int claudeGptFiveHourPercent;

  const ModelUsageStats({
    this.geminiWeeklyPercent = 51,
    this.geminiFiveHourPercent = 95,
    this.claudeGptWeeklyPercent = 81,
    this.claudeGptFiveHourPercent = 100,
  });
}

/// Central catalog managing native Antigravity 2.0 models & custom injected models.
class ModelCatalog {
  /// Standard Antigravity 2.0 built-in models (source of truth from Antigravity IDE UI).
  static const List<AntigravityModel> standardModels = [
    AntigravityModel(
      id: 'gemini-3.7-flash',
      displayName: 'Gemini 3.7 Flash Medium',
      tag: 'Fast',
      effort: 'Medium',
    ),
    AntigravityModel(
      id: 'gemini-3.6-flash',
      displayName: 'Gemini 3.6 Flash Medium',
      tag: 'Fast',
      effort: 'Medium',
    ),
    AntigravityModel(
      id: 'gemini-3.5-flash',
      displayName: 'Gemini 3.5 Flash Medium',
      tag: 'Fast',
      effort: 'Medium',
    ),
    AntigravityModel(
      id: 'gemini-3.1-pro',
      displayName: 'Gemini 3.1 Pro Low',
      effort: 'Low',
    ),
    AntigravityModel(
      id: 'claude-sonnet-4.6-thinking',
      displayName: 'Claude Sonnet 4.6 (Thinking)',
      isThinking: true,
      effort: 'Thinking',
    ),
    AntigravityModel(
      id: 'claude-opus-4.6-thinking',
      displayName: 'Claude Opus 4.6 (Thinking)',
      isThinking: true,
      effort: 'Thinking',
    ),
    AntigravityModel(
      id: 'gpt-oss-120b',
      displayName: 'GPT-OSS 120B (Medium)',
      effort: 'Medium',
    ),
  ];

  /// Default model when opening a fresh session.
  static const AntigravityModel defaultModel = AntigravityModel(
    id: 'gemini-3.7-flash',
    displayName: 'Gemini 3.7 Flash Medium',
    tag: 'Fast',
    effort: 'Medium',
  );

  /// Fetches custom models dynamically from custom_models.json via the daemon.
  static Future<List<AntigravityModel>> fetchCustomModels(DaemonApi? api) async {
    if (api == null) return const [];
    try {
      // Try both standard and IDE config locations
      String content = '';
      try {
        final res = await api.readFile('custom_models.json', workspacePath: '.gemini/antigravity');
        content = res['content']?.toString() ?? '';
      } catch (_) {
        try {
          final res = await api.readFile('custom_models.json', workspacePath: '.gemini/antigravity-ide');
          content = res['content']?.toString() ?? '';
        } catch (_) {}
      }

      if (content.isEmpty) return const [];
      final dynamic parsed = jsonDecode(content);
      if (parsed is! Map<String, dynamic>) return const [];

      final customList = <AntigravityModel>[];
      final providers = parsed['providers'] as List<dynamic>? ?? [];

      for (final p in providers) {
        if (p is! Map<String, dynamic>) continue;
        final enabled = p['enabled'] == true;
        if (!enabled) continue;

        final latencyMs = (p['latencyMs'] as num?)?.toInt();
        final status = p['status'] as String? ?? 'online';
        final models = p['models'] as List<dynamic>? ?? [];

        for (final m in models) {
          if (m is! Map<String, dynamic>) continue;
          if (m['enabled'] == false) continue;

          final id = m['id']?.toString() ?? '';
          final displayName = m['displayName']?.toString() ?? id;
          if (id.isEmpty) continue;

          customList.add(AntigravityModel(
            id: id,
            displayName: displayName,
            isCustom: true,
            latencyMs: latencyMs,
            status: status,
          ));
        }
      }

      // Also check flat models array if present
      final flatModels = parsed['models'] as List<dynamic>? ?? [];
      for (final m in flatModels) {
        if (m is! Map<String, dynamic>) continue;
        if (m['enabled'] == false) continue;
        final id = m['id']?.toString() ?? '';
        final displayName = m['displayName']?.toString() ?? id;
        if (id.isNotEmpty && !customList.any((c) => c.id == id)) {
          customList.add(AntigravityModel(
            id: id,
            displayName: displayName,
            isCustom: true,
          ));
        }
      }

      return customList;
    } catch (e) {
      debugPrint('[ModelCatalog] Failed to fetch custom models: $e');
      return const [];
    }
  }

  /// Returns full combined list of available models.
  static Future<List<AntigravityModel>> getAllAvailableModels(DaemonApi? api) async {
    final custom = await fetchCustomModels(api);
    if (custom.isEmpty) {
      return standardModels;
    }
    return [...standardModels, ...custom];
  }
}

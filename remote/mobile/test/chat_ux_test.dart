import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/notifications/approval_notifier.dart';
import 'package:mobile/core/protocol/daemon_api.dart';
import 'package:mobile/features/chat_stream/chat_stream_screen.dart';
import 'package:mobile/widgets/tool_approval_card.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Tests de l'audit UX des écrans de chat (correctifs P0/P1/P2) :
//   UX1 — deux approbations empilées ne s'écrasent plus (navigation ◀ ▶)
//   UX2 — la carte d'approbation est épinglée (hors ListView, toujours visible)
//   UX3 — le raisonnement (« Thought ») est replié par défaut et se déplie
//   UX4 — hors-ligne : le champ reste éditable (promesse de l'outbox)
//   UX5 — les erreurs de stream sont stylisées (pas de markdown brut)
// ──────────────────────────────────────────────────────────────────────────────

({DaemonApi api, StreamController<dynamic> ctrl, List<Map<String, dynamic>> out})
    _mkApi() {
  final out = <Map<String, dynamic>>[];
  final ctrl = StreamController<dynamic>();
  final api = DaemonApi(incoming: ctrl.stream, send: (d) => out.add(d as Map<String, dynamic>));
  return (api: api, ctrl: ctrl, out: out);
}

void _approval(StreamController<dynamic> ctrl, String requestId, String callId, String tool) {
  ctrl.add(jsonEncode({
    'type': 'stream_delta',
    'requestId': requestId,
    'data': {
      'events': [
        {
          'kind': 'approval_required',
          'callId': callId,
          'tool': tool,
          'detail': '{"command_line":"echo $tool"}',
          'cascadeId': 'c1',
        }
      ],
    },
  }));
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required DaemonApi api,
  required StreamController<dynamic> ctrl,
  bool isConnected = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B5CF6),
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        body: ChatStreamScreen(
          api: api,
          activeSessionId: 'c1',
          activeProjectName: 'Test',
          isConnected: isConnected,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Envoie un message via la barre de saisie — le SEUL chemin qui abonne
/// vraiment l'écran au stream (le probe l'a prouvé : api.sendPrompt seul
/// crée un stream sans listener côté écran → les deltas sont perdus).
Future<void> _sendViaBar(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.arrow_forward));
  await tester.pump();
}

void main() {
  group('Audit UX chat — approbations empilées (P0-1)', () {
    testWidgets('une 2ᵉ approbation ne remplace pas la 1ʳᵉ : navigation ◀ ▶',
        (tester) async {
      final (:api, :ctrl, :out) = _mkApi();
      await _pumpScreen(tester, api: api, ctrl: ctrl);

      // Envoi via la barre → l'écran écoute le stream (requestId 'r1').
      await _sendViaBar(tester, 'fais deux trucs');
      expect(out.first['type'], 'send_prompt');

      _approval(ctrl, 'r1', 'call-1', 'run_command');
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(ToolApprovalCard), findsOneWidget);
      expect(find.textContaining('Approbation 1/2'), findsNothing);

      // 2ᵉ approbation pendant que la 1ʳᵉ est encore affichée.
      _approval(ctrl, 'r1', 'call-2', 'edit_file');
      await tester.pump(const Duration(milliseconds: 120));

      // Les deux demandes coexistent : compteur « 1/2 » + navigation.
      expect(find.byType(ToolApprovalCard), findsOneWidget);
      expect(find.textContaining('1/2'), findsOneWidget);
      expect(find.byKey(const Key('approval-next')), findsOneWidget);

      // Bascule sur la 2ᵉ carte.
      await tester.tap(find.byKey(const Key('approval-next')));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.textContaining('2/2'), findsOneWidget);
      // La carte edit_file est affichée — le nom du tool apparaît dans le
      // badge, la commande et le label « toujours autoriser » : on accepte
      // plusieurs occurrences.
      expect(find.textContaining('edit_file'), findsWidgets);

      // Décision sur la 2ᵉ → retour automatique à la 1ʳᵉ restante.
      await tester.tap(find.text('Approuver'));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(ToolApprovalCard), findsOneWidget);
      expect(find.textContaining('1/1'), findsOneWidget);

      // La 1ʳᵉ est toujours approvable.
      await tester.tap(find.text('Approuver'));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(ToolApprovalCard), findsNothing);

      // Deux décisions envoyées (une par callId).
      expect(
        out.where((m) => m['type'] == 'submit_approval'),
        hasLength(2),
      );

      await ctrl.close();
      api.dispose();
    });
  });

  group('Audit UX chat — thought replié par défaut (P0-3)', () {
    testWidgets('le raisonnement est replié et le toggle le déplie vraiment',
        (tester) async {
      final (:api, :ctrl, :out) = _mkApi();
      await _pumpScreen(tester, api: api, ctrl: ctrl);

      await _sendViaBar(tester, 'raisonne');

      ctrl.add(jsonEncode({
        'type': 'stream_delta',
        'requestId': 'r1',
        'data': {
          'events': [
            {'kind': 'thinking', 'delta': 'je réfléchis profondément à ce problème très complexe'},
          ],
        },
      }));
      await tester.pump(const Duration(milliseconds: 120));

      // 1ᵉʳ envoi : m1 (user) + a2 (assistant) → la pensée vit sur la bulle a2.
      final thoughtText = find.byKey(const Key('thought-a2'));
      expect(thoughtText, findsOneWidget);
      final collapsed = tester.widget<Text>(thoughtText);
      expect(collapsed.maxLines, 1, reason: 'Thought doit être replié par défaut');

      await tester.tap(find.byIcon(Icons.psychology_outlined));
      await tester.pump();
      final expanded = tester.widget<Text>(thoughtText);
      expect(expanded.maxLines, isNull, reason: 'Le toggle doit vraiment déplier');

      await ctrl.close();
      api.dispose();
    });
  });

  group('Audit UX chat — carte épinglée + hors-ligne éditable (P0-2/P1-5)', () {
    testWidgets('hors-ligne : le TextField reste éditable et le send est accepté',
        (tester) async {
      final (:api, :ctrl, :out) = _mkApi();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF8B5CF6),
              brightness: Brightness.dark,
            ),
          ),
          home: Scaffold(
            body: ChatStreamScreen(
              api: api,
              activeSessionId: 'c1',
              activeProjectName: 'Test',
              isConnected: false, // simulate offline
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Le champ accepte la saisie malgré l'état hors-ligne.
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      await tester.enterText(field, 'message offline');
      await tester.pump();

      final sendButton = find.byIcon(Icons.arrow_forward);
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await tester.pump();

      // Le message est ajouté localement (bulle utilisateur) malgré l'absence
      // de connexion — la livraison au daemon est gérée par l'outbox.
      expect(find.text('message offline'), findsOneWidget);

      await ctrl.close();
      api.dispose();
    });
  });

  group('Audit UX chat — erreur stylisée (P2-9)', () {
    testWidgets('une erreur de stream s\'affiche en bulle danger, pas en markdown',
        (tester) async {
      final (:api, :ctrl, :out) = _mkApi();
      await _pumpScreen(tester, api: api, ctrl: ctrl);

      await _sendViaBar(tester, 'plante');

      ctrl.add(jsonEncode({
        'type': 'stream_end',
        'requestId': 'r1',
        'error': 'internal daemon failure',
        'data': {'outcome': 'error'},
      }));
      await tester.pump(const Duration(milliseconds: 120));

      // L'erreur est rendue dans un état visuel dédié (icône + fond danger).
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await ctrl.close();
      api.dispose();
    });
  });

  group('B2 — tap notification → ré-ouverture de l\'approbation', () {
    testWidgets('le tap re-fetch get_pending_approval et affiche la carte',
        (tester) async {
      final (:api, :ctrl, :out) = _mkApi();
      await _pumpScreen(tester, api: api, ctrl: ctrl);

      // Aucune carte au départ.
      expect(find.byType(ToolApprovalCard), findsNothing);

      // L'utilisateur tape la notification « Approbation requise » (émise
      // pendant que l'app était en arrière-plan). Le daemon répond avec le
      // contexte de l'approbation encore en attente.
      ApprovalNotifier.instance.tapsSink.add({
        'kind': 'approval',
        'cascadeId': 'c1',
      });
      await tester.pump();

      // get_pending_approval part bien vers le daemon…
      final getReq =
          out.where((m) => m['type'] == 'get_pending_approval').toList();
      expect(getReq, hasLength(1));
      expect(getReq.first['cascadeId'], 'c1');

      // … et sa réponse fait apparaître la carte.
      ctrl.add(jsonEncode({
        'type': 'response',
        'requestId': getReq.first['requestId'],
        'data': {
          'cascadeId': 'c1',
          'callId': 'call_tap',
          'trajectoryId': 'traj_t',
          'stepIndex': 2,
          'approvalType': 'run_command',
          'command': 'git push',
        },
      }));
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byType(ToolApprovalCard), findsOneWidget);
      expect(find.textContaining('git push'), findsOneWidget);

      // Approuver → submit_approval avec les métadonnées re-fetchées.
      await tester.tap(find.text('Approuver'));
      await tester.pump(const Duration(milliseconds: 120));
      final submits = out.where((m) => m['type'] == 'submit_approval').toList();
      expect(submits, hasLength(1));
      expect(submits.first['callId'], 'call_tap');
      expect(submits.first['trajectoryId'], 'traj_t');
      expect(submits.first['stepIndex'], 2);
      expect(find.byType(ToolApprovalCard), findsNothing);

      await ctrl.close();
      api.dispose();
    });
  });
}

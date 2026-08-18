import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/protocol/daemon_api.dart';
import 'package:mobile/core/protocol/messages.dart';
import 'package:mobile/features/chat_stream/chat_stream_screen.dart';
import 'package:mobile/features/chat_stream/widgets/queued_messages_card.dart';
import 'package:mobile/widgets/chat_input_bar.dart';

/// Mock DaemonApi capturant les appels sendPrompt pour tester la concurrence.
class ConcurrencyMockDaemonApi extends Fake implements DaemonApi {
  final List<Map<String, dynamic>> sentPrompts = [];
  final Map<String, List<void Function(Map<String, dynamic>)>> listeners = {};

  @override
  Stream<Map<String, dynamic>> sendPrompt(
    String cascadeId,
    String prompt, {
    String? base64Data,
    String? fileName,
    List<String>? images,
    String? modelUID,
    int? modelEnum,
  }) {
    sentPrompts.add({
      'cascadeId': cascadeId,
      'prompt': prompt,
      'modelUID': modelUID,
      'modelEnum': modelEnum,
    });

    final ctrl = Stream<Map<String, dynamic>>.multi((controller) {
      listeners.putIfAbsent(cascadeId, () => []).add((data) {
        controller.add(data);
        if (data['type'] == 'stream_end') {
          controller.close();
        }
      });
    });
    return ctrl;
  }

  void emitDelta(String cascadeId, String text) {
    for (final l in listeners[cascadeId] ?? []) {
      l({
        'type': 'stream_delta',
        'cascadeId': cascadeId,
        'data': {
          'events': [
            {'delta': text}
          ]
        }
      });
    }
  }

  void emitEnd(String cascadeId, {String outcome = 'done', String? message}) {
    final list = List<void Function(Map<String, dynamic>)>.from(listeners[cascadeId] ?? []);
    for (final l in list) {
      l({
        'type': 'stream_end',
        'cascadeId': cascadeId,
        'data': {
          'outcome': outcome,
          'message': message ?? '',
          'cascadeId': cascadeId,
        }
      });
    }
    listeners.remove(cascadeId);
  }

  @override
  Future<void> stopGeneration({String? cascadeId}) async {
    emitEnd(cascadeId ?? '', outcome: 'cancelled');
  }

  @override
  Future<Map<String, dynamic>> getSessionHistory(String cascadeId) async {
    return {'steps': []};
  }

  @override
  Future<Map<String, dynamic>> getSyncSession(String cascadeId) async {
    return {'messages': []};
  }
}

void main() {
  group('Scénarios de Concurrence, Race Conditions & États Partagés (Queued Messages)', () {
    late ConcurrencyMockDaemonApi api;

    setUp(() {
      api = ConcurrencyMockDaemonApi();
    });

    void setViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
    }

    testWidgets('Scénario 1 : Envoi pendant streaming met automatiquement en file sans collision', (tester) async {
      setViewport(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatStreamScreen(
              api: api,
              activeSessionId: 'sess_1',
              activeProjectName: 'TestProj',
              isConnected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Premier prompt envoyé quand idle -> part immédiatement vers le daemon
      await tester.enterText(find.byType(TextField), 'Premier message');
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-message-button')));
      await tester.pump();

      expect(api.sentPrompts.length, equals(1));
      expect(api.sentPrompts[0]['prompt'], equals('Premier message'));

      // Le stream est maintenant actif pour sess_1
      api.emitDelta('sess_1', 'Traitement en cours...');
      await tester.pump();

      // 2. Deuxième prompt saisi pendant que le stream tourne
      await tester.enterText(find.byType(TextField), 'Deuxième message en file');
      await tester.pump();

      // Le bouton affiche l'action d'ajout à la file
      expect(find.byKey(const Key('send-message-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('send-message-button')));
      await tester.pump();

      // Vérification : le 2ème prompt N'A PAS été envoyé au daemon immédiatement (pas de race/collision)
      expect(api.sentPrompts.length, equals(1));

      // La carte QueuedMessagesCard est visible avec compteur 1
      expect(find.byType(QueuedMessagesCard), findsOneWidget);
      expect(find.text('Queued Messages'), findsOneWidget);
      expect(find.text('Deuxième message en file'), findsOneWidget);

      // 3. Le stream se termine avec succès (outcome = done)
      api.emitEnd('sess_1', outcome: 'done');
      await tester.pumpAndSettle();

      // Vérification : le 2ème prompt a été dépilé et envoyé automatiquement
      expect(api.sentPrompts.length, equals(2));
      expect(api.sentPrompts[1]['prompt'], equals('Deuxième message en file'));
      // La carte disparait car la file est vide
      expect(find.byType(QueuedMessagesCard), findsNothing);
    });

    testWidgets('Scénario 2 : Annulation (Emergency Stop) ne déclenche PAS le message en file', (tester) async {
      setViewport(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatStreamScreen(
              api: api,
              activeSessionId: 'sess_1',
              activeProjectName: 'TestProj',
              isConnected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Envoi du prompt 1
      await tester.enterText(find.byType(TextField), 'Tâche longue');
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-message-button')));
      await tester.pump();

      // Enfilement du prompt 2
      await tester.enterText(find.byType(TextField), 'Tâche suivante');
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-message-button')));
      await tester.pump();

      expect(find.byType(QueuedMessagesCard), findsOneWidget);

      // L'utilisateur clique sur le bouton Stop
      await tester.tap(find.byKey(const Key('stop-generation-button')));
      await tester.pumpAndSettle();

      // Vérification : le stream s'arrête mais le prompt 2 n'a PAS été exécuté accidentellement
      expect(api.sentPrompts.length, equals(1));
      // Le message reste dans la file pour que l'utilisateur puisse le modifier ou le relancer
      expect(find.byType(QueuedMessagesCard), findsOneWidget);
      expect(find.text('Tâche suivante'), findsOneWidget);
    });

    testWidgets('Scénario 3 : Isolation multi-session — fin de stream en background ne pollue pas la session active', (tester) async {
      setViewport(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatStreamScreen(
              api: api,
              activeSessionId: 'sess_A',
              activeProjectName: 'TestProj',
              isConnected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Message A1');
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-message-button')));
      await tester.pump();

      // Met en file un message A2 sur sess_A
      await tester.enterText(find.byType(TextField), 'Message A2 en file');
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-message-button')));
      await tester.pump();

      // Simulation : sess_A termine son stream
      api.emitEnd('sess_A', outcome: 'done');
      await tester.pumpAndSettle();

      // Message A2 a été correctement routé vers sess_A
      expect(api.sentPrompts.length, equals(2));
      expect(api.sentPrompts[1]['cascadeId'], equals('sess_A'));
      expect(api.sentPrompts[1]['prompt'], equals('Message A2 en file'));
    });

    testWidgets('Scénario 4 : Action "Edit" retire de la file et restaure dans le TextField', (tester) async {
      setViewport(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatStreamScreen(
              api: api,
              activeSessionId: 'sess_1',
              activeProjectName: 'TestProj',
              isConnected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Premier prompt
      await tester.enterText(find.byType(TextField), 'Prompt 1');
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-message-button')));
      await tester.pump();

      // Met en file un prompt avec une faute
      await tester.enterText(find.byType(TextField), 'Prompt 2 avec fote');
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-message-button')));
      await tester.pump();

      expect(find.byType(QueuedMessagesCard), findsOneWidget);

      // Clic sur "Edit" (icône crayon)
      await tester.tap(find.byTooltip('Edit message'));
      await tester.pumpAndSettle();

      // Vérification : la file est maintenant vide et le texte est rechargé dans le champ
      expect(find.byType(QueuedMessagesCard), findsNothing);
      expect(find.text('Prompt 2 avec fote'), findsOneWidget);
    });

    testWidgets('Scénario 5 : Action "Delete" supprime sans envoyer', (tester) async {
      setViewport(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatStreamScreen(
              api: api,
              activeSessionId: 'sess_1',
              activeProjectName: 'TestProj',
              isConnected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Premier prompt
      await tester.enterText(find.byType(TextField), 'Prompt 1');
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-message-button')));
      await tester.pump();

      // Met en file
      await tester.enterText(find.byType(TextField), 'Prompt à supprimer');
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-message-button')));
      await tester.pump();

      expect(find.byType(QueuedMessagesCard), findsOneWidget);

      // Clic sur "Delete"
      await tester.tap(find.byTooltip('Delete from queue'));
      await tester.pumpAndSettle();

      expect(find.byType(QueuedMessagesCard), findsNothing);

      // Le stream se termine -> rien n'est envoyé car la file est vide
      api.emitEnd('sess_1', outcome: 'done');
      await tester.pumpAndSettle();

      expect(api.sentPrompts.length, equals(1));
    });
  });
}

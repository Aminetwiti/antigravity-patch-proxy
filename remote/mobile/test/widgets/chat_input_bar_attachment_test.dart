import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/chat_input_bar.dart';

void main() {
  testWidgets('ChatInputBar renders attachment preview and clears on tap', (tester) async {
    String? sentMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            onSend: (msg, {modelEnum, modelUID, queued = false}) {
              sentMessage = msg;
            },
          ),
        ),
      ),
    );

    // Initial state: no attachment preview
    expect(find.byIcon(Icons.close_rounded), findsNothing);

    // Verify attachment button is present
    expect(find.byIcon(Icons.add), findsOneWidget);

    // Tap attachment button to open bottom sheet menu
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // Verify menu items
    expect(find.text('Prendre une photo'), findsOneWidget);
    expect(find.text('Choisir une image'), findsOneWidget);
    expect(find.text('Sélectionner un fichier'), findsOneWidget);
    expect(find.text('Saisie manuelle (Base64 / Texte)'), findsOneWidget);

    // Tap manual entry
    await tester.tap(find.text('Saisie manuelle (Base64 / Texte)'));
    await tester.pumpAndSettle();

    // Dialog is shown
    expect(find.text('Joindre un fichier (.txt, .json, .md, .csv)'), findsOneWidget);

    // Enter file name and content
    await tester.enterText(find.widgetWithText(TextField, 'Nom du fichier (ex: data.json, doc.md)'), 'test_config.json');
    await tester.enterText(find.widgetWithText(TextField, 'Contenu'), '{"theme": "zenithal"}');

    // Tap 'Joindre'
    await tester.tap(find.text('Joindre'));
    await tester.pumpAndSettle();

    // Verify attachment preview card is displayed
    expect(find.text('test_config.json'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    // Send message with attachment
    await tester.enterText(find.byType(TextField), 'Check this config');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(sentMessage, isNotNull);
    expect(sentMessage, contains('[Fichier: test_config.json]'));
    expect(sentMessage, contains('{"theme": "zenithal"}'));
    expect(sentMessage, contains('Check this config'));

    // Verify attachment preview is cleared after send
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });
}

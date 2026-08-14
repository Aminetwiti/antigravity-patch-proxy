import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SettingsScreen displays correctly and handles branch loading', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(
          initialSettings: {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('PROFILE'), findsOneWidget);
    expect(find.text('WORKSPACE & BRANCH'), findsOneWidget);
    expect(find.text("Nom d'affichage"), findsOneWidget); 
  });

  testWidgets('SettingsScreen triggers deletion dialog', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(
          initialSettings: {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    final listFinder = find.byType(ListView);
    final deleteButton = find.text('Supprimer le projet');
    
    await tester.dragUntilVisible(
      deleteButton,
      listFinder,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('Supprimer '), findsWidgets);
    
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    
    expect(find.text('Annuler'), findsNothing);
  });
}




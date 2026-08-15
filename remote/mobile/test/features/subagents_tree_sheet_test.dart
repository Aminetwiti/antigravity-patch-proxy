import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/protocol/daemon_api.dart';
import 'package:mobile/features/subagents/subagents_tree_sheet.dart';

void main() {
  testWidgets('SubagentsTreeSheet affiche la liste des sous-agents après chargement', (tester) async {
    final ctrl = StreamController<dynamic>();
    final api = DaemonApi(
      incoming: ctrl.stream,
      send: (d) {
        final map = d is String ? jsonDecode(d) as Map<String, dynamic> : Map<String, dynamic>.from(d as Map);
        if (map['type'] == 'get_subagents') {
          ctrl.add(jsonEncode({
            'type': 'response',
            'requestId': map['requestId'],
            'data': {
              'cascadeId': 'test-cascade-1',
              'subagents': [
                {
                  'id': 'sub-1',
                  'parentId': 'test-cascade-1',
                  'typeName': 'research',
                  'role': 'Codebase Researcher',
                  'prompt': 'Explore auth middleware',
                  'state': 'running',
                },
                {
                  'id': 'sub-2',
                  'parentId': 'test-cascade-1',
                  'typeName': 'database-debugger',
                  'role': 'DB Optimizer',
                  'prompt': 'Profile slow queries',
                  'state': 'completed',
                },
              ],
            },
          }));
        }
      },
    );
    addTearDown(ctrl.close);
    addTearDown(api.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubagentsTreeSheet(
            api: api,
            cascadeId: 'test-cascade-1',
            sessionTitle: 'Refactor Auth System',
          ),
        ),
      ),
    );

    // Initial loading
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    // Renders subagent cards
    expect(find.text('Hiérarchie des Sous-Agents'), findsOneWidget);
    expect(find.text('Codebase Researcher'), findsOneWidget);
    expect(find.text('DB Optimizer'), findsOneWidget);
    expect(find.text('research'), findsOneWidget);
    expect(find.text('database-debugger'), findsOneWidget);
    expect(find.text('Explore auth middleware'), findsOneWidget);
  });

  testWidgets('SubagentsTreeSheet affiche état vide si aucun sous-agent', (tester) async {
    final ctrl = StreamController<dynamic>();
    final api = DaemonApi(
      incoming: ctrl.stream,
      send: (d) {
        final map = d is String ? jsonDecode(d) as Map<String, dynamic> : Map<String, dynamic>.from(d as Map);
        if (map['type'] == 'get_subagents') {
          ctrl.add(jsonEncode({
            'type': 'response',
            'requestId': map['requestId'],
            'data': {
              'cascadeId': 'test-empty',
              'subagents': [],
            },
          }));
        }
      },
    );
    addTearDown(ctrl.close);
    addTearDown(api.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubagentsTreeSheet(
            api: api,
            cascadeId: 'test-empty',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Aucun sous-agent actif'), findsOneWidget);
  });
}

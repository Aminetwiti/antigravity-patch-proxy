import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/protocol/messages.dart';
import 'package:mobile/widgets/tool_approval_card.dart';

void main() {
  group('Comprehensive Approval Modules Tests', () {
    testWidgets('File Permission displays 5 scopes and absolute path', (tester) async {
      final req = ToolApprovalRequest.fromJson({
        'callId': 'call-file-123',
        'toolName': 'write_to_file',
        'filePath': 'C:/Users/amine/sensitive/config.json',
        'approvalType': 'file_permission',
        'description': 'Write outside workspace boundary',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ToolApprovalCard(
                request: req,
                onDecision: (_, {scope = ApprovalScope.once, denyReason = ''}) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check title and file path
      expect(find.text('Allow file access outside workspace?'), findsOneWidget);
      expect(find.text('C:/Users/amine/sensitive/config.json'), findsOneWidget);

      // Check all 5 options
      expect(find.byKey(const Key('approval-option-1')), findsOneWidget);
      expect(find.byKey(const Key('approval-option-2')), findsOneWidget);
      expect(find.byKey(const Key('approval-option-3')), findsOneWidget);
      expect(find.byKey(const Key('approval-option-4')), findsOneWidget);
      expect(find.byKey(const Key('approval-option-5')), findsOneWidget);
    });

    testWidgets('Destructive Action displays high risk warning banner', (tester) async {
      final req = ToolApprovalRequest.fromJson({
        'callId': 'call-rm-123',
        'toolName': 'run_command',
        'command': 'rm -rf ./build/data',
        'isDestructive': true,
        'description': 'Delete build data recursively',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ToolApprovalCard(
                request: req,
                onDecision: (d, {scope = ApprovalScope.once, denyReason = ''}) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Action Destructive / Risque Élevé'), findsOneWidget);
      expect(find.textContaining('Attention : Cette opération risque de supprimer'), findsOneWidget);
    });

    testWidgets('MCP tool displays server badge and tool name', (tester) async {
      final req = ToolApprovalRequest.fromJson({
        'callId': 'call-mcp-999',
        'toolName': 'create_server',
        'mcpServer': 'coolify',
        'approvalType': 'mcp_tool',
        'description': 'Create new server in Coolify',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ToolApprovalCard(
                request: req,
                onDecision: (d, {scope = ApprovalScope.once, denyReason = ''}) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Allow MCP tool execution (coolify)?'), findsOneWidget);
      expect(find.text('coolify -> create_server'), findsOneWidget);
    });
  });
}

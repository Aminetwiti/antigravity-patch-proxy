import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/protocol/messages.dart';
import 'package:mobile/widgets/tool_approval_card.dart';

void main() {
  group('Advanced Scenarios Phase 1 Tests', () {
    testWidgets('ToolApprovalCard debounces rapid taps (Scénario 6)', (WidgetTester tester) async {
      int tapCount = 0;
      final request = ToolApprovalRequest(
        callId: 'test_call',
        toolName: 'run_command',
        command: 'echo hello',
        description: 'test',
        cascadeId: 'test_cascade',
        trajectoryId: 'test_trajectory',
        stepIndex: 1,
        approvalType: 'approval',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolApprovalCard(
              request: request,
              onDecision: (decision, {ApprovalScope scope = ApprovalScope.once}) async {
                tapCount++;
                // Simulate a network delay of 500ms
                await Future.delayed(const Duration(milliseconds: 500));
              },
            ),
          ),
        ),
      );

      // Find the Approve button
      final approveButton = find.text('Approuver');
      expect(approveButton, findsOneWidget);

      // Tap 3 times rapidly
      await tester.tap(approveButton);
      await tester.tap(approveButton);
      await tester.tap(approveButton);

      // Wait a bit but not full 500ms
      await tester.pump(const Duration(milliseconds: 100));

      // The button text should now be 'En cours...' and tapCount should be exactly 1
      expect(find.text('En cours...'), findsOneWidget);
      expect(tapCount, 1);

      // Wait for the simulated network delay to finish
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // Text should revert to 'Approuver'
      expect(find.text('Approuver'), findsOneWidget);
      expect(tapCount, 1, reason: 'Debounce failed, tapped multiple times');
    });
  });
}

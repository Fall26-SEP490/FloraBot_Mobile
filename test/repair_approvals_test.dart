import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/features/repair_approvals.dart';

void main() {
  test('repair approval expiry uses time rather than non-null value', () {
    final now = DateTime.utc(2026, 11, 23, 10);
    expect(repairApprovalActive({'expiresAt': null}, now), isFalse);
    expect(
      repairApprovalActive({'expiresAt': '2026-11-23T09:00:00Z'}, now),
      isFalse,
    );
    expect(
      repairApprovalActive({'expiresAt': '2026-11-23T11:00:00Z'}, now),
      isTrue,
    );
  });

  testWidgets('seller approves repair using task ID and sees returned expiry', (
    tester,
  ) async {
    String? expiry;
    final mutations = <String>[];
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((request) async {
        if (request.method == 'POST') {
          mutations.add(request.url.path);
          expiry = DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String();
          return http.Response(jsonEncode({'expiresAt': expiry}), 200);
        }
        return http.Response(
          jsonEncode([
            {
              'id': 'repair-task',
              'kioskName': 'Kiosk 12',
              'slotCode': 'S01',
              'reason': 'Cửa tủ bị kẹt',
              'expiresAt': expiry,
            },
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RepairApprovalsPage(api))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chờ duyệt'), findsOneWidget);
    await tester.tap(find.text('Kiosk 12'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Duyệt quyền mở ô'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(mutations, ['/api/me/technical-repairs/repair-task/approve']);
    expect(find.text('Đã duyệt'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Duyệt quyền mở ô'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

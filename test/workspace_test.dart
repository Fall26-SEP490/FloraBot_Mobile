import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:florabot_mobile/app.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/auth.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/ui/common.dart';

void main() {
  for (final role in AppRole.values) {
    testWidgets('${role.code} gets only its role navigation', (tester) async {
      final requests = <String>[];
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          requests.add(r.url.path);
          return http.Response(jsonEncode({'items': [], 'total': 0}), 200);
        }),
      );
      final auth = AuthController(api, MemoryTokenVault())
        ..loading = false
        ..session = Session.fromJson({
          'id': '1',
          'name': 'Test',
          'role': role.code,
          if (role == AppRole.staff || role == AppRole.seller)
            'sellerId': 'shop',
        });
      await tester.pumpWidget(FloraBotApp(auth: auth));
      await tester.pumpAndSettle();
      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      final labels = nav.destinations
          .cast<NavigationDestination>()
          .map((e) => e.label)
          .toList();
      expect(labels.contains('Lắp đặt'), role == AppRole.technician);
      expect(labels.contains('Tủ hoa'), role == AppRole.seller);
      expect(labels.contains('Khám phá'), role == AppRole.customer);
      if (role == AppRole.staff) {
        expect(requests.every((p) => !p.startsWith('/api/sellers/')), true);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      api.dispose();
    });
  }
  testWidgets('login fits a small phone and validates empty inputs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((_) async => http.Response('{}', 500)),
    );
    final auth = AuthController(api, MemoryTokenVault())..loading = false;
    await tester.pumpWidget(FloraBotApp(auth: auth));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Đăng nhập');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(auth.session, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
    api.dispose();
  });
  testWidgets('OTP is erased when application goes to background', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAccessCode(context, {
                'code': '123456',
                'expiresAt': DateTime.now()
                    .add(const Duration(minutes: 1))
                    .toIso8601String(),
              }),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('123456'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('123456'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

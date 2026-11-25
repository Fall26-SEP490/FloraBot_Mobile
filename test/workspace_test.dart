import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:florabot_mobile/app.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/auth.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/technician_iot_health.dart';
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
      expect(labels.contains('Sức khỏe'), role == AppRole.technician);
      expect(labels.contains('Tủ hoa'), role == AppRole.seller);
      expect(labels.contains('Đơn đặt'), role == AppRole.customer);
      expect(labels.contains('Khám phá'), isFalse);
      expect(labels.contains('Tin nhắn'), isFalse);
      expect(
        find.byType(DrawerButton),
        role == AppRole.seller ? findsOneWidget : findsNothing,
      );
      if (role == AppRole.seller) {
        await tester.tap(find.byType(DrawerButton));
        await tester.pumpAndSettle();
        expect(find.text('Vận hành shop'), findsOneWidget);
        expect(find.text('Yêu cầu sửa chữa'), findsNothing);
        expect(find.text('Phụ kiện'), findsNothing);
        expect(find.text('Việc của nhân viên'), findsNothing);
        expect(find.text('Chấm dứt thuê kiosk'), findsNothing);
        await tester.tap(find.text('Mẫu hoa và phụ kiện'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Phụ kiện'));
        await tester.pumpAndSettle();
        expect(requests.any((p) => p.contains('/accessories')), isTrue);
        expect(find.byType(Drawer), findsNothing);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }
      expect(
        find.byTooltip('Tin nhắn'),
        role == AppRole.technician ? findsNothing : findsOneWidget,
      );
      if (role != AppRole.technician) {
        await tester.tap(find.byTooltip('Tin nhắn'));
        await tester.pumpAndSettle();
        expect(find.text('Tin nhắn'), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }
      if (role == AppRole.staff) {
        expect(requests.every((p) => !p.startsWith('/api/sellers/')), true);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      api.dispose();
    });
  }
  testWidgets('Technical kiosk health tab opens all four compartments', (
    tester,
  ) async {
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((request) async {
        final Object body = switch (request.url.path) {
          '/api/staff/kiosk-health' => [
            {
              'id': 'kiosk12',
              'code': 'K-HCM-12',
              'name': 'Kiosk 12',
              'status': 'ONLINE',
            },
          ],
          '/api/staff/kiosk-health/kiosk12' => {
            'kioskStatus': 'ONLINE',
            'isFresh': true,
            'observedAt': DateTime.now().toUtc().toIso8601String(),
            'slots': [
              for (var i = 1; i <= 4; i++)
                {
                  'slotCode': 'S0$i',
                  'flowerDetected': i == 1,
                  'doorClosed': true,
                },
            ],
          },
          _ => {'items': []},
        };
        return http.Response(jsonEncode(body), 200);
      }),
    );
    final auth = AuthController(api, MemoryTokenVault())
      ..loading = false
      ..session = Session.fromJson({
        'id': 'tech',
        'name': 'Test',
        'role': 'TECHNICIAN',
      });
    await tester.pumpWidget(FloraBotApp(auth: auth));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sức khỏe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('K-HCM-12'));
    await tester.pumpAndSettle();
    for (var slot = 1; slot <= 4; slot++) {
      expect(find.text('Ô S0$slot'), findsOneWidget);
    }
    expect(find.text('LM393 · Phát hiện vật'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
    api.dispose();
  });
  testWidgets('IoT health refresh clears stale compartment observations', (
    tester,
  ) async {
    var reads = 0;
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/staff/tasks/assigned-task/iot-health');
        return http.Response(
          jsonEncode({
            'isFresh': ++reads == 1,
            'observedAt': DateTime.now().toUtc().toIso8601String(),
            'slots': [
              {
                'slotCode': 'S01',
                'flowerDetected': false,
                'doorClosed': true,
                'lastCycle': 'OPEN_TIMEOUT',
              },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [TechnicianIoTHealth(api: api, taskId: 'assigned-task')],
          ),
        ),
      ),
    );
    expect(reads, 0);
    await tester.tap(find.text('Sức khỏe thiết bị IoT'));
    await tester.pumpAndSettle();
    final timeout = find.textContaining('hết thời gian chờ tín hiệu mở');
    expect(timeout, findsOneWidget);
    final refresh = find.text('Đọc lại tín hiệu');
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(timeout, findsNothing);
    expect(find.text('MC-38 · Chưa xác định'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
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
    await tester.tap(find.text('Tài khoản'));
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

  testWidgets(
    'guest browses flowers first and resumes ordering after signing in',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          if (r.url.path == '/api/shop/catalog') {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'productId': 'rose',
                    'sellerId': 'shop',
                    'kioskId': 'kiosk',
                    'name': 'Bó hồng pastel',
                    'price': 250000,
                    'shopName': 'Shop Hoa',
                    'kioskName': 'Kiosk Hòa Lạc',
                    'address': 'Hà Nội',
                    'preorderAvailable': true,
                  },
                ],
                'hasMore': false,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (r.url.path == '/api/mobile/auth/login') {
            return http.Response(
              jsonEncode({
                'accessToken': 'token-123',
                'refreshToken': 'r' * 64,
                'user': {
                  'id': 'cust-1',
                  'name': 'Khách Hàng',
                  'role': 'CUSTOMER',
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (r.url.path.endsWith('/preorder-availability')) {
            return http.Response(
              jsonEncode({'available': true}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(
            jsonEncode([]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final auth = AuthController(api, MemoryTokenVault())..loading = false;
      await tester.pumpWidget(FloraBotApp(auth: auth));
      await tester.pumpAndSettle();

      // Guest sees catalog immediately without login wall
      expect(find.text('Bó hồng pastel'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Đăng nhập'), findsOneWidget);

      // Selecting "Đặt trước" prompts login / register
      await tester.tap(find.widgetWithText(FilledButton, 'Đặt trước'));
      await tester.pumpAndSettle();
      expect(find.text('Đăng nhập để đặt hoa'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Tạo tài khoản'),
        findsOneWidget,
      );

      // Proceed to login and sign in
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'khach@florabot.site',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'MatKhauAnToan123!',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pumpAndSettle();

      // Automatically opens the preorder form for the chosen flower
      expect(auth.session?.role, AppRole.customer);
      expect(find.text('Yêu cầu báo giá'), findsOneWidget);
      expect(find.text('Bó hồng pastel · Shop Hoa'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      api.dispose();
    },
  );
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

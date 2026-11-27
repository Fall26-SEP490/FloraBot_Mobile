import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:florabot_mobile/app.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/auth.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/ui/brand.dart';
import 'package:florabot_mobile/features/technician_iot_health.dart';
import 'package:florabot_mobile/features/flower_advisor.dart';
import 'package:florabot_mobile/ui/team_widgets.dart';
import 'package:florabot_mobile/features/subscriptions.dart';
import 'package:florabot_mobile/ui/common.dart';

void main() {
  testWidgets(
    'flower advisor optional filters fit a narrow phone with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((_) async => http.Response('{}', 200)),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(body: FlowerAdvisorPage(api)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Chất liệu'));
      await tester.tap(find.text('Chất liệu'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Lụa/vải'));
      expect(find.text('Không yêu cầu'), findsOneWidget);
      await tester.tap(find.text('Lụa/vải'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Lụa/vải'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextField).first);
      expect(
        find.widgetWithText(FilledButton, 'Tìm hoa phù hợp').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sensor cards and paging fit a narrow phone with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'kioskStatus': 'ONLINE',
            'isFresh': true,
            'observedAt': DateTime.now().toUtc().toIso8601String(),
            'slots': [
              {
                'slotCode': 'S01',
                'flowerDetected': false,
                'doorClosed': true,
                'lastCycle': 'CLOSE_DETECTED',
              },
            ],
          }),
          200,
        ),
      ),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            children: [
              TechnicianIoTHealth.forKiosk(api: api, kioskId: 'kiosk'),
              const RentalStatus('PENDING_PAYMENT'),
              const TeamStatus('SUBMITTED'),
              TeamPaging(page: 123, more: true, busy: false, onPage: (_) {}),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Không phát hiện vật'), findsOneWidget);
    expect(find.text('Cửa đóng'), findsOneWidget);
    expect(find.textContaining('Heartbeat'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'shared form remains scrollable with keyboard and can close without submitting',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      Map<String, String>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await askForm(context, 'Thông tin cá nhân', const [
                    InputSpec('name', 'Họ tên'),
                    InputSpec('phone', 'Số điện thoại'),
                    InputSpec('address', 'Địa chỉ', lines: 3),
                  ]);
                },
                child: const Text('Mở'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Xác nhận'));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('Đóng biểu mẫu'));
      await tester.tap(find.byTooltip('Đóng biểu mẫu'));
      await tester.pumpAndSettle();
      expect(find.text('Thông tin cá nhân'), findsNothing);
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  test('status text has readable contrast on its background', () {
    for (final code in [
      'ASSIGNED',
      'IN_PROGRESS',
      'SUBMITTED',
      'COMPLETED',
      'FAULT',
      'CANCELLED',
      'UNKNOWN',
    ]) {
      final appearance = statusAppearance(code);
      final foreground = appearance.foreground.computeLuminance();
      final background = appearance.background.computeLuminance();
      final light = foreground > background ? foreground : background;
      final dark = foreground > background ? background : foreground;
      expect(
        (light + .05) / (dark + .05),
        greaterThanOrEqualTo(4.5),
        reason: code,
      );
    }
  });
  testWidgets('long titles and statuses fit a narrow phone with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (final code in [
                    'ASSIGNED',
                    'IN_PROGRESS',
                    'SUBMITTED',
                    'COMPLETED',
                  ])
                    RecordCard(
                      title: 'Kiosk Nguyễn Văn Linh – Khu công nghệ cao',
                      subtitle: 'Kiểm tra đúng ô, chụp ảnh và gửi báo cáo',
                      status: code,
                      onTap: () {},
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final role in [AppRole.technician, AppRole.staff]) {
    testWidgets('${role.code} overview is compact and opens assigned work', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient(
          (request) async =>
              http.Response(jsonEncode({'items': [], 'hasMore': false}), 200),
        ),
      );
      final auth = AuthController(api, MemoryTokenVault())
        ..loading = false
        ..session = Session.fromJson({
          'id': 'user',
          'name': 'Người dùng thử',
          'role': role.code,
          if (role == AppRole.staff) 'sellerId': 'shop',
        });
      addTearDown(auth.dispose);
      addTearDown(api.dispose);
      await tester.pumpWidget(FloraBotApp(auth: auth));
      await tester.pumpAndSettle();
      expect(find.byType(FlowerJourney), findsNothing);
      expect(find.text('Bắt đầu từ đây'), findsNothing);
      expect(find.text('Công việc được giao'), findsOneWidget);
      expect(
        tester.widget<FloralBackdrop>(find.byType(FloralBackdrop)).decorated,
        isFalse,
      );
      await tester.tap(find.text('Công việc được giao'));
      await tester.pumpAndSettle();
      expect(find.text('Công việc của tôi'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

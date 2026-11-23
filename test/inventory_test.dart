import 'dart:convert';
import 'dart:typed_data';
import 'package:florabot_mobile/features/kiosk_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/core/slot_labels.dart';
import 'package:florabot_mobile/features/inventory.dart';
import 'package:florabot_mobile/features/inventory_history.dart';

void main() {
  final seller = Session.fromJson({
    'id': 'owner',
    'name': 'Shop',
    'role': 'SELLER',
    'sellerId': 'shop',
  });
  final kiosk = <String, dynamic>{
    'id': 'kiosk',
    'name': 'Kiosk Hà Nội',
    'code': 'K-HN-01',
    'address': 'Hòa Lạc, Hà Nội',
    'status': 'OFFLINE',
    'canEditLocation': false,
  };
  final slot = <String, dynamic>{
    'id': 'slot',
    'slotCode': 'S01',
    'zone': 'WALK_IN',
    'status': 'RENTED_EMPTY',
    'sensorEnabled': true,
    'sensorReady': true,
  };
  ApiClient client({
    Json? overrideSlot,
    List<Json> requests = const [],
    String kioskStatus = 'OFFLINE',
    ValueChanged<Json>? onCommand,
    List<Json> people = const [],
    ValueChanged<Json>? onTask,
  }) => ApiClient(
    Uri.parse('https://example.test'),
    transport: MockClient((r) async {
      dynamic body = [];
      if (r.url.path.endsWith('/kiosks')) {
        body = [
          {...kiosk, 'status': kioskStatus},
        ];
      }
      if (r.url.path.endsWith('/maintenance-open') && r.method == 'POST') {
        onCommand?.call(objectOf(jsonDecode(r.body)));
      }
      if (r.url.path.endsWith('/slots')) body = [overrideSlot ?? slot];
      if (r.url.path.endsWith('/staff')) body = people;
      if (r.url.path.endsWith('/inventory-tasks') && r.method == 'POST') {
        onTask?.call(objectOf(jsonDecode(r.body)));
      }
      if (r.url.path.endsWith('/products')) {
        body = [
          {
            'id': 'flower-id',
            'name': 'Hoa hồng',
            'status': 'ACTIVE',
            'quantity': 10,
          },
        ];
      }
      if (r.url.path.endsWith('/layout-requests')) body = requests;
      if (r.url.path.endsWith('/inventory-history')) {
        body = {
          'items': [
            {
              'movementType': 'STOCK_IN',
              'slotCode': 'S01',
              'actorName': 'An',
              'createdAt': '2026-11-23T01:00:00Z',
            },
          ],
          'hasMore': r.url.queryParameters['page'] == '1',
        };
      }
      if (r.url.path.endsWith('/active')) return http.Response('', 204);
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  Future<void> render(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  test('orders held or awaiting pickup block stock mutations', () {
    for (final s in [
      {'bouquetStatus': 'HELD'},
      {'bouquetStatus': 'SOLD'},
      {'orderStatus': 'PAID'},
      {'orderStatus': 'DISPENSE_FAILED'},
    ]) {
      expect(slotOrderBlocked(s), isTrue);
    }
    expect(slotOrderBlocked(slot), isFalse);
  });
  testWidgets('kiosk search retains names and codes without region', (
    tester,
  ) async {
    final api = client();
    addTearDown(api.dispose);
    await render(tester, KiosksPage(api, seller));
    expect(find.text('Kiosk Hà Nội'), findsOneWidget);
    expect(find.text('Mã: K-HN-01'), findsNothing);
    await tester.enterText(find.byType(TextField), 'không có');
    await tester.pumpAndSettle();
    expect(find.text('Không có kiosk phù hợp.'), findsOneWidget);
  });
  testWidgets('status filter shares search row and opens a compact menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = client();
    addTearDown(api.dispose);
    await render(tester, KiosksPage(api, seller));
    final search = tester.getRect(find.byType(TextField));
    final filterMenu = find.byWidgetPredicate(
      (w) =>
          w is PopupMenuButton<String> && w.tooltip == 'Lọc trạng thái: Tất cả',
    );
    final filter = tester.getRect(filterMenu);
    expect(search.top, filter.top);
    expect(search.height, filter.height);
    await tester.tap(filterMenu);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(PopupMenuItem<String>).first).width,
      lessThanOrEqualTo(200),
    );
    await tester.tap(find.text('Trực tuyến'));
    await tester.pumpAndSettle();
    expect(find.text('Không có kiosk phù hợp.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final width in [360.0, 800.0]) {
    testWidgets('slots show searchable flower name at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = client(
        overrideSlot: {
          ...slot,
          'productId': 'flower-id',
          'bouquetId': 'bouquet-id',
          'status': 'STOCKED',
          'priceSnapshot': 10000,
        },
      );
      addTearDown(api.dispose);
      await render(tester, SlotsPage(api, seller, kiosk));
      expect(find.text('Hoa hồng'), findsOneWidget);
      expect(find.text('flower-id'), findsNothing);
      await tester.enterText(find.byType(TextField), 'hồng');
      await tester.pumpAndSettle();
      expect(find.text('Ô S01'), findsOneWidget);
      final statusFilter = find.byWidgetPredicate(
        (w) =>
            w is PopupMenuButton<String> &&
            w.tooltip == 'Lọc trạng thái: Tất cả ô',
      );
      expect(
        tester.getRect(find.byType(TextField)).top,
        tester.getRect(statusFilter).top,
      );
      expect(tester.widget<AppBar>(find.byType(AppBar)).centerTitle, isTrue);
      expect(find.text('Lịch sử'), findsNothing);
      await tester.tap(find.byTooltip('Tùy chọn kiosk'));
      await tester.pumpAndSettle();
      expect(find.text('Lịch sử'), findsOneWidget);
      expect(find.text('Đổi loại ô'), findsOneWidget);
      expect(find.text('Vị trí kiosk'), findsNothing);
      await tester.tapAt(const Offset(8, 400));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.tap(statusFilter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ô trống'));
      await tester.pumpAndSettle();
      expect(find.text('Không có ô tủ phù hợp.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('kiosk and compartment buttons open separate pages', (
    tester,
  ) async {
    final paths = <String>[];
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        paths.add(r.url.path);
        dynamic data = [];
        if (r.url.path.endsWith('/kiosks')) data = [kiosk];
        if (r.url.path.endsWith('/slots')) data = [slot];
        if (r.url.path.endsWith('/flower-presence')) {
          data = {
            'isFresh': false,
            'observedAt': null,
            'slots': [
              {'slotCode': 'S01', 'hasFlowers': null},
            ],
          };
        }
        return http.Response(
          jsonEncode(data),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.dispose);
    await render(tester, KiosksPage(api, seller));
    expect(find.text('Xem kiosk'), findsOneWidget);
    expect(find.text('Xem ô tủ'), findsOneWidget);
    expect(paths.where((p) => p.endsWith('/slots')), isEmpty);
    await tester.tap(find.text('Xem kiosk'));
    await tester.pumpAndSettle();
    expect(find.text('Cảm biến ô tủ'), findsOneWidget);
    expect(paths, contains('/api/kiosks/kiosk/flower-presence'));
    expect(paths.where((p) => p.endsWith('/slots')), isEmpty);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xem ô tủ'));
    await tester.pumpAndSettle();
    expect(find.text('Ô S01'), findsOneWidget);
    expect(find.text('Cảm biến ô tủ'), findsNothing);
    expect(paths, contains('/api/me/kiosks/kiosk/slots'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Xem kiosk'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final fresh in [true, false]) {
    testWidgets(
      'kiosk presence uses live signal and hides stale readings: $fresh',
      (tester) async {
        int reads = 0;
        final api = ApiClient(
          Uri.parse('https://example.test'),
          transport: MockClient((r) async {
            dynamic data = [kiosk];
            if (r.url.path.endsWith('/flower-presence')) {
              reads++;
              if (reads > 1) return http.Response('{}', 503);
              data = {
                'isFresh': true,
                'observedAt': DateTime.now()
                    .subtract(Duration(seconds: fresh ? 0 : 60))
                    .toUtc()
                    .toIso8601String(),
                'slots': [
                  {'slotCode': 'S01', 'hasFlowers': true},
                  {'slotCode': 'S02', 'hasFlowers': false},
                ],
              };
            }
            return http.Response(
              jsonEncode(data),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        addTearDown(api.dispose);
        await render(tester, KioskOverviewPage(api, seller, kiosk));
        expect(find.text('Có hoa'), fresh ? findsOneWidget : findsNothing);
        expect(
          find.text('Không có hoa'),
          fresh ? findsOneWidget : findsNothing,
        );
        if (!fresh) expect(find.text('Chưa xác định'), findsNWidgets(2));
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(reads, 2);
        expect(find.text('Có hoa'), findsNothing);
        expect(find.text('Chưa xác định'), findsNWidgets(2));
        expect(find.text('Chưa đọc được cảm biến.'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
        expect(reads, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('offline slot cannot send an open command', (tester) async {
    final api = client();
    addTearDown(api.dispose);
    await render(tester, SlotDetail(api, seller, kiosk, slot));
    expect(
      find.text('Kiosk chưa trực tuyến. Chờ kết nối để mở ô.'),
      findsNothing,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Mở ô nạp hoa'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Giao nhân viên'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có nhân viên đang hoạt động.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('staff tab immediately displays assignment form and submits', (
    tester,
  ) async {
    Json? task;
    final stocked = {
      ...slot,
      'status': 'STOCKED',
      'bouquetId': 'bouquet',
      'bouquetStatus': 'STOCKED',
    };
    final api = client(
      overrideSlot: stocked,
      people: [
        {'id': 'staff', 'name': 'Nhân viên An'},
      ],
      onTask: (value) => task = value,
    );
    addTearDown(api.dispose);
    await render(tester, SlotDetail(api, seller, kiosk, stocked));
    await tester.tap(find.text('Giao nhân viên'));
    await tester.pumpAndSettle();
    expect(find.text('Giao việc cho nhân viên'), findsOneWidget);
    expect(find.text('Giao ô này cho nhân viên'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhân viên An').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      'Thu hồi hoa cũ tại ô S01',
    );
    final submit = find.widgetWithText(FilledButton, 'Giao việc');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(task?['assigneeId'], 'staff');
    expect(task?['action'], 'REMOVE');
    expect(task?['slotId'], 'slot');
    expect(task?['expectedBouquetId'], 'bouquet');
    expect(task?['instructions'], 'Thu hồi hoa cũ tại ô S01');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final online in [false, true]) {
    testWidgets(
      'stocked slot keeps operation form visible when online=$online',
      (tester) async {
        Json? command;
        final stocked = {
          ...slot,
          'status': 'STOCKED',
          'bouquetStatus': 'STOCKED',
          'bouquetId': 'bouquet',
        };
        final api = client(
          overrideSlot: stocked,
          kioskStatus: online ? 'ONLINE' : 'OFFLINE',
          onCommand: (value) => command = value,
        );
        addTearDown(api.dispose);
        await render(tester, SlotDetail(api, seller, kiosk, stocked));
        expect(find.text('Thu hồi hoặc thay hoa'), findsOneWidget);
        expect(find.byType(TextFormField), findsOneWidget);
        final button = find.widgetWithText(FilledButton, 'Bắt đầu thu hồi hoa');
        expect(tester.widget<FilledButton>(button).onPressed != null, online);
        if (online) {
          await tester.enterText(find.byType(TextFormField), 'Thu hồi hoa cũ');
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(command?['operation'], 'START');
          expect(command?['action'], 'REMOVE');
          expect(command?['expectedBouquetId'], 'bouquet');
          expect(command?['reason'], 'Thu hồi hoa cũ');
        } else {
          expect(command, isNull);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final width in [360.0, 800.0]) {
    testWidgets(
      'slot summary hides raw sentinel and preserves bouquet details at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const bouquetCode = 'FB-01a2039db8eb7b06a90a10c698b25571';
        final stocked = {
          ...slot,
          'status': 'STOCKED',
          'bouquetId': 'bouquet',
          'productId': 'flower-id',
          'priceSnapshot': 10000,
          'sellableUntil': '9999-12-31T23:59:00Z',
          'qrCode': bouquetCode,
          'bouquetStatus': 'SOLD',
          'orderStatus': 'PAID',
        };
        final api = client(overrideSlot: stocked);
        addTearDown(api.dispose);
        await render(tester, SlotDetail(api, seller, kiosk, stocked));
        expect(find.text('Không giới hạn'), findsOneWidget);
        expect(find.textContaining('9999'), findsNothing);
        expect(find.text('Hoa hồng'), findsOneWidget);
        expect(find.text(bouquetCode), findsNothing);
        await tester.tap(find.text('Mã bó hoa'));
        await tester.pumpAndSettle();
        expect(find.text(bouquetCode), findsOneWidget);
        await tester.tap(find.text('Giao nhân viên'));
        await tester.pumpAndSettle();
        expect(find.text('Giao ô này cho nhân viên'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('system managed location has no edit action', (tester) async {
    final api = client();
    addTearDown(api.dispose);
    await render(tester, KioskLocationPage(api, seller, kiosk));
    expect(find.text('Cập nhật vị trí kiosk'), findsNothing);
    expect(
      find.text('Vị trí do hệ thống quản lý. Shop chỉ có quyền xem.'),
      findsOneWidget,
    );
  });
  testWidgets('pending layout request prevents duplicate submission', (
    tester,
  ) async {
    final api = client(
      requests: [
        {
          'status': 'PENDING',
          'walkInSlots': 0,
          'preorderSlots': 1,
          'reason': 'Thay đổi',
          'createdAt': '2026-11-23',
        },
      ],
    );
    addTearDown(api.dispose);
    await render(tester, SlotLayoutPage(api, 'kiosk', [slot]));
    expect(find.text('Đang có yêu cầu chờ duyệt.'), findsOneWidget);
    expect(find.text('Yêu cầu đổi loại ô'), findsNothing);
    expect(find.text('Gửi yêu cầu'), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Tăng ô Tại chỗ',
            ),
          )
          .onPressed,
      isNull,
    );
  });
  for (final width in [360.0, 800.0]) {
    testWidgets('layout counters preserve total and submit on page at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Json? submitted;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          if (r.method == 'POST') submitted = objectOf(jsonDecode(r.body));
          return http.Response(
            jsonEncode(
              r.url.path.endsWith('/slots')
                  ? [
                      slot,
                      {...slot, 'id': 'second', 'zone': 'PREORDER'},
                    ]
                  : [],
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.dispose);
      await render(tester, SlotLayoutPage(api, 'kiosk', [slot]));
      expect(find.text('Tổng 2 ô'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Gửi yêu cầu'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Tăng ô Đặt trước'));
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Chuyển 1 ô tại chỗ sang đặt trước.'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Giảm ô Tại chỗ',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Gửi yêu cầu'));
      await tester.pumpAndSettle();
      expect(find.text('Nhập lý do từ 5 ký tự.'), findsOneWidget);
      expect(submitted, isNull);
      await tester.enterText(find.byType(TextFormField), 'Thêm ô đặt trước');
      await tester.tap(find.text('Gửi yêu cầu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(submitted, {
        'walkInSlots': 0,
        'preorderSlots': 2,
        'reason': 'Thêm ô đặt trước',
      });
      expect(tester.takeException(), isNull);
    });
  }
  for (final failOnce in [false, true]) {
    testWidgets('history scroll loads next page and handles retry: $failOnce', (
      tester,
    ) async {
      final calls = <int>[];
      bool failed = false;
      Json event(int n) => {
        'seq': n,
        'movementType': 'STOCK_IN',
        'slotCode': 'S$n',
        'actorName': 'Nhân viên',
        'createdAt': '2026-11-23T01:00:00Z',
      };
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          final page = int.parse(r.url.queryParameters['page']!);
          calls.add(page);
          if (page == 2 && failOnce && !failed) {
            failed = true;
            return http.Response('{}', 503);
          }
          return http.Response(
            jsonEncode({
              'items': page == 1
                  ? [for (int i = 1; i <= 24; i++) event(i)]
                  : [event(24), event(25)],
              'hasMore': page == 1,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.dispose);
      await render(tester, InventoryHistoryPage(api, 'kiosk'));
      expect(calls, [1]);
      expect(find.byTooltip('Trang sau'), findsNothing);
      await tester.scrollUntilVisible(find.text('Ô S24'), 400);
      await tester.pumpAndSettle();
      if (failOnce) {
        await tester.scrollUntilVisible(find.text('Thử lại'), 150);
        expect(find.text('Chưa tải thêm được lịch sử.'), findsOneWidget);
        await tester.tap(find.text('Thử lại'));
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(find.text('Ô S25'), 100);
      await tester.pumpAndSettle();
      expect(calls, failOnce ? [1, 2, 2] : [1, 2]);
      expect(find.text('Ô S24'), findsOneWidget);
      expect(find.text('Ô S25'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(calls.last, 1);
      expect(find.text('Ô S25'), findsNothing);
    });
  }
  for (final initialStatus in ['RENTED_EMPTY', 'LOCKED']) {
    testWidgets(
      'seller can report device fault with evidence from $initialStatus slot',
      (tester) async {
        tester.view.physicalSize = const Size(420, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? uploadPath;
        String? uploadContentType;
        Json? faultBody;
        var slotStatus = initialStatus;
        final api = ApiClient(
          Uri.parse('https://example.test'),
          transport: MockClient((r) async {
            if (r.url.path.endsWith('/kiosks')) {
              return http.Response(
                jsonEncode([kiosk]),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            if (r.url.path.endsWith('/slots')) {
              return http.Response(
                jsonEncode([
                  {...slot, 'status': slotStatus},
                ]),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            if (r.url.path.endsWith('/products')) {
              return http.Response(
                jsonEncode([]),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            if (r.url.path.endsWith('/active')) {
              return initialStatus == 'LOCKED'
                  ? http.Response(
                      jsonEncode({
                        'id': 'maintenance',
                        'stage': 'NeedsInspection',
                        'availableActions': ['report-issue'],
                      }),
                      200,
                      headers: {
                        'content-type': 'application/json; charset=utf-8',
                      },
                    )
                  : http.Response('', 204);
            }
            if (r.url.path ==
                '/api/sellers/shop/slots/slot/evidence/report_device_fault') {
              uploadPath = r.url.path;
              uploadContentType = r.headers['content-type'];
              return http.Response(
                jsonEncode({'reference': 'evidence:v1:slot-fault-proof'}),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            if (r.url.path == '/api/sellers/shop/flows/report_device_fault') {
              faultBody = objectOf(jsonDecode(r.body));
              slotStatus = initialStatus == 'LOCKED' ? 'LOCKED' : 'FAULT';
              return http.Response(
                jsonEncode({'ok': true}),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            return http.Response('[]', 200);
          }),
        );
        addTearDown(api.dispose);
        final samplePng = XFile.fromData(
          Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0]),
          name: 'fault.png',
          mimeType: 'image/png',
        );
        await render(
          tester,
          SlotDetail(
            api,
            seller,
            kiosk,
            slot,
            pickEvidence: (_) async => samplePng,
          ),
        );
        await tester.ensureVisible(find.text('Báo sự cố ô S01'));
        await tester.tap(find.text('Báo sự cố ô S01'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(TextFormField),
          ),
          'Cửa ô S01 bị kẹt chốt khóa không mở được',
        );
        await tester.tap(find.text('Tiếp tục chụp / chọn ảnh'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Gửi báo cáo sự cố ô S01?'), findsOneWidget);
        expect(
          find.textContaining(
            'hủy lượt thanh toán chưa hoàn tất hoặc tạo yêu cầu hoàn tiền cho đơn đang giao',
          ),
          findsOneWidget,
        );
        expect(faultBody, isNull);
        await tester.tap(find.text('Xác nhận'));
        await tester.pumpAndSettle();
        expect(
          uploadPath,
          '/api/sellers/shop/slots/slot/evidence/report_device_fault',
        );
        expect(uploadContentType, 'image/png');
        expect(faultBody, {
          'p_kiosk': 'kiosk',
          'p_slot': 'slot',
          'p_desc': 'Cửa ô S01 bị kẹt chốt khóa không mở được',
          'p_photo': 'evidence:v1:slot-fault-proof',
        });
        expect(
          find.text(
            'Ô đã có báo cáo sự cố. Đội vận hành sẽ kiểm tra và xử lý.',
          ),
          findsOneWidget,
        );
        expect(find.text('Báo sự cố ô S01'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'seller approves technical repair directly inside FAULT slot detail',
    (tester) async {
      tester.view.physicalSize = const Size(420, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? expiry;
      final mutations = <String>[];
      final faultSlot = {...slot, 'status': 'FAULT'};
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/kiosks')) {
            return http.Response(
              jsonEncode([kiosk]),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (r.url.path.endsWith('/slots')) {
            return http.Response(
              jsonEncode([faultSlot]),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (r.url.path.endsWith('/products')) {
            return http.Response(
              jsonEncode([]),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (r.url.path.endsWith('/active')) return http.Response('', 204);
          if (r.url.path == '/api/me/technical-repairs') {
            return http.Response(
              jsonEncode([
                {
                  'id': 'repair-task-1',
                  'kioskId': 'kiosk',
                  'slotId': 'slot',
                  'kioskName': 'Kiosk Hà Nội',
                  'slotCode': 'S01',
                  'reason': 'Cửa ô S01 kẹt chốt khóa',
                  'expiresAt': expiry,
                },
                {
                  'id': 'wrong-task',
                  'kioskId': 'other-kiosk',
                  'slotId': 'other-slot',
                  'kioskName': 'Kiosk Hà Nội',
                  'slotCode': 'S01',
                  'reason': 'Ca sửa của kiosk trùng tên',
                  'expiresAt': null,
                },
              ]),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (r.url.path == '/api/me/technical-repairs/repair-task-1/approve' &&
              r.method == 'POST') {
            mutations.add(r.url.path);
            expiry = DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String();
            return http.Response(
              jsonEncode({'expiresAt': expiry}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('[]', 200);
        }),
      );
      addTearDown(api.dispose);
      await render(tester, SlotDetail(api, seller, kiosk, faultSlot));
      await tester.ensureVisible(find.text('Duyệt quyền mở ô'));
      expect(find.text('Yêu cầu mở ô sửa chữa'), findsOneWidget);
      expect(find.text('Cửa ô S01 kẹt chốt khóa'), findsOneWidget);
      expect(find.text('Ca sửa của kiosk trùng tên'), findsNothing);
      expect(find.text('Chờ duyệt'), findsOneWidget);
      await tester.tap(find.text('Duyệt quyền mở ô'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Duyệt quyền mở ô?'), findsOneWidget);
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(mutations, ['/api/me/technical-repairs/repair-task-1/approve']);
      expect(find.text('Đã duyệt'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Duyệt quyền mở ô'),
        findsNothing,
      );
      expect(find.textContaining('Đã duyệt quyền mở ô đến'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'fault slot polls new repair requests without reloading slot form',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var repairReads = 0, slotReads = 0;
      final fault = {...slot, 'status': 'FAULT'};
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((request) async {
          Object body = [];
          if (request.url.path.endsWith('/active')) {
            return http.Response('', 204);
          }
          if (request.url.path.endsWith('/slots')) {
            slotReads++;
            body = [fault];
          }
          if (request.url.path.endsWith('/kiosks')) body = [kiosk];
          if (request.url.path == '/api/me/technical-repairs') {
            repairReads++;
            body = repairReads == 1
                ? []
                : [
                    {
                      'id': 'new-task',
                      'kioskId': 'kiosk',
                      'slotId': 'slot',
                      'kioskName': 'Kiosk Hà Nội',
                      'slotCode': 'S01',
                      'reason': 'Ca sửa mới xuất hiện',
                      'expiresAt': null,
                    },
                  ];
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.dispose);
      await render(tester, SlotDetail(api, seller, kiosk, fault));
      expect(repairReads, 1);
      expect(find.text('Ca sửa mới xuất hiện'), findsNothing);
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(repairReads, 2);
      expect(slotReads, 1);
      expect(find.text('Ca sửa mới xuất hiện'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

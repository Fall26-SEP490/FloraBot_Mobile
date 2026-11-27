import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/customer_kiosks.dart';
import 'package:florabot_mobile/features/customer_reviews.dart';
import 'package:florabot_mobile/features/kiosk_application.dart';
import 'package:florabot_mobile/features/seasonal_export.dart';
import 'package:florabot_mobile/features/seasonal_advice.dart';
import 'package:florabot_mobile/features/staff_stock.dart';
import 'package:florabot_mobile/features/task_support.dart';

http.Response json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));
Future<void> largeScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> tapBusyModal(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  test('Excel export preserves text IDs and treats formulas as text', () {
    final bytes = seasonalExcel(
      'invoice_id,product_id,product_name,paid_date,quantity,season,holiday\r\n000123,000456,"=SUM(1,2) & Hoa",2026-11-27,3,AUTUMN,\r\n',
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final sheet = utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content,
    );
    expect(sheet, contains('000123'));
    expect(sheet, contains('=SUM(1,2) &amp; Hoa'));
    expect(sheet, isNot(contains('<f>')));
    expect(sheet, contains('<c r="E2"><v>3</v></c>'));
    expect(sheet, contains('state="frozen"'));
    expect(archive.findFile('[Content_Types].xml'), isNotNull);
  });
  test('Excel export rejects unexpected columns and truncated CSV', () {
    expect(() => seasonalExcel('name,total\nA,12'), throwsA(isA<ApiError>()));
    expect(
      () => seasonalExcel(
        'invoice_id,product_id,product_name,paid_date,quantity,season,holiday\n1,2,3',
      ),
      throwsA(isA<ApiError>()),
    );
  });
  test('review photos enforce type and 2MB limit', () {
    expect(
      () => encodeReviewPhoto(Uint8List(2 * 1024 * 1024 + 1)),
      throwsA(isA<ApiError>()),
    );
    expect(
      () => encodeReviewPhoto(Uint8List.fromList(utf8.encode('<html>'))),
      throwsA(isA<ApiError>()),
    );
    expect(
      encodeReviewPhoto(Uint8List.fromList([255, 216, 255, 0])),
      '/9j/AA==',
    );
  });
  test('CSV download refreshes an expired access token once', () async {
    final headers = <String?>[];
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((request) async {
        headers.add(request.headers['Authorization']);
        return request.headers['Authorization'] == 'Bearer fresh'
            ? http.Response('a,b\n1,2', 200)
            : json({}, 401);
      }),
    );
    addTearDown(api.dispose);
    api.accessToken = 'old';
    api.refreshSession = () async {
      api.accessToken = 'fresh';
    };
    expect(
      await api.request(
        'GET',
        '/api/sellers/shop/ai/sales.csv',
        textResponse: true,
      ),
      'a,b\n1,2',
    );
    expect(headers, ['Bearer old', 'Bearer fresh']);
  });
  test('kiosks sort online first then distance; search ignores accents', () {
    final rows = <Json>[
      {
        'id': 'off',
        'name': 'Kiosk gần',
        'status': 'OFFLINE',
        'latitude': 10,
        'longitude': 106,
      },
      {
        'id': 'far',
        'name': 'Kiosk xa',
        'status': 'ONLINE',
        'latitude': 11,
        'longitude': 106,
      },
      {
        'id': 'near',
        'name': 'Kiosk gần nhất',
        'status': 'ONLINE',
        'latitude': 10.1,
        'longitude': 106,
      },
    ];
    expect(
      sortedCustomerKiosks(
        rows,
        origin: const LatLng(10, 106),
      ).map((r) => r['id']),
      ['near', 'far', 'off'],
    );
    expect(sortedCustomerKiosks(rows, query: 'gan nhat').single['id'], 'near');
    expect(kioskPoint({'latitude': 999, 'longitude': 0}), isNull);
  });
  testWidgets('location denial keeps kiosk list usable', (tester) async {
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient(
        (r) async => json([
          {
            'id': 'k',
            'name': 'Kiosk HCM 14',
            'status': 'ONLINE',
            'latitude': 10,
            'longitude': 106,
          },
        ]),
      ),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(
      host(
        CustomerKiosksPage(
          api,
          showMap: false,
          locate: () async =>
              throw const ApiError(400, 'Chưa có quyền vị trí.'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tìm kiosk gần tôi'));
    await tester.pumpAndSettle();
    expect(find.text('Kiosk HCM 14'), findsOneWidget);
    expect(find.text('Chưa có quyền vị trí.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('eligible customer submits review and cannot submit twice', (
    tester,
  ) async {
    Json? posted;
    final reads = <String>[];
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        reads.add(r.url.path);
        if (r.method == 'POST') {
          posted = objectOf(jsonDecode(r.body));
          return json({'id': 'review'});
        }
        if (r.url.path.endsWith('review-eligibility')) {
          return json({'eligible': posted == null});
        }
        return json({'items': [], 'hasMore': false});
      }),
    );
    addTearDown(api.dispose);
    await largeScreen(tester);
    await tester.pumpWidget(
      host(
        CustomerReviewsPage(
          api,
          productId: 'flower',
          sellerId: 'shop',
          canReview: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tapBusyModal(tester, 'Viết đánh giá');
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Gửi đánh giá'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('5 sao'));
    await tester.enterText(find.byType(TextField), 'Hoa rất đẹp');
    await tapBusyModal(tester, 'Gửi đánh giá');
    await tester.pumpAndSettle();
    expect(posted, {'stars': 5, 'comment': 'Hoa rất đẹp', 'photoBase64': null});
    expect(find.text('Viết đánh giá'), findsNothing);
    await tester.tap(find.text('Cả shop'));
    await tester.pumpAndSettle();
    expect(reads, contains('/api/shop/sellers/shop/reviews'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('review list remains readable when eligibility is forbidden', (
    tester,
  ) async {
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient(
        (r) async => r.url.path.endsWith('review-eligibility')
            ? json({'detail': 'Không được gửi'}, 403)
            : json({
                'items': [
                  {
                    'reviewerName': 'Khách đã mua',
                    'stars': 5,
                    'comment': 'Hoa đẹp',
                  },
                ],
                'hasMore': false,
              }),
      ),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(
      host(
        CustomerReviewsPage(
          api,
          productId: 'flower',
          sellerId: 'shop',
          canReview: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Khách đã mua'), findsOneWidget);
    expect(find.text('Viết đánh giá'), findsNothing);
    expect(find.text('Không được gửi'), findsOneWidget);
  });
  testWidgets('private evidence paginates and uses bearer authentication', (
    tester,
  ) async {
    final paths = <String>[];
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        paths.add(r.url.toString());
        expect(r.headers['Authorization'], 'Bearer token');
        if (r.url.path.endsWith('/evidence')) {
          return json({
            'items': [
              {'id': r.url.queryParameters['page'] == '1' ? 'first' : 'second'},
            ],
            'hasMore': r.url.queryParameters['page'] == '1',
          });
        }
        return json({}, 404);
      }),
    );
    api.accessToken = 'token';
    addTearDown(api.dispose);
    await tester.pumpWidget(
      host(EvidenceGallery(api, '/api/staff/tasks/task/evidence')),
    );
    await tester.pumpAndSettle();
    expect(paths.any((p) => p.endsWith('/evidence/first')), isTrue);
    await tester.tap(find.text('Trang sau'));
    await tester.pumpAndSettle();
    expect(paths.any((p) => p.contains('page=2')), isTrue);
    expect(paths.any((p) => p.endsWith('/evidence/second')), isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('task history retrieves older pages from backend', (
    tester,
  ) async {
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient(
        (r) async => json({
          'history': [
            {
              'actorName': r.url.queryParameters['page'] == '1' ? 'Mới' : 'Cũ',
              'fromStatus': 'ASSIGNED',
              'toStatus': 'IN_PROGRESS',
            },
          ],
          'hasMore': r.url.queryParameters['page'] == '1',
        }),
      ),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(
      host(TaskHistoryPage(api, '/api/staff/tasks/task')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trang sau'));
    await tester.pumpAndSettle();
    expect(find.text('Cũ'), findsOneWidget);
    expect(find.text('Mới'), findsNothing);
  });
  testWidgets('repair readiness reports backend blocker then ready', (
    tester,
  ) async {
    var reads = 0;
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        reads++;
        return json({
          'code': reads == 1 ? 'REPAIR_SENSOR_STALE' : null,
          'detail': reads == 1 ? 'Tín hiệu cảm biến đã cũ.' : null,
          'pendingCommandIds': [],
        });
      }),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(host(RepairReadinessPanel(api, 'task')));
    await tester.pumpAndSettle();
    expect(find.text('Tín hiệu cảm biến đã cũ.'), findsOneWidget);
    await tester.tap(find.text('Kiểm tra lại'));
    await tester.pumpAndSettle();
    expect(find.text('Đủ điều kiện gửi báo cáo.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'staff stock recovers a committed timeout without duplicate POST',
    (tester) async {
      var posts = 0;
      Json? payload;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          if (r.method == 'POST') {
            posts++;
            payload = objectOf(jsonDecode(r.body));
            throw TimeoutException('lost response');
          }
          return json({
            'products': [
              {'id': 'p', 'name': 'Hoa hồng'},
            ],
            'slots': [
              {'id': 's', 'code': 'S01', 'zone': 'WALK_IN'},
            ],
            'actions': payload == null
                ? []
                : [
                    {'id': payload!['id'], 'qrCode': 'QR-BO-HOA'},
                  ],
          });
        }),
      );
      addTearDown(api.dispose);
      await largeScreen(tester);
      await tester.pumpWidget(host(StaffStockPage(api, 'task')));
      await tester.pumpAndSettle();
      await tapBusyModal(tester, 'Nạp hoa');
      for (final text in ['Hoa hồng', 'S01']) {
        final dropdowns = find.byType(DropdownButtonFormField<String>);
        await tester.tap(text == 'Hoa hồng' ? dropdowns.first : dropdowns.last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text(text).last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.enterText(find.byType(TextFormField), 'QR-BO-HOA');
      await tapBusyModal(tester, 'Xác nhận');
      await tapBusyModal(tester, 'Xác nhận');
      await tester.pumpAndSettle();
      expect(payload?['productId'], 'p');
      expect(payload?['slotId'], 's');
      expect(payload?['qrCode'], 'QR-BO-HOA');
      await tapBusyModal(tester, 'Kiểm tra kết quả nạp');
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'customer rental creates member payload without seller API access',
    (tester) async {
      Json? posted;
      String? postPath;
      final paths = <String>[];
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          paths.add(r.url.path);
          if (r.method == 'POST') {
            posted = objectOf(jsonDecode(r.body));
            postPath = r.url.path;
            return json({
              'id': 'app',
              'status': 'REQUESTED',
              'annualFee': 10000,
            });
          }
          if (r.url.path.endsWith('/current')) return json({}, 404);
          if (r.url.path == '/api/kiosk-packages') {
            return json({
              'configured': true,
              'annualSlotPrice': 10000,
              'version': 3,
            });
          }
          return json({}, 404);
        }),
      );
      addTearDown(api.dispose);
      await largeScreen(tester);
      final customer = Session.fromJson({
        'id': 'customer',
        'name': 'Khách',
        'role': 'CUSTOMER',
      });
      await tester.pumpWidget(
        host(
          KioskApplicationPage(
            api,
            customer,
            locationPicker: (_, _, _) async =>
                (point: (latitude: 10.77, longitude: 106.7), address: null),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      final values = [
        'Shop Hoa Mới',
        '0901234567',
        'shop@example.test',
        'Ngân hàng TMCP Quân đội',
        'NGUYEN VAN A',
        '123456789',
        '12 Nguyễn Trãi',
      ];
      for (var i = 0; i < values.length; i++) {
        final field = fields.at(i);
        await tester.ensureVisible(field);
        if (i == 3) {
          tester.widget<TextFormField>(field).controller!.text = values[i];
        } else {
          await tester.enterText(field, values[i]);
        }
      }
      await tapBusyModal(tester, 'Chọn vị trí trên bản đồ');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tapBusyModal(tester, 'Gửi hồ sơ thuê kiosk');
      await tester.pumpAndSettle();
      expect(postPath, '/api/member/kiosk-applications');
      expect(posted?['shopName'], values[0]);
      expect(posted?['bankAccountNumber'], '123456789');
      expect(posted?['pricingVersion'], 3);
      expect(posted?['latitude'], 10.77);
      expect(paths.any((path) => path.startsWith('/api/sellers/')), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('advice remains independent of forecast availability', (
    tester,
  ) async {
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient(
        (r) async => json([
          {
            'occasion': 'Ngày nhà giáo',
            'offer': 'Bó hướng dương',
            'nextStep': 'Mở đặt trước',
            'matchingProducts': ['Hoa nắng'],
          },
        ]),
      ),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(
      host(
        SeasonalAdvicePanel(
          api,
          '/api/sellers/shop/ai/seasonal-advice?month=11&year=2026',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mở đặt trước'), findsOneWidget);
    expect(find.text('Hoa nắng'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

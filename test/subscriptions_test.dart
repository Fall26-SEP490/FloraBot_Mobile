import 'dart:convert';

import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/subscriptions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

final seller = Session.fromJson({
  'id': 'owner',
  'name': 'Shop',
  'role': 'SELLER',
  'sellerId': 'shop',
});
final kiosk = <String, dynamic>{
  'id': 'kiosk',
  'name': 'Kiosk HCM 12',
  'status': 'OFFLINE',
  'slotCount': 4,
  'address': 'Địa chỉ kiosk',
};
final active = <String, dynamic>{
  'id': 'current',
  'kioskId': 'kiosk',
  'kioskName': 'Kiosk HCM 12',
  'status': 'ACTIVE',
  'price': 40000,
  'periodFrom': '2026-11-15',
  'periodTo': '2027-11-15',
};
final pending = <String, dynamic>{
  ...active,
  'id': 'renewal',
  'status': 'PENDING_PAYMENT',
  'periodFrom': '2027-11-15',
  'periodTo': '2028-11-15',
};

Future<void> host(WidgetTester tester, ApiClient api, Widget child) async {
  tester.view.physicalSize = const Size(360, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(api.dispose);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'rental detail reads all kiosk pages before offering renewal actions',
    (tester) async {
      final pages = <String>[];
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          expect(r.method, 'GET');
          expect(r.url.queryParameters['kioskId'], 'kiosk');
          pages.add(r.url.queryParameters['page']!);
          return json({
            'subscriptions': r.url.queryParameters['page'] == '1'
                ? [pending]
                : [active],
            'hasMore': r.url.queryParameters['page'] == '1',
          });
        }),
      );
      await host(tester, api, KioskRentalDetail(api, seller, kiosk));
      expect(pages, ['1', '2']);
      expect(find.text('Kỳ thuê hiện tại'), findsOneWidget);
      expect(find.text('Kỳ gia hạn'), findsOneWidget);
      expect(find.text('Tiếp tục thanh toán'), findsOneWidget);
      expect(find.text('Gia hạn thêm 12 tháng'), findsNothing);
      expect(find.text('15/11/2026 – 15/11/2027'), findsOneWidget);
      expect(find.text('15/11/2027 – 15/11/2028'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelling an unpaid renewal keeps the current rental', (
    tester,
  ) async {
    var cancelled = false;
    final posts = <String>[];
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        if (r.method == 'POST') {
          posts.add(r.url.path);
          cancelled = true;
          return http.Response('', 204);
        }
        return json({
          'subscriptions': [
            active,
            {...pending, 'status': cancelled ? 'CANCELLED' : 'PENDING_PAYMENT'},
          ],
          'hasMore': false,
        });
      }),
    );
    await host(tester, api, KioskRentalDetail(api, seller, kiosk));
    await tester.ensureVisible(find.text('Hủy kỳ gia hạn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hủy kỳ gia hạn'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(posts, isEmpty);
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(posts, ['/api/sellers/shop/subscriptions/renewal/cancel']);
    expect(find.text('Tiếp tục thanh toán'), findsNothing);
    expect(find.text('Kỳ thuê hiện tại'), findsOneWidget);
    expect(find.text('15/11/2026 – 15/11/2027'), findsOneWidget);
    expect(find.text('Gia hạn thêm 12 tháng'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'refresh before creating renewal recovers an existing pending one',
    (tester) async {
      var reads = 0;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          expect(r.method, 'GET');
          reads++;
          return json({
            'subscriptions': [active, if (reads > 1) pending],
            'hasMore': false,
          });
        }),
      );
      await host(tester, api, KioskRentalDetail(api, seller, kiosk));
      await tester.tap(find.text('Gia hạn thêm 12 tháng'));
      await tester.pumpAndSettle();
      expect(find.text('Tiếp tục thanh toán'), findsOneWidget);
      expect(find.text('Gia hạn thêm 12 tháng'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'payment uses exact renewal endpoint and refuses an unrelated checkout host',
    (tester) async {
      final posts = <String>[];
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          if (r.method == 'POST') {
            posts.add(r.url.path);
            return json({'checkoutUrl': 'https://example.test/not-payos'});
          }
          return json({
            'subscriptions': [active, pending],
            'hasMore': false,
          });
        }),
      );
      await host(tester, api, KioskRentalDetail(api, seller, kiosk));
      await tester.ensureVisible(find.text('Tiếp tục thanh toán'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tiếp tục thanh toán'));
      await tester.pumpAndSettle();
      expect(posts, ['/api/sellers/shop/subscriptions/renewal/payment-link']);
      expect(
        find.text('Liên kết thanh toán PayOS không hợp lệ.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rental list separates ended periods into history', (
    tester,
  ) async {
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        if (r.url.path.endsWith('/kiosks')) return json([kiosk]);
        return json({
          'subscriptions': [
            active,
            pending,
            {
              ...active,
              'id': 'old',
              'status': 'TERMINATED',
              'kioskName': 'Kiosk cũ',
            },
          ],
          'hasMore': false,
        });
      }),
    );
    await host(tester, api, SubscriptionsPage(api, seller));
    expect(find.text('Kiosk HCM 12'), findsOneWidget);
    expect(find.text('Kiosk cũ'), findsNothing);
    await tester.tap(find.text('Lịch sử'));
    await tester.pumpAndSettle();
    expect(find.text('Đã chấm dứt'), findsOneWidget);
    expect(find.text('Kiosk cũ'), findsOneWidget);
    expect(find.text('Kiosk HCM 12'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/seller_overview.dart';

void main() {
  testWidgets(
    'entire revenue card opens payment details and back returns to overview',
    (tester) async {
      final paths = <String>[];
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((request) async {
          paths.add(request.url.path);
          final Object data = request.url.path.endsWith('/reports/sales')
              ? {'grossPaid': 1250000, 'paidOrders': 3, 'byKiosk': []}
              : request.url.path.endsWith('/payments')
              ? {'payments': [], 'totalCount': 0}
              : {'items': [], 'hasMore': false};
          return http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SellerOverviewPage(
              api,
              Session.fromJson({
                'id': 'seller',
                'name': 'Shop',
                'role': 'SELLER',
                'sellerId': 'shop',
              }),
              (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.250.000 đ').first);
      await tester.pumpAndSettle();
      expect(paths.any((p) => p.endsWith('/payments')), isTrue);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.text('Doanh thu bán hoa'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Tổng doanh thu'), findsOneWidget);
      expect(find.text('Doanh thu từng kiosk'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Seller attention matches requested and paid orders, excludes closed orders',
    () {
      expect(sellerOrderNeedsAction({'state': 'REQUESTED'}), isTrue);
      expect(sellerOrderNeedsAction({'state': 'QUOTED'}), isFalse);
      expect(
        sellerOrderNeedsAction({'orderStatus': 'PAID', 'ready': false}),
        isTrue,
      );
      expect(
        sellerOrderNeedsAction({'orderStatus': 'PAID', 'ready': true}),
        isFalse,
      );
      expect(
        sellerOrderNeedsAction({
          'state': 'REQUESTED',
          'orderStatus': 'COMPLETED',
        }),
        isFalse,
      );
    },
  );

  for (final width in [320.0, 360.0, 800.0]) {
    testWidgets(
      'Seller overview loads real summaries, paginates attention and handles partial failure at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final calls = <String>[];
        final api = ApiClient(
          Uri.parse('https://example.test'),
          transport: MockClient((request) async {
            calls.add(request.url.toString());
            final path = request.url.path;
            dynamic data;
            if (path.endsWith('/reports/sales')) {
              data = {
                'grossPaid': 1250000,
                'paidOrders': 5,
                'byKiosk': [
                  {'kioskName': 'Kiosk HCM 12', 'grossPaid': 1250000},
                ],
              };
            } else if (path.endsWith('/preorders')) {
              final next = request.url.queryParameters['page'] == '2';
              data = {
                'items': [
                  next
                      ? {
                          'id': 'paid-order',
                          'productName': 'Bó hoa cần nạp',
                          'orderStatus': 'PAID',
                          'ready': false,
                          'orderCode': 'FB-2',
                          'pickupAt': '2026-11-23T10:00:00Z',
                        }
                      : {
                          'id': 'closed',
                          'productName': 'Hoa đã nhận',
                          'orderStatus': 'COMPLETED',
                        },
                ],
                'hasMore': !next,
              };
            } else if (path.endsWith('/staff/accounts')) {
              return http.Response(
                '{}',
                503,
                headers: {'content-type': 'application/json'},
              );
            } else if (path.endsWith('/chats')) {
              data = {
                'items': [
                  {'id': 'chat-1', 'unreadCount': 2},
                ],
                'hasMore': false,
              };
            } else {
              data = [
                {'id': 'product-1', 'status': 'ACTIVE'},
              ];
            }
            return http.Response(
              jsonEncode(data),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        int? destination;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.3 : 1)),
              child: child!,
            ),
            home: Scaffold(
              body: SellerOverviewPage(
                api,
                Session.fromJson({
                  'id': 'seller',
                  'name': 'Shop',
                  'role': 'SELLER',
                  'sellerId': 'shop',
                  'sellerStatus': 'ACTIVE',
                }),
                (value) => destination = value,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Tổng doanh thu'), findsOneWidget);
        expect(find.text('1.250.000 đ'), findsNWidgets(2));
        await tester.tap(find.text('Doanh thu từng kiosk'));
        await tester.pumpAndSettle();
        expect(find.text('1.250.000 đ'), findsNWidgets(3));
        await tester.tap(find.text('Doanh thu từng kiosk'));
        await tester.pumpAndSettle();
        expect(calls.any((url) => url.endsWith('/preorders?page=2')), isTrue);
        await tester.scrollUntilVisible(find.text('Bó hoa cần nạp'), 300);
        expect(find.textContaining('Cần nạp hoa'), findsOneWidget);
        expect(find.text('Hoa đã nhận'), findsNothing);
        await tester.ensureVisible(find.text('Tất cả đơn'));
        await tester.tap(find.text('Tất cả đơn'));
        expect(destination, 2);
        await tester.scrollUntilVisible(find.text('Cửa hàng của tôi'), 250);
        await tester.pumpAndSettle();
        expect(find.text('Chưa tải được dữ liệu.'), findsOneWidget);
        expect(find.text('1/1'), findsOneWidget);
        expect(find.text('1 hội thoại chưa đọc'), findsOneWidget);
        await tester.ensureVisible(find.text('Gần đây'));
        await tester.tap(find.text('Gần đây'));
        await tester.pumpAndSettle();
        final arrows = find.byWidgetPredicate(
          (widget) =>
              widget is Icon &&
              widget.icon == Icons.chevron_right &&
              widget.size == 18,
        );
        expect(arrows, findsNothing);
        expect(tester.takeException(), isNull);
        api.dispose();
      },
    );
  }
}

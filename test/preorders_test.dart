import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/orders.dart';
import 'package:florabot_mobile/features/preorder_support.dart';

http.Response json(dynamic data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Session session(bool seller) => Session.fromJson({
  'id': seller ? 'owner' : 'customer',
  'role': seller ? 'SELLER' : 'CUSTOMER',
  'name': 'Test',
  if (seller) 'sellerId': 'shop',
});
Json sample() => {
  'id': 'request',
  'kind': 'CUSTOM',
  'state': 'ORDERED',
  'productId': 'product',
  'sellerId': 'shop',
  'kioskId': 'kiosk',
  'productName': 'Bó hoa tươi - Only rose 18 (Size 50 bông)',
  'shopName': 'Shop Hoa',
  'kioskName': 'Kiosk HCM 12',
  'address': 'FPT University, Hòa Lạc, Hà Nội',
  'orderId': 'order',
  'orderCode': 'FB261121-2CE559',
  'orderStatus': 'COMPLETED',
  'ready': true,
  'pickupAt': DateTime.now()
      .add(const Duration(days: 2))
      .toUtc()
      .toIso8601String(),
  'pickupBefore': DateTime.now()
      .add(const Duration(days: 2, hours: 2))
      .toUtc()
      .toIso8601String(),
  'quotedPrice': 12000,
  'quotedFlowerPrice': 10000,
  'quotedAccessoryTotal': 2000,
  'quoteVersion': 3,
  'quoteNote': 'Chuẩn bị theo yêu cầu',
  'instructions': 'Chúc mừng khai trương, hoa màu tươi sáng',
  'requestedAccessories': [
    {'accessoryId': 'ribbon', 'name': 'Nơ', 'quantity': 2},
  ],
  'quotedAccessories': [
    {
      'accessoryId': 'ribbon',
      'name': 'Nơ',
      'quantity': 2,
      'unitPrice': 1000,
      'lineTotal': 2000,
    },
  ],
};
Future<void> render(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> tapModal(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

void main() {
  testWidgets(
    'staff assignment filters unsafe slots and reuses ID after retry',
    (tester) async {
      final row = {...sample(), 'orderStatus': 'PAID', 'ready': false};
      final bodies = <Json>[];
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          if (r.method == 'POST') {
            bodies.add(objectOf(jsonDecode(r.body)));
            return json({}, bodies.length == 1 ? 503 : 200);
          }
          if (r.url.path.endsWith('/staff')) {
            return json([
              {'id': 'staff', 'name': 'Nhân viên An'},
            ]);
          }
          if (r.url.path.endsWith('/slots')) {
            return json([
              {
                'id': 'slot',
                'slotCode': 'S03',
                'kioskId': 'kiosk',
                'zone': 'PREORDER',
                'status': 'RENTED_EMPTY',
                'sensorReady': true,
              },
              {
                'id': 'bad',
                'slotCode': 'S04',
                'kioskId': 'kiosk',
                'zone': 'PREORDER',
                'status': 'RENTED_EMPTY',
                'sensorReady': false,
              },
            ]);
          }
          if (r.url.path.endsWith('/kiosks')) {
            return json([
              {'id': 'kiosk', 'status': 'OFFLINE'},
            ]);
          }
          return json({
            'items': [row],
            'hasMore': false,
          });
        }),
      );
      addTearDown(api.dispose);
      await render(tester, OrderDetail(api, session(true), row));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Tự nạp hoa'),
            )
            .onPressed,
        isNull,
      );
      await tapModal(tester, find.text('Giao nhân viên nạp hoa'));
      await tapModal(
        tester,
        find.byType(DropdownButtonFormField<String>).first,
      );
      await tapModal(tester, find.text('Nhân viên An').last);
      await tapModal(tester, find.byType(DropdownButtonFormField<String>).last);
      expect(find.text('S04'), findsNothing);
      await tapModal(tester, find.text('S03').last);
      await tester.enterText(
        find.byType(TextFormField),
        'Nạp hoa và hai chiếc nơ',
      );
      await tapModal(tester, find.text('Xác nhận'));
      expect(find.text('Giao nhân viên nạp hoa?'), findsOneWidget);
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(bodies.length, 1);
      await tester.tap(find.text('Giao nhân viên nạp hoa'));
      await tester.pumpAndSettle();
      expect(bodies.length, 2);
      expect(bodies[0]['id'], bodies[1]['id']);
      expect(bodies.last['slotId'], 'slot');
      expect(bodies.last['assigneeId'], 'staff');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'seller rejection sends quote rejection API only after confirmation',
    (tester) async {
      final row = {
        ...sample(),
        'state': 'REQUESTED',
        'orderId': null,
        'orderStatus': null,
      };
      Json? posted;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          if (r.method == 'POST') {
            posted = objectOf(jsonDecode(r.body));
            return json({});
          }
          return json({
            'items': [row],
            'hasMore': false,
          });
        }),
      );
      addTearDown(api.dispose);
      await render(tester, OrderDetail(api, session(true), row));
      expect(find.text('Hủy đơn'), findsNothing);
      await tapModal(tester, find.text('Từ chối yêu cầu'));
      await tester.enterText(
        find.byType(TextFormField),
        'Chưa đáp ứng yêu cầu hoa',
      );
      await tapModal(tester, find.text('Xác nhận'));
      expect(posted, isNull);
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(posted?['reject'], true);
      expect(posted?['price'], 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('expired loading access is not usable for fulfillment', (
    tester,
  ) async {
    final row = {...sample(), 'orderStatus': 'PAID', 'ready': false};
    final posts = <String>[];
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        if (r.method == 'POST') {
          posts.add(r.url.path);
          return json({
            'id': 'expired',
            'requiresCode': false,
            'expiresAt': '2000-01-01T00:00:00Z',
          });
        }
        if (r.url.path.endsWith('/kiosks')) {
          return json([
            {'id': 'kiosk', 'status': 'ONLINE'},
          ]);
        }
        if (r.url.path.endsWith('/slots')) {
          return json([
            {
              'id': 'slot',
              'slotCode': 'S03',
              'kioskId': 'kiosk',
              'zone': 'PREORDER',
              'status': 'RENTED_EMPTY',
              'sensorReady': true,
            },
          ]);
        }
        return json({
          'items': [row],
          'hasMore': false,
        });
      }),
    );
    addTearDown(api.dispose);
    await render(tester, OrderDetail(api, session(true), row));
    await tapModal(tester, find.text('Tự nạp hoa'));
    await tapModal(tester, find.byType(DropdownButtonFormField<String>).first);
    await tapModal(tester, find.text('S03').last);
    await tester.enterText(find.byType(TextFormField), 'QR-THUC-TE');
    await tester.ensureVisible(find.text('Xác nhận'));
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(posts, ['/api/me/preorders/request/loading-access']);
    expect(
      find.text('Quyền nạp hoa đã hết hạn. Yêu cầu mã mở ô mới.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('customer can request payment link without marking order paid', (
    tester,
  ) async {
    final row = {
      ...sample(),
      'orderStatus': 'AWAITING_PAYMENT',
      'ready': false,
    };
    final paths = <String>[];
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        if (r.method == 'POST') {
          paths.add(r.url.path);
          return json({
            'amount': 12000,
            'recipientName': 'Shop Hoa',
            'checkoutUrl': 'https://pay.example.test/order',
          });
        }
        return json({
          'items': [row],
          'hasMore': false,
        });
      }),
    );
    addTearDown(api.dispose);
    await render(tester, OrderDetail(api, session(false), row));
    await tapModal(tester, find.text('Thanh toán qua payOS'));
    expect(find.text('Mở trang thanh toán?'), findsOneWidget);
    await tester.tap(find.text('Quay lại'));
    await tester.pumpAndSettle();
    expect(paths, ['/api/member/preorders/request/payment-link']);
    expect(find.text('Chờ thanh toán'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  test('action rules match web status, readiness and deadline', () {
    final row = {...sample(), 'orderStatus': 'PAID'};
    expect(preorderCanSendOtp(row), isTrue);
    for (final status in [
      'COMPLETED',
      'REFUNDED',
      'DISPENSING',
      'CANCELLED',
      'DISPENSE_FAILED',
    ]) {
      expect(preorderCanSendOtp({...row, 'orderStatus': status}), isFalse);
    }
    expect(preorderCanSendOtp({...row, 'ready': false}), isFalse);
    expect(
      preorderCanSendOtp({...row, 'pickupBefore': '2000-01-01T00:00:00Z'}),
      isFalse,
    );
    expect(preorderCanCancel(row, false), isFalse);
    expect(preorderCanCancel(row, true), isTrue);
    expect(preorderCanCancel(sample(), true), isFalse);
    expect(
      preorderCanCancel({...row, 'orderStatus': 'DISPENSING'}, true),
      isFalse,
    );
  });

  test('detail finds order moved beyond hint and first page', () async {
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        final page = int.parse(r.url.queryParameters['page']!);
        return json({
          'items': [
            page == 3 ? sample() : {'id': 'other-$page'},
          ],
          'hasMore': page < 3,
        });
      }),
    );
    addTearDown(api.dispose);
    expect(
      (await findPreorder(
        api,
        '/api/sellers/shop/preorders',
        'request',
        hint: 2,
      ))['id'],
      'request',
    );
  });

  for (final width in [360.0, 800.0]) {
    testWidgets(
      'compact list and completed detail have correct actions at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = ApiClient(
          Uri.parse('https://example.test'),
          transport: MockClient(
            (r) async => json({
              'items': [sample()],
              'hasMore': false,
            }),
          ),
        );
        addTearDown(api.dispose);
        await render(tester, OrdersPage(api, session(true)));
        expect(find.text('Đã nhận hoa'), findsOneWidget);
        expect(find.text('Shop Hoa'), findsNothing);
        await tester.tap(find.text('FB261121-2CE559'));
        await tester.pumpAndSettle();
        expect(find.text('Đã nhận hoa'), findsOneWidget);
        expect(find.text('Nơ × 2'), findsOneWidget);
        expect(find.text('Tự nạp hoa'), findsNothing);
        expect(find.text('Gửi mã nhận hoa'), findsNothing);
        expect(find.text('Hủy đơn'), findsNothing);
        expect(find.textContaining('Hoa đã được xác nhận nạp'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('quote submits flower price and explicit accessory quantities', (
    tester,
  ) async {
    final row = {
      ...sample(),
      'state': 'QUOTED',
      'orderId': null,
      'orderStatus': null,
      'quotedAccessories': [
        {
          'accessoryId': 'ribbon',
          'quantity': 1,
          'name': 'Nơ',
          'lineTotal': 1000,
        },
      ],
      'quotedPrice': 11000,
    };
    Json? posted;
    final paths = <String>[];
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        paths.add(r.url.toString());
        if (r.method == 'POST') {
          posted = objectOf(jsonDecode(r.body));
          return json({});
        }
        if (r.url.path.endsWith('/accessories')) {
          return json([
            {
              'id': 'ribbon',
              'name': 'Nơ',
              'status': 'ACTIVE',
              'price': 1000,
              'stockQuantity': 1,
              'kioskId': null,
            },
          ]);
        }
        return json({
          'items': [row],
          'hasMore': false,
        });
      }),
    );
    addTearDown(api.dispose);
    await render(tester, OrderDetail(api, session(true), row));
    await tapModal(tester, find.text('Chỉnh sửa báo giá'));
    expect(paths.any((p) => p.endsWith('/accessories?scope=ALL')), isTrue);
    await tester.enterText(find.byType(TextFormField).first, '20000');
    await tapModal(tester, find.text('Xem lại báo giá'));
    expect(find.textContaining('Tổng 21.000 đ'), findsOneWidget);
    expect(posted, isNull);
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(posted?['price'], 20000);
    expect(posted?['accessories'], [
      {'accessoryId': 'ribbon', 'quantity': 1},
    ]);
    expect(posted?.containsKey('_total'), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('customer accepts exact quote version', (tester) async {
    final row = {
      ...sample(),
      'state': 'QUOTED',
      'orderId': null,
      'orderStatus': null,
    };
    Json? posted;
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        if (r.method == 'POST') {
          posted = objectOf(jsonDecode(r.body));
          return json({});
        }
        return json({
          'items': [row],
          'hasMore': false,
        });
      }),
    );
    addTearDown(api.dispose);
    await render(tester, OrderDetail(api, session(false), row));
    await tapModal(tester, find.text('Chấp nhận báo giá'));
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(posted?['quoteVersion'], 3);
    expect(posted?['price'], 12000);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ready seller order sends pickup OTP and applies cooldown', (
    tester,
  ) async {
    final row = {...sample(), 'orderStatus': 'PAID'};
    final posts = <String>[];
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        if (r.method == 'POST') {
          posts.add(r.url.path);
          return json({
            'recipientMasked': 'k***@mail.com',
            'resendAfterSeconds': 60,
          });
        }
        return json({
          'items': [row],
          'hasMore': false,
        });
      }),
    );
    addTearDown(api.dispose);
    await render(tester, OrderDetail(api, session(true), row));
    await tapModal(tester, find.text('Gửi mã nhận hoa'));
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(posts, ['/api/me/preorders/request/pickup-otp']);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Chờ trước khi gửi lại mã'),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final requiresCode in [false, true]) {
    testWidgets(
      'self fulfillment verifies access and actual QR, requiresCode=$requiresCode',
      (tester) async {
        bool ready = false;
        Json? fulfilled;
        final posts = <String>[];
        Json order() => {...sample(), 'orderStatus': 'PAID', 'ready': ready};
        final slot = {
          'id': 'slot',
          'slotCode': 'S03',
          'kioskId': 'kiosk',
          'zone': 'PREORDER',
          'status': 'RENTED_EMPTY',
          'sensorReady': true,
        };
        final api = ApiClient(
          Uri.parse('https://example.test'),
          transport: MockClient((r) async {
            if (r.method == 'POST') {
              posts.add(r.url.path);
              if (r.url.path.endsWith('/loading-access')) {
                return json({
                  'id': 'access',
                  'requiresCode': requiresCode,
                  'expiresAt': DateTime.now()
                      .add(const Duration(minutes: 5))
                      .toUtc()
                      .toIso8601String(),
                });
              }
              if (r.url.path.endsWith('/fulfill')) {
                fulfilled = objectOf(jsonDecode(r.body));
                ready = true;
              }
              return json({});
            }
            if (r.url.path.endsWith('/kiosks')) {
              return json([
                {'id': 'kiosk', 'status': 'ONLINE'},
              ]);
            }
            if (r.url.path.endsWith('/slots')) {
              return json([
                slot,
                {...slot, 'id': 'bad', 'slotCode': 'S04', 'sensorReady': false},
              ]);
            }
            return json({
              'items': [order()],
              'hasMore': false,
            });
          }),
        );
        addTearDown(api.dispose);
        await render(tester, OrderDetail(api, session(true), order()));
        await tapModal(tester, find.text('Tự nạp hoa'));
        final dropdowns = find.byType(DropdownButtonFormField<String>);
        await tapModal(tester, dropdowns.first);
        expect(find.text('S04'), findsNothing);
        await tapModal(tester, find.text('S03').last);
        await tester.enterText(find.byType(TextFormField), 'QR-BO-HOA-THUC-TE');
        await tapModal(tester, find.text('Xác nhận'));
        if (requiresCode) {
          expect(find.text('Mã OTP 6 số'), findsOneWidget);
          await tester.enterText(find.byType(TextField), '123456');
          await tester.pump();
          await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận mở ô'));
        }
        await tester.pumpAndSettle();
        expect(posts, [
          '/api/me/preorders/request/loading-access',
          if (requiresCode) '/api/me/maintenance-access/access/confirm',
        ]);
        await tapModal(tester, find.text('Tự nạp hoa'));
        await tapModal(tester, find.text('Xác nhận'));
        expect(find.text('Xác nhận nạp hoa?'), findsOneWidget);
        await tester.tap(find.text('Xác nhận'));
        await tester.pumpAndSettle();
        expect(fulfilled, {
          'slotId': 'slot',
          'qrCode': 'QR-BO-HOA-THUC-TE',
          'loadingAccessId': 'access',
        });
        expect(find.text('Sẵn sàng nhận'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('paid cancellation explicitly warns refund is pending admin', (
    tester,
  ) async {
    final row = {...sample(), 'orderStatus': 'PAID'};
    Json? body;
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        if (r.method == 'POST') {
          body = objectOf(jsonDecode(r.body));
          return json({});
        }
        return json({
          'items': [row],
          'hasMore': false,
        });
      }),
    );
    addTearDown(api.dispose);
    await render(tester, OrderDetail(api, session(true), row));
    await tapModal(tester, find.text('Hủy đơn'));
    await tester.enterText(
      find.byType(TextFormField),
      'Không thể chuẩn bị hoa',
    );
    await tapModal(tester, find.text('Xem lại yêu cầu hủy'));
    expect(find.textContaining('tiền chưa được hoàn ngay'), findsOneWidget);
    expect(body, isNull);
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(body, {'reason': 'Không thể chuẩn bị hoa'});
    await tester.pumpWidget(const SizedBox());
  });
}

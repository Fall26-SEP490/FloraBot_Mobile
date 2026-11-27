import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:florabot_mobile/app.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/auth.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/ui/customer_flower_card.dart';

http.Response json(dynamic value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  testWidgets(
    'suggested flower opens with back navigation preserving AI draft and results',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var adviceRequests = 0;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((request) async {
          if (request.url.path == '/api/shop/flower-chat') {
            adviceRequests++;
            return json({
              'message': 'Gợi ý cho bạn',
              'suggestions': [
                {
                  'productId': 'rose',
                  'kioskId': 'kiosk',
                  'name': 'Hoa tư vấn',
                  'price': 10000,
                  'shopName': 'Shop Hoa',
                },
              ],
            });
          }
          return json({
            'items': [
              for (final name in ['Hoa tư vấn', 'Hoa khác'])
                {
                  'productId': name == 'Hoa tư vấn' ? 'rose' : 'other',
                  'sellerId': 'shop',
                  'kioskId': 'kiosk',
                  'name': name,
                  'price': 10000,
                  'shopName': 'Shop Hoa',
                  'kioskName': 'Kiosk A',
                  'tags': ['flower:rose'],
                },
            ],
            'hasMore': false,
          });
        }),
      );
      final auth = AuthController(api, MemoryTokenVault())
        ..loading = false
        ..session = Session.fromJson({
          'id': 'customer',
          'name': 'Khách',
          'role': 'CUSTOMER',
        });
      addTearDown(auth.dispose);
      addTearDown(api.dispose);
      await tester.pumpWidget(FloraBotApp(auth: auth));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Hoa');
      await tester.tap(find.byTooltip('Gợi ý chọn hoa bằng AI'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Tặng sinh nhật mẹ');
      await tester.tap(find.text('Tìm hoa phù hợp'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Xem mẫu'));
      await tester.tap(find.text('Xem mẫu'));
      await tester.pumpAndSettle();
      expect(find.text('Mẫu hoa gợi ý'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(
        find.widgetWithText(CustomerFlowerCard, 'Hoa tư vấn'),
        findsOneWidget,
      );
      expect(find.text('Hoa khác'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(CustomerFlowerCard),
          matching: find.text('Hoa tư vấn'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chi tiết mẫu hoa'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Mẫu hoa gợi ý'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Tặng sinh nhật mẹ',
      );
      expect(find.text('Gợi ý cho bạn'), findsOneWidget);
      expect(adviceRequests, 1);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Hoa',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('web catalog filters apply locally across all pages and reset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reads = <Uri>[];
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        reads.add(r.url);
        final second = r.url.queryParameters['page'] == '2';
        return json({
          'items': [
            if (!second)
              {
                'productId': 'premium',
                'sellerId': 'shop',
                'name': 'Bó hoa cao cấp',
                'price': 500000,
                'shopName': 'Shop Hoa',
                'kioskName': 'Kiosk A',
                'tags': ['flower:rose'],
              },
            if (second)
              {
                'productId': 'budget',
                'sellerId': 'shop2',
                'name': 'Bó hoa vừa túi tiền',
                'price': 150000,
                'shopName': 'Shop Khác',
                'kioskName': 'Kiosk B',
                'tags': ['flower:sunflower'],
              },
          ],
          'hasMore': !second,
        });
      }),
    );
    final auth = AuthController(api, MemoryTokenVault())
      ..loading = false
      ..session = Session.fromJson({
        'id': 'customer',
        'name': 'Khách',
        'role': 'CUSTOMER',
      });
    await tester.pumpWidget(FloraBotApp(auth: auth));
    await tester.pumpAndSettle();
    final search = find.byType(TextField);
    await tester.enterText(search, 'hoa');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bộ lọc'));
    await tester.pumpAndSettle();
    for (final label in [
      'Loại hoa',
      'Hình thức nhận hoa',
      'Khoảng giá',
      'Tủ nhận hoa',
      'Cửa hàng',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    final filterLeft = tester.getTopLeft(find.text('Loại hoa')).dx;
    for (final label in [
      'Hình thức nhận hoa',
      'Khoảng giá',
      'Tủ nhận hoa',
      'Cửa hàng',
    ]) {
      expect(tester.getTopLeft(find.text(label)).dx, closeTo(filterLeft, 1));
    }
    expect(find.text('Hoa hồng (1)'), findsOneWidget);
    final priceChoice = find.widgetWithText(ChoiceChip, 'Dưới 300.000 đ');
    await tester.ensureVisible(priceChoice);
    await tester.tap(priceChoice);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(priceChoice).selected, isTrue);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.tap(find.text('Áp dụng bộ lọc'));
    await tester.pumpAndSettle();
    expect(find.text('Bó hoa vừa túi tiền'), findsOneWidget);
    expect(find.text('Bó hoa cao cấp'), findsNothing);
    expect(reads.where((u) => u.queryParameters['page'] == '2').length, 1);
    expect(reads.length, 2);
    expect(tester.widget<TextField>(search).controller!.text, 'hoa');
    await tester.tap(find.byTooltip('Bộ lọc'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đặt lại'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Áp dụng bộ lọc'));
    await tester.pumpAndSettle();
    expect(find.text('Bó hoa cao cấp'), findsOneWidget);
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(reads.length, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
    api.dispose();
  });

  for (final width in [360.0, 430.0]) {
    testWidgets(
      'customer home shows preorder flowers and opens ordering at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final requests = <Uri>[];
        final api = ApiClient(
          Uri.parse('https://example.test'),
          transport: MockClient((r) async {
            requests.add(r.url);
            if (r.url.path == '/api/shop/catalog') {
              expect(r.url.queryParameters['availablePreorderOnly'], isNull);
              return json({
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
                  {
                    'productId': 'sunflower',
                    'sellerId': 'shop',
                    'kioskId': 'kiosk',
                    'name': 'Hướng dương tặng ngày tốt nghiệp',
                    'price': 180000,
                    'shopName': 'Shop Hoa',
                    'preorderAvailable': false,
                  },
                ],
                'hasMore': false,
              });
            }
            return json({'items': [], 'hasMore': false});
          }),
        );
        final auth = AuthController(api, MemoryTokenVault())
          ..loading = false
          ..session = Session.fromJson({
            'id': 'customer',
            'name': 'Khách',
            'role': 'CUSTOMER',
          });
        await tester.pumpWidget(FloraBotApp(auth: auth));
        await tester.pumpAndSettle();
        expect(find.text('Hoa đặt trước'), findsNothing);
        expect(find.text('Chọn mẫu hoa, nhận tại kiosk.'), findsNothing);
        expect(find.byTooltip('Bộ lọc'), findsOneWidget);
        expect(
          (tester.getCenter(find.byType(TextField)).dy -
                  tester.getCenter(find.byTooltip('Bộ lọc')).dy)
              .abs(),
          lessThan(2),
        );
        expect(find.byType(CustomerFlowerCard), findsNWidgets(2));
        expect(requests.any((u) => u.path == '/api/member/preorders'), isFalse);
        expect(find.text('Cần chú ý trên trang này'), findsNothing);
        final first = find.byType(CustomerFlowerCard).first;
        final second = find.byType(CustomerFlowerCard).last;
        expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
        expect(tester.getSize(first).height, tester.getSize(second).height);
        expect(
          find.descendant(
            of: first,
            matching: find.byType(CustomerFlowerStatusBadge),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: first,
            matching: find.widgetWithText(FilledButton, 'Đặt trước'),
          ),
          findsOneWidget,
        );
        final soldOutButton = find.descendant(
          of: second,
          matching: find.widgetWithText(FilledButton, 'Hết hàng'),
        );
        expect(soldOutButton, findsOneWidget);
        expect(tester.widget<FilledButton>(soldOutButton).onPressed, isNull);
        expect(
          find.descendant(
            of: second,
            matching: find.byType(CustomerFlowerStatusBadge),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Hướng dương tặng ngày tốt nghiệp'));
        await tester.pumpAndSettle();
        expect(find.byType(CustomerFlowerDetail), findsOneWidget);
        expect(find.text('Mẫu này tạm hết hàng.'), findsOneWidget);
        final detailSoldOut = find.descendant(
          of: find.byType(CustomerFlowerDetail),
          matching: find.widgetWithText(FilledButton, 'Hết hàng'),
        );
        expect(tester.widget<FilledButton>(detailSoldOut).onPressed, isNull);
        expect(
          find.widgetWithText(OutlinedButton, 'Nhắn shop'),
          findsOneWidget,
        );
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bó hồng pastel'));
        await tester.pumpAndSettle();
        expect(find.byType(CustomerFlowerDetail), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(BackButton), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(CustomerFlowerCard), findsNWidgets(2));
        await tester.tap(find.text('Bó hồng pastel'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Kiosk Hòa Lạc'), findsOneWidget);
        final order = find.descendant(
          of: find.byType(CustomerFlowerDetail),
          matching: find.widgetWithText(FilledButton, 'Đặt trước'),
        );
        await tester.ensureVisible(order);
        await tester.tap(order);
        await tester.pumpAndSettle();
        expect(find.text('Yêu cầu đặt trước'), findsOneWidget);
        expect(find.text('Chưa cần thanh toán'), findsOneWidget);
        expect(find.text('Gửi yêu cầu'), findsOneWidget);
        expect(find.text('Tủ nhận hoa'), findsOneWidget);
        expect(
          requests.every((u) => !u.path.endsWith('/api/member/preorders')),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        auth.dispose();
        api.dispose();
      },
    );
  }

  testWidgets(
    'customer home retries a failed catalog request and shows the empty state',
    (tester) async {
      var attempts = 0;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          if (r.url.path == '/api/shop/catalog') {
            if (++attempts == 1) return json({'detail': 'Tạm gián đoạn'}, 503);
            return json({'items': [], 'hasMore': false});
          }
          return json({});
        }),
      );
      final auth = AuthController(api, MemoryTokenVault())
        ..loading = false
        ..session = Session.fromJson({
          'id': 'customer',
          'name': 'Khách',
          'role': 'CUSTOMER',
        });
      await tester.pumpWidget(FloraBotApp(auth: auth));
      await tester.pumpAndSettle();
      expect(find.text('Tạm gián đoạn'), findsOneWidget);
      await tester.tap(find.text('Tải lại'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa có mẫu hoa nào.'), findsOneWidget);
      expect(attempts, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      api.dispose();
    },
  );
}

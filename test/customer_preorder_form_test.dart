import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:florabot_mobile/app.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/auth.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/customer_preorder_form.dart';

http.Response _json(dynamic value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _flowerRow({
  String productId = 'prod-rose',
  String sellerId = 'seller-1',
  String kioskId = 'kiosk-a',
  String kioskName = 'Kiosk A',
  String address = '123 Nguyễn Trãi, Hà Nội',
  num price = 250000,
  String name = 'Bó hồng pastel',
  String shopName = 'Tiệm Hoa Mùa Xuân',
  String? zone = 'PREORDER',
}) => {
  'productId': productId,
  'sellerId': sellerId,
  'kioskId': kioskId,
  'kioskName': kioskName,
  'address': address,
  'price': price,
  'name': name,
  'shopName': shopName,
  'zone': zone,
};

Future<void> _selectTomorrowDate(WidgetTester tester) async {
  final dateField = find.text('Chọn ngày');
  await tester.ensureVisible(dateField);
  await tester.tap(dateField);
  await tester.pumpAndSettle();
  // showDatePicker opens on tomorrow (today + 1) by default, so tapping OK confirms it.
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _selectPickupTime(WidgetTester tester, String slot) async {
  final timeDropdown = find.byKey(const ValueKey('preorder-time-dropdown'));
  await tester.ensureVisible(timeDropdown);
  await tester.tap(timeDropdown);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text(slot),
    160,
    scrollable: find.byType(Scrollable).last,
  );
  final option = find.text(slot).last;
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'supports multi-kiosk switch, accessories total, quick tags, validation, and submit to orders tab',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Map<String, dynamic>? postedBody;
      final slotChecks = <String>[];
      final catalogItems = [
        _flowerRow(
          kioskId: 'kiosk-a',
          kioskName: 'Kiosk A',
          address: 'Địa chỉ A',
        ),
        _flowerRow(
          kioskId: 'kiosk-b',
          kioskName: 'Kiosk B',
          address: 'Địa chỉ B',
        ),
      ];

      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          if (r.url.path == '/api/shop/catalog') {
            return _json({'items': catalogItems, 'hasMore': false});
          }
          if (r.url.path ==
              '/api/member/sellers/seller-1/catalog/accessories') {
            return _json([
              {
                'id': 'acc-card',
                'name': 'Thiệp viết tay',
                'price': 30000,
                'availableQuantity': 2,
              },
              {
                'id': 'acc-bear',
                'name': 'Gấu bông mini',
                'price': 90000,
                'availableQuantity': 0,
              },
            ]);
          }
          if (r.url.path.endsWith('/preorder-availability')) {
            if (r.url.queryParameters.containsKey('pickupAt')) {
              slotChecks.add(r.url.path);
            }
            return _json({'available': true});
          }
          if (r.method == 'POST' && r.url.path == '/api/member/preorders') {
            postedBody = jsonDecode(r.body) as Map<String, dynamic>;
            return _json({'id': postedBody!['id']}, 201);
          }
          if (r.url.path == '/api/member/preorders') {
            return _json({'items': [], 'hasMore': false});
          }
          return _json({});
        }),
      );

      final auth = AuthController(api, MemoryTokenVault())
        ..loading = false
        ..session = Session.fromJson({
          'id': 'customer-1',
          'name': 'Khách hàng',
          'role': 'CUSTOMER',
        });

      await tester.pumpWidget(FloraBotApp(auth: auth));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Đặt trước').first);
      await tester.pumpAndSettle();

      // Header & base price
      expect(find.text('Yêu cầu đặt trước'), findsOneWidget);
      expect(find.text('Bó hồng pastel · Tiệm Hoa Mùa Xuân'), findsOneWidget);
      expect(find.text('Giá mẫu'), findsOneWidget);
      expect(find.text('250.000 đ'), findsOneWidget);

      // Accessories section: add Thiệp viết tay up to max stock (2)
      expect(find.text('Phụ kiện'), findsOneWidget);
      expect(find.text('Hết hàng'), findsOneWidget);
      await tester.tap(find.text('Thêm'));
      await tester.pumpAndSettle();
      expect(find.text('Tạm tính'), findsOneWidget);
      expect(find.text('280.000 đ'), findsOneWidget);
      expect(find.text('Phụ kiện: 30.000 đ'), findsOneWidget);

      await tester.tap(find.byTooltip('Tăng số lượng Thiệp viết tay'));
      await tester.pumpAndSettle();
      expect(find.text('310.000 đ'), findsOneWidget);
      expect(find.text('Đã chọn tối đa'), findsOneWidget);

      // Switch kiosk from Kiosk A to Kiosk B
      expect(find.text('Địa chỉ A'), findsOneWidget);
      final kioskDropdown = find.text('Kiosk A').first;
      await tester.ensureVisible(kioskDropdown);
      await tester.tap(kioskDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kiosk B').last);
      await tester.pumpAndSettle();
      expect(find.text('Địa chỉ B'), findsOneWidget);

      // Inline validation when pickup date/time missing
      await tester.tap(find.text('Gửi yêu cầu'));
      await tester.pumpAndSettle();
      expect(find.text('Chọn ngày giờ nhận (tối đa 30 ngày).'), findsOneWidget);

      // Pick date + time and verify live availability check fired for Kiosk B
      await _selectTomorrowDate(tester);
      await _selectPickupTime(tester, '10:00');
      expect(slotChecks, contains('/api/kiosks/kiosk-b/preorder-availability'));

      // Validation when brief < 10 chars
      await tester.tap(find.text('Gửi yêu cầu'));
      await tester.pumpAndSettle();
      expect(find.text('Nhập ít nhất 10 ký tự.'), findsOneWidget);

      // Quick suggestion chip populates instructions
      final chip = find.widgetWithText(ActionChip, 'Sinh nhật');
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.text('Tặng sinh nhật, hoa tông pastel'), findsOneWidget);
      // Price stays pinned at the bottom footer after scrolling down
      expect(tester.getTopLeft(find.text('310.000 đ')).dy, greaterThan(700));

      // Submit request
      await tester.tap(find.text('Gửi yêu cầu'));
      await tester.pumpAndSettle();

      expect(postedBody, isNotNull);
      expect(postedBody!['kind'], 'CUSTOM');
      expect(postedBody!['productId'], 'prod-rose');
      expect(postedBody!['kioskId'], 'kiosk-b');
      expect(postedBody!['instructions'], 'Tặng sinh nhật, hoa tông pastel');
      expect(postedBody!['accessories'], [
        {'accessoryId': 'acc-card', 'quantity': 2},
      ]);

      // Done state + jump to Đơn đặt tab
      expect(find.text('Đã gửi yêu cầu'), findsOneWidget);
      await tester.tap(find.text('Xem đơn đặt'));
      await tester.pumpAndSettle();
      expect(find.text('Đơn đặt của tôi'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      api.dispose();
    },
  );

  testWidgets(
    'blocks unavailable slot, confirms dirty close, retries ambiguous failure with same UUID, and handles 409 sold out',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var slotAvailable = false;
      var postAttempt = 0;
      final sentIds = <String>[];

      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          if (r.url.path ==
              '/api/member/sellers/seller-1/catalog/accessories') {
            return _json([]);
          }
          if (r.url.path == '/api/kiosks/kiosk-a/preorder-availability') {
            if (r.url.queryParameters.containsKey('pickupAt')) {
              return _json({
                'available': slotAvailable,
                if (!slotAvailable) 'message': 'Tủ đã hết chỗ khung giờ này.',
              });
            }
            return _json({'available': true});
          }
          if (r.method == 'POST' && r.url.path == '/api/member/preorders') {
            final body = jsonDecode(r.body) as Map<String, dynamic>;
            sentIds.add('${body['id']}');
            postAttempt++;
            if (postAttempt == 1) {
              return _json({'message': 'Lỗi máy chủ tạm thời'}, 500);
            }
            return _json({
              'code': 'PREORDER_PRODUCT_OUT_OF_STOCK',
              'message': 'Sản phẩm đã hết hàng',
            }, 409);
          }
          if (r.url.path == '/api/shop/catalog') {
            return _json({'items': [], 'hasMore': false});
          }
          return _json({});
        }),
      );

      final item = _flowerRow();
      await tester.pumpWidget(
        MaterialApp(
          home: CustomerPreorderFormPage(
            api: api,
            item: item,
            catalogRows: [item],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Empty accessories section stays hidden
      expect(find.text('Phụ kiện'), findsNothing);

      // Select date + unavailable time
      await _selectTomorrowDate(tester);
      await _selectPickupTime(tester, '09:00');
      expect(find.text('Tủ đã hết chỗ khung giờ này.'), findsOneWidget);

      // Add brief so form is dirty, then verify close confirm dialog
      final chip = find.widgetWithText(ActionChip, 'Kỷ niệm');
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Đóng yêu cầu đặt trước'));
      await tester.pumpAndSettle();
      expect(find.text('Đóng form?'), findsOneWidget);
      await tester.tap(find.text('Ở lại'));
      await tester.pumpAndSettle();
      expect(find.text('Yêu cầu đặt trước'), findsOneWidget);

      // Submitting while slot unavailable stays blocked
      await tester.tap(find.text('Gửi yêu cầu'));
      await tester.pumpAndSettle();
      expect(sentIds, isEmpty);

      // Now slot becomes available when choosing another slot
      slotAvailable = true;
      await _selectPickupTime(tester, '11:00');

      // First submit hits 500 -> ambiguous retry mode with same UUID
      await tester.tap(find.text('Gửi yêu cầu'));
      await tester.pumpAndSettle();
      expect(find.text('Gửi lại'), findsOneWidget);
      expect(find.text('Kiểm tra đơn đặt'), findsOneWidget);
      expect(sentIds.length, 1);

      // Retry sends exact same id, hits 409 PREORDER_PRODUCT_OUT_OF_STOCK -> sold out alert
      await tester.tap(find.text('Gửi lại'));
      await tester.pumpAndSettle();
      expect(sentIds.length, 2);
      expect(sentIds[0], sentIds[1]);
      expect(find.text('Mẫu hoa đã hết hàng.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
}

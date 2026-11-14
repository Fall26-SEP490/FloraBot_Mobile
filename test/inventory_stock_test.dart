import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/inventory.dart';

void main() {
  testWidgets('kiosk slots form two columns and open the selected slot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const first = {
      'id': 'one',
      'slotCode': 'S01',
      'zone': 'WALK_IN',
      'status': 'LOCKED',
    };
    const second = {
      'id': 'two',
      'slotCode': 'S02',
      'zone': 'WALK_IN',
      'status': 'RENTED_EMPTY',
      'sensorEnabled': true,
      'sensorReady': true,
    };
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((request) async {
        if (request.url.path.endsWith('/two/maintenance-sessions/active')) {
          return http.Response('', 204);
        }
        final data = request.url.path.endsWith('/slots')
            ? [first, second, first]
            : [];
        return http.Response(jsonEncode(data), 200);
      }),
    );
    final session = Session.fromJson({
      'id': 'owner',
      'name': 'Owner',
      'role': 'SELLER',
      'sellerId': 'shop',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlotsPage(api, session, const {
            'id': 'kiosk',
            'name': 'Kiosk',
            'address': 'Địa chỉ',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final left = find.text('Ô S01');
    final right = find.text('Ô S02');
    expect(left, findsOneWidget);
    expect(tester.getTopLeft(left).dy, tester.getTopLeft(right).dy);
    expect(tester.getTopLeft(left).dx, lessThan(tester.getTopLeft(right).dx));
    expect(find.text('Trang sau'), findsNothing);
    tester.view.physicalSize = const Size(320, 720);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(left).dx, tester.getTopLeft(right).dx);
    expect(tester.getTopLeft(left).dy, lessThan(tester.getTopLeft(right).dy));
    await tester.tap(right);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SlotDetail>(find.byType(SlotDetail)).slot['id'],
      'two',
    );
    expect(find.text('Tự nạp hoa · Lấy mã mở ô'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });

  test('unknown inventory is explicit and cannot be selected for loading', () {
    final input = stockProductInput([
      {'id': 'missing', 'name': 'Missing quantity', 'status': 'ACTIVE'},
      {'id': 'empty', 'name': 'No stock', 'status': 'ACTIVE', 'quantity': 0},
      {
        'id': 'available',
        'name': 'In stock',
        'status': 'ACTIVE',
        'quantity': 1,
      },
      {
        'id': 'inactive',
        'name': 'Inactive',
        'status': 'DISABLED',
        'quantity': 5,
      },
    ]);
    expect(input.choiceDetails['missing'], 'Chưa có dữ liệu tồn shop');
    expect(input.choiceDetails['empty'], 'Tồn shop: 0 bó');
    expect(input.choiceDetails['available'], 'Tồn shop: 1 bó');
    expect(input.disabledChoices, {'missing', 'empty'});
    expect(input.choices!.containsKey('inactive'), false);
  });

  testWidgets(
    'assignment refreshes stock and shows quantities even with long names',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var productReads = 0;
      Map<String, dynamic>? ownerRequest;
      const slot = {
        'id': 'slot',
        'slotCode': 'S01',
        'zone': 'WALK_IN',
        'status': 'RENTED_EMPTY',
        'sensorEnabled': false,
        'sensorReady': true,
      };
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/me/kiosks/kiosk/slots') {
            return http.Response(jsonEncode([slot]), 200);
          }
          if (path == '/api/sellers/shop/staff') {
            return http.Response('[{"id":"staff","name":"Staff"}]', 200);
          }
          if (path == '/api/me/maintenance-access') {
            ownerRequest = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'code': '123456',
                'expiresAt': DateTime.now()
                    .add(const Duration(minutes: 5))
                    .toIso8601String(),
              }),
              200,
            );
          }
          if (path == '/api/me/products') {
            productReads++;
            return http.Response(
              jsonEncode([
                {
                  'id': 'empty',
                  'name': 'Bó hoa tươi - Only rose 18 (Size 50 bông)',
                  'status': 'ACTIVE',
                  'quantity': 0,
                },
                {
                  'id': 'available',
                  'name': 'Florabot 12',
                  'status': 'ACTIVE',
                  'quantity': productReads == 1 ? 9 : 1,
                },
              ]),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          throw StateError('Unexpected request: $path');
        }),
      );
      final session = Session.fromJson({
        'id': 'owner',
        'name': 'Owner',
        'role': 'SELLER',
        'sellerId': 'shop',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlotDetail(api, session, const {
              'id': 'kiosk',
              'name': 'Kiosk',
            }, slot),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final assign = find.text('Giao ô này cho nhân viên');
      await tester.ensureVisible(assign);
      await tester.tap(assign);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(productReads, 2);
      final productField = find.byType(DropdownButtonFormField<String>).last;
      await tester.ensureVisible(productField);
      await tester.tap(productField);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Tồn shop: 0 bó'), findsOneWidget);
      expect(find.text('Tồn shop: 1 bó'), findsOneWidget);
      expect(find.text('Tồn shop: 9 bó'), findsNothing);
      final zero = tester
          .widgetList<DropdownMenuItem<String>>(
            find.byType(DropdownMenuItem<String>),
          )
          .where((item) => item.value == 'empty');
      expect(zero.every((item) => !item.enabled), true);
      await tester.tap(find.text('Tồn shop: 0 bó'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.state<FormFieldState<String>>(productField).value, isNull);
      await tester.tap(find.text('Tồn shop: 1 bó'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.state<FormFieldState<String>>(productField).value,
        'available',
      );
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(productField)).pop();
      await tester.pumpAndSettle();

      final load = find.text('Tự nạp hoa · Lấy mã mở ô');
      await tester.ensureVisible(load);
      await tester.tap(load);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Tồn shop: 1 bó'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextFormField), 'Nạp hoa vào ô thử');
      final issue = find.text('Lấy OTP thao tác');
      await tester.ensureVisible(issue);
      await tester.tap(issue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(ownerRequest, containsPair('action', 'LOAD'));
      expect(ownerRequest, containsPair('productId', 'available'));
      expect(ownerRequest!.containsKey('assigneeId'), false);
      expect(find.text('123456'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
}

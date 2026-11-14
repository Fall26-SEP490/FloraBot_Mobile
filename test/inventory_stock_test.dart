import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/inventory.dart';

void main() {
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
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
}

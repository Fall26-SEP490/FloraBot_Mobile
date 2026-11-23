import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/inventory.dart';
import 'package:florabot_mobile/features/seller_tools.dart';
import 'package:florabot_mobile/ui/catalog_widgets.dart';

void main() {
  final seller = Session.fromJson({
    'id': 'owner',
    'name': 'Shop',
    'role': 'SELLER',
    'sellerId': 'shop',
  });

  for (final width in [360.0, 800.0]) {
    testWidgets('product details group information and preserve status action at $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Json? mutation;
      final api = ApiClient(Uri.parse('https://example.test'), transport: MockClient((request) async {
        Object response;
        if (request.method == 'POST') {
          expect(request.url.path, '/api/me/flows/set_product_status');
          mutation = objectOf(jsonDecode(request.body));
          response = {};
        } else if (request.url.path.endsWith('/photos')) {
          response = {'items': [], 'hasMore': false};
        } else {
          response = [{'id': 'rose', 'name': 'Bó hồng pastel', 'price': 250000, 'quantity': 4,
            'status': 'ACTIVE', 'lengthCm': 20, 'widthCm': 15, 'heightCm': 30,
            'tags': ['flower:rose', 'color:pink'], 'description': 'Hoa dành tặng sinh nhật'}];
        }
        return http.Response(jsonEncode(response), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }));
      addTearDown(api.dispose);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProductsPage(api, seller))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bó hồng pastel'));
      await tester.pumpAndSettle();
      expect(find.text('Ảnh mẫu hoa'), findsOneWidget);
      expect(find.text('Chưa có ảnh mẫu hoa'), findsOneWidget);
      expect(find.text('Thông tin mẫu hoa'), findsOneWidget);
      expect(find.text('Hoa hồng'), findsOneWidget);
      expect(find.text('Hồng'), findsOneWidget);
      expect(find.textContaining('flower:rose'), findsNothing);
      final stop = find.widgetWithText(OutlinedButton, 'Ngừng bán mẫu hoa');
      await tester.ensureVisible(stop);
      await tester.pumpAndSettle();
      await tester.tap(stop);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(mutation, {'productId': 'rose', 'status': 'INACTIVE'});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'catalog filters products without duplicated heading or camera actions',
    (tester) async {
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient(
          (request) async => http.Response(
            jsonEncode([
              {
                'id': 'a',
                'name': 'Hoa hồng',
                'price': 10000,
                'quantity': 3,
                'status': 'ACTIVE',
              },
              {
                'id': 'b',
                'name': 'Hoa cúc',
                'price': 20000,
                'quantity': 0,
                'status': 'DRAFT',
              },
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ProductsPage(api, seller))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mẫu hoa'), findsNothing);
      expect(find.byTooltip('Thêm ảnh'), findsNothing);
      expect(find.text('Hoa hồng'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'cúc');
      await tester.pumpAndSettle();
      expect(find.text('Hoa hồng'), findsNothing);
      expect(find.text('Hoa cúc'), findsOneWidget);
      await tester.tap(find.byTooltip('Lọc trạng thái'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(
          of: find.text('Đang bán'),
          matching: find.byWidgetPredicate(
            (w) => w is CheckedPopupMenuItem<String>,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Không có mẫu hoa phù hợp.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'product creation keeps metadata and classification in one form',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Json? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await showCatalogEditor(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final values = [
        'Bó hồng pastel',
        '250000',
        '4',
        '20,25',
        '15',
        '30',
        'Bó hoa thử nghiệm',
      ];
      for (var index = 0; index < values.length; index++) {
        final field = find.byType(TextFormField).at(index);
        await tester.ensureVisible(field);
        await tester.enterText(field, values[index]);
      }
      final save = find.widgetWithText(FilledButton, 'Tạo mẫu hoa');
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        save,
        300,
        scrollable: find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        find.text('Chọn ít nhất một loại hoa và một màu.'),
        findsOneWidget,
      );
      for (final label in ['Hoa hồng', 'Hồng']) {
        final chip = find.widgetWithText(FilterChip, label);
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(
        save,
        300,
        scrollable: find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(result, {
        'name': 'Bó hồng pastel',
        'price': 250000,
        'quantity': 4,
        'lengthCm': 20.25,
        'widthCm': 15.0,
        'heightCm': 30.0,
        'description': 'Bó hoa thử nghiệm',
        'tags': ['flower:rose', 'color:pink'],
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'accessory create uses the existing API with name and price only',
    (tester) async {
      Json? payload;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((request) async {
          if (request.method == 'POST') {
            expect(request.url.path, '/api/sellers/shop/accessories');
            payload = objectOf(jsonDecode(request.body));
            return http.Response('{"id":"accessory"}', 200);
          }
          return http.Response('[]', 200);
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AccessoriesPage(api, seller))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tạo phụ kiện'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(2));
      await tester.enterText(find.byType(TextFormField).at(0), 'Nơ');
      await tester.enterText(find.byType(TextFormField).at(1), '10000');
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Tạo phụ kiện'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Tạo phụ kiện'));
      await tester.pumpAndSettle();
      expect(payload, {'name': 'Nơ', 'price': 10000});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

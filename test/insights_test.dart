import 'dart:async';
import 'dart:convert';

import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/insights.dart';
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

Future<void> host(
  WidgetTester tester,
  ApiClient api, {
  double width = 360,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(api.dispose);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: InsightsPage(api, seller))),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [360.0, 800.0]) {
    testWidgets(
      'sales uses date range and forecast uses matching history at $width',
      (tester) async {
        Uri? salesUrl;
        Json? forecastBody;
        final api = ApiClient(
          Uri.parse('https://example.test'),
          transport: MockClient((r) async {
            if (r.url.path.endsWith('/seasonal-advice')) return json([]);
            if (r.method == 'GET') {
              salesUrl = r.url;
              return json({
                'totalInvoices': 8,
                'totalUnits': 9,
                'products': [
                  {'name': 'Hoa hồng', 'totalInvoices': 8, 'totalUnits': 9},
                ],
              });
            }
            expect(r.url.path, '/api/sellers/shop/ai/seasonal-forecast');
            forecastBody = jsonDecode(r.body) as Json;
            return json({
              'warnings': [
                'Annual seasonality is not validated (14-day holdout).',
              ],
              'products': [
                {
                  'name': 'Hoa hồng',
                  'observedUnits': 9,
                  'observedInvoiceCount': 8,
                  'forecastUnits': null,
                  'modelStatus': 'INSUFFICIENT_HISTORY',
                  'explanation': 'Cần thêm lịch sử bán hàng.',
                },
              ],
            });
          }),
        );
        await host(tester, api, width: width);
        expect(salesUrl!.path, '/api/sellers/shop/ai/seasonal-sales');
        expect(salesUrl!.queryParameters.keys, containsAll(['from', 'to']));
        expect(salesUrl!.queryParameters, isNot(contains('month')));
        expect(find.text('8 hóa đơn · 9 bó'), findsOneWidget);
        expect(forecastBody, isNull);
        await tester.tap(find.text('Dự báo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Xem dự báo'));
        await tester.pumpAndSettle();
        expect(forecastBody!['historyFrom'], salesUrl!.queryParameters['from']);
        expect(forecastBody!['historyTo'], salesUrl!.queryParameters['to']);
        final start = DateTime(
          forecastBody!['year'] as int,
          forecastBody!['month'] as int,
        );
        expect(
          start.isAfter(DateTime.parse(forecastBody!['historyTo'] as String)),
          isTrue,
        );
        expect(find.text('Chưa đủ dữ liệu'), findsOneWidget);
        expect(
          find.text('Dự báo chưa được kiểm chứng theo mùa hằng năm.'),
          findsOneWidget,
        );
        expect(find.textContaining('null bó'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('changing forecast month discards an older response', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    Json? body;
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        if (r.url.path.endsWith('/seasonal-advice')) return json([]);
        if (r.method == 'GET') {
          return json({'totalInvoices': 0, 'totalUnits': 0, 'products': []});
        }
        body = jsonDecode(r.body) as Json;
        return response.future;
      }),
    );
    await host(tester, api);
    await tester.tap(find.text('Dự báo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xem dự báo'));
    await tester.pump();
    final currentMonth =
        '${(body!['month'] as int).toString().padLeft(2, '0')}/${body!['year']}';
    await tester.tap(find.text(currentMonth));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final monthPicker = find.byType(DropdownButtonFormField<int>).last;
    await tester.tap(monthPicker);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final next = (body!['month'] as int) == 12
        ? 1
        : (body!['month'] as int) + 1;
    // December's next selectable month belongs to the following year.
    if ((body!['month'] as int) == 12) {
      await tester.tap(find.text('Tháng 12').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('${(body!['year'] as int) + 1}').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    } else {
      await tester.tap(find.text('Tháng $next').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.tap(find.text('Chọn tháng'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    response.complete(
      json({
        'warnings': [],
        'products': [
          {'name': 'Kết quả cũ', 'forecastUnits': 20},
        ],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kết quả cũ'), findsNothing);
    expect(find.text('Chọn tháng để xem số bó dự kiến.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

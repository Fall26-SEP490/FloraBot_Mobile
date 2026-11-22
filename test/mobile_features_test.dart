import 'package:florabot_mobile/features/inventory.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/seller_tools.dart';
import 'package:florabot_mobile/features/flower_advisor.dart';
import 'package:florabot_mobile/features/qr_scanner.dart';
import 'package:florabot_mobile/ui/product_tags.dart';

http.Response jsonResponse(String body, int status) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Session seller() => Session.fromJson({
  'id': 'owner',
  'name': 'Shop',
  'role': 'SELLER',
  'sellerId': 'shop',
});
void main() {
  test('QR accepts only HTTPS FloraBot links without credentials', () {
    expect(floraBotQrLink('https://florabot.site/nhan-hoa'), isNotNull);
    for (final value in [
      'https://florabot.site.evil.test',
      'https://evil.test',
      'http://florabot.site',
      'https://user:pass@florabot.site',
      'https://florabot.site:8443',
    ]) {
      expect(floraBotQrLink(value), isNull);
    }
  });
  test('seller tags distinguish group and supported code', () {
    expect(knownProductTag('flower:rose'), isTrue);
    expect(knownProductTag('material:other'), isTrue);
    expect(knownProductTag('color:rose'), isFalse);
    expect(knownProductTag('rose'), isFalse);
    expect(productTagGroups['flower']!['babys-breath'], 'Hoa baby');
  });
  testWidgets('editing characteristics preserves custom seller tags', (
    tester,
  ) async {
    List<String>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await chooseProductTags(context, [
                  'flower:rose',
                  'color:pink',
                  'custom-note',
                ]);
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu đặc điểm'));
    await tester.pumpAndSettle();
    expect(saved, containsAll(['flower:rose', 'color:pink', 'custom-note']));
  });
  testWidgets('missing payment channel explains administrator configuration', (
    tester,
  ) async {
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async => jsonResponse('{}', 404)),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: PaymentChannelPage(api, seller()))),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Quản trị viên gắn cấu hình'), findsOneWidget);
    expect(find.text('Gắn cấu hình'), findsNothing);
    expect(tester.takeException(), isNull);
    api.dispose();
  });
  testWidgets('complaint without assigned task renders and can be accepted', (
    tester,
  ) async {
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient(
        (r) async => jsonResponse(
          jsonEncode({
            'id': 'c',
            'orderCode': 'O1',
            'status': 'REPORTED',
            'reason': 'Hoa cần kiểm tra',
            'version': 1,
            'task': null,
            'evidence': {'items': []},
            'items': [],
          }),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ComplaintDetail(api, seller(), 'c'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tiếp nhận'), findsOneWidget);
    expect(tester.takeException(), isNull);
    api.dispose();
  });
  testWidgets('accessory toggle sends backend INACTIVE status', (tester) async {
    http.Request? mutation;
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        if (r.method == 'PATCH') {
          mutation = r;
          return jsonResponse('{}', 200);
        }
        return jsonResponse(
          jsonEncode([
            {
              'id': 'a',
              'name': 'Thiệp',
              'price': 10000,
              'stockQuantity': 2,
              'status': 'ACTIVE',
            },
          ]),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AccessoriesPage(api, seller()))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dừng bán'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(mutation?.url.path, '/api/sellers/shop/accessories/a/status');
    expect(jsonDecode(mutation!.body)['status'], 'INACTIVE');
    api.dispose();
  });
  testWidgets('AI uses preorder endpoint and numeric budget', (tester) async {
    http.Request? request;
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        request = r;
        return jsonResponse(
          jsonEncode({'message': 'Chưa có mẫu phù hợp', 'suggestions': []}),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: FlowerAdvisorPage(api))),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Tặng mẹ hoa hồng');
    await tester.ensureVisible(find.text('Tìm hoa phù hợp'));
    await tester.tap(find.text('Tìm hoa phù hợp'));
    await tester.pumpAndSettle();
    expect(request?.url.path, '/api/shop/flower-chat');
    final body = jsonDecode(request!.body);
    expect(body['mode'], 'PREORDER');
    expect(body['budget'], 300000);
    expect(find.text('Chưa có mẫu phù hợp'), findsOneWidget);
    api.dispose();
  });
  testWidgets('refund without transfer permission offers no mutation action', (
    tester,
  ) async {
    final methods = <String>[];
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        methods.add(r.method);
        return jsonResponse(
          jsonEncode({
            'id': 'refund',
            'orderCode': 'O1',
            'amount': 200000,
            'status': 'PENDING',
            'canAccessBank': false,
            'canSubmitTransfer': false,
            'submission': null,
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SellerRefundDetail(api, seller(), 'refund')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gửi chứng từ chuyển khoản'), findsNothing);
    expect(find.text('Xem tài khoản nhận hoàn'), findsNothing);
    expect(methods, ['GET']);
    expect(tester.takeException(), isNull);
    api.dispose();
  });
  testWidgets('accepting complaint submits current version', (tester) async {
    Map<String, dynamic>? body;
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        if (r.method == 'POST') {
          expect(r.url.path, '/api/me/complaints/c/accept');
          body = jsonDecode(r.body);
          return jsonResponse('{}', 200);
        }
        return jsonResponse(
          jsonEncode({
            'orderCode': 'O1',
            'status': 'REPORTED',
            'reason': 'Kiểm tra',
            'version': 7,
            'task': null,
            'evidence': {'items': []},
            'items': [],
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ComplaintDetail(api, seller(), 'c'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp nhận'));
    await tester.pumpAndSettle();
    expect(body?['version'], 7);
    api.dispose();
  });
  test('AI results must match actual seller tags and current budget', () async {
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient(
        (r) async => jsonResponse(
          jsonEncode({
            'items': [
              {
                'productId': 'p',
                'kioskId': 'k',
                'price': 250000,
                'tags': ['flower:rose', 'color:white', 'material:wax'],
              },
            ],
            'hasMore': false,
          }),
          200,
        ),
      ),
    );
    final response = {
      'message': 'Hoa phù hợp',
      'suggestions': [
        {
          'id': 'b',
          'productId': 'p',
          'kioskId': 'k',
          'name': 'Hoa hồng',
          'price': 200000,
        },
      ],
    };
    final rejected = await verifyFlowerSuggestions(api, response, {
      'flower': 'rose',
      'color': 'pink',
      'material': 'wax',
    }, 300000);
    expect(rejected['suggestions'], isEmpty);
    final accepted = await verifyFlowerSuggestions(api, response, {
      'flower': 'rose',
      'color': 'white',
      'material': 'wax',
    }, 300000);
    expect((accepted['suggestions'] as List).single['price'], 250000);
    final overBudget = await verifyFlowerSuggestions(api, response, {
      'flower': 'rose',
    }, 210000);
    expect(overBudget['suggestions'], isEmpty);
    api.dispose();
  });
  testWidgets('slot without maintenance session accepts HTTP 204', (
    tester,
  ) async {
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        if (r.url.path.endsWith('/active')) return http.Response('', 204);
        if (r.url.path.endsWith('/slots')) {
          return jsonResponse(
            jsonEncode([
              {
                'id': 's',
                'slotCode': 'S01',
                'zone': 'WALK_IN',
                'sensorEnabled': true,
                'status': 'RENTED_EMPTY',
              },
            ]),
            200,
          );
        }
        return jsonResponse('[]', 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlotDetail(
            api,
            seller(),
            {'id': 'k', 'name': 'Tủ hoa'},
            {'id': 's', 'slotCode': 'S01'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('FormatException'), findsNothing);
    expect(find.text('Ô S01'), findsWidgets);
    expect(tester.takeException(), isNull);
    api.dispose();
  });
}


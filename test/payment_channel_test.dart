import 'dart:convert';

import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/payment_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Session _seller() => Session.fromJson({
  'id': 'owner',
  'name': 'Shop Hoa',
  'role': 'SELLER',
  'sellerId': 'shop',
});

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets(
    'revenue shortcut opens transactions and loads settings only when selected',
    (tester) async {
      final paths = <String>[];
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          paths.add(r.url.path);
          if (r.url.path.endsWith('/reports/sales')) {
            return _json({
              'grossPaid': 120000,
              'totalRefunded': 20000,
              'netReceipts': 100000,
              'paidOrders': 3,
            });
          }
          if (r.url.path.endsWith('/payments')) {
            return _json({'payments': [], 'totalCount': 0});
          }
          if (r.url.path.endsWith('/bank')) return _json({'status': 'MISSING'});
          return _json({}, 404);
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        _host(PaymentChannelPage(api, _seller(), startWithTransactions: true)),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
            .selected,
        {1},
      );
      expect(find.text('120.000 đ'), findsOneWidget);
      expect(paths.any((p) => p.endsWith('/payments')), isTrue);
      expect(paths.any((p) => p.endsWith('/bank')), isFalse);
      await tester.tap(find.text('Kênh & tài khoản'));
      await tester.pumpAndSettle();
      expect(paths.any((p) => p.endsWith('/payment-channel')), isTrue);
      expect(paths.any((p) => p.endsWith('/bank')), isTrue);
      expect(find.text('Khai báo tài khoản'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('payment settings omit loyalty UI and requests', (tester) async {
    final paths = <String>[];
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/bank')) {
          return _json({'status': 'MISSING'});
        }
        return _json({}, 404);
      }),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(_host(PaymentChannelPage(api, _seller())));
    await tester.pumpAndSettle();
    expect(find.textContaining('tích điểm'), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(paths.any((path) => path.contains('loyalty')), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'missing PayOS channel shows unconfigured state without action buttons',
    (tester) async {
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((request) async {
          switch (request.url.path) {
            case '/api/sellers/shop/payment-channel':
              return _json({'message': 'Chưa cấu hình'}, 404);
            case '/api/sellers/shop/bank':
              return _json({
                'status': 'MISSING',
                'bankName': null,
                'holder': null,
                'accountSuffix': null,
              });
            case '/api/sellers/shop/loyalty-settings':
              return _json({
                'sellerId': 'shop',
                'enabled': false,
                'earnRatePercent': 1.0,
              });
            default:
              return _json({}, 404);
          }
        }),
      );

      await tester.pumpWidget(_host(PaymentChannelPage(api, _seller())));
      await tester.pumpAndSettle();

      expect(find.text('Chưa cấu hình'), findsOneWidget);
      expect(find.textContaining('Quản trị viên gắn cấu hình'), findsOneWidget);
      expect(find.text('Kiểm tra xác thực PayOS'), findsNothing);
      expect(find.text('Tạm dừng nhận thanh toán'), findsNothing);
      expect(find.text('Mở lại kênh thanh toán'), findsNothing);
      expect(find.text('Khai báo tài khoản'), findsOneWidget);
      expect(tester.takeException(), isNull);
      api.dispose();
    },
  );

  testWidgets(
    'seller declares shop refund bank via bottom sheet and Vietnam bank picker',
    (tester) async {
      Map<String, dynamic> bank = {
        'status': 'MISSING',
        'bankName': null,
        'holder': null,
        'accountSuffix': null,
      };
      Map<String, dynamic>? sentBank;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((request) async {
          switch (request.url.path) {
            case '/api/sellers/shop/payment-channel':
              return _json({}, 404);
            case '/api/sellers/shop/bank':
              return _json(bank);
            case '/api/sellers/shop/flows/set_seller_bank':
              sentBank = jsonDecode(request.body) as Map<String, dynamic>;
              bank = {
                'status': 'READY',
                'bankName': sentBank!['p_bank'],
                'holder': sentBank!['p_holder'],
                'accountSuffix': '6789',
              };
              return _json({'success': true});
            case '/api/sellers/shop/loyalty-settings':
              return _json({
                'sellerId': 'shop',
                'enabled': false,
                'earnRatePercent': 1.0,
              });
            default:
              return _json({}, 404);
          }
        }),
      );

      await tester.pumpWidget(_host(PaymentChannelPage(api, _seller())));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Khai báo tài khoản'));
      await tester.tap(find.text('Khai báo tài khoản'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextFormField, 'Tên ngân hàng *'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Tìm theo tên hoặc mã ngân hàng'),
        'vcb',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ngoại thương Việt Nam'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên chủ tài khoản *'),
        'nguyen van a',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Số tài khoản ngân hàng *'),
        '0123456789',
      );
      await tester.tap(find.text('Lưu tài khoản'));
      await tester.pumpAndSettle();

      expect(sentBank, {
        'p_bank': 'Ngoại thương Việt Nam',
        'p_holder': 'NGUYEN VAN A',
        'p_account_enc': '0123456789',
      });
      expect(find.text('Đã sẵn sàng'), findsOneWidget);
      expect(find.text('•••• •••• •••• 6789'), findsOneWidget);
      expect(find.text('Thay đổi tài khoản'), findsOneWidget);
      expect(tester.takeException(), isNull);
      api.dispose();
    },
  );

  testWidgets(
    'seller verifies pending PayOS channel and pauses then resumes active channel',
    (tester) async {
      Map<String, dynamic> channel = {
        'sellerId': 'shop',
        'version': 1,
        'state': 'PENDING_VERIFICATION',
        'expectedBankBin': '970436',
        'expectedBankAccountMasked': '******1234',
        'expectedBankName': 'SHOP HOA',
        'verifiedAt': null,
      };
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((request) async {
          switch (request.url.path) {
            case '/api/sellers/shop/payment-channel':
              return _json(channel);
            case '/api/sellers/shop/payment-channel/verify':
              channel = {
                ...channel,
                'state': 'ACTIVE',
                'verifiedAt': '2026-11-20T10:00:00Z',
              };
              return _json({
                'verified': true,
                'state': 'ACTIVE',
                'message': 'Kênh thanh toán đã được xác thực thành công.',
              });
            case '/api/sellers/shop/payment-channel/status':
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              channel = {...channel, 'state': body['status']};
              return _json(channel);
            case '/api/sellers/shop/bank':
              return _json({'status': 'READY', 'accountSuffix': '1234'});
            case '/api/sellers/shop/loyalty-settings':
              return _json({
                'sellerId': 'shop',
                'enabled': false,
                'earnRatePercent': 1.0,
              });
            default:
              return _json({}, 404);
          }
        }),
      );

      await tester.pumpWidget(_host(PaymentChannelPage(api, _seller())));
      await tester.pumpAndSettle();

      expect(find.text('Chờ xác thực'), findsOneWidget);
      await tester.ensureVisible(find.text('Kiểm tra xác thực PayOS'));
      await tester.tap(find.text('Kiểm tra xác thực PayOS'));
      await tester.pumpAndSettle();

      expect(find.text('Đã kích hoạt'), findsOneWidget);
      expect(find.text('Tạm dừng nhận thanh toán'), findsOneWidget);

      await tester.ensureVisible(find.text('Tạm dừng nhận thanh toán'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tạm dừng nhận thanh toán'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();

      expect(find.text('Tạm dừng'), findsOneWidget);
      expect(find.text('Mở lại kênh thanh toán'), findsOneWidget);

      await tester.ensureVisible(find.text('Mở lại kênh thanh toán'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mở lại kênh thanh toán'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();

      expect(find.text('Đã kích hoạt'), findsOneWidget);
      expect(tester.takeException(), isNull);
      api.dispose();
    },
  );

  testWidgets(
    'transactions tab shows metrics, reconciles PENDING payment, paginates, and filters',
    (tester) async {
      final paymentQueries = <String>[];
      var pendingReconciled = false;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((request) async {
          switch (request.url.path) {
            case '/api/sellers/shop/payment-channel':
              return _json({}, 404);
            case '/api/sellers/shop/bank':
              return _json({'status': 'READY', 'accountSuffix': '1234'});
            case '/api/sellers/shop/loyalty-settings':
              return _json({
                'sellerId': 'shop',
                'enabled': true,
                'earnRatePercent': 1.0,
              });
            case '/api/sellers/shop/reports/sales':
              return _json({
                'sellerId': 'shop',
                'grossPaid': pendingReconciled ? 1550000 : 1200000,
                'totalRefunded': 200000,
                'netReceipts': pendingReconciled ? 1350000 : 1000000,
                'paidOrders': pendingReconciled ? 5 : 4,
              });
            case '/api/sellers/shop/payments/pay-1/reconcile':
              pendingReconciled = true;
              return _json({
                'paymentId': 'pay-1',
                'previousStatus': 'PENDING',
                'currentStatus': 'SUCCEEDED',
                'providerStatus': 'PAID',
                'amount': 350000,
                'transitioned': true,
              });
            case '/api/sellers/shop/payments':
              final query = request.url.query;
              paymentQueries.add(query);
              final page =
                  int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
              final statusFilter = request.url.queryParameters['status'];
              if (page == 2) {
                return _json({
                  'payments': [
                    {
                      'id': 'pay-3',
                      'orderCode': 990,
                      'amount': 250000,
                      'status': 'SUCCEEDED',
                      'createdAt': '2026-11-19T08:00:00Z',
                      'receiverAccountMasked': '******1234',
                    },
                  ],
                  'totalCount': 12,
                  'page': 2,
                  'pageSize': 10,
                });
              }
              final all = [
                {
                  'id': 'pay-1',
                  'orderCode': 1001,
                  'amount': 350000,
                  'status': pendingReconciled ? 'SUCCEEDED' : 'PENDING',
                  'createdAt': '2026-11-20T09:00:00Z',
                  'receiverAccountMasked': '******1234',
                },
                {
                  'id': 'pay-2',
                  'orderCode': 1000,
                  'amount': 400000,
                  'status': 'SUCCEEDED',
                  'paidAt': '2026-11-20T08:00:00Z',
                  'createdAt': '2026-11-20T07:55:00Z',
                  'receiverAccountMasked': '******1234',
                },
              ];
              final filtered = statusFilter == null
                  ? all
                  : all.where((e) => e['status'] == statusFilter).toList();
              return _json({
                'payments': filtered,
                'totalCount': statusFilter == null ? 12 : filtered.length,
                'page': 1,
                'pageSize': 10,
              });
            default:
              return _json({}, 404);
          }
        }),
      );

      await tester.pumpWidget(_host(PaymentChannelPage(api, _seller())));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Giao dịch'));
      await tester.pumpAndSettle();

      expect(find.text('1.200.000 đ'), findsOneWidget);
      expect(find.text('200.000 đ'), findsOneWidget);
      expect(find.text('1.000.000 đ'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('Đơn #1001'), findsOneWidget);
      expect(find.text('Đối soát PayOS'), findsOneWidget);

      await tester.ensureVisible(find.text('Đối soát PayOS'));
      await tester.tap(find.text('Đối soát PayOS'));
      await tester.pumpAndSettle();

      expect(find.text('Đối soát PayOS'), findsNothing);
      expect(find.text('1.550.000 đ'), findsOneWidget);

      await tester.ensureVisible(find.text('Sau'));
      await tester.tap(find.text('Sau'));
      await tester.pumpAndSettle();

      expect(find.text('Trang 2'), findsOneWidget);
      expect(find.text('Đơn #990'), findsOneWidget);

      await tester.ensureVisible(find.byTooltip('Lọc trạng thái giao dịch'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Lọc trạng thái giao dịch'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'Chờ thanh toán'),
      );
      await tester.pumpAndSettle();

      expect(
        paymentQueries.last,
        allOf(contains('page=1'), contains('status=PENDING')),
      );
      expect(find.text('Chưa có giao dịch bán hoa phù hợp.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      api.dispose();
    },
  );
}

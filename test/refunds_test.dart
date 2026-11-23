import 'dart:async';
import 'dart:convert';

import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/refunds.dart';
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

Json detail({bool approved = true, bool bank = true, Json? submission}) => {
  'id': 'refund',
  'orderCode': 'FB-123',
  'amount': 200000,
  'status': 'PENDING',
  'isApproved': approved,
  'canAccessBank': approved && bank,
  'canSubmitTransfer':
      approved &&
      bank &&
      (submission == null || submission['status'] == 'REJECTED'),
  'submission': submission,
};

Future<void> showDetail(WidgetTester tester, ApiClient api) async {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(api.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SellerRefundDetail(api, seller, 'refund')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pending refund explains missing approval or customer bank', (
    tester,
  ) async {
    var current = detail(approved: false);
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        expect(r.method, 'GET');
        return json(current);
      }),
    );
    await showDetail(tester, api);
    expect(find.text('Chờ Admin duyệt khoản hoàn.'), findsOneWidget);
    expect(find.text('Xem tài khoản nhận hoàn'), findsNothing);
    current = detail(bank: false);
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(
      find.text('Khách chưa bổ sung tài khoản nhận hoàn trên biên nhận.'),
      findsOneWidget,
    );
    expect(find.text('Gửi chứng từ chuyển khoản'), findsNothing);
  });

  testWidgets(
    'rejected evidence shows reason and attempt count with resend form',
    (tester) async {
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient(
          (r) async => json(
            detail(
              submission: {
                'status': 'REJECTED',
                'attemptCount': 2,
                'providerReference': 'BANK-456',
                'reviewReason': 'Ảnh không rõ mã giao dịch',
              },
            ),
          ),
        ),
      );
      await showDetail(tester, api);
      expect(find.text('Bị từ chối'), findsOneWidget);
    expect(find.text('Chứng từ lần 2'), findsOneWidget);
      expect(
        find.text('Lý do từ chối: Ảnh không rõ mã giao dịch'),
        findsOneWidget,
      );
      expect(find.text('Gửi lại chứng từ'), findsOneWidget);
      expect(find.text('REJECTED'), findsNothing);
      final send = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Gửi chứng từ chuyển khoản'),
      );
      expect(send.onPressed, isNull);
    },
  );

  testWidgets('pending review prevents duplicate submission', (tester) async {
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient(
        (r) async => json(
          detail(
            submission: {
              'status': 'PENDING_REVIEW',
              'providerReference': 'BANK-456',
              'attemptCount': 1,
            },
          ),
        ),
      ),
    );
    await showDetail(tester, api);
    expect(find.text('Đã gửi chứng từ. Chờ Admin đối chiếu.'), findsOneWidget);
    expect(find.text('Xem tài khoản nhận hoàn'), findsNothing);
    expect(find.text('Gửi chứng từ chuyển khoản'), findsNothing);
  });

  testWidgets(
    'bank access posts audit reason and hides sensitive data after 60 seconds',
    (tester) async {
      var accesses = 0;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/bank-details')) {
            expect(r.method, 'POST');
            expect(jsonDecode(r.body), {'reason': 'Đối chiếu hoàn tiền'});
            accesses++;
            return json({
              'bankName': 'MB Bank',
              'holder': 'NGUYEN VAN A',
              'account': '123456789',
            });
          }
          return json(detail());
        }),
      );
      await showDetail(tester, api);
      await tester.enterText(
        find.widgetWithText(TextField, 'Đối chiếu tài khoản để hoàn tiền'),
        'Đối chiếu hoàn tiền',
      );
      await tester.tap(find.text('Xem tài khoản nhận hoàn'));
      await tester.pumpAndSettle();
      expect(accesses, 1);
      expect(find.text('123456789'), findsOneWidget);
      expect(find.text('NGUYEN VAN A'), findsOneWidget);
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(find.text('123456789'), findsNothing);
      expect(find.text('Xem tài khoản nhận hoàn'), findsOneWidget);
    },
  );

  testWidgets(
    'bank response after backgrounding does not reveal receiver details',
    (tester) async {
      final response = Completer<http.Response>();
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient(
          (r) async => r.url.path.endsWith('/bank-details')
              ? response.future
              : json(detail()),
        ),
      );
      await showDetail(tester, api);
      await tester.enterText(
        find.widgetWithText(TextField, 'Đối chiếu tài khoản để hoàn tiền'),
        'Đối chiếu hoàn tiền',
      );
      await tester.tap(find.text('Xem tài khoản nhận hoàn'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      response.complete(
        json({
          'bankName': 'MB Bank',
          'holder': 'NGUYEN VAN A',
          'account': '123456789',
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('123456789'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('transfer calendar only allows the last 30 days', (tester) async {
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async => json(detail())),
    );
    await showDetail(tester, api);
    await tester.ensureVisible(find.text('Chọn ngày và giờ'));
    await tester.tap(find.text('Chọn ngày và giờ'));
    await tester.pumpAndSettle();
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(
      picker.firstDate,
      DateUtils.dateOnly(DateTime.now().subtract(const Duration(days: 30))),
    );
    expect(picker.lastDate, DateUtils.dateOnly(DateTime.now()));
    expect(tester.takeException(), isNull);
  });
}

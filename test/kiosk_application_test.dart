import 'dart:convert';

import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/goong.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/kiosk_application.dart';
import 'package:florabot_mobile/ui/location_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
final seller = Session.fromJson({
  'id': 'owner',
  'name': 'Shop Hoa',
  'role': 'SELLER',
  'sellerId': 'shop',
});
final awaiting = <String, dynamic>{
  'id': 'app',
  'status': 'AWAITING_PAYMENT',
  'annualFee': 20000,
  'paymentId': 'payment',
  'canVoluntaryCancel': true,
  'installationAddress': '12 Nguyễn Trãi, Hà Nội',
  'walkInSlots': 1,
  'preorderSlots': 1,
};

http.Response setup(
  http.Request request, {
  bool bankReady = true,
  int version = 3,
}) {
  return switch (request.url.path) {
    '/api/kiosk-packages' => json({
      'configured': true,
      'annualSlotPrice': 10000,
      'version': version,
    }),
    '/api/sellers/shop/bank' => json({
      'status': bankReady ? 'READY' : 'MISSING',
      'bankName': 'MB Bank',
      'holder': 'NGUYEN VAN A',
      'accountSuffix': '1234',
    }),
    '/api/me/shop' => json({'shopName': 'Shop Hoa', 'status': 'ACTIVE'}),
    _ => json({'detail': 'Not found'}, 404),
  };
}

Future<void> host(
  WidgetTester tester,
  ApiClient api, {
  GoongPlacesClient? placesClient,
  Future<KioskLocation?> Function(BuildContext, KioskPoint?, String)?
  locationPicker,
}) async {
  tester.view.physicalSize = const Size(360, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(api.dispose);
  if (placesClient != null) addTearDown(placesClient.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: KioskApplicationPage(
          api,
          seller,
          placesClient: placesClient,
          locationPicker:
              locationPicker ??
              (_, _, _) async => (
                point: (latitude: 21.0285, longitude: 105.8542),
                address: null,
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> fillDraft(WidgetTester tester) async {
  final field = find.byType(TextFormField);
  await tester.ensureVisible(field);
  await tester.enterText(field, '12 Nguyễn Trãi, Hà Nội');
  final location = find.text('Chọn vị trí trên bản đồ');
  await tester.ensureVisible(location);
  await tester.tap(location);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byType(CheckboxListTile));
  await tester.tap(find.byType(CheckboxListTile));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'paid application cancellation sends a refund request after confirmation',
    (tester) async {
      Json? cancelledBody;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/current')) {
            return json({...awaiting, 'status': 'PAID_REVIEW'});
          }
          if (r.url.path.endsWith('/cancel')) {
            cancelledBody = jsonDecode(r.body) as Json;
            return json({
              ...awaiting,
              'status': 'REFUND_PENDING',
              'canVoluntaryCancel': false,
              'bankName': 'MB Bank',
              'bankHolder': 'NGUYEN VAN A',
              'bankAccountSuffix': '1234',
            });
          }
          return setup(r);
        }),
      );
      await host(tester, api);
      await tester.tap(find.text('Hủy hồ sơ'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'Không còn nhu cầu thuê',
      );
      await tester.tap(find.text('Tiếp tục'));
      await tester.pumpAndSettle();
      expect(cancelledBody, isNull);
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(cancelledBody, {'reason': 'Không còn nhu cầu thuê'});
      expect(find.text('Chờ hoàn tiền'), findsOneWidget);
      expect(find.text('Gửi hồ sơ thuê kiosk'), findsNothing);
      expect(find.text('Hủy hồ sơ'), findsNothing);
    },
  );

  testWidgets(
    'native application submits exact slot demand, coordinates and pricing version',
    (tester) async {
      Json? body;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          if (r.method == 'POST') {
            expect(r.url.path, '/api/me/kiosk-applications');
            body = jsonDecode(r.body) as Json;
            return json(awaiting, 201);
          }
          return setup(r);
        }),
      );
      await host(tester, api);
      await tester.tap(find.byTooltip('Tăng Ô đặt trước'));
      await fillDraft(tester);
      await tester.ensureVisible(find.text('Gửi hồ sơ thuê kiosk'));
      await tester.tap(find.text('Gửi hồ sơ thuê kiosk'));
      await tester.pumpAndSettle();
      expect(body, {
        'installationAddress': '12 Nguyễn Trãi, Hà Nội',
        'latitude': 21.0285,
        'longitude': 105.8542,
        'walkInSlots': 1,
        'preorderSlots': 1,
        'pricingVersion': 3,
      });
      expect(find.text('Thanh toán phí thuê'), findsOneWidget);
      expect(find.text('Gửi hồ sơ thuê kiosk'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pricing change invalidates accepted total before creating application',
    (tester) async {
      var prices = 0;
      var posts = 0;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          if (r.method == 'POST') posts++;
          if (r.url.path == '/api/kiosk-packages') {
            return setup(r, version: ++prices == 1 ? 3 : 4);
          }
          return setup(r);
        }),
      );
      await host(tester, api);
      await fillDraft(tester);
      await tester.ensureVisible(find.text('Gửi hồ sơ thuê kiosk'));
      await tester.tap(find.text('Gửi hồ sơ thuê kiosk'));
      await tester.pumpAndSettle();
      expect(posts, 0);
      expect(
        find.text('Bảng giá đã thay đổi. Kiểm tra tổng phí và xác nhận lại.'),
        findsOneWidget,
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
    },
  );

  testWidgets('editing address invalidates its previous pin', (tester) async {
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async => setup(r)),
    );
    await host(tester, api);
    await fillDraft(tester);
    await tester.ensureVisible(find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'Địa chỉ khác');
    await tester.pumpAndSettle();
    expect(find.text('Chọn vị trí trên bản đồ'), findsOneWidget);
    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Gửi hồ sơ thuê kiosk'),
    );
    expect(submit.onPressed, isNull);
  });

  testWidgets('missing refund bank prevents creation', (tester) async {
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async => setup(r, bankReady: false)),
    );
    await host(tester, api);
    expect(find.text('Cập nhật ngân hàng shop'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Gửi hồ sơ thuê kiosk'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'existing pending application resumes native payment and reconciles on server',
    (tester) async {
      final posts = <String>[];
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/current')) return json(awaiting);
          if (r.method == 'POST') {
            posts.add(r.url.path);
            return json({...awaiting, 'status': 'PAID_REVIEW'});
          }
          return setup(r);
        }),
      );
      await host(tester, api);
      expect(find.text('Gửi hồ sơ thuê kiosk'), findsNothing);
      await tester.tap(find.text('Kiểm tra thanh toán'));
      await tester.pumpAndSettle();
      expect(posts, ['/api/member/kiosk-applications/app/reconcile']);
      expect(find.text('Chờ duyệt'), findsOneWidget);
      expect(find.text('Thanh toán phí thuê'), findsNothing);
    },
  );

  testWidgets('checkout does not accept a URL outside PayOS', (tester) async {
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        if (r.url.path.endsWith('/current')) return json(awaiting);
        if (r.url.path.endsWith('/payment-link')) {
          return json({'checkoutUrl': 'https://example.test/checkout'});
        }
        return setup(r);
      }),
    );
    await host(tester, api);
    await tester.tap(find.text('Thanh toán phí thuê'));
    await tester.pumpAndSettle();
    expect(
      find.text('Liên kết thanh toán PayOS không hợp lệ.'),
      findsOneWidget,
    );
    expect(find.text('Chờ thanh toán'), findsOneWidget);
  });

  testWidgets(
    'inline Goong suggestion search pins coordinates automatically and submits',
    (tester) async {
      Json? submittedBody;
      var pickerOpened = false;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          if (r.method == 'POST' &&
              r.url.path == '/api/me/kiosk-applications') {
            submittedBody = jsonDecode(r.body) as Json;
            return json(awaiting, 201);
          }
          return setup(r);
        }),
      );
      final places = GoongPlacesClient(
        'rest-test',
        transport: MockClient((r) async {
          if (r.url.path == '/Place/AutoComplete') {
            expect(r.url.queryParameters['input'], 'fpt');
            return json({
              'status': 'OK',
              'predictions': [
                {
                  'place_id': 'place-fpt',
                  'description': 'Đại học FPT, Hòa Lạc, Hà Nội',
                  'structured_formatting': {
                    'main_text': 'Đại học FPT',
                    'secondary_text': 'Khu Công nghệ cao Hòa Lạc, Hà Nội',
                  },
                },
              ],
            });
          }
          if (r.url.path == '/Place/Detail') {
            expect(r.url.queryParameters['place_id'], 'place-fpt');
            return json({
              'status': 'OK',
              'result': {
                'formatted_address': 'Đại học FPT, Hòa Lạc, Hà Nội',
                'geometry': {
                  'location': {'lat': 21.0124, 'lng': 105.5253},
                },
              },
            });
          }
          return json({'status': 'ZERO_RESULTS'});
        }),
      );

      await host(
        tester,
        api,
        placesClient: places,
        locationPicker: (_, _, _) async {
          pickerOpened = true;
          return null;
        },
      );

      await tester.ensureVisible(find.byType(TextFormField));
      await tester.enterText(find.byType(TextFormField), 'fpt');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('Đại học FPT'), findsOneWidget);
      expect(
        find.text('Khu Công nghệ cao Hòa Lạc, Hà Nội'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Đại học FPT'));
      await tester.tap(find.text('Đại học FPT'));
      await tester.pumpAndSettle();

      expect(pickerOpened, isFalse);
      expect(find.text('Đại học FPT, Hòa Lạc, Hà Nội'), findsOneWidget);
      expect(
        find.text('Đã ghim vị trí tự động từ địa chỉ gợi ý'),
        findsOneWidget,
      );
      expect(find.text('Đã ghim vị trí · Chọn lại'), findsOneWidget);

      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Gửi hồ sơ thuê kiosk'));
      await tester.tap(find.text('Gửi hồ sơ thuê kiosk'));
      await tester.pumpAndSettle();

      expect(submittedBody, {
        'installationAddress': 'Đại học FPT, Hòa Lạc, Hà Nội',
        'latitude': 21.0124,
        'longitude': 105.5253,
        'walkInSlots': 1,
        'preorderSlots': 0,
        'pricingVersion': 3,
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty Goong search offers manual map picker fallback',
    (tester) async {
      var pickerOpened = false;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async => setup(r)),
      );
      final places = GoongPlacesClient(
        'rest-test',
        transport: MockClient((r) async => json({'status': 'ZERO_RESULTS'})),
      );

      await host(
        tester,
        api,
        placesClient: places,
        locationPicker: (_, _, _) async {
          pickerOpened = true;
          return (
            point: (latitude: 10.7769, longitude: 106.7009),
            address: null,
          );
        },
      );

      await tester.ensureVisible(find.byType(TextFormField));
      await tester.enterText(find.byType(TextFormField), 'khong co ket qua');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Không tìm thấy địa chỉ phù hợp'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Ghim thủ công trên bản đồ'));
      await tester.tap(find.text('Ghim thủ công trên bản đồ'));
      await tester.pumpAndSettle();

      expect(pickerOpened, isTrue);
      expect(find.text('Đã ghim vị trí · Chọn lại'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing address after selecting Goong suggestion clears automatic pin',
    (tester) async {
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async => setup(r)),
      );
      final places = GoongPlacesClient(
        'rest-test',
        transport: MockClient((r) async {
          if (r.url.path == '/Place/AutoComplete') {
            return json({
              'status': 'OK',
              'predictions': [
                {
                  'place_id': 'p1',
                  'description': 'Chợ Bến Thành, Quận 1, TP.HCM',
                },
              ],
            });
          }
          if (r.url.path == '/Place/Detail') {
            return json({
              'status': 'OK',
              'result': {
                'formatted_address': 'Chợ Bến Thành, Quận 1, TP.HCM',
                'geometry': {
                  'location': {'lat': 10.7725, 'lng': 106.6980},
                },
              },
            });
          }
          return json({'status': 'ZERO_RESULTS'});
        }),
      );

      await host(tester, api, placesClient: places);
      await tester.ensureVisible(find.byType(TextFormField));
      await tester.enterText(find.byType(TextFormField), 'ben thanh');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Chợ Bến Thành, Quận 1, TP.HCM'));
      await tester.tap(find.text('Chợ Bến Thành, Quận 1, TP.HCM'));
      await tester.pumpAndSettle();
      expect(find.text('Đã ghim vị trí · Chọn lại'), findsOneWidget);

      await tester.ensureVisible(find.byType(TextFormField));
      await tester.enterText(find.byType(TextFormField), 'Dia chi moi');
      await tester.pumpAndSettle();

      expect(find.text('Chọn vị trí trên bản đồ'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Gửi hồ sơ thuê kiosk'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

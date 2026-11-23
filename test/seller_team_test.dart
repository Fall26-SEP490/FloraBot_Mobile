import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/seller_staff.dart';
import 'package:florabot_mobile/features/seller_tasks.dart';

void main() {
  final seller = Session.fromJson({
    'id': 'owner',
    'name': 'Shop',
    'role': 'SELLER',
    'sellerId': 'shop',
  });
  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  final staff = {
    'id': 'staff',
    'fullName': 'Nhân viên A',
    'email': 'staff@example.test',
    'phone': '0901234567',
    'status': 'ACTIVE',
  };
  final task = {
    'id': 'task',
    'kioskId': 'k',
    'kioskName': 'Kiosk 12',
    'address': 'Hà Nội',
    'kind': 'DELIVERY',
    'workType': 'FLOWER_QUALITY',
    'complaintId': 'c',
    'status': 'SUBMITTED',
    'version': 8,
    'assigneeId': 'staff',
    'assigneeName': 'Nhân viên A',
    'instructions': 'Kiểm tra chất lượng hoa',
    'report': 'Đã kiểm tra hoa',
  };

  test('quality reports must be reviewed through complaint workflow', () {
    expect(sellerTaskTransitions(task), isEmpty);
    expect(sellerTaskTransitions({...task, 'workType': null}), {
      'COMPLETED',
      'IN_PROGRESS',
      'CANCELLED',
    });
    expect(sellerTaskTransitions({...task, 'status': 'IN_PROGRESS'}), {
      'CANCELLED',
    });
    expect(sellerTaskTransitions({...task, 'status': 'COMPLETED'}), isEmpty);
  });

  testWidgets('staff temporary lock uses LOCKED rather than DISABLED', (
    tester,
  ) async {
    Json? payload;
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((request) async {
        if (request.method == 'PATCH') {
          payload = objectOf(jsonDecode(request.body));
          return json({...staff, 'status': 'LOCKED'});
        }
        return request.url.path.endsWith('/accounts')
            ? json([staff])
            : json(staff);
      }),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: StaffManagementPage(api, seller))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nhân viên shop'), findsNothing);
    await tester.tap(find.text('Nhân viên A'));
    await tester.pumpAndSettle();
    final lock = find.widgetWithText(OutlinedButton, 'Tạm khóa tài khoản');
    await tester.ensureVisible(lock);
    await tester.tap(lock);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(payload, {'status': 'LOCKED'});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'new staff form supports backend six-character initial password',
    (tester) async {
      Json? payload;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((request) async {
          if (request.method == 'POST') {
            payload = objectOf(jsonDecode(request.body));
            return json(staff, 201);
          }
          return json([]);
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: StaffManagementPage(api, seller))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Thêm nhân viên'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      // Use keyboard types to locate email/phone independently of layout order.
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        final controller = field.controller;
        if (controller == null) continue;
        if (field.obscureText) {
          controller.text = 'abc123';
        } else if (field.keyboardType == TextInputType.emailAddress) {
          controller.text = 'new@example.test';
        } else if (field.keyboardType == TextInputType.phone) {
          controller.text = '0901234567';
        } else {
          controller.text = 'Nhân viên mới';
        }
      }
      final submit = find.widgetWithText(FilledButton, 'Tạo tài khoản');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(payload?['password'], 'abc123');
      expect(payload?['email'], 'new@example.test');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'seller delivery creation reuses idempotency key after uncertain response',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final keys = <String?>[];
      Json? payload;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/staff-delivery-scopes')) {
            return json([
              {'kioskId': 'k', 'kioskName': 'Kiosk 12', 'address': 'Hà Nội'},
            ]);
          }
          if (request.url.path.endsWith('/staff')) {
            return json([
              {'id': 'staff', 'name': 'Nhân viên A'},
            ]);
          }
          if (request.method == 'POST') {
            expect(request.url.path, '/api/me/staff-tasks');
            keys.add(request.headers['Idempotency-Key']);
            payload = objectOf(jsonDecode(request.body));
            return keys.length == 1 ? json({}, 503) : json({'id': 'task'}, 201);
          }
          return json({'items': [], 'page': 1, 'hasMore': false});
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SellerTasksPage(api, seller))),
      );
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.byTooltip('Giao việc mới'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        if (attempt == 0) {
          final selectors = find.byType(DropdownButtonFormField<String>);
          await tester.tap(selectors.at(0));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.text('Nhân viên A').last);
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(selectors.at(1));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.text('Kiosk 12 · Hà Nội').last);
          await tester.pump(const Duration(milliseconds: 400));
          await tester.enterText(
            find.byType(TextFormField),
            'Giao hoa và kiểm tra tại tủ',
          );
          FocusManager.instance.primaryFocus?.unfocus();
        }
        final submit = find.widgetWithText(FilledButton, 'Giao công việc');
        await tester.ensureVisible(submit);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(submit);
        await tester.pumpAndSettle();
      }
      expect(payload, {
        'assigneeId': 'staff',
        'kioskId': 'k',
        'instructions': 'Giao hoa và kiểm tra tại tủ',
      });
      expect(keys.length, 2);
      expect(keys.first, isNotNull);
      expect(keys.first, keys.last);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'seller quality task links to complaint review without generic approval',
    (tester) async {
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient(
          (request) async => request.url.path.endsWith('/task')
              ? json({
                  'version': 8,
                  'status': 'SUBMITTED',
                  'kioskStatus': 'OFFLINE',
                  'history': [],
                  'hasMore': false,
                })
              : json({
                  'items': [task],
                  'hasMore': false,
                }),
        ),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(home: SellerTaskDetailPage(api, seller, task)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Duyệt / trả báo cáo'), findsOneWidget);
      expect(find.text('Duyệt hoàn tất'), findsNothing);
      expect(find.text('Hủy công việc'), findsNothing);
      expect(find.text('Ảnh minh chứng'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'stale task versions disable transition instead of submitting old metadata',
    (tester) async {
      final delivery = {...task, 'workType': null};
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient(
          (request) async => request.url.path.endsWith('/task')
              ? json({
                  'version': 9,
                  'status': 'SUBMITTED',
                  'kioskStatus': 'OFFLINE',
                  'history': [],
                })
              : json({
                  'items': [delivery],
                  'hasMore': false,
                }),
        ),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(home: SellerTaskDetailPage(api, seller, delivery)),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Duyệt hoàn tất'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Tải lại công việc'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

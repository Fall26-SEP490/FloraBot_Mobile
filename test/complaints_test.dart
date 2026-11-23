import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/complaints.dart';

void main() {
  final seller = Session.fromJson({
    'id': 'owner',
    'name': 'Shop',
    'role': 'SELLER',
    'sellerId': 'shop',
  });
  Json complaint({
    String handling = 'REPORTED',
    String status = 'OPEN',
    Json? task,
    Json? replacement,
  }) => {
    'id': 'c',
    'orderCode': 'FB01',
    'kioskId': 'k',
    'status': status,
    'handlingState': handling,
    'version': 7,
    'reason': 'Hoa cần kiểm tra chất lượng',
    'createdAt': '2026-11-23T04:00:00Z',
    if (handling != 'REPORTED') 'acceptedAt': '2026-11-23T04:10:00Z',
    'items': [
      {'orderItemId': 'oi', 'name': 'Hoa hồng', 'slotCode': 'S03'},
    ],
    'task': task,
    'replacement': replacement,
    'evidence': {'page': 1, 'hasMore': false, 'items': []},
  };
  http.Response json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  test(
    'quality actions follow handling state, task and replacement lifecycle',
    () {
      expect(complaintActions(complaint()), {'accept'});
      expect(complaintActions(complaint(handling: 'ACCEPTED')), {'assignment'});
      expect(
        complaintActions(
          complaint(handling: 'IN_PROGRESS', task: {'status': 'ASSIGNED'}),
        ),
        {'replacement-plan'},
      );
      expect(
        complaintActions(
          complaint(handling: 'REVIEW_REQUIRED', task: {'status': 'SUBMITTED'}),
        ),
        {'review'},
      );
      expect(
        complaintActions(
          complaint(
            handling: 'REVIEW_REQUIRED',
            task: {'status': 'SUBMITTED'},
            replacement: {'state': 'LOADED'},
          ),
        ),
        {'review', 'replacement/cancel'},
      );
      expect(
        complaintActions(
          complaint(
            handling: 'RESOLVED',
            status: 'CLOSED',
            task: {'status': 'COMPLETED'},
          ),
        ),
        isEmpty,
      );
      expect(complaintActions(complaint(handling: 'REFUND_REVIEW')), isEmpty);
    },
  );

  testWidgets('complaint list searches and server filter uses handling state', (
    tester,
  ) async {
    final requests = <Uri>[];
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async {
        requests.add(r.url);
        return json({
          'items': [complaint()],
          'page': 1,
          'hasMore': false,
        });
      }),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ComplaintsPage(api, seller))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chờ tiếp nhận'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'không khớp');
    await tester.pumpAndSettle();
    expect(find.text('Không có phản ánh phù hợp.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.byTooltip('Lọc phản ánh'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('Chờ duyệt báo cáo'),
        matching: find.byWidgetPredicate(
          (w) => w is CheckedPopupMenuItem<String>,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['state'], 'REVIEW_REQUIRED');
    expect(requests.last.queryParameters['page'], '1');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('assignment sends directory user ID and complaint version', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Json? payload;
    final data = complaint(handling: 'ACCEPTED');
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((request) async {
        if (request.url.path.endsWith('/staff')) {
          return json([
            {'id': 'staff-a', 'name': 'Nhân viên A'},
          ]);
        }
        if (request.method == 'POST') {
          expect(request.url.path, '/api/me/complaints/c/assignment');
          payload = objectOf(jsonDecode(request.body));
          return json({});
        }
        return json(data);
      }),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ComplaintDetail(api, seller, 'c'))),
    );
    await tester.pumpAndSettle();
    final assign = find.widgetWithText(
      OutlinedButton,
      'Giao nhân viên kiểm tra',
    );
    await tester.ensureVisible(assign);
    await tester.tap(assign);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    final selectors = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(selectors.at(0));
    await tester.tap(selectors.at(0));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Nhân viên A').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(selectors.at(1));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Hoa hồng').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
      find.byType(TextFormField),
      'Kiểm tra chất lượng hoa tại tủ',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    final submit = find.widgetWithText(FilledButton, 'Giao việc');
    await tester.ensureVisible(submit);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(payload?['assigneeId'], 'staff-a');
    expect(payload?['orderItemId'], 'oi');
    expect(payload?['version'], 7);
    expect(payload?['taskId'], matches(RegExp(r'^[a-f0-9-]{36}$')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'replacement plan includes ready preorder slots and excludes unsafe choices',
    (tester) async {
      final data = complaint(
        handling: 'IN_PROGRESS',
        task: {
          'id': 't',
          'version': 3,
          'status': 'IN_PROGRESS',
          'instructions': 'Kiểm tra hoa tại tủ',
        },
      );
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((r) async {
          if (r.url.path == '/api/me/products') {
            return json([
              {
                'id': 'ok',
                'name': 'Hoa còn tồn',
                'quantity': 2,
                'status': 'ACTIVE',
              },
              {
                'id': 'no',
                'name': 'Hoa hết tồn',
                'quantity': 0,
                'status': 'ACTIVE',
              },
            ]);
          }
          if (r.url.path.endsWith('/slots')) {
            return json([
              for (final entry in [
                ('pre', 'S03', 'k', true),
                ('not-ready', 'S04', 'k', false),
                ('other', 'S05', 'other', true),
              ])
                {
                  'id': entry.$1,
                  'slotCode': entry.$2,
                  'kioskId': entry.$3,
                  'sensorReady': entry.$4,
                  'zone': 'PREORDER',
                  'status': 'RENTED_EMPTY',
                  'bouquetId': null,
                },
            ]);
          }
          return json(data);
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ComplaintDetail(api, seller, 'c'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Duyệt báo cáo'), findsNothing);
      final plan = find.widgetWithText(OutlinedButton, 'Chọn hoa thay và ô tủ');
      await tester.ensureVisible(plan);
      await tester.tap(plan);
      await tester.pump(const Duration(milliseconds: 400));
      final selectors = tester
          .widgetList<DropdownButton<String>>(
            find.byType(DropdownButton<String>),
          )
          .toList();
      expect(selectors.length, 2);
      expect(selectors[0].items!.map((i) => i.value), ['ok']);
      expect(selectors[1].items!.map((i) => i.value), ['pre']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('review options prevent releasing replacement before loading', (
    tester,
  ) async {
    final data = complaint(
      handling: 'REVIEW_REQUIRED',
      task: {
        'id': 't',
        'version': 3,
        'status': 'SUBMITTED',
        'instructions': 'Kiểm tra hoa',
        'report': 'Đã kiểm tra',
      },
      replacement: {'state': 'PLANNED', 'slotCode': 'S03'},
    );
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((r) async => json(data)),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ComplaintDetail(api, seller, 'c'))),
    );
    await tester.pumpAndSettle();
    final review = find.widgetWithText(FilledButton, 'Duyệt báo cáo');
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pump(const Duration(milliseconds: 400));
    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(dropdown.items!.map((i) => i.value), ['RETURN']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

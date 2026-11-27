import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/tasks.dart';
import 'package:florabot_mobile/features/preorder_quote.dart';
import 'package:florabot_mobile/ui/common.dart';

http.Response json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
final technician = Session.fromJson({
  'id': 'tech',
  'name': 'Kỹ thuật',
  'role': 'TECHNICIAN',
});
Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  test('quote follows backend price and pickup boundaries', () {
    final now = DateTime.utc(2026, 11, 27, 8);
    for (final amount in ['abc', '0', '999', '100000001']) {
      expect(quotePriceError(amount), isNotNull);
    }
    for (final amount in ['1000', '100000000']) {
      expect(quotePriceError(amount), isNull);
    }
    expect(quotePickupError(null, now: now), isNotNull);
    expect(
      quotePickupError(now.add(const Duration(minutes: 59)), now: now),
      isNotNull,
    );
    expect(
      quotePickupError(now.add(const Duration(hours: 1)), now: now),
      isNull,
    );
    expect(
      quotePickupError(now.add(const Duration(days: 30)), now: now),
      isNull,
    );
    expect(
      quotePickupError(now.add(const Duration(days: 30, seconds: 1)), now: now),
      isNotNull,
    );
  });

  for (final kind in ['KIOSK_REMOVAL', 'INCIDENT']) {
    testWidgets('$kind submits to its own backend workflow', (tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? postedPath;
      Json? posted;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((request) async {
          if (request.method == 'POST') {
            postedPath = request.url.path;
            posted = objectOf(jsonDecode(request.body));
            return json({'version': 8});
          }
          if (request.url.path.endsWith('/repair-readiness')) {
            return json({'code': null, 'pendingCommandIds': []});
          }
          expect(request.url.path, '/api/staff/tasks/task');
          return json({
            'version': 7,
            'status': 'IN_PROGRESS',
            'history': [],
            'kioskStatus': 'ONLINE',
            if (kind == 'INCIDENT') 'slotCode': 'S01',
          });
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        host(
          TaskDetailPage(api, technician, {
            'id': 'task',
            'kind': kind,
            'kioskName': 'Kiosk 12',
            'version': 1,
            'status': 'IN_PROGRESS',
            'instructions': 'Kiểm tra tại tủ',
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Lấy OTP sửa ô'),
        kind == 'INCIDENT' ? findsOneWidget : findsNothing,
      );
      await tester.ensureVisible(find.text('Gửi báo cáo để duyệt'));
      await tester.tap(find.text('Gửi báo cáo để duyệt'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
        find.byType(TextFormField),
        'Đã kiểm tra và hoàn tất công việc',
      );
      await tester.ensureVisible(find.text('Xác nhận'));
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(
        postedPath,
        '/api/staff/tasks/task/${kind == 'INCIDENT' ? 'resolve-incident' : 'transition'}',
      );
      expect(posted?['version'], 7);
      if (kind == 'KIOSK_REMOVAL') expect(posted?['status'], 'SUBMITTED');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('task search and kiosk selection include later API pages', (
    tester,
  ) async {
    final pages = <String>[];
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((request) async {
        final page = request.url.queryParameters['page'];
        pages.add(page!);
        return json({
          'hasMore': page == '1',
          'items': page == '1'
              ? [
                  for (var i = 0; i < 25; i++)
                    {
                      'id': 'task-$i',
                      'kioskId': '12',
                      'kioskName': 'Kiosk HCM 12',
                      'kind': 'INCIDENT',
                      'status': 'ASSIGNED',
                      'instructions': 'Kiểm tra khóa',
                    },
                ]
              : [
                  {
                    'id': 'last',
                    'kioskId': '14',
                    'kioskName': 'Kiosk HCM 14',
                    'kind': 'KIOSK_REMOVAL',
                    'status': 'IN_PROGRESS',
                    'instructions': 'Công việc cuối cùng',
                  },
                ],
        });
      }),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(host(TasksPage(api, technician)));
    await tester.pumpAndSettle();
    expect(pages, ['1', '2']);
    expect(find.byType(RecordCard), findsNWidgets(10));
    await tester.enterText(find.byType(TextField), 'cong viec cuoi');
    await tester.pumpAndSettle();
    expect(find.byType(RecordCard), findsOneWidget);
    expect(find.textContaining('Tháo dỡ kiosk'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kiosk HCM 14').last);
    await tester.pumpAndSettle();
    expect(find.byType(RecordCard), findsOneWidget);
    expect(pages, ['1', '2']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'slow background refresh is single flight and keeps draft on failure',
    (tester) async {
      final key = GlobalKey<ResourceViewState>();
      final slow = Completer<String>();
      var reads = 0;
      await tester.pumpWidget(
        host(
          ResourceView(
            key: key,
            load: () {
              reads++;
              return reads == 1 ? Future.value('ready') : slow.future;
            },
            builder: (_, data, _) =>
                Column(children: [Text('$data'), const TextField()]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Giữ nội dung đang nhập');
      final first = key.currentState!.reload(background: true);
      final second = key.currentState!.reload(background: true);
      await tester.pump(const Duration(seconds: 8));
      expect(reads, 2);
      expect(find.text('ready'), findsOneWidget);
      expect(find.text('Giữ nội dung đang nhập'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      slow.completeError(const ApiError(503, 'Tạm mất kết nối'));
      await Future.wait([first, second]);
      await tester.pumpAndSettle();
      expect(find.text('ready'), findsOneWidget);
      expect(find.text('Giữ nội dung đang nhập'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('initial read cannot overlap a refresh', (tester) async {
    final key = GlobalKey<ResourceViewState>();
    final slow = Completer<String>();
    var reads = 0;
    await tester.pumpWidget(
      host(
        ResourceView(
          key: key,
          load: () {
            reads++;
            return slow.future;
          },
          builder: (_, data, _) => Text('$data'),
        ),
      ),
    );
    final refresh = key.currentState!.reload(background: true);
    slow.complete('loaded');
    await refresh;
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.text('loaded'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

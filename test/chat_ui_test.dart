import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/core/models.dart';
import 'package:florabot_mobile/features/chat.dart';

void main() {
  final seller = Session.fromJson({
    'id': 'owner-1',
    'name': 'Shop Hoa Của Tâm',
    'role': 'SELLER',
    'sellerId': 'shop-1',
  });

  testWidgets('staff directory opens the tapped employee without a picker', (
    tester,
  ) async {
    final opened = <String>[];
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((request) async {
        Object result = {'items': [], 'hasMore': false};
        if (request.url.path == '/api/sellers/shop-1/staff') {
          result = [
            {'id': 'staff-a', 'name': 'Nhân viên A'},
            {'id': 'staff-b', 'name': 'Nhân viên B'},
          ];
        } else if (request.url.path.endsWith('/chat/open')) {
          opened.add(request.url.path);
          expect(request.method, 'POST');
          result = {'id': 'chat-b', 'otherPartyName': 'Nhân viên B'};
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ChatsPage(api, seller))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhân viên'));
    await tester.pumpAndSettle();
    expect(find.text('Nhân viên A'), findsOneWidget);
    expect(find.text('Nhân viên B'), findsOneWidget);
    expect(find.text('Nhắn nhân viên'), findsNothing);
    expect(opened, isEmpty);
    await tester.tap(find.text('Nhân viên B'));
    await tester.pumpAndSettle();
    expect(opened, ['/api/sellers/shop-1/staff/staff-b/chat/open']);
    expect(find.byType(ChatThread), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final scenario in ['unchanged', 'new-draft', 'failed']) {
    testWidgets('sending chat preserves composer correctly: $scenario', (
      tester,
    ) async {
      final pending = Completer<http.Response>();
      Json? sent;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/messages') &&
              request.method == 'POST') {
            sent = objectOf(jsonDecode(request.body));
            return pending.future;
          }
          return http.Response(
            jsonEncode({'items': [], 'hasMore': false}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ChatThread(api, 'chat', false, 'Khách')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Tin đang gửi');
      await tester.tap(find.byTooltip('Gửi tin nhắn'));
      await tester.pump();
      if (scenario == 'new-draft') {
        await tester.enterText(find.byType(TextField), 'Bản nháp tiếp theo');
      }
      pending.complete(
        http.Response(
          '{}',
          scenario == 'failed' ? 503 : 200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await tester.pumpAndSettle();
      expect(sent, {'content': 'Tin đang gửi'});
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        scenario == 'new-draft'
            ? 'Bản nháp tiếp theo'
            : scenario == 'failed'
            ? 'Tin đang gửi'
            : '',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('empty later chat page retains navigation back', (tester) async {
    final pages = <String?>[];
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((request) async {
        final first = request.url.queryParameters['page'] == '1';
        if (request.url.path.endsWith('/chats')) {
          pages.add(request.url.queryParameters['page']);
        }
        return http.Response(
          jsonEncode({
            'items': first
                ? [
                    {'id': 'c', 'otherPartyName': 'Khách kiểm thử'},
                  ]
                : [],
            'hasMore': first,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ChatsPage(api, seller))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trang sau'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có cuộc trò chuyện nào.'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Trang trước'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Trang trước'));
    await tester.pumpAndSettle();
    expect(find.text('Khách kiểm thử'), findsOneWidget);
    expect(pages, ['1', '2', '1']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ChatsPage opens AI chat and queries /api/shop/flower-chat', (
    tester,
  ) async {
    Json? aiRequest;
    final api = ApiClient(
      Uri.parse('https://example.test'),
      transport: MockClient((request) async {
        if (request.url.path == '/api/sellers/shop-1/chats') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'chat-1',
                  'otherPartyName': 'Vo Chi Tam',
                  'lastMessage': 'Mình kiểm tra lại lịch nhận nhé.',
                  'unreadCount': 2,
                },
              ],
              'hasMore': false,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path == '/api/shop/flower-chat') {
          aiRequest = objectOf(jsonDecode(request.body));
          return http.Response(
            jsonEncode({
              'intent': 'FLOWERS',
              'message': 'Bạn nên ghi rõ loại hoa, màu sắc và dịp tặng.',
              'suggestions': [],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          jsonEncode({'items': [], 'hasMore': false}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Tin nhắn')),
          body: ChatsPage(api, seller),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trợ lý AI FloraBot'), findsOneWidget);
    expect(find.text('Vo Chi Tam'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Trang trước'), findsNothing);

    await tester.tap(find.text('Trợ lý AI FloraBot'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Viết mô tả & gắn tag'));
    await tester.pumpAndSettle();

    expect(
      aiRequest?['question'],
      'Tôi nên viết mô tả và gắn tag cho bó hoa như thế nào?',
    );
    expect(
      find.text('Bạn nên ghi rõ loại hoa, màu sắc và dịp tặng.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'ChatThread pins composer at bottom while scrolling messages and sends text',
    (tester) async {
      tester.view.physicalSize = const Size(400, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final messages = <Json>[
        for (var i = 1; i <= 15; i++)
          {
            'id': 'm$i',
            'senderName': i.isEven ? 'Shop Hoa Của Tâm' : 'Vo Chi Tam',
            'isMine': i.isEven,
            'content': 'Tin nhắn thử nghiệm số $i',
            'createdAt': '2026-11-23T10:${i.toString().padLeft(2, '0')}:00Z',
          },
      ];
      Json? posted;
      final api = ApiClient(
        Uri.parse('https://example.test'),
        transport: MockClient((request) async {
          if (request.url.path == '/api/chats/chat-1/messages' &&
              request.method == 'GET') {
            return http.Response(
              jsonEncode({'items': messages, 'hasMore': false}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.url.path == '/api/chats/chat-1/messages' &&
              request.method == 'POST') {
            posted = objectOf(jsonDecode(request.body));
            messages.add({
              'id': 'm16',
              'senderName': 'Shop Hoa Của Tâm',
              'isMine': true,
              'content': posted!['content'],
              'createdAt': '2026-11-23T10:30:00Z',
            });
            return http.Response(
              jsonEncode({'ok': true}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.url.path == '/api/chats/chat-1/read') {
            return http.Response(jsonEncode({'ok': true}), 200);
          }
          return http.Response(jsonEncode({'items': []}), 200);
        }),
      );
      addTearDown(api.dispose);

      await tester.pumpWidget(
        MaterialApp(home: ChatThread(api, 'chat-1', false, 'Vo Chi Tam')),
      );
      await tester.pumpAndSettle();

      final composerBefore = tester.getRect(find.byType(TextField));
      expect(composerBefore.bottom, greaterThan(680));

      // Drag the message list downward (scrolling up to older messages)
      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pumpAndSettle();

      // Composer must remain pinned at the exact same bottom coordinate.
      final composerAfter = tester.getRect(find.byType(TextField));
      expect(composerAfter.top, composerBefore.top);
      expect(composerAfter.bottom, composerBefore.bottom);

      await tester.enterText(find.byType(TextField), 'Chào bạn nhé!');
      await tester.tap(find.byTooltip('Gửi tin nhắn'));
      await tester.pumpAndSettle();

      expect(posted, {'content': 'Chào bạn nhé!'});
      expect(find.text('Chào bạn nhé!'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

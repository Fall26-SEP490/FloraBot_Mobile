import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:florabot_mobile/core/api.dart';
import 'package:florabot_mobile/ui/common.dart';

Widget screen(
  Future<dynamic> Function() load, {
  Future<void> Function()? action,
}) => MaterialApp(
  home: Scaffold(
    body: ResourceView(
      load: load,
      builder: (context, data, state) => Column(
        children: [
          Text('Value: $data'),
          FilledButton(
            onPressed: state.reload,
            child: const Text('Refresh data'),
          ),
          if (action != null)
            FilledButton(
              onPressed: () => state.run(action),
              child: const Text('Save change'),
            ),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('refresh displays pending state then the new server value', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<String>();
    await tester.pumpWidget(
      screen(() => ++calls == 1 ? Future.value('old') : pending.future),
    );
    await tester.pumpAndSettle();
    expect(find.text('Value: old'), findsOneWidget);
    await tester.tap(find.text('Refresh data'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete('updated');
    await tester.pumpAndSettle();
    expect(find.text('Value: updated'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets(
    'successful mutation reloads data without reporting setState error',
    (tester) async {
      var reads = 0, saves = 0;
      await tester.pumpWidget(
        screen(
          () async => ++reads,
          action: () async {
            saves++;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save change'));
      await tester.pumpAndSettle();
      expect(find.text('Value: 2'), findsOneWidget);
      expect(saves, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('retry recovers after server failure', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      screen(() async {
        if (++calls == 1) {
          throw const ApiError(503, 'Server temporarily unavailable');
        }
        return 'recovered';
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Server temporarily unavailable'), findsOneWidget);
    await tester.tap(find.text('Tải lại'));
    await tester.pumpAndSettle();
    expect(find.text('Value: recovered'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

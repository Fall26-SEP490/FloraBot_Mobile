import 'package:florabot_mobile/ui/common.dart';
import 'package:florabot_mobile/ui/vietnam_bank_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Refund form sends the selected bank name', (tester) async {
    Map<String, String>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await askForm(context, 'Tài khoản nhận hoàn', [
                  const InputSpec(
                    'bank',
                    'Tên ngân hàng',
                    picker: pickVietnamBank,
                  ),
                ]);
              },
              child: const Text('Mở form'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở form'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextFormField, 'Tên ngân hàng'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Tìm theo tên hoặc mã ngân hàng'),
      'vcb',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ngoại thương Việt Nam'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(result, {'bank': 'Ngoại thương Việt Nam'});
  });
}

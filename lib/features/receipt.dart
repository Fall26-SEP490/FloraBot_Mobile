import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';

// Receipt possession credentials stay in memory and in HTTPS bodies/headers.
class ReceiptPage extends StatelessWidget {
  const ReceiptPage(this.api, this.orderId, this.trackingToken, {super.key});
  final ApiClient api;
  final String orderId, trackingToken;
  @override
  Widget build(BuildContext context) => ResourceView(
    title: 'Biên nhận và hỗ trợ',
    load: () => api.post('/api/receipts/lookup', {
      'orderId': orderId,
      'trackingToken': trackingToken,
    }),
    builder: (context, data, state) {
      final receipt = objectOf(data), refunds = objectOf(receipt['refunds']);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageTitle(
            valueOf(receipt, 'orderCode'),
            dateText(receipt['createdAt']),
          ),
          StatusChip(receipt['status']),
          for (final row in (receipt['items'] as List).map(objectOf))
            RecordCard(
              title: valueOf(row, 'name'),
              subtitle:
                  '${row['quantity']} × ${money(row['unitPrice'])} • ${money(row['total'])}',
            ),
          InfoBox(
            'Tổng thanh toán: ${money(receipt['total'])}\n'
            'Chờ hoàn: ${money(refunds['pendingAmount'])}\nĐã hoàn: ${money(refunds['paidAmount'])}',
          ),
          if (receipt['hasComplaint'] == true)
            const InfoBox(
              'Đã có khiếu nại. Liên hệ shop hoặc bộ phận hỗ trợ để theo dõi xử lý.',
            ),
          if (receipt['canComplain'] == true) ...[
            InfoBox(
              'Hạn tiếp nhận khiếu nại: ${dateText(receipt['disputeDeadline'])}',
            ),
            FilledButton.icon(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final form =
                          await askForm(context, 'Báo vấn đề với hoa', [
                            const InputSpec(
                              'reason',
                              'Mô tả tình trạng thực tế',
                              minLength: 10,
                              lines: 4,
                            ),
                          ], submitLabel: 'Tiếp tục chụp / chọn ảnh');
                      if (form == null || !context.mounted) return;
                      final image = await chooseEvidence(context);
                      if (image == null) return;
                      final evidence = await api.upload(
                        '/api/receipts/$orderId/evidence',
                        image,
                        receiptToken: trackingToken,
                      );
                      if (!context.mounted ||
                          !await confirm(
                            context,
                            'Gửi khiếu nại?',
                            form['reason']!,
                          )) {
                        return;
                      }
                      await api.post('/api/receipts/flows/open_dispute', {
                        'p_order': orderId,
                        'p_tracking': trackingToken,
                        'p_reason': form['reason'],
                        'p_photo': evidence['reference'],
                      });
                    }),
              icon: const Icon(Icons.support_agent),
              label: const Text('Gửi khiếu nại kèm ảnh'),
            ),
          ],
          if ((refunds['pendingAmount'] as num? ?? 0) > 0) ...[
            InfoBox(
              receipt['refundInformationProvided'] == true
                  ? 'Đã gửi thông tin nhận hoàn tiền. Chỉ cập nhật nếu cần chỉnh sửa.'
                  : 'Điền tài khoản nhận hoàn tiền. Thời điểm chi trả do bộ phận phụ trách xác nhận.',
            ),
            OutlinedButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final form =
                          await askForm(context, 'Thông tin nhận hoàn tiền', [
                            const InputSpec(
                              'bank',
                              'Tên ngân hàng',
                              minLength: 2,
                            ),
                            const InputSpec(
                              'account',
                              'Số tài khoản',
                              numeric: true,
                              minLength: 6,
                            ),
                            const InputSpec(
                              'holder',
                              'Tên chủ tài khoản',
                              minLength: 2,
                            ),
                          ]);
                      if (form == null || !context.mounted) return;
                      if (!await confirm(
                        context,
                        'Gửi thông tin ngân hàng?',
                        '${form['bank']}\n${form['account']}\n${form['holder']}',
                      )) {
                        return;
                      }
                      await api.post('/api/receipts/flows/submit_refund_info', {
                        'p_order': orderId,
                        'p_tracking': trackingToken,
                        'p_bank': form['bank'],
                        'p_account_enc': form['account'],
                        'p_holder': form['holder'],
                      });
                    }),
              child: const Text('Thông tin nhận hoàn tiền'),
            ),
          ],
        ],
      );
    },
  );
}

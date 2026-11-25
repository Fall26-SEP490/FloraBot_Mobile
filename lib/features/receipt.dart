import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/inventory_widgets.dart';
import 'inventory.dart' show openPage;
import 'preorder_support.dart';
import '../ui/vietnam_bank_picker.dart';

String _formatReceiptItemName(String raw) => raw.replaceFirst(
  RegExp(r'^Hoa dat rieng:\s*', caseSensitive: false),
  'Hoa đặt riêng: ',
);

// Receipt possession credentials stay in memory and in HTTPS bodies/headers.
class ReceiptPage extends StatelessWidget {
  const ReceiptPage(this.api, this.orderId, this.trackingToken, {super.key});
  final ApiClient api;
  final String orderId, trackingToken;
  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => api.post('/api/receipts/lookup', {
      'orderId': orderId,
      'trackingToken': trackingToken,
    }),
    builder: (context, data, state) {
      final receipt = objectOf(data), refunds = objectOf(receipt['refunds']);
      final items = (receipt['items'] as List? ?? const [])
          .map(objectOf)
          .toList();
      final pendingRefund = (refunds['pendingAmount'] as num? ?? 0);
      final paidRefund = (refunds['paidAmount'] as num? ?? 0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PreorderSection(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      valueOf(receipt, 'orderCode'),
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.4,
                        fontWeight: FontWeight.w800,
                        color: forest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: InventoryStatus('${receipt['status'] ?? ''}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                dateText(receipt['createdAt']),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF617267),
                ),
              ),
              const Divider(height: 20, color: Color(0xFFEAF0E7)),
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatReceiptItemName(valueOf(items[i], 'name')),
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              fontWeight: FontWeight.w700,
                              color: forest,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${items[i]['quantity']} × ${money(items[i]['unitPrice'])}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF617267),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      money(items[i]['total']),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: forest,
                      ),
                    ),
                  ],
                ),
              ],
              const Divider(height: 20, color: Color(0xFFEAF0E7)),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tổng thanh toán',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: forest,
                      ),
                    ),
                  ),
                  Text(
                    money(receipt['total']),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: forest,
                    ),
                  ),
                ],
              ),
              if (pendingRefund > 0) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Chờ hoàn tiền',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF925B0A),
                        ),
                      ),
                    ),
                    Text(
                      money(pendingRefund),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF925B0A),
                      ),
                    ),
                  ],
                ),
              ],
              if (paidRefund > 0) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Đã hoàn tiền',
                        style: TextStyle(fontSize: 13, color: forest),
                      ),
                    ),
                    Text(
                      money(paidRefund),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: forest,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (receipt['hasComplaint'] == true)
            OutlinedButton(
              onPressed: () => openPage(
                context,
                'Tiến độ phản ánh',
                CustomerComplaintPage(api, orderId, trackingToken),
              ),
              child: const Text('Theo dõi xử lý phản ánh'),
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
                              picker: pickVietnamBank,
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

class CustomerComplaintPage extends StatelessWidget {
  const CustomerComplaintPage(
    this.api,
    this.orderId,
    this.trackingToken, {
    super.key,
  });
  final ApiClient api;
  final String orderId, trackingToken;
  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => api.post('/api/receipts/complaints/lookup', {
      'orderId': orderId,
      'trackingToken': trackingToken,
    }),
    builder: (context, data, state) {
      final item = objectOf(data);
      final replacement = item['replacement'] is Map
          ? objectOf(item['replacement'])
          : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageTitle(
            'Đơn ${item['orderCode']}',
            valueOf(item, 'reason'),
            status: StatusChip(item['handlingState']),
          ),
          if (item['resolution'] != null) InfoBox('${item['resolution']}'),
          if (replacement != null) ...[
            StatusHeading(
              title: const Text(
                'Hoa thay thế',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              status: StatusChip(replacement['state']),
            ),
            InfoBox(
              'Ô nhận hoa thay: ${replacement['slotCode']}\nHạn nhận: ${dateText(replacement['expiresAt'])}',
            ),
          ],
        ],
      );
    },
  );
}

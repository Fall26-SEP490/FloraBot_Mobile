import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';

String preorderState(Json row) => '${row['orderStatus'] ?? row['state'] ?? ''}';
bool preorderClosed(Json row) => [
  'COMPLETED',
  'REFUNDED',
  'CANCELLED',
  'EXPIRED',
  'REJECTED',
].contains(preorderState(row));
bool preorderCanCancel(Json row, bool seller) =>
    !preorderClosed(row) &&
    (row['orderStatus'] == null
        ? ['REQUESTED', 'QUOTED'].contains(row['state'])
        : row['orderStatus'] == 'AWAITING_PAYMENT' ||
              (seller && row['orderStatus'] == 'PAID'));
bool preorderQuoteExpired(Json row, [DateTime? now]) {
  final expiry = DateTime.tryParse('${row['quoteExpiresAt']}');
  return expiry != null && !expiry.isAfter(now ?? DateTime.now());
}

bool preorderCanSendOtp(Json row, [DateTime? now]) =>
    row['kind'] == 'CUSTOM' &&
    row['state'] == 'ORDERED' &&
    row['orderStatus'] == 'PAID' &&
    row['ready'] == true &&
    (DateTime.tryParse(
          '${row['pickupBefore']}',
        )?.isAfter(now ?? DateTime.now()) ??
        false);
(String, Color) preorderAppearance(Json row) {
  final code = preorderState(row);
  if (code == 'PAID') {
    return (
      row['ready'] == true ? 'Sẵn sàng nhận' : 'Cần nạp hoa',
      const Color(0xFF075985),
    );
  }
  if (code == 'REQUESTED') return ('Chờ báo giá', const Color(0xFF925B0A));
  if (code == 'QUOTED') {
    return (
      preorderQuoteExpired(row) ? 'Báo giá hết hạn' : 'Đã báo giá',
      const Color(0xFF925B0A),
    );
  }
  const labels = {
    'AWAITING_PAYMENT': 'Chờ thanh toán',
    'DISPENSING': 'Đang nhận hoa',
    'COMPLETED': 'Đã nhận hoa',
    'REFUNDED': 'Đã hoàn tiền',
    'DISPENSE_FAILED': 'Chờ xử lý hoàn tiền',
    'DISPUTED': 'Đang phản ánh',
    'CANCELLED': 'Đã hủy',
    'REJECTED': 'Đã từ chối',
    'EXPIRED': 'Hết hạn thanh toán',
  };
  final color = ['COMPLETED', 'REFUNDED'].contains(code)
      ? forest
      : ['CANCELLED', 'REJECTED', 'EXPIRED', 'DISPENSE_FAILED'].contains(code)
      ? const Color(0xFFB42318)
      : const Color(0xFF925B0A);
  return (labels[code] ?? statusText(code), color);
}

String preorderCode(Json row) => valueOf(
  row,
  'orderCode',
  '#${'${row['id']}'.substring(0, '${row['id']}'.length.clamp(0, 8))}',
);

Future<List<Json>> allPreorders(ApiClient api, String base) async {
  final rows = <Json>[], seen = <String>{};
  for (int page = 1; ; page++) {
    final result = objectOf(await api.get('$base?page=$page'));
    final current = itemsOf(result);
    int added = 0;
    for (final row in current) {
      if (seen.add('${row['id']}')) {
        rows.add({...row, '_mobilePage': page});
        added++;
      }
    }
    if (result['hasMore'] != true) return rows;
    if (added == 0) {
      throw const FormatException(
        'Danh sách đơn thay đổi. Vuốt xuống để tải lại.',
      );
    }
  }
}

Future<Json> findPreorder(
  ApiClient api,
  String base,
  String id, {
  int hint = 1,
}) async {
  Json? hinted;
  if (hint > 1) {
    hinted = objectOf(await api.get('$base?page=$hint'));
    final row = itemsOf(
      hinted,
    ).where((row) => '${row['id']}' == id).firstOrNull;
    if (row != null) return row;
  }
  final seen = <String>{};
  for (int page = 1; ; page++) {
    final result = page == hint && hinted != null
        ? hinted
        : objectOf(await api.get('$base?page=$page'));
    final current = itemsOf(result);
    final row = current.where((row) => '${row['id']}' == id).firstOrNull;
    if (row != null) return row;
    if (result['hasMore'] != true) {
      throw const ApiError(404, 'Không tìm thấy đơn đặt trước.');
    }
    int added = 0;
    for (final item in current) {
      if (seen.add('${item['id']}')) added++;
    }
    if (added == 0) {
      throw const FormatException(
        'Danh sách đơn thay đổi. Quay lại danh sách để tải lại.',
      );
    }
  }
}

class PreorderStatus extends StatelessWidget {
  const PreorderStatus(this.order, {super.key});
  final Json order;
  @override
  Widget build(BuildContext context) {
    final (label, color) = preorderAppearance(order);
    return Text(
      label,
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: 12,
        height: 1.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
  }
}

class PreorderCard extends StatelessWidget {
  const PreorderCard(
    this.order, {
    required this.onTap,
    required this.seller,
    super.key,
  });
  final Json order;
  final VoidCallback onTap;
  final bool seller;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFDDE6DF)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      preorderCode(order),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                        color: forest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 132),
                    child: PreorderStatus(order),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                valueOf(order, 'productName', 'Đơn theo mẫu'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: forest,
                ),
              ),
              if (!seller)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    valueOf(order, 'shopName'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF617267),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              _Meta(Icons.location_on_outlined, valueOf(order, 'kioskName')),
              const SizedBox(height: 5),
              _Meta(Icons.schedule, dateText(order['pickupAt'])),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order['quotedPrice'] == null
                          ? 'Chưa báo giá'
                          : money(order['quotedPrice']),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: order['quotedPrice'] == null
                            ? const Color(0xFF617267)
                            : forest,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 15, color: const Color(0xFF617267)),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            height: 1.4,
            color: Color(0xFF617267),
          ),
        ),
      ),
    ],
  );
}

class PreorderSection extends StatelessWidget {
  const PreorderSection({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFDDE6DF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class PreorderPackingList extends StatelessWidget {
  const PreorderPackingList(this.order, {super.key});
  final Json order;
  @override
  Widget build(BuildContext context) {
    final quoted = itemsOf(order['quotedAccessories'] ?? []),
        requested = itemsOf(order['requestedAccessories'] ?? []);
    final breakdown = order['quotedFlowerPrice'] != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (breakdown) _Amount('Bó hoa', money(order['quotedFlowerPrice'])),
        for (final item in breakdown ? quoted : requested)
          _Amount(
            '${valueOf(item, 'name')} × ${item['quantity']}',
            breakdown ? money(item['lineTotal']) : 'Khách yêu cầu',
          ),
        if (breakdown)
          for (final item in requested)
            if ((quoted
                            .where(
                              (q) => q['accessoryId'] == item['accessoryId'],
                            )
                            .firstOrNull?['quantity']
                        as num? ??
                    0) <
                (item['quantity'] as num? ?? 0))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${item['name']}: nhận ${quoted.where((q) => q['accessoryId'] == item['accessoryId']).firstOrNull?['quantity'] ?? 0}/${item['quantity']}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF925B0A),
                  ),
                ),
              ),
        if (order['quotedPrice'] != null)
          _Amount(
            [
                  'PAID',
                  'DISPENSING',
                  'COMPLETED',
                  'REFUNDED',
                ].contains(order['orderStatus'])
                ? 'Tổng thanh toán'
                : 'Tổng báo giá',
            money(order['quotedPrice']),
            bold: true,
          ),
      ],
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount(this.label, this.amount, {this.bold = false});
  final String label, amount;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              color: forest,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          amount,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: forest,
          ),
        ),
      ],
    ),
  );
}

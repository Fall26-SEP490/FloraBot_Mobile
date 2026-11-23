import 'package:flutter/material.dart';
import '../core/models.dart';
import '../ui/common.dart';

class PreorderQuoteEditor extends StatefulWidget {
  const PreorderQuoteEditor({
    required this.order,
    required this.catalog,
    required this.initialPrice,
    required this.chooseTime,
    super.key,
  });
  final Json order;
  final List<Json> catalog;
  final dynamic initialPrice;
  final Future<DateTime?> Function(DateTime?) chooseTime;
  @override
  State<PreorderQuoteEditor> createState() => _PreorderQuoteEditorState();
}

class _PreorderQuoteEditorState extends State<PreorderQuoteEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController price, note;
  late DateTime? pickup;
  final quantities = <String, int>{};
  String? error;
  List<Json> get requested =>
      itemsOf(widget.order['requestedAccessories'] ?? []);
  Json? current(Json item) => widget.catalog
      .where(
        (row) =>
            row['id'] == item['accessoryId'] &&
            (row['kioskId'] == null ||
                row['kioskId'] == widget.order['kioskId']) &&
            row['status'] == 'ACTIVE',
      )
      .firstOrNull;
  int stock(Json item) =>
      (current(item)?['stockQuantity'] as num? ?? 0).toInt().clamp(0, 1 << 30);
  int unitPrice(Json item) => (current(item)?['price'] as num? ?? 0).toInt();
  bool get invalidStock => requested.any(
    (item) =>
        (quantities['${item['accessoryId']}'] ?? 0) > stock(item) ||
        ((quantities['${item['accessoryId']}'] ?? 0) > 0 &&
            unitPrice(item) <= 0),
  );
  int get accessoryTotal => requested.fold(
    0,
    (total, item) =>
        total + (quantities['${item['accessoryId']}'] ?? 0) * unitPrice(item),
  );
  @override
  void initState() {
    super.initState();
    price = TextEditingController(text: '${widget.initialPrice ?? ''}');
    note = TextEditingController(
      text: widget.order['quoteNote'] as String? ?? '',
    );
    pickup = DateTime.tryParse('${widget.order['pickupAt']}');
    final quoted = itemsOf(widget.order['quotedAccessories'] ?? []);
    for (final item in requested) {
      final accepted = quoted
          .where((q) => q['accessoryId'] == item['accessoryId'])
          .firstOrNull;
      num quantity = 0;
      if (widget.order['quotedFlowerPrice'] != null) {
        if (accepted != null) quantity = accepted['quantity'] as num? ?? 0;
      } else {
        quantity = item['quantity'] as num? ?? 0;
      }
      quantities['${item['accessoryId']}'] = quantity.toInt();
    }
  }

  @override
  void dispose() {
    price.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Báo giá đơn đặt trước',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: forest,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng báo giá',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Giá bó hoa (đồng)',
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) =>
                    int.tryParse(value ?? '') == null ||
                        (int.tryParse(value ?? '') ?? 0) <= 0
                    ? 'Nhập giá bó hoa hợp lệ.'
                    : null,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final value = await widget.chooseTime(pickup);
                  if (mounted && value != null) setState(() => pickup = value);
                },
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(
                  'Lịch nhận: ${dateText(pickup?.toIso8601String())}',
                ),
              ),
              if (requested.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Phụ kiện khách yêu cầu',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: forest,
                  ),
                ),
                for (final item in requested)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${item['name']} · Yêu cầu ${item['quantity']}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: forest,
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${money(unitPrice(item))}/cái · Còn ${stock(item)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF617267),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Giảm ${item['name']}',
                              onPressed:
                                  (quantities['${item['accessoryId']}'] ?? 0) >
                                      0
                                  ? () => setState(
                                      () => quantities['${item['accessoryId']}'] =
                                          quantities['${item['accessoryId']}']! -
                                          1,
                                    )
                                  : null,
                              icon: const Icon(Icons.remove, size: 18),
                            ),
                            Text(
                              '${quantities['${item['accessoryId']}']}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Tăng ${item['name']}',
                              onPressed:
                                  (quantities['${item['accessoryId']}'] ?? 0) <
                                      (item['quantity'] as num? ?? 0)
                                  ? () => setState(
                                      () => quantities['${item['accessoryId']}'] =
                                          quantities['${item['accessoryId']}']! +
                                          1,
                                    )
                                  : null,
                              icon: const Icon(Icons.add, size: 18),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (invalidStock)
                  const Text(
                    'Giảm số lượng phụ kiện theo tồn kho hiện có.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFB42318)),
                  ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: note,
                minLines: 2,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú báo giá',
                  counterText: '',
                ),
                validator: (value) => (value ?? '').trim().length < 5
                    ? 'Nhập ghi chú từ 5 ký tự.'
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                'Tổng báo giá: ${money((int.tryParse(price.text) ?? 0) + accessoryTotal)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: forest,
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Color(0xFFB42318)),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: invalidStock
                    ? null
                    : () {
                        if (form.currentState?.validate() != true) return;
                        if (pickup == null ||
                            !pickup!.isAfter(DateTime.now())) {
                          setState(
                            () => error = 'Chọn lịch nhận trong tương lai.',
                          );
                          return;
                        }
                        Navigator.pop(context, <String, dynamic>{
                          'price': int.parse(price.text),
                          'pickupAt': pickup!.toUtc().toIso8601String(),
                          'note': note.text.trim(),
                          'reject': false,
                          if (requested.isNotEmpty)
                            'accessories': [
                              for (final item in requested)
                                if ((quantities['${item['accessoryId']}'] ??
                                        0) >
                                    0)
                                  {
                                    'accessoryId': item['accessoryId'],
                                    'quantity':
                                        quantities['${item['accessoryId']}'],
                                  },
                            ],
                          '_total': int.parse(price.text) + accessoryTotal,
                        });
                      },
                child: const Text('Xem lại báo giá'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

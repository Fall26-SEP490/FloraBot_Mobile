import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';
import 'inventory.dart';
import 'chat.dart';
import 'receipt.dart';

Future<DateTime?> choosePickup(
  BuildContext context, {
  DateTime? initial,
}) async {
  final now = DateTime.now();
  final start = initial != null && initial.isAfter(now)
      ? initial
      : now.add(const Duration(hours: 2));
  final day = await showDatePicker(
    context: context,
    initialDate: start,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: now.add(const Duration(days: 365)),
  );
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(start),
  );
  if (time == null) return null;
  final result = DateTime(day.year, day.month, day.day, time.hour, time.minute);
  if (!result.isAfter(DateTime.now())) {
    throw const ApiError(400, 'Lịch nhận phải ở tương lai.');
  }
  return result;
}

class CatalogPage extends StatefulWidget {
  const CatalogPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  String search = '';
  @override
  Widget build(BuildContext context) => ApiListPage(
    api: widget.api,
    path:
        '/api/shop/catalog?availablePreorderOnly=true&search=${Uri.encodeQueryComponent(search)}',
    title: 'Chọn hoa, hẹn ngày nhận',
    subtitle: 'Hoa theo mẫu từ các shop, nhận tại kiosk được chọn.',
    actions: [
      SearchBar(
        hintText: 'Tên hoa, shop...',
        leading: const Icon(Icons.search),
        onSubmitted: (value) => setState(() => search = value.trim()),
        trailing: [
          IconButton(
            tooltip: 'Xóa tìm kiếm',
            onPressed: () => setState(() => search = ''),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      const SizedBox(height: 12),
    ],
    item: (context, row, state) => Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: state.busy ? null : () => book(state, row),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (Uri.tryParse('${row['photo']}')?.scheme == 'https')
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    '${row['photo']}',
                    height: 180,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(
                      height: 100,
                      child: Icon(
                        Icons.local_florist_outlined,
                        size: 50,
                        color: forest,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                valueOf(row, 'name'),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text('${money(row['price'])} • ${valueOf(row, 'shopName')}'),
              const SizedBox(height: 8),
              Text(
                '${valueOf(row, 'kioskName')}\n${valueOf(row, 'address')}',
                style: const TextStyle(color: Color(0xFF617568)),
              ),
              const SizedBox(height: 8),
              const Text(
                'Đặt theo mẫu • Shop sẽ xác nhận báo giá',
                style: TextStyle(color: forest, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: state.busy
                    ? null
                    : () => state.run(
                        () => openCustomerChat(
                          context,
                          widget.api,
                          '${row['sellerId']}',
                          productId: '${row['productId']}',
                        ),
                      ),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Trao đổi với shop'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Future<void> book(ResourceViewState state, Json row) => state.run(() async {
    final form = await askForm(
      context,
      'Yêu cầu đặt ${row['name']}',
      [
        const InputSpec(
          'instructions',
          'Mong muốn / ghi chú cho shop',
          minLength: 10,
          lines: 4,
        ),
      ],
      submitLabel: 'Tiếp tục chọn lịch',
      description:
          'Giá hiển thị là tham khảo. Shop báo giá và bạn chấp nhận trước khi thanh toán.',
    );
    if (form == null || !mounted) return;
    final pickup = await choosePickup(context);
    if (pickup == null) return;
    final availability = objectOf(
      await widget.api.get(
        '/api/kiosks/${row['kioskId']}/preorder-availability?pickupAt=${Uri.encodeQueryComponent(pickup.toUtc().toIso8601String())}',
      ),
    );
    if (availability['available'] != true) {
      throw ApiError(
        409,
        valueOf(availability, 'message', 'Điểm nhận chưa đủ chỗ.'),
      );
    }
    if (!mounted ||
        !await confirm(
          context,
          'Gửi yêu cầu đặt hoa?',
          '${row['shopName']}\n${row['kioskName']}\nNhận lúc ${dateText(pickup.toIso8601String())}\nChưa thu tiền ở bước này.',
        )) {
      return;
    }
    await widget.api.post('/api/member/preorders', {
      'id': const Uuid().v4(),
      'kind': 'CUSTOM',
      'productId': row['productId'],
      'kioskId': row['kioskId'],
      'pickupAt': pickup.toUtc().toIso8601String(),
      'instructions': form['instructions'],
    });
    if (mounted) {
      message(context, 'Đã gửi yêu cầu. Xem báo giá tại mục Đơn đặt.');
    }
  });
}

class OrdersPage extends StatelessWidget {
  const OrdersPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  Widget build(BuildContext context) {
    final base = session.role == AppRole.seller
        ? '/api/sellers/${session.sellerId}/preorders'
        : '/api/member/preorders';
    return ApiListPage(
      api: api,
      path: base,
      title: session.role == AppRole.seller
          ? 'Đơn đặt trước'
          : 'Đơn đặt của tôi',
      subtitle: 'Báo giá, thanh toán, chuẩn bị và theo dõi lịch nhận hoa.',
      item: (context, row, state) => RecordCard(
        title: valueOf(row, 'productName', 'Đơn theo mẫu'),
        subtitle:
            '${valueOf(row, 'orderCode', 'Chờ báo giá')} • ${valueOf(row, 'shopName')}\nNhận: ${dateText(row['pickupAt'])}',
        status: row['orderStatus'] ?? row['state'],
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => OrderDetail(api, session, row),
            ),
          );
          await state.reload();
        },
      ),
    );
  }
}

class OrderDetail extends StatefulWidget {
  const OrderDetail(this.api, this.session, this.order, {super.key});
  final ApiClient api;
  final Session session;
  final Json order;
  @override
  State<OrderDetail> createState() => _OrderDetailState();
}

class _OrderDetailState extends State<OrderDetail> {
  String? loadingId, loadingSlotId;
  bool get owner => widget.session.role == AppRole.seller;
  String get id => '${widget.order['id']}';
  String get base => owner
      ? '/api/sellers/${widget.session.sellerId}/preorders'
      : '/api/member/preorders';
  Future<Json> load() async {
    final hint = widget.order['_mobilePage'] as int? ?? 1;
    for (final page in {hint, 1}) {
      final rows = itemsOf(await widget.api.get('$base?page=$page'));
      for (final row in rows) {
        if (row['id'] == id) return row;
      }
    }
    throw const ApiError(
      404,
      'Danh sách đã thay đổi. Quay lại danh sách đơn rồi mở lại để lấy dữ liệu mới nhất.',
    );
  }

  @override
  Widget build(BuildContext context) => ResourceView(
    title: 'Chi tiết đơn đặt',
    load: load,
    builder: (context, data, state) {
      final order = objectOf(data);
      final terminal =
          [
            'CANCELLED',
            'REJECTED',
            'EXPIRED',
            'COMPLETED',
            'REFUNDED',
          ].contains(order['state']) ||
          ['COMPLETED', 'REFUNDED'].contains(order['orderStatus']);
      final awaitingQuote =
          ['REQUESTED', 'QUOTED'].contains(order['state']) &&
          order['orderId'] == null;
      final paid = order['orderStatus'] == 'PAID';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageTitle(
            valueOf(order, 'productName', 'Đơn theo mẫu'),
            valueOf(order, 'orderCode', 'Chờ chốt đơn'),
          ),
          StatusChip(order['orderStatus'] ?? order['state']),
          RecordCard(
            title: valueOf(order, 'shopName'),
            subtitle:
                '${valueOf(order, 'kioskName')}\n${valueOf(order, 'address')}',
            onTap: () =>
                state.run(() => navigateAddress(valueOf(order, 'address'))),
          ),
          InfoBox(
            'Lịch nhận: ${dateText(order['pickupAt'])}\nNhận trước: ${dateText(order['pickupBefore'])}\nGiá đã báo: ${order['quotedPrice'] == null ? 'Chờ shop' : money(order['quotedPrice'])}',
          ),
          Text('Yêu cầu: ${valueOf(order, 'instructions')}'),
          if (!owner &&
              order['orderId'] != null &&
              order['trackingToken'] != null)
            OutlinedButton.icon(
              onPressed: () => openPage(
                context,
                'Biên nhận và hỗ trợ',
                ReceiptPage(
                  widget.api,
                  '${order['orderId']}',
                  '${order['trackingToken']}',
                ),
              ),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Biên nhận và hỗ trợ đơn hàng'),
            ),
          if (order['quoteNote'] != null)
            InfoBox('Ghi chú báo giá: ${order['quoteNote']}'),
          if (owner && awaitingQuote) ...[
            FilledButton(
              onPressed: state.busy ? null : () => quote(state, order),
              child: const Text('Báo giá / cập nhật báo giá'),
            ),
            TextButton(
              onPressed: state.busy
                  ? null
                  : () => quote(state, order, reject: true),
              child: const Text('Từ chối yêu cầu'),
            ),
          ],
          if (!owner && order['state'] == 'QUOTED' && order['orderId'] == null)
            FilledButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      if (!await confirm(
                        context,
                        'Chấp nhận báo giá?',
                        '${money(order['quotedPrice'])}\nLịch nhận: ${dateText(order['pickupAt'])}\n${valueOf(order, 'quoteNote', '')}',
                      )) {
                        return;
                      }
                      await widget.api.post('$base/$id/accept', {
                        'price': order['quotedPrice'],
                        'pickupAt': order['pickupAt'],
                        'note': order['quoteNote'] ?? '',
                      });
                    }),
              child: const Text('Chấp nhận báo giá'),
            ),
          if (!owner && order['orderStatus'] == 'AWAITING_PAYMENT')
            FilledButton.icon(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final link = objectOf(
                        await widget.api.post(
                          '/api/member/preorders/$id/payment-link',
                        ),
                      );
                      if (!context.mounted) return;
                      if (await confirm(
                        context,
                        'Mở trang thanh toán?',
                        '${money(link['amount'])}\nNgười nhận: ${link['recipientName'] ?? 'Theo kênh đã xác minh'}\nChỉ backend xác nhận thanh toán thành công.',
                      )) {
                        await openSafeLink('${link['checkoutUrl']}');
                      }
                    }),
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Thanh toán qua payOS'),
            ),
          if (owner && paid && order['ready'] != true) ...[
            FilledButton(
              onPressed: state.busy ? null : () => loadPreorder(state, order),
              child: const Text('Nạp đơn vào ô PREORDER'),
            ),
            OutlinedButton(
              onPressed: state.busy ? null : () => assignPreorder(state, order),
              child: const Text('Giao nhân viên nạp đơn'),
            ),
          ],
          if (order['ready'] == true)
            const InfoBox(
              'Hoa đã được xác nhận nạp vào kiosk. Khách nhận trong đúng khung giờ bằng OTP email.',
            ),
          if (owner &&
              order['ready'] == true &&
              ['PAID', 'DISPENSING'].contains(order['orderStatus']))
            FilledButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      if (!await confirm(
                        context,
                        'Gửi mã nhận hoa?',
                        'OTP 8 số gửi đến email đăng nhập của khách. Mã cũ có thể bị vô hiệu khi gửi lại.',
                      )) {
                        return;
                      }
                      final result = objectOf(
                        await widget.api.post(
                          '/api/me/preorders/$id/pickup-otp',
                        ),
                      );
                      if (context.mounted) {
                        message(
                          context,
                          'Đã tiếp nhận gửi đến ${result['recipientMasked'] ?? 'email của khách'}. Kiểm tra trạng thái email nếu khách chưa nhận.',
                        );
                      }
                    }),
              child: const Text('Gửi / gửi lại OTP nhận hoa'),
            ),
          if (!owner && paid)
            const InfoBox(
              'Mã nhận hoa gồm 8 số được shop gửi đến EMAIL ĐĂNG NHẬP sau khi đã nạp hoa. App không đọc hoặc lưu OTP email. Hãy nhập mã tại đúng kiosk trong khung giờ nhận.',
            ),
          if (!owner && !terminal)
            const InfoBox(
              'Sau khi trả tiền hoặc thao tác ở kiosk, kéo xuống để cập nhật. Quay về từ trang thanh toán không tự đánh dấu đơn đã trả tiền.',
            ),
          if (!terminal)
            TextButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final form = await askForm(
                        context,
                        'Yêu cầu hủy đơn',
                        [
                          const InputSpec(
                            'reason',
                            'Lý do hủy',
                            minLength: 5,
                            lines: 3,
                          ),
                        ],
                        description:
                            'Backend quyết định điều kiện hủy và nghĩa vụ hoàn tiền theo trạng thái hiện tại.',
                      );
                      if (form != null) {
                        await widget.api.post('$base/$id/cancel', {
                          'reason': form['reason'],
                        });
                      }
                    }),
              child: const Text('Hủy theo điều kiện của đơn'),
            ),
        ],
      );
    },
  );
  Future<void> quote(
    ResourceViewState state,
    Json order, {
    bool reject = false,
  }) => state.run(() async {
    final form =
        await askForm(context, reject ? 'Từ chối yêu cầu' : 'Báo giá', [
          if (!reject)
            InputSpec(
              'price',
              'Giá trọn đơn (đồng)',
              initial: '${order['quotedPrice'] ?? ''}',
              numeric: true,
            ),
          const InputSpec('note', 'Ghi chú / lý do', lines: 3, minLength: 5),
        ]);
    if (form == null || !mounted) return;
    final pickup = reject
        ? DateTime.tryParse('${order['pickupAt']}')
        : await choosePickup(
            context,
            initial: DateTime.tryParse('${order['pickupAt']}'),
          );
    if (pickup == null) return;
    await widget.api.post('$base/$id/quote', {
      'price': reject ? 0 : integerInput(form['price']),
      'pickupAt': pickup.toUtc().toIso8601String(),
      'note': form['note'],
      'reject': reject,
    });
  });
  Future<void> loadPreorder(
    ResourceViewState state,
    Json order,
  ) => state.run(() async {
    final slots =
        itemsOf(
              await widget.api.get('/api/me/kiosks/${order['kioskId']}/slots'),
            )
            .where(
              (s) =>
                  s['zone'] == 'PREORDER' &&
                  (s['status'] == 'RENTED_EMPTY' || s['id'] == loadingSlotId),
            )
            .toList();
    if (!mounted) return;
    final form = await askForm(context, 'Nạp hoa cho đơn này', [
      InputSpec(
        'slotId',
        'Ô PREORDER trống',
        initial: loadingSlotId ?? '',
        choices: {for (final s in slots) '${s['id']}': '${s['slotCode']}'},
      ),
      const InputSpec(
        'operation',
        'Bước thực hiện',
        choices: {
          'OTP': 'Gửi OTP nạp đến email của tôi',
          'FULFILL': 'Xác nhận sau khi nạp và đóng cửa',
        },
      ),
    ]);
    if (form == null) return;
    if (form['operation'] == 'OTP') {
      final sent = objectOf(
        await widget.api.post('/api/me/preorders/$id/loading-access', {
          'slotId': form['slotId'],
        }),
      );
      loadingId = '${sent['id']}';
      loadingSlotId = form['slotId'];
      if (mounted) {
        await showAccessCode(context, {
          ...sent,
          'message': 'Kiểm tra email đăng nhập của người nạp hoa để lấy OTP.',
        });
      }
    } else {
      if (loadingId == null || loadingSlotId != form['slotId']) {
        throw const ApiError(
          409,
          'Lấy quyền nạp đúng ô trong phiên này trước.',
        );
      }
      await widget.api.post('$base/$id/fulfill', {
        'slotId': form['slotId'],
        'qrCode': 'FB-${const Uuid().v4()}',
        'loadingAccessId': loadingId,
      });
      loadingId = null;
      loadingSlotId = null;
    }
  });
  Future<void> assignPreorder(ResourceViewState state, Json order) => state.run(
    () async {
      final staff = itemsOf(
        await widget.api.get('/api/sellers/${widget.session.sellerId}/staff'),
      );
      final slots = itemsOf(
        await widget.api.get('/api/me/kiosks/${order['kioskId']}/slots'),
      ).where((s) => s['zone'] == 'PREORDER' && s['status'] == 'RENTED_EMPTY');
      if (!mounted) return;
      final form = await askForm(context, 'Giao nạp đơn', [
        InputSpec(
          'assigneeId',
          'Nhân viên',
          choices: {for (final s in staff) '${s['id']}': valueOf(s, 'name')},
        ),
        InputSpec(
          'slotId',
          'Ô PREORDER',
          choices: {for (final s in slots) '${s['id']}': '${s['slotCode']}'},
        ),
        const InputSpec('instructions', 'Hướng dẫn', minLength: 10, lines: 3),
      ]);
      if (form != null) {
        await widget.api.post('$base/$id/assignment', {
          'id': const Uuid().v4(),
          ...form,
        });
      }
    },
  );
}

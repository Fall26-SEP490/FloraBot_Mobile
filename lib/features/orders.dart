import 'dart:async';
import 'preorder_support.dart';
import 'preorder_quote.dart';
import '../ui/inventory_widgets.dart';
import 'flower_advisor.dart';
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
      OutlinedButton.icon(
        onPressed: () async {
          final selected = await openPage<String>(
            context,
            'Gợi ý chọn hoa',
            FlowerAdvisorPage(widget.api),
          );
          if (selected != null && mounted) {
            setState(
              () => search = selected.length > 100
                  ? selected.substring(0, 100)
                  : selected,
            );
          }
        },
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Gợi ý chọn hoa bằng AI'),
      ),
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

class OrdersPage extends StatefulWidget {
  const OrdersPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  String search = '', filter = 'ALL';
  int page = 1;
  bool get seller => widget.session.role == AppRole.seller;
  String get base => seller
      ? '/api/sellers/${widget.session.sellerId}/preorders'
      : '/api/member/preorders';
  bool matches(Json row) => switch (filter) {
    'ATTENTION' =>
      seller
          ? (row['orderStatus'] == null && row['state'] == 'REQUESTED') ||
                (row['orderStatus'] == 'PAID' && row['ready'] != true)
          : (row['state'] == 'QUOTED' && !preorderQuoteExpired(row)) ||
                row['orderStatus'] == 'AWAITING_PAYMENT',
    'PREPARING' => row['orderStatus'] == 'PAID' && row['ready'] != true,
    'READY' => row['orderStatus'] == 'PAID' && row['ready'] == true,
    'CANCELLED' => [
      'CANCELLED',
      'REJECTED',
      'EXPIRED',
    ].contains(preorderState(row)),
    'ALL' => true,
    _ => preorderState(row) == filter,
  };
  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => allPreorders(widget.api, base),
    builder: (context, data, state) {
      final rows = itemsOf(data)
          .where(
            (row) =>
                matches(row) &&
                '${row['orderCode']} ${row['id']} ${row['productName']} ${row['kioskName']}'
                    .toLowerCase()
                    .contains(search.trim().toLowerCase()),
          )
          .toList();
      final pages = ((rows.length + 9) ~/ 10).clamp(1, 1000000);
      final current = page.clamp(1, pages);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            seller ? 'Đơn đặt trước' : 'Đơn đặt của tôi',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: forest,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Mã đơn, tên hoa, kiosk...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() {
                      search = value;
                      page = 1;
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InventoryFilter(
                value: filter,
                options: const {
                  'ALL': 'Tất cả đơn',
                  'ATTENTION': 'Cần xử lý',
                  'REQUESTED': 'Chờ báo giá',
                  'QUOTED': 'Đã báo giá',
                  'AWAITING_PAYMENT': 'Chờ thanh toán',
                  'PREPARING': 'Cần nạp hoa',
                  'READY': 'Sẵn sàng nhận',
                  'COMPLETED': 'Đã nhận hoa',
                  'REFUNDED': 'Đã hoàn tiền',
                  'CANCELLED': 'Đã hủy / hết hạn',
                },
                onChanged: (value) => setState(() {
                  filter = value;
                  page = 1;
                }),
              ),
            ],
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'Không có đơn phù hợp.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF617267)),
              ),
            ),
          for (final row in rows.skip((current - 1) * 10).take(10))
            PreorderCard(
              row,
              seller: seller,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        OrderDetail(widget.api, widget.session, row),
                  ),
                );
                if (context.mounted) await state.reload();
              },
            ),
          if (pages > 1)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: current > 1
                        ? () => setState(() => page = current - 1)
                        : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    child: const Text(
                      'Trang trước',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '$current / $pages',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: forest,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: current < pages
                        ? () => setState(() => page = current + 1)
                        : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    child: const Text(
                      'Trang sau',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
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
  DateTime? loadingExpiresAt;
  String? loadingQr;
  Timer? clock;
  DateTime? nextOtpAt;
  @override
  void initState() {
    super.initState();
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    clock?.cancel();
    super.dispose();
  }

  Future<Json> load() async {
    final order = await findPreorder(
      widget.api,
      base,
      id,
      hint: widget.order['_mobilePage'] as int? ?? 1,
    );
    if (owner && order['orderStatus'] == 'PAID' && order['ready'] != true) {
      try {
        final rows = itemsOf(
          await widget.api.get(
            '/api/sellers/${widget.session.sellerId}/kiosks',
          ),
        );
        return {
          ...order,
          '_kioskStatus': rows
              .where((row) => row['id'] == order['kioskId'])
              .firstOrNull?['status'],
        };
      } on ApiError {
        return {...order, '_kioskStatus': null};
      }
    }
    return order;
  }

  @override
  Widget build(BuildContext context) => ResourceView(
    title: 'Chi tiết đơn đặt trước',
    load: load,
    builder: (context, data, state) {
      final order = objectOf(data);
      final status = preorderState(order);
      final awaitingQuote =
          owner &&
          ['REQUESTED', 'QUOTED'].contains(order['state']) &&
          order['orderId'] == null;
      final needsLoad =
          owner &&
          order['kind'] == 'CUSTOM' &&
          status == 'PAID' &&
          order['ready'] != true;
      final canOtp = owner && preorderCanSendOtp(order);
      final otpCooling = nextOtpAt?.isAfter(DateTime.now()) ?? false;
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
                      preorderCode(order),
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF617267),
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
              const SizedBox(height: 10),
              Text(
                valueOf(order, 'productName', 'Đơn theo mẫu'),
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: forest,
                ),
              ),
              const SizedBox(height: 12),
              InventoryField('Lịch nhận', dateText(order['pickupAt'])),
              InventoryField('Nhận trước', dateText(order['pickupBefore'])),
              if (order['payBefore'] != null && status == 'AWAITING_PAYMENT')
                InventoryField('Hạn trả tiền', dateText(order['payBefore'])),
              if (order['quoteExpiresAt'] != null && order['state'] == 'QUOTED')
                InventoryField(
                  'Hạn báo giá',
                  dateText(order['quoteExpiresAt']),
                ),
              PreorderPackingList(order),
            ],
          ),
          PreorderSection(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 18,
                    color: forest,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      valueOf(order, 'kioskName', 'Điểm nhận hoa'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: forest,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Xem đường đi',
                    onPressed: state.busy
                        ? null
                        : () => state.run(
                            () => navigateAddress(valueOf(order, 'address')),
                          ),
                    icon: const Icon(Icons.open_in_new, size: 18),
                  ),
                ],
              ),
              if (!owner)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    valueOf(order, 'shopName'),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF617267),
                    ),
                  ),
                ),
              Text(
                valueOf(order, 'address', 'Chưa có địa chỉ'),
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFF617267),
                ),
              ),
            ],
          ),
          if ('${order['instructions'] ?? ''}'.trim().isNotEmpty ||
              '${order['quoteNote'] ?? ''}'.trim().isNotEmpty)
            PreorderSection(
              children: [
                if ('${order['instructions'] ?? ''}'.trim().isNotEmpty) ...[
                  const Text(
                    'Yêu cầu của khách',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF617267),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${order['instructions']}',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: forest,
                    ),
                  ),
                ],
                if ('${order['quoteNote'] ?? ''}'.trim().isNotEmpty) ...[
                  if ('${order['instructions'] ?? ''}'.trim().isNotEmpty)
                    const SizedBox(height: 14),
                  const Text(
                    'Ghi chú báo giá',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF617267),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${order['quoteNote']}',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: forest,
                    ),
                  ),
                ],
              ],
            ),
          if (awaitingQuote) ...[
            FilledButton(
              onPressed: state.busy ? null : () => quote(state, order),
              child: Text(
                order['state'] == 'QUOTED' ? 'Chỉnh sửa báo giá' : 'Báo giá',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB42318),
                backgroundColor: const Color(0xFFFFF4F3),
                side: const BorderSide(color: Color(0xFFFECDCA)),
              ),
              onPressed: state.busy
                  ? null
                  : () => quote(state, order, reject: true),
              child: const Text(
                'Từ chối yêu cầu',
                style: TextStyle(color: Color(0xFFB42318)),
              ),
            ),
          ],
          if (needsLoad) ...[
            if (order['_kioskStatus'] != 'ONLINE')
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Kiosk chưa trực tuyến hoặc chưa xác định kết nối. Bạn vẫn có thể giao việc cho nhân viên.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Color(0xFFB42318),
                  ),
                ),
              ),
            FilledButton(
              onPressed: state.busy || order['_kioskStatus'] != 'ONLINE'
                  ? null
                  : () => loadPreorder(state, order),
              child: const Text('Tự nạp hoa'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: state.busy ? null : () => assignPreorder(state, order),
              child: const Text('Giao nhân viên nạp hoa'),
            ),
          ],
          if (status == 'PAID' && order['ready'] == true)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                (DateTime.tryParse(
                          '${order['pickupBefore']}',
                        )?.isBefore(DateTime.now()) ??
                        false)
                    ? 'Đã quá lịch nhận hoa. Cần kiểm tra với khách.'
                    : 'Hoa đã sẵn sàng tại tủ.',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF075985),
                ),
              ),
            ),
          if (canOtp)
            OutlinedButton.icon(
              onPressed: state.busy || otpCooling
                  ? null
                  : () => state.run(() async {
                      if (!await confirm(
                        context,
                        'Gửi mã nhận hoa?',
                        'Mã nhận hoa gửi đến email của khách. Mã cũ có thể hết hiệu lực khi gửi lại.',
                      )) {
                        return;
                      }
                      final result = objectOf(
                        await widget.api.post(
                          '/api/me/preorders/$id/pickup-otp',
                        ),
                      );
                      if (!mounted) return;
                      setState(
                        () => nextOtpAt = DateTime.now().add(
                          Duration(
                            seconds:
                                (result['resendAfterSeconds'] as num? ?? 30)
                                    .toInt(),
                          ),
                        ),
                      );
                      if (context.mounted) {
                        message(
                          context,
                          'Đã tiếp nhận gửi mã đến ${result['recipientMasked'] ?? 'email của khách'}.',
                        );
                      }
                    }),
              icon: const Icon(Icons.mail_outline, size: 18),
              label: Text(
                otpCooling ? 'Chờ trước khi gửi lại mã' : 'Gửi mã nhận hoa',
              ),
            ),
          if (!owner &&
              order['state'] == 'QUOTED' &&
              order['orderId'] == null &&
              !preorderQuoteExpired(order))
            FilledButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      if (!await confirm(
                        context,
                        'Chấp nhận báo giá?',
                        '${money(order['quotedPrice'])}\nLịch nhận: ${dateText(order['pickupAt'])}\n${order['quoteNote'] ?? ''}',
                      )) {
                        return;
                      }
                      await widget.api.post('$base/$id/accept', {
                        'price': order['quotedPrice'],
                        'pickupAt': order['pickupAt'],
                        'note': order['quoteNote'] ?? '',
                        'quoteVersion': order['quoteVersion'],
                      });
                    }),
              child: const Text('Chấp nhận báo giá'),
            ),
          if (!owner && status == 'AWAITING_PAYMENT')
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
                        '${money(link['amount'])}\nNgười nhận: ${link['recipientName'] ?? 'Theo kênh đã xác minh'}',
                      )) {
                        await openSafeLink('${link['checkoutUrl']}');
                      }
                    }),
              icon: const Icon(Icons.qr_code_2, size: 18),
              label: const Text('Thanh toán qua payOS'),
            ),
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
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Biên nhận và hỗ trợ'),
            ),
          if (preorderCanCancel(order, owner) && !awaitingQuote)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB42318),
                  backgroundColor: const Color(0xFFFFF4F3),
                  side: const BorderSide(color: Color(0xFFFECDCA)),
                ),
                onPressed: state.busy ? null : () => cancel(state, order),
                child: const Text(
                  'Hủy đơn',
                  style: TextStyle(color: Color(0xFFB42318)),
                ),
              ),
            ),
        ],
      );
    },
  );

  Future<void> cancel(
    ResourceViewState state,
    Json order,
  ) => state.run(() async {
    final form = await askForm(context, 'Hủy đơn đặt trước', [
      const InputSpec('reason', 'Lý do hủy', minLength: 5, lines: 3),
    ], submitLabel: 'Xem lại yêu cầu hủy');
    if (form == null || !mounted) return;
    if (form['reason']!.trim().length > 1000) {
      throw const ApiError(400, 'Lý do hủy tối đa 1.000 ký tự.');
    }
    if (!await confirm(
      context,
      'Xác nhận hủy đơn?',
      '${form['reason']}\n${order['orderStatus'] == 'PAID' ? 'Đơn đã thanh toán sẽ tạo yêu cầu hoàn tiền để quản trị viên xử lý; tiền chưa được hoàn ngay.' : 'Yêu cầu hủy sẽ được gửi cho hệ thống xử lý.'}',
    )) {
      return;
    }
    await widget.api.post('$base/$id/cancel', {
      'reason': form['reason']!.trim(),
    });
  });
  Future<void> quote(
    ResourceViewState state,
    Json order, {
    bool reject = false,
  }) => state.run(() async {
    if (reject) {
      final form = await askForm(context, 'Từ chối yêu cầu', [
        const InputSpec('note', 'Lý do từ chối', minLength: 5, lines: 3),
      ]);
      if (form == null || !mounted) return;
      if (form['note']!.trim().length > 1000) {
        throw const ApiError(400, 'Lý do tối đa 1.000 ký tự.');
      }
      if (!await confirm(context, 'Từ chối đơn này?', form['note']!)) return;
      await widget.api.post('$base/$id/quote', {
        'price': 0,
        'pickupAt': order['pickupAt'],
        'note': form['note']!.trim(),
        'reject': true,
      });
      return;
    }
    final requested = itemsOf(order['requestedAccessories'] ?? []);
    final catalog = requested.isEmpty
        ? <Json>[]
        : itemsOf(
            await widget.api.get(
              '/api/sellers/${widget.session.sellerId}/accessories?scope=ALL',
            ),
          );
    dynamic initialPrice = order['quotedFlowerPrice'] ?? order['quotedPrice'];
    if (initialPrice == null) {
      final products = itemsOf(await widget.api.get('/api/me/products'));
      initialPrice = products
          .where((p) => p['id'] == order['productId'])
          .firstOrNull?['price'];
    }
    if (!mounted) return;
    final body = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: paper,
      builder: (_) => PreorderQuoteEditor(
        order: order,
        catalog: catalog,
        initialPrice: initialPrice,
        chooseTime: (initial) => choosePickup(context, initial: initial),
      ),
    );
    if (body == null || !mounted) return;
    final total = body.remove('_total');
    if (!await confirm(
      context,
      'Gửi báo giá?',
      'Tổng ${money(total)}\nLịch nhận: ${dateText(body['pickupAt'])}\n${body['note']}',
    )) {
      return;
    }
    await widget.api.post('$base/$id/quote', body);
  });

  List<Json> eligibleSlots(dynamic data, Json order) => itemsOf(data)
      .where(
        (slot) =>
            slot['kioskId'] == order['kioskId'] &&
            slot['zone'] == 'PREORDER' &&
            slot['status'] == 'RENTED_EMPTY' &&
            slot['bouquetId'] == null &&
            slot['sensorReady'] == true,
      )
      .toList();

  Future<void> loadPreorder(
    ResourceViewState state,
    Json order,
  ) => state.run(() async {
    final kiosks = itemsOf(
      await widget.api.get('/api/sellers/${widget.session.sellerId}/kiosks'),
    );
    if (kiosks
            .where((k) => k['id'] == order['kioskId'])
            .firstOrNull?['status'] !=
        'ONLINE') {
      throw const ApiError(
        409,
        'Kiosk chưa trực tuyến. Chưa thể mở ô để nạp hoa.',
      );
    }
    final slots = eligibleSlots(
      await widget.api.get('/api/me/kiosks/${order['kioskId']}/slots'),
      order,
    );
    if (slots.isEmpty) {
      throw const ApiError(
        409,
        'Chưa có ô đặt trước trống và sẵn sàng cảm biến.',
      );
    }
    if (!mounted) return;
    final accessValid =
        loadingId != null &&
        (loadingExpiresAt?.isAfter(DateTime.now()) ?? false);
    final form = await askForm(context, 'Nạp hoa cho đơn', [
      InputSpec(
        'slotId',
        'Ô đặt trước',
        initial: slots.any((s) => s['id'] == loadingSlotId)
            ? loadingSlotId!
            : '',
        choices: {for (final s in slots) '${s['id']}': valueOf(s, 'slotCode')},
      ),
      InputSpec(
        'qrCode',
        'Mã QR trên bó hoa',
        initial: loadingQr ?? '',
        minLength: 2,
      ),
      InputSpec(
        'operation',
        'Thao tác',
        initial: accessValid ? 'FULFILL' : 'OTP',
        choices: const {
          'OTP': '1. Nhận mã và mở ô',
          'FULFILL': '2. Xác nhận đã nạp và đóng cửa',
        },
      ),
    ]);
    if (form == null || !mounted) return;
    loadingQr = form['qrCode']!.trim();
    if (loadingQr!.length > 120 ||
        RegExp(r'[\x00-\x1F\x7F-\x9F]').hasMatch(loadingQr!)) {
      throw const ApiError(400, 'Mã bó hoa quá dài.');
    }
    final canFulfill =
        loadingId != null &&
        loadingSlotId == form['slotId'] &&
        (loadingExpiresAt?.isAfter(DateTime.now()) ?? false);
    if (form['operation'] == 'OTP' || !canFulfill) {
      final sent = objectOf(
        await widget.api.post('/api/me/preorders/$id/loading-access', {
          'slotId': form['slotId'],
        }),
      );
      if (!mounted) return;
      final expiry = DateTime.tryParse('${sent['expiresAt']}');
      if (expiry == null || !expiry.isAfter(DateTime.now())) {
        throw const ApiError(
          409,
          'Quyền nạp hoa đã hết hạn. Yêu cầu mã mở ô mới.',
        );
      }
      final confirmed = sent['requiresCode'] == false
          ? sent
          : await showAccessCode(context, {
              ...sent,
              'message': 'Nhập mã từ email của bạn khi đang ở đúng ô tủ.',
            }, api: widget.api);
      if (confirmed == null || !mounted) return;
      loadingId = '${sent['id']}';
      loadingSlotId = form['slotId'];
      loadingExpiresAt = expiry;
      if (form['operation'] == 'OTP' || sent['requiresCode'] != false) {
        message(
          context,
          'Đặt hoa và phụ kiện vào ô, đóng cửa rồi xác nhận đã nạp.',
        );
        return;
      }
    }
    if (loadingId == null ||
        loadingSlotId != form['slotId'] ||
        !(loadingExpiresAt?.isAfter(DateTime.now()) ?? false)) {
      throw const ApiError(409, 'Quyền nạp đã hết hạn. Yêu cầu mã mở ô mới.');
    }
    if (!mounted) return;
    if (!await confirm(
      context,
      'Xác nhận nạp hoa?',
      'Ô ${slots.firstWhere((s) => s['id'] == form['slotId'])['slotCode']} · $loadingQr\nĐã đặt đúng bó hoa, đủ phụ kiện và đóng cửa ô.',
    )) {
      return;
    }
    await widget.api.post('$base/$id/fulfill', {
      'slotId': form['slotId'],
      'qrCode': loadingQr,
      'loadingAccessId': loadingId,
    });
    loadingId = null;
    loadingSlotId = null;
    loadingExpiresAt = null;
    loadingQr = null;
  });

  Json? pendingAssignment;
  Future<void> assignPreorder(
    ResourceViewState state,
    Json order,
  ) => state.run(() async {
    if (pendingAssignment == null) {
      final staff = itemsOf(
        await widget.api.get('/api/sellers/${widget.session.sellerId}/staff'),
      );
      final slots = eligibleSlots(
        await widget.api.get('/api/me/kiosks/${order['kioskId']}/slots'),
        order,
      );
      if (staff.isEmpty) {
        throw const ApiError(409, 'Chưa có nhân viên đang hoạt động.');
      }
      if (slots.isEmpty) {
        throw const ApiError(
          409,
          'Chưa có ô đặt trước trống và sẵn sàng cảm biến.',
        );
      }
      if (!mounted) return;
      final form = await askForm(context, 'Giao nhân viên nạp hoa', [
        InputSpec(
          'assigneeId',
          'Nhân viên',
          choices: {for (final s in staff) '${s['id']}': valueOf(s, 'name')},
        ),
        InputSpec(
          'slotId',
          'Ô đặt trước',
          choices: {
            for (final s in slots) '${s['id']}': valueOf(s, 'slotCode'),
          },
        ),
        const InputSpec('instructions', 'Hướng dẫn', minLength: 10, lines: 3),
      ]);
      if (form == null || !mounted) return;
      if (form['instructions']!.trim().length > 2000) {
        throw const ApiError(400, 'Hướng dẫn tối đa 2.000 ký tự.');
      }
      if (!await confirm(
        context,
        'Giao nhân viên nạp hoa?',
        '${staff.firstWhere((s) => s['id'] == form['assigneeId'])['name']} · Ô ${slots.firstWhere((s) => s['id'] == form['slotId'])['slotCode']}\n${form['instructions']}',
      )) {
        return;
      }
      pendingAssignment = {'id': const Uuid().v4(), ...form};
    }
    try {
      await widget.api.post('$base/$id/assignment', pendingAssignment!);
      pendingAssignment = null;
      if (mounted) message(context, 'Đã giao nhân viên nạp hoa.');
    } on ApiError catch (e) {
      if ([400, 403, 404, 409].contains(e.status)) pendingAssignment = null;
      rethrow;
    }
  });
}

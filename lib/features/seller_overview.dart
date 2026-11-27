import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';
import 'account.dart';
import 'inventory.dart';
import 'orders.dart';
import 'payment_channel.dart';

bool sellerOrderNeedsAction(Json order) {
  final status = order['orderStatus'] ?? order['state'];
  if ([
        'COMPLETED',
        'CANCELLED',
        'EXPIRED',
        'REFUNDED',
        'REJECTED',
      ].contains(status) ||
      order['state'] == 'REJECTED') {
    return false;
  }
  return (order['orderStatus'] == null && order['state'] == 'REQUESTED') ||
      (order['orderStatus'] == 'PAID' && order['ready'] != true);
}

class SellerOverviewPage extends StatefulWidget {
  const SellerOverviewPage(this.api, this.session, this.navigate, {super.key});
  final ApiClient api;
  final Session session;
  final ValueChanged<int> navigate;
  @override
  State<SellerOverviewPage> createState() => _SellerOverviewPageState();
}

class _SellerOverviewPageState extends State<SellerOverviewPage> {
  final resources = <String, Future<dynamic>>{};
  bool attention = true, refreshing = false;
  late DateTime month;
  String get base => '/api/sellers/${widget.session.sellerId}';
  String get monthValue =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    month = DateTime(now.year, now.month);
    load();
  }

  Future<Json> pages(String path) async {
    final rows = <String, Json>{};
    bool more = false;
    for (var page = 1; page <= 50; page++) {
      final result = objectOf(await widget.api.get('$path?page=$page'));
      final items = itemsOf(result);
      final before = rows.length;
      for (final row in items) {
        rows['${row['id']}'] = row;
      }
      more = result['hasMore'] == true;
      if (!more) break;
      if (rows.length == before) {
        throw const FormatException('Chưa đọc được đầy đủ danh sách.');
      }
    }
    return {'items': rows.values.toList(), 'hasMore': more};
  }

  void load() {
    resources['total'] = widget.api.get('$base/reports/sales');
    resources['month'] = widget.api.get(
      '$base/reports/sales?month=$monthValue',
    );
    resources['orders'] = pages('$base/preorders');
    resources['products'] = widget.api.get('/api/me/products');
    resources['staff'] = widget.api.get('$base/staff/accounts');
    resources['chats'] = pages('$base/chats');
    // Register handlers immediately: sections may finish before their builder mounts.
    for (final future in resources.values) {
      future.ignore();
    }
  }

  Future<void> refresh() async {
    if (refreshing) return;
    setState(() {
      refreshing = true;
      load();
    });
    await Future.wait(
      resources.values.map(
        (future) => future.then<void>((_) {}, onError: (Object _) {}),
      ),
    );
    if (mounted) setState(() => refreshing = false);
  }

  Widget data(String key, Widget Function(dynamic) builder) =>
      FutureBuilder<dynamic>(
        future: resources[key],
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Chưa tải được dữ liệu.',
                      style: TextStyle(color: Color(0xFFB42318)),
                    ),
                  ),
                  TextButton(onPressed: refresh, child: const Text('Thử lại')),
                ],
              ),
            );
          }
          return builder(snapshot.data);
        },
      );

  Widget card(List<Widget> children, {VoidCallback? onTap}) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFDDE6DF)),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );

  Widget heading(String title, String action, VoidCallback onTap) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: forest,
          ),
        ),
      ),
      Flexible(
        child: Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onTap,
            child: Text(action, textAlign: TextAlign.end),
          ),
        ),
      ),
    ],
  );

  Widget shopRow(
    IconData icon,
    String title,
    String value,
    VoidCallback onTap,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: forest, size: 21),
    title: Text(title, style: const TextStyle(fontSize: 15)),
    subtitle: Text(
      value,
      style: const TextStyle(color: forest, fontWeight: FontWeight.w600),
    ),
    trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF718478)),
    onTap: onTap,
  );

  void moveMonth(int offset) {
    setState(() {
      month = DateTime(month.year, month.month + offset);
      resources['month'] = widget.api.get(
        '$base/reports/sales?month=$monthValue',
      );
      resources['month']!.ignore();
    });
  }

  Future<void> showPage(
    BuildContext pageContext,
    String title,
    Widget child,
  ) async {
    await openPage(pageContext, title, child);
    if (mounted) await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (refreshing) const LinearProgressIndicator(),
          card(
            [
              const Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tổng doanh thu',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: forest,
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Icon(Icons.chevron_right_rounded, color: forest),
                ],
              ),
              const SizedBox(height: 12),
              data('total', (value) {
                final report = objectOf(value);
                return Text(
                  report['grossPaid'] == null
                      ? 'Chưa có số liệu'
                      : money(report['grossPaid']),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: forest,
                  ),
                );
              }),
            ],
            onTap: () => showPage(
              context,
              'Tổng doanh thu',
              PaymentChannelPage(
                widget.api,
                widget.session,
                startWithTransactions: true,
              ),
            ),
          ),
          const SizedBox(height: 14),
          card([
            Row(
              children: [
                IconButton(
                  tooltip: 'Tháng trước',
                  onPressed: () => moveMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    'Tháng ${month.month}/${month.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: forest,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tháng sau',
                  onPressed: month.year == now.year && month.month == now.month
                      ? null
                      : () => moveMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            data('month', (value) {
              final report = objectOf(value);
              final kiosks = (report['byKiosk'] as List? ?? [])
                  .map(objectOf)
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    report['grossPaid'] == null
                        ? 'Chưa có số liệu'
                        : money(report['grossPaid']),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: forest,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${report['paidOrders'] ?? '—'} đơn đã thanh toán',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF617267),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: const Text(
                      'Doanh thu từng kiosk',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: forest,
                      ),
                    ),
                    children: [
                      if (kiosks.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Chưa có doanh thu theo kiosk trong tháng này.',
                          ),
                        ),
                      for (final kiosk in kiosks)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  valueOf(kiosk, 'kioskName', 'Kiosk'),
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  money(kiosk['grossPaid']),
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: forest,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              );
            }),
          ]),
          const SizedBox(height: 16),
          card([
            heading('Đơn cần theo dõi', 'Tất cả đơn', () => widget.navigate(2)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Cần xử lý'),
                  selected: attention,
                  onSelected: (_) => setState(() => attention = true),
                ),
                ChoiceChip(
                  label: const Text('Gần đây'),
                  selected: !attention,
                  onSelected: (_) => setState(() => attention = false),
                ),
              ],
            ),
            const SizedBox(height: 8),
            data('orders', (value) {
              final page = objectOf(value);
              final rows = itemsOf(page)
                  .where((row) => !attention || sellerOrderNeedsAction(row))
                  .take(5)
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        attention
                            ? 'Không có đơn cần xử lý${page['hasMore'] == true ? ' trong các trang đã tải' : ''}.'
                            : 'Chưa có đơn đặt trước.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF617267)),
                      ),
                    ),
                  for (final order in rows)
                    _OrderSummary(
                      order: order,
                      onTap: () => showPage(
                        context,
                        'Chi tiết đơn',
                        OrderDetail(widget.api, widget.session, order),
                      ),
                    ),
                  if (page['hasMore'] == true)
                    const Text(
                      'Danh sách chưa tải hết. Mở Tất cả đơn để xem thêm.',
                      style: TextStyle(fontSize: 14, color: Color(0xFF617267)),
                    ),
                ],
              );
            }),
          ]),
          const SizedBox(height: 16),
          card([
            const Text(
              'Cửa hàng của tôi',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: forest,
              ),
            ),
            const SizedBox(height: 8),
            data('staff', (value) {
              final rows = itemsOf(value);
              return shopRow(
                Icons.people_outline,
                'Nhân viên hoạt động',
                '${rows.where((row) => row['status'] == 'ACTIVE').length}/${rows.length}',
                () => showPage(
                  context,
                  'Nhân viên shop',
                  StaffManagementPage(widget.api, widget.session),
                ),
              );
            }),
            data('products', (value) {
              final rows = itemsOf(value);
              return shopRow(
                Icons.local_florist_outlined,
                'Mẫu hoa đang bán',
                '${rows.where((row) => row['status'] == 'ACTIVE').length}/${rows.length}',
                () => showPage(
                  context,
                  'Mẫu hoa',
                  ProductsPage(widget.api, widget.session),
                ),
              );
            }),
            shopRow(
              Icons.storefront_outlined,
              'Trạng thái cửa hàng',
              widget.session.sellerStatus == null
                  ? 'Chưa xác định'
                  : statusText(widget.session.sellerStatus),
              () =>
                  showPage(context, 'Hồ sơ shop', ShopProfilePage(widget.api)),
            ),
            data('chats', (value) {
              final page = objectOf(value);
              final count = itemsOf(page)
                  .where(
                    (row) => (num.tryParse('${row['unreadCount']}') ?? 0) > 0,
                  )
                  .length;
              return shopRow(
                Icons.chat_bubble_outline,
                'Tin nhắn khách hàng',
                '$count${page['hasMore'] == true ? '+' : ''} hội thoại chưa đọc',
                () => widget.navigate(3),
              );
            }),
          ]),
        ],
      ),
    );
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.order, required this.onTap});
  final Json order;
  final VoidCallback onTap;

  (String, Color) get state {
    final status = order['orderStatus'] ?? order['state'];
    if ([
      'CANCELLED',
      'EXPIRED',
      'REJECTED',
      'DISPENSE_FAILED',
    ].contains(status)) {
      return (statusText(status), const Color(0xFFB42318));
    }
    if (status == 'COMPLETED' || status == 'REFUNDED') {
      return (statusText(status), forest);
    }
    if (status == 'PAID') {
      return (
        order['ready'] == true ? 'Chờ khách nhận' : 'Cần nạp hoa',
        const Color(0xFF075985),
      );
    }
    if (status == 'REQUESTED') {
      return ('Cần báo giá', const Color(0xFF925B0A));
    }
    return (statusText(status), const Color(0xFF925B0A));
  }

  Widget detail(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(icon, size: 14, color: const Color(0xFF617267)),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Color(0xFF52685B),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final (label, color) = state;
    final id = '${order['id'] ?? ''}';
    final code = valueOf(
      order,
      'orderCode',
      '#${id.substring(0, id.length.clamp(0, 8))}',
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: forest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 112,
                    child: Text(
                      label,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                valueOf(order, 'productName', 'Hoa theo yêu cầu'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF203E2D),
                ),
              ),
              const SizedBox(height: 9),
              detail(
                Icons.location_on_outlined,
                valueOf(order, 'kioskName', 'Chưa có kiosk'),
              ),
              const SizedBox(height: 5),
              detail(
                Icons.schedule_outlined,
                'Nhận: ${dateText(order['pickupAt'])}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

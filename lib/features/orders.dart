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
import '../ui/customer_flower_card.dart';
import 'customer_catalog_filters.dart';
import 'customer_preorder_form.dart';

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

typedef PendingFlowerOrder = ({Json item, List<Json> rows});

class CatalogPage extends StatefulWidget {
  const CatalogPage(
    this.api,
    this.session, {
    this.onOpenOrders,
    this.onGuestOrder,
    this.onGuestChat,
    this.pendingOrder,
    this.pendingChat,
    this.onPendingConsumed,
    super.key,
  });
  final ApiClient api;
  final Session? session;
  final VoidCallback? onOpenOrders;
  final Future<void> Function(BuildContext, Json, List<Json>)? onGuestOrder;
  final Future<void> Function(BuildContext, Json)? onGuestChat;
  final PendingFlowerOrder? pendingOrder;
  final Json? pendingChat;
  final VoidCallback? onPendingConsumed;
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final _resourceKey = GlobalKey<ResourceViewState>();
  String search = '';
  final overviewSearch = TextEditingController();
  CustomerCatalogFilters filters = const CustomerCatalogFilters();
  int visibleFlowers = 6;
  bool _pendingHandled = false;

  @override
  void initState() {
    super.initState();
    _resumePendingIfNeeded();
  }

  void _resumePendingIfNeeded() {
    if (_pendingHandled || widget.session == null) return;
    final pendingOrder = widget.pendingOrder;
    final pendingChat = widget.pendingChat;
    if (pendingOrder == null && pendingChat == null) return;
    _pendingHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      widget.onPendingConsumed?.call();
      if (!mounted) return;
      if (pendingOrder != null) {
        await _openPreorder(pendingOrder.item, rows: pendingOrder.rows);
      } else if (pendingChat != null) {
        final sellerId = '${pendingChat['sellerId'] ?? ''}';
        if (sellerId.isNotEmpty) {
          await openCustomerChat(
            context,
            widget.api,
            sellerId,
            productId: '${pendingChat['productId'] ?? ''}',
          );
        }
      }
    });
  }

  @override
  void dispose() {
    overviewSearch.dispose();
    super.dispose();
  }

  Future<dynamic> loadOverview() async {
    final flowers = <Json>[];
    var page = 1;
    while (mounted) {
      final result = await widget.api.get('/api/shop/catalog?page=$page');
      final rows = itemsOf(result);
      flowers.addAll(rows);
      if (result is! Map || result['hasMore'] != true || rows.isEmpty) break;
      page++;
    }
    return {'items': flowers, 'hasMore': false};
  }

  Future<void> openFilters(List<Json> rows) async {
    final selected = await showCustomerCatalogFilters(context, rows, filters);
    if (selected != null && mounted) {
      setState(() {
        filters = selected.filters;
        if (selected.clearSearch) {
          search = '';
          overviewSearch.clear();
        }
        visibleFlowers = 6;
      });
    }
  }

  Future<void> preview(
    ResourceViewState state,
    Json row,
    List<Json> rows,
  ) async {
    final sellerId = '${row['sellerId'] ?? ''}';
    final order = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (detailContext) => CustomerFlowerDetail(
          item: row,
          onChat: sellerId.isEmpty
              ? null
              : () {
                  if (widget.session == null) {
                    widget.onGuestChat?.call(detailContext, row);
                  } else {
                    openCustomerChat(
                      detailContext,
                      widget.api,
                      sellerId,
                      productId: '${row['productId'] ?? ''}',
                    );
                  }
                },
        ),
      ),
    );
    if (order == true && mounted) await book(state, row, rows: rows);
  }

  Future<void> openAdvisor() async {
    final selected = await openPage<String>(
      context,
      'Gợi ý chọn hoa',
      FlowerAdvisorPage(widget.api),
    );
    if (selected != null && mounted) {
      final query = selected.length > 100
          ? selected.substring(0, 100)
          : selected;
      setState(() {
        search = query.trim();
        overviewSearch.text = search;
        visibleFlowers = 6;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ResourceView(
    key: _resourceKey,
    resourceKey: 'customer-overview-all',
    load: loadOverview,
    builder: (context, data, state) {
      final rows = itemsOf(data);
      final matching = filterCustomerFlowers(rows, filters, search);
      final flowers = matching.take(visibleFlowers).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    controller: overviewSearch,
                    style: const TextStyle(fontSize: 14),
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Tìm hoa hoặc shop',
                      prefixIcon: Icon(Icons.search_rounded, size: 21),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                    onChanged: (value) => setState(() {
                      search = value.trim();
                      visibleFlowers = 6;
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  tooltip: 'Gợi ý chọn hoa bằng AI',
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(10),
                    backgroundColor: Colors.white,
                    foregroundColor: forest,
                    side: const BorderSide(color: Color(0xFFD4E0D4)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: state.busy ? null : openAdvisor,
                  icon: const Icon(Icons.auto_awesome, size: 21),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  tooltip: 'Bộ lọc',
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(10),
                    backgroundColor: Colors.white,
                    foregroundColor: forest,
                    side: const BorderSide(color: Color(0xFFD4E0D4)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: state.busy ? null : () => openFilters(rows),
                  icon: Icon(
                    filters.active
                        ? Icons.filter_alt_rounded
                        : Icons.filter_list,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (flowers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                search.isEmpty && !filters.active
                    ? 'Chưa có mẫu hoa nào.'
                    : 'Không tìm thấy mẫu hoa phù hợp.',
                textAlign: TextAlign.center,
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 700 ? 3 : 2;
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final row in flowers)
                      SizedBox(
                        width: width,
                        child: CustomerFlowerCard(
                          item: row,
                          onOpen: state.busy
                              ? null
                              : () => preview(state, row, rows),
                          onOrder: state.busy || !canCustomerPreorder(row)
                              ? null
                              : () => book(state, row, rows: rows),
                        ),
                      ),
                  ],
                );
              },
            ),
          if (matching.length > visibleFlowers) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: state.busy
                  ? null
                  : () => setState(() => visibleFlowers += 6),
              child: const Text('Xem thêm mẫu hoa'),
            ),
          ],
        ],
      );
    },
  );
  Future<void> _openPreorder(
    Json row, {
    List<Json> rows = const [],
    ResourceViewState? state,
  }) async {
    final result = await openCustomerPreorderForm(
      context,
      api: widget.api,
      item: row,
      catalogRows: rows,
    );
    if (!mounted || result == null) return;
    if (result == CustomerPreorderResult.viewOrders) {
      if (widget.onOpenOrders != null) {
        widget.onOpenOrders!();
      } else {
        message(context, 'Đã gửi yêu cầu. Xem báo giá tại mục Đơn đặt.');
      }
      return;
    }
    await (state ?? _resourceKey.currentState)?.reload();
  }

  Future<void> book(
    ResourceViewState state,
    Json row, {
    List<Json> rows = const [],
  }) async {
    if (widget.session == null) {
      await widget.onGuestOrder?.call(context, row, rows);
      return;
    }
    await _openPreorder(row, rows: rows, state: state);
  }
}

class OrdersPage extends StatefulWidget {
  const OrdersPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final searchInput = TextEditingController();
  String search = '', filter = 'ALL';
  int page = 1;
  bool get seller => widget.session.role == AppRole.seller;
  String get base => seller
      ? '/api/sellers/${widget.session.sellerId}/preorders'
      : '/api/member/preorders';

  @override
  void dispose() {
    searchInput.dispose();
    super.dispose();
  }

  List<(String, String)> get _filters => seller
      ? const [
          ('ALL', 'Tất cả'),
          ('ATTENTION', 'Cần xử lý'),
          ('QUOTED', 'Chờ khách'),
          ('READY', 'Tại tủ'),
          ('COMPLETED', 'Hoàn tất'),
          ('CANCELLED', 'Hủy / Hết hạn'),
        ]
      : const [
          ('ALL', 'Tất cả'),
          ('ATTENTION', 'Cần xử lý'),
          ('TRACKING', 'Đang theo dõi'),
          ('READY', 'Nhận tại tủ'),
          ('COMPLETED', 'Hoàn tất'),
          ('CANCELLED', 'Hủy / Hết hạn'),
        ];

  bool matchesFilter(Json row, String code) => switch (code) {
    'ATTENTION' => preorderNeedsAttention(row, seller: seller),
    'TRACKING' =>
      !preorderClosed(row) && !preorderNeedsAttention(row, seller: seller),
    'QUOTED' =>
      (row['orderStatus'] == null &&
              row['state'] == 'QUOTED' &&
              !preorderQuoteExpired(row)) ||
          row['orderStatus'] == 'AWAITING_PAYMENT',
    'READY' => row['orderStatus'] == 'PAID' && row['ready'] == true,
    'COMPLETED' => ['COMPLETED', 'REFUNDED'].contains(preorderState(row)),
    'CANCELLED' =>
      ['CANCELLED', 'REJECTED', 'EXPIRED'].contains(preorderState(row)) ||
          (row['orderStatus'] == null &&
              row['state'] == 'QUOTED' &&
              preorderQuoteExpired(row)),
    'ALL' => true,
    _ => preorderState(row) == code,
  };

  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => allPreorders(widget.api, base),
    builder: (context, data, state) {
      final allRows = itemsOf(data);
      final query = normalizeOrderQuery(search);
      final rows = allRows
          .where(
            (row) =>
                matchesFilter(row, filter) &&
                (query.isEmpty ||
                    normalizeOrderQuery(
                      '${row['orderCode']} ${row['id']} ${row['productName']} ${row['shopName']} ${row['kioskName']} ${row['address']}',
                    ).contains(query)),
          )
          .toList();
      final pages = ((rows.length + 9) ~/ 10).clamp(1, 1000000);
      final current = page.clamp(1, pages);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  seller ? 'Đơn đặt trước' : 'Đơn đặt của tôi',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: forest,
                  ),
                ),
              ),
              if (allRows.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF3EC),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${allRows.length} đơn',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: forest,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 44,
            child: TextField(
              controller: searchInput,
              style: const TextStyle(fontSize: 14),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: seller
                    ? 'Tìm mã đơn, tên hoa, tủ...'
                    : 'Tìm mã đơn, tên hoa, shop, tủ...',
                prefixIcon: const Icon(Icons.search_rounded, size: 21),
                suffixIcon: search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Xóa tìm kiếm',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          searchInput.clear();
                          search = '';
                          page = 1;
                        }),
                      ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
              ),
              onChanged: (value) => setState(() {
                search = value;
                page = 1;
              }),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < _filters.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Builder(
                    builder: (_) {
                      final (code, label) = _filters[i];
                      final selected = filter == code;
                      final count = code == 'ALL'
                          ? allRows.length
                          : allRows
                                .where((row) => matchesFilter(row, code))
                                .length;
                      final text = code == 'ALL' || count == 0
                          ? label
                          : '$label ($count)';
                      return ChoiceChip(
                        label: Text(text),
                        selected: selected,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        selectedColor: const Color(0xFFE4EFE8),
                        backgroundColor: Colors.white,
                        side: BorderSide(
                          color: selected
                              ? forest
                              : code == 'ATTENTION' && count > 0
                              ? const Color(0xFFF3C677)
                              : const Color(0xFFD6E1D8),
                        ),
                        labelStyle: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              selected || (code == 'ATTENTION' && count > 0)
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? forest
                              : code == 'ATTENTION' && count > 0
                              ? const Color(0xFF925B0A)
                              : const Color(0xFF476451),
                        ),
                        onSelected: (_) => setState(() {
                          filter = code;
                          page = 1;
                        }),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 40,
                    color: Color(0xFF9BB0A3),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    allRows.isEmpty
                        ? 'Chưa có đơn đặt nào.'
                        : 'Không có đơn phù hợp.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF617267),
                    ),
                  ),
                  if (filter != 'ALL' || search.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => setState(() {
                        filter = 'ALL';
                        search = '';
                        searchInput.clear();
                        page = 1;
                      }),
                      child: const Text('Xem tất cả đơn'),
                    ),
                  ],
                ],
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
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: PreorderStatus(order, seller: owner),
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
              PreorderStepper(order),
              const SizedBox(height: 12),
              InventoryField('Lịch nhận', dateText(order['pickupAt'])),
              if (order['pickupBefore'] != null)
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
          if (!owner && status == 'PAID' && order['ready'] != true)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Shop đang chuẩn bị hoa.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF075985),
                ),
              ),
            ),
          if (status == 'PAID' && order['ready'] == true)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                (DateTime.tryParse(
                          '${order['pickupBefore']}',
                        )?.isBefore(DateTime.now()) ??
                        false)
                    ? 'Đã quá lịch nhận hoa. Cần kiểm tra với khách.'
                    : owner
                    ? 'Hoa đã sẵn sàng tại tủ.'
                    : 'Hoa đã sẵn sàng tại tủ. Dùng mã OTP trong email để nhận.',
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
          if (!owner && '${order['sellerId'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: state.busy
                    ? null
                    : () => openCustomerChat(
                        context,
                        widget.api,
                        '${order['sellerId']}',
                        productId: '${order['productId'] ?? ''}'.isEmpty
                            ? null
                            : '${order['productId']}',
                      ),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Nhắn shop'),
              ),
            ),
          if (!owner &&
              order['orderId'] != null &&
              order['trackingToken'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
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

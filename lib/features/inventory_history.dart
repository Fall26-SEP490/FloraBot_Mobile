import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/inventory_widgets.dart';

class InventoryHistoryPage extends StatefulWidget {
  const InventoryHistoryPage(this.api, this.kioskId, {super.key});
  final ApiClient api;
  final String kioskId;
  @override
  State<InventoryHistoryPage> createState() => _InventoryHistoryPageState();
}

class _InventoryHistoryPageState extends State<InventoryHistoryPage> {
  final scroll = ScrollController();
  List<Json> items = [];
  int page = 0, generation = 0;
  bool loading = false, hasMore = true, retryReset = false;
  Object? error;

  @override
  void initState() {
    super.initState();
    scroll.addListener(loadNearEnd);
    unawaited(fetch(reset: true));
  }

  @override
  void didUpdateWidget(InventoryHistoryPage old) {
    super.didUpdateWidget(old);
    if (old.kioskId != widget.kioskId || old.api != widget.api) {
      items = [];
      unawaited(fetch(reset: true));
    }
  }

  @override
  void dispose() {
    generation++;
    scroll.dispose();
    super.dispose();
  }

  void loadNearEnd() {
    if (mounted &&
        scroll.hasClients &&
        scroll.position.extentAfter < 240 &&
        !loading &&
        error == null &&
        hasMore) {
      unawaited(fetch());
    }
  }

  String eventKey(Json row) =>
      '${row['seq'] ?? '${row['createdAt']}:${row['movementType']}:${row['slotCode']}:${row['bouquetId']}:${row['orderId']}'}';

  Future<void> fetch({bool reset = false}) async {
    if (!reset && (loading || !hasMore)) return;
    final epoch = reset ? ++generation : generation;
    final nextPage = reset ? 1 : page + 1;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = objectOf(
        await widget.api.get(
          '/api/me/inventory-history?kioskId=${Uri.encodeComponent(widget.kioskId)}&page=$nextPage',
        ),
      );
      if (!mounted || epoch != generation) return;
      final incoming = itemsOf(result);
      final seen = reset ? <String>{} : items.map(eventKey).toSet();
      final fresh = incoming.where((row) => seen.add(eventKey(row))).toList();
      setState(() {
        items = reset ? fresh : [...items, ...fresh];
        page = nextPage;
        hasMore = result['hasMore'] == true && fresh.isNotEmpty;
      });
      if (reset && scroll.hasClients) scroll.jumpTo(0);
    } catch (e) {
      if (!mounted || epoch != generation) return;
      setState(() {
        error = e;
        retryReset = reset;
      });
    } finally {
      if (mounted && epoch == generation) {
        setState(() => loading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) => loadNearEnd());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: () => fetch(reset: true),
      child: ListView.builder(
        controller: scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: items.length + 1,
        itemBuilder: (context, index) {
          if (index < items.length) return _HistoryEntry(items[index]);
          if (loading) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          if (error != null) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Text(
                    items.isEmpty
                        ? 'Chưa tải được lịch sử.'
                        : retryReset
                        ? 'Chưa làm mới được lịch sử.'
                        : 'Chưa tải thêm được lịch sử.',
                    style: const TextStyle(color: Color(0xFFB42318)),
                  ),
                  TextButton(
                    onPressed: () => fetch(reset: retryReset),
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            );
          }
          if (items.isEmpty) {
            return SizedBox(
              height: MediaQuery.sizeOf(context).height * .6,
              child: const Center(
                child: Text(
                  'Chưa có lịch sử tại tủ.',
                  style: TextStyle(color: Color(0xFF617267)),
                ),
              ),
            );
          }
          return const SizedBox(height: 8);
        },
      ),
    );
  }
}

class _HistoryEntry extends StatelessWidget {
  const _HistoryEntry(this.row);
  final Json row;
  static const labels = {
    'STOCK_IN': 'Nạp hoa',
    'HOLD': 'Giữ hoa',
    'RELEASE': 'Hủy giữ hoa',
    'SALE_OUT': 'Đã bán',
    'EXPIRE_OUT': 'Hoa hết hạn bán',
    'DAMAGE': 'Hoa hỏng',
    'RETURN_SELLER': 'Trả hoa về shop',
  };
  @override
  Widget build(BuildContext context) {
    final movement = row['movementType'];
    final color = ['DAMAGE', 'EXPIRE_OUT'].contains(movement)
        ? const Color(0xFFB42318)
        : movement == 'HOLD'
        ? const Color(0xFF925B0A)
        : movement == 'SALE_OUT'
        ? const Color(0xFF075985)
        : forest;
    final actor = row['performedBy'] == '10000000-0000-0000-0000-0000000000ff'
        ? 'Tự động'
        : valueOf(row, 'actorName', 'Không ghi nhận');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE6DF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              switch (movement) {
                'STOCK_IN' => Icons.add_circle_outline,
                'SALE_OUT' => Icons.shopping_bag_outlined,
                'HOLD' => Icons.lock_outline,
                'RELEASE' => Icons.lock_open,
                'DAMAGE' || 'EXPIRE_OUT' => Icons.error_outline,
                _ => Icons.swap_horiz,
              },
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        labels[movement] ?? 'Thay đổi tồn kho',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Ô ${row['slotCode'] ?? '—'}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: forest,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  dateText(row['createdAt']),
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: Color(0xFF617267),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    actor,
                    if (row['orderCode'] != null) 'Đơn ${row['orderCode']}',
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: forest,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SlotLayoutPage extends StatefulWidget {
  const SlotLayoutPage(this.api, this.kioskId, this.slots, {super.key});
  final ApiClient api;
  final String kioskId;
  final List<Json> slots;
  @override
  State<SlotLayoutPage> createState() => _SlotLayoutPageState();
}

class _SlotLayoutPageState extends State<SlotLayoutPage> {
  final form = GlobalKey<FormState>();
  final reason = TextEditingController();
  int? desiredWalk;
  String? original;
  int visibleHistory = 5;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ResourceView(
    load: () async {
      final requests = await widget.api.get(
        '/api/me/kiosks/${widget.kioskId}/layout-requests',
      );
      final slots = await widget.api.get(
        '/api/me/kiosks/${widget.kioskId}/slots',
      );
      return {'requests': requests, 'slots': slots};
    },
    builder: (context, data, state) {
      final payload = objectOf(data);
      final requests = itemsOf(payload['requests']);
      final slots = itemsOf(payload['slots']);
      final pending = requests.any(
        (row) => ['PENDING', 'APPLYING'].contains(row['status']),
      );
      final walk = slots.where((row) => row['zone'] == 'WALK_IN').length;
      final pre = slots.where((row) => row['zone'] == 'PREORDER').length;
      final signature = '${slots.length}:$walk:$pre';
      if (signature != original) {
        original = signature;
        desiredWalk = walk;
      }
      final target = desiredWalk ?? walk;
      final validLayout = slots.isNotEmpty && walk + pre == slots.length;
      final editable = validLayout && !pending && !state.busy;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDDE6DF)),
            ),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Số ô sau khi đổi',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: forest,
                          ),
                        ),
                      ),
                      Text(
                        'Tổng ${slots.length} ô',
                        style: const TextStyle(
                          fontSize: 13,
                          color: forest,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hiện tại: $walk tại chỗ · $pre đặt trước',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Color(0xFF617267),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _LayoutCounter(
                    label: 'Tại chỗ',
                    value: target,
                    decrease: editable && target > 0
                        ? () => setState(() => desiredWalk = target - 1)
                        : null,
                    increase: editable && target < slots.length
                        ? () => setState(() => desiredWalk = target + 1)
                        : null,
                  ),
                  const SizedBox(height: 14),
                  _LayoutCounter(
                    label: 'Đặt trước',
                    value: slots.length - target,
                    decrease: editable && target < slots.length
                        ? () => setState(() => desiredWalk = target + 1)
                        : null,
                    increase: editable && target > 0
                        ? () => setState(() => desiredWalk = target - 1)
                        : null,
                  ),
                  if (target != walk)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        target < walk
                            ? 'Chuyển ${walk - target} ô tại chỗ sang đặt trước.'
                            : 'Chuyển ${target - walk} ô đặt trước sang tại chỗ.',
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: forest,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (pending)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Đang có yêu cầu chờ duyệt.',
                        style: TextStyle(
                          color: Color(0xFF925B0A),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  if (!validLayout)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Chưa đủ thông tin cơ cấu ô để gửi yêu cầu.',
                        style: TextStyle(
                          color: Color(0xFFB42318),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  if (!pending && validLayout) ...[
                    const SizedBox(height: 24),
                    const Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Lý do ',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: forest,
                            ),
                          ),
                          TextSpan(
                            text: '*',
                            style: TextStyle(color: Color(0xFFB42318)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: reason,
                      enabled: !state.busy,
                      minLines: 2,
                      maxLines: 3,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        hintText: 'Nhập lý do thay đổi',
                        counterText: '',
                      ),
                      validator: (value) => (value ?? '').trim().length < 5
                          ? 'Nhập lý do từ 5 ký tự.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: !editable || target == walk
                          ? null
                          : () {
                              if (form.currentState?.validate() != true) return;
                              state.run(() async {
                                if (!await confirm(
                                  context,
                                  'Gửi yêu cầu đổi loại ô?',
                                  '$target ô tại chỗ · ${slots.length - target} ô đặt trước',
                                )) {
                                  return;
                                }
                                await widget.api.post(
                                  '/api/me/kiosks/${widget.kioskId}/layout-requests',
                                  {
                                    'walkInSlots': target,
                                    'preorderSlots': slots.length - target,
                                    'reason': reason.text.trim(),
                                  },
                                );
                                if (!context.mounted) return;
                                reason.clear();
                                message(context, 'Đã gửi yêu cầu đổi loại ô.');
                              });
                            },
                      child: const Text('Gửi yêu cầu'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Lịch sử yêu cầu',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: forest,
                  ),
                ),
              ),
              if (requests.isEmpty)
                const Text(
                  'Chưa có',
                  style: TextStyle(fontSize: 12, color: Color(0xFF617267)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (final row in requests.take(visibleHistory))
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE6DF)),
              ),
              child: ExpansionTile(
                key: ValueKey(
                  row['id'] ?? '${row['createdAt']}:${row['status']}',
                ),
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${row['walkInSlots']} tại chỗ · ${row['preorderSlots']} đặt trước',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: forest,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(child: InventoryStatus('${row['status']}')),
                  ],
                ),
                subtitle: Text(
                  dateText(row['createdAt']),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF617267),
                  ),
                ),
                children: [
                  InventoryField('Lý do', valueOf(row, 'reason')),
                  if (row['reviewNote'] != null)
                    InventoryField('Phản hồi', '${row['reviewNote']}'),
                ],
              ),
            ),
          if (requests.length > visibleHistory)
            TextButton(
              onPressed: () => setState(() => visibleHistory += 5),
              child: const Text('Xem thêm yêu cầu'),
            ),
        ],
      );
    },
  );
}

class _LayoutCounter extends StatelessWidget {
  const _LayoutCounter({
    required this.label,
    required this.value,
    this.decrease,
    this.increase,
  });
  final String label;
  final int value;
  final VoidCallback? decrease, increase;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: forest,
          ),
        ),
      ),
      SizedBox(
        width: 36,
        height: 36,
        child: IconButton.outlined(
          tooltip: 'Giảm ô $label',
          onPressed: decrease,
          icon: const Icon(Icons.remove, size: 18),
          style: IconButton.styleFrom(
            foregroundColor: forest,
            padding: EdgeInsets.zero,
            minimumSize: const Size(36, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
      SizedBox(
        width: 40,
        child: Text(
          '$value',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: forest,
          ),
        ),
      ),
      SizedBox(
        width: 36,
        height: 36,
        child: IconButton.filled(
          tooltip: 'Tăng ô $label',
          onPressed: increase,
          icon: const Icon(Icons.add, size: 18),
          style: IconButton.styleFrom(
            backgroundColor: forest,
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            minimumSize: const Size(36, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    ],
  );
}

export 'refunds.dart' show SellerRefundsPage, SellerRefundDetail;
export 'complaints.dart' show ComplaintsPage, ComplaintDetail;
export 'payment_channel.dart' show PaymentChannelPage;
import '../ui/catalog_widgets.dart';
import 'inventory.dart' show integerInput, openPage;
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';

class AccessoriesPage extends StatefulWidget {
  const AccessoriesPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  State<AccessoriesPage> createState() => _AccessoriesPageState();
}

class _AccessoriesPageState extends State<AccessoriesPage> {
  ApiClient get api => widget.api;
  String get base => '/api/sellers/${widget.session.sellerId}/accessories';
  String query = '', filter = 'ALL';
  final uncertainRestocks = <String>{};

  Future<void> edit(BuildContext context, Json? item) async {
    final body = await showCatalogEditor(context, item: item, accessory: true);
    if (body == null) return;
    if (item == null) {
      await api.post(base, body);
    } else {
      await api.put('$base/${item['id']}', body);
    }
  }

  bool matches(Json item) =>
      (filter == 'ALL' || item['status'] == filter) &&
      valueOf(item, 'name').toLowerCase().contains(query.trim().toLowerCase());

  Future<void> detail(Json row, ResourceViewState listState) async {
    await openPage(
      context,
      'Chi tiết phụ kiện',
      ResourceView(
        load: () => api.get('$base?scope=SHOP'),
        builder: (context, data, state) {
          final item = itemsOf(
            data,
          ).where((r) => r['id'] == row['id']).firstOrNull;
          if (item == null) return const Text('Phụ kiện không còn khả dụng.');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusHeading(
                        title: Text(
                          valueOf(item, 'name'),
                          style: const TextStyle(
                            fontSize: 21,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                            color: forest,
                          ),
                        ),
                        status: CatalogStatus(valueOf(item, 'status')),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Giá bán',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF617568),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  money(item['price']),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: forest,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Tồn tại shop',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF617568),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${item['stockQuantity'] ?? 0}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: forest,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: state.busy
                    ? null
                    : () => state.run(() => edit(context, item)),
                icon: const Icon(Icons.edit_outlined, size: 19),
                label: const Text('Chỉnh sửa phụ kiện'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed:
                    state.busy || uncertainRestocks.contains('${item['id']}')
                    ? null
                    : () => state.run(() async {
                        final form = await askForm(context, 'Bổ sung tồn kho', [
                          const InputSpec(
                            'quantity',
                            'Số lượng thêm',
                            numeric: true,
                          ),
                        ], submitLabel: 'Kiểm tra số lượng');
                        if (form == null || !context.mounted) return;
                        final qty = integerInput(form['quantity']);
                        final current =
                            (item['stockQuantity'] as num?)?.toInt() ?? 0;
                        if (qty > 2147483647 || current + qty > 2147483647) {
                          throw const ApiError(
                            400,
                            'Số lượng tồn vượt giới hạn cho phép.',
                          );
                        }
                        if (!await confirm(
                          context,
                          'Xác nhận nhập kho?',
                          '${item['name']}: $current + $qty = ${current + qty}.',
                        )) {
                          return;
                        }
                        try {
                          await api.post(
                            '/api/sellers/${widget.session.sellerId}/flows/restock_accessory',
                            {'p_accessory': item['id'], 'p_qty': qty},
                          );
                        } on ApiError catch (error) {
                          if (error.ambiguous ||
                              error.status == 0 ||
                              error.status >= 500) {
                            uncertainRestocks.add('${item['id']}');
                            throw const ApiError(
                              0,
                              'Chưa xác định lần nhập kho đã ghi nhận chưa. Cần đối chiếu trước khi nhập tiếp.',
                            );
                          }
                          rethrow;
                        }
                        if (context.mounted) {
                          message(context, 'Đã bổ sung $qty phụ kiện.');
                        }
                      }),
                icon: const Icon(Icons.inventory_2_outlined, size: 19),
                label: const Text('Bổ sung tồn kho'),
              ),
              if (uncertainRestocks.contains('${item['id']}'))
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Cần đối chiếu lần nhập kho trước khi bổ sung tiếp.',
                    style: TextStyle(color: Color(0xFFB42318)),
                  ),
                ),
              const SizedBox(height: 10),
              OutlinedButton(
                style: item['status'] == 'ACTIVE'
                    ? OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB42318),
                      )
                    : null,
                onPressed: state.busy
                    ? null
                    : () => state.run(() async {
                        final next = item['status'] == 'ACTIVE'
                            ? 'INACTIVE'
                            : 'ACTIVE';
                        if (await confirm(
                          context,
                          next == 'ACTIVE'
                              ? 'Bật bán phụ kiện?'
                              : 'Ngừng bán phụ kiện?',
                          valueOf(item, 'name'),
                        )) {
                          await api.request(
                            'PATCH',
                            '$base/${item['id']}/status',
                            body: {'status': next},
                          );
                        }
                      }),
                child: Text(
                  item['status'] == 'ACTIVE' ? 'Ngừng bán' : 'Bật bán',
                ),
              ),
            ],
          );
        },
      ),
    );
    await listState.reload();
  }

  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => api.get('$base?scope=SHOP'),
    builder: (context, data, state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CatalogToolbar(
          accessory: true,
          query: query,
          status: filter,
          onQuery: (value) => setState(() => query = value),
          onStatus: (value) => setState(() => filter = value),
          onCreate: state.busy
              ? null
              : () => state.run(() => edit(context, null)),
        ),
        if (itemsOf(data).where(matches).isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('Không có phụ kiện phù hợp.')),
          ),
        for (final item in itemsOf(data).where(matches))
          CatalogListItem(
            item: item,
            accessory: true,
            onTap: () => detail(item, state),
          ),
      ],
    ),
  );
}

class TerminationsPage extends StatelessWidget {
  const TerminationsPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  Widget build(BuildContext context) => ApiListPage(
    api: api,
    path: '/api/sellers/${session.sellerId}/kiosks',
    title: 'Chấm dứt thuê kiosk',
    subtitle: 'Chọn kiosk để xem hoặc gửi yêu cầu.',
    item: (context, item, state) => RecordCard(
      title: valueOf(item, 'name'),
      subtitle: valueOf(item, 'code'),
      onTap: () => openPage(
        context,
        'Chấm dứt thuê',
        TerminationDetail(api, session, item),
      ),
    ),
  );
}

class TerminationDetail extends StatelessWidget {
  const TerminationDetail(this.api, this.session, this.kiosk, {super.key});
  final ApiClient api;
  final Session session;
  final Json kiosk;
  String get base =>
      '/api/sellers/${session.sellerId}/kiosks/${kiosk['id']}/termination-requests';
  Future<dynamic> load() async {
    try {
      return await api.get('$base/current');
    } on ApiError catch (e) {
      if (e.status == 404) return <String, dynamic>{};
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => ResourceView(
    load: load,
    builder: (context, data, state) {
      final item = objectOf(data);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageTitle(
            valueOf(kiosk, 'name'),
            'Yêu cầu được quản lý vận hành xét duyệt.',
            status: item.isEmpty ? null : StatusChip(item['status']),
          ),
          if (item.isNotEmpty) ...[
            Text(valueOf(item, 'reason')),
            Text(valueOf(item, 'reviewReason', '')),
            Text('Tiến độ: ${item['lifecycleStatus'] ?? ''}'),
          ],
          if (item.isEmpty ||
              ['CANCELLED', 'REJECTED', 'COMPLETED'].contains(item['status']))
            FilledButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final form = await askForm(context, 'Yêu cầu chấm dứt', [
                        const InputSpec(
                          'reason',
                          'Lý do',
                          minLength: 10,
                          lines: 4,
                        ),
                      ]);
                      if (form == null || !context.mounted) return;
                      if (await confirm(
                        context,
                        'Gửi yêu cầu chấm dứt thuê?',
                        'Yêu cầu áp dụng cho ${kiosk['name']}. Quản lý sẽ xét duyệt trước khi bàn giao.',
                      )) {
                        await api.post(base, {'reason': form['reason']});
                      }
                    }),
              child: const Text('Gửi yêu cầu'),
            ),
          if (item['status'] == 'REQUESTED')
            OutlinedButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final form = await askForm(context, 'Rút yêu cầu', [
                        const InputSpec(
                          'reason',
                          'Lý do rút',
                          minLength: 10,
                          lines: 3,
                        ),
                      ]);
                      if (form != null) {
                        await api.post('$base/${item['id']}/withdraw', {
                          'version': item['version'],
                          'reason': form['reason'],
                        });
                      }
                    }),
              child: const Text('Rút yêu cầu'),
            ),
        ],
      );
    },
  );
}

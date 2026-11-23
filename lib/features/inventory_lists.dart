import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../core/slot_labels.dart';
import '../ui/common.dart';
import '../ui/inventory_widgets.dart';
import 'inventory.dart' show openPage, SlotDetail;
import 'inventory_history.dart';
import 'kiosk_overview.dart';

class KiosksPage extends StatefulWidget {
  const KiosksPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  State<KiosksPage> createState() => _KiosksPageState();
}

class _KiosksPageState extends State<KiosksPage> {
  String search = '', filter = 'ALL';
  Future<void> visit(Widget page, ResourceViewState state) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
    if (mounted) await state.reload();
  }

  @override
  Widget build(BuildContext context) => ResourceView(
    load: () =>
        widget.api.get('/api/sellers/${widget.session.sellerId}/kiosks'),
    builder: (context, data, state) {
      final kiosks = itemsOf(data)
          .where(
            (row) =>
                (filter == 'ALL' || row['status'] == filter) &&
                '${row['name']} ${row['code']} ${row['address']}'
                    .toLowerCase()
                    .contains(search.trim().toLowerCase()),
          )
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageTitle('Tủ hoa', 'Quản lý kiosk và các ô tủ của shop.'),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Tìm kiosk...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => search = value),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InventoryFilter(
                value: filter,
                options: const {
                  'ALL': 'Tất cả',
                  'ONLINE': 'Trực tuyến',
                  'OFFLINE': 'Ngoại tuyến',
                  'FAULT': 'Sự cố',
                },
                onChanged: (value) => setState(() => filter = value),
              ),
            ],
          ),
          if (kiosks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'Không có kiosk phù hợp.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final kiosk in kiosks)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDDE6DF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          valueOf(kiosk, 'name', 'Kiosk'),
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.4,
                            fontWeight: FontWeight.w700,
                            color: forest,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      InventoryStatus(valueOf(kiosk, 'status')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    valueOf(kiosk, 'address', 'Chưa có địa chỉ'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Color(0xFF617267),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        onPressed: () => visit(
                          KioskOverviewPage(widget.api, widget.session, kiosk),
                          state,
                        ),
                        icon: const Icon(Icons.info_outline, size: 16),
                        label: const Text(
                          'Xem kiosk',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        onPressed: () => visit(
                          SlotsPage(widget.api, widget.session, kiosk),
                          state,
                        ),
                        icon: const Icon(Icons.grid_view_outlined, size: 16),
                        label: const Text(
                          'Xem ô tủ',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class SlotsPage extends StatefulWidget {
  const SlotsPage(this.api, this.session, this.kiosk, {super.key});
  final ApiClient api;
  final Session session;
  final Json kiosk;
  @override
  State<SlotsPage> createState() => _SlotsPageState();
}

class _SlotsPageState extends State<SlotsPage> {
  final resource = GlobalKey<ResourceViewState>();
  String search = '', filter = 'ALL';
  List<Json> loadedSlots = [];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      centerTitle: true,
      title: Text(
        valueOf(widget.kiosk, 'name', 'Kiosk'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Tùy chọn kiosk',
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'history', child: Text('Lịch sử')),
            PopupMenuItem(
              value: 'layout',
              enabled: loadedSlots.isNotEmpty,
              child: const Text('Đổi loại ô'),
            ),
          ],
          onSelected: (value) async {
            await openPage(
              context,
              value == 'history' ? 'Lịch sử tại tủ' : 'Đổi loại ô',
              value == 'history'
                  ? InventoryHistoryPage(widget.api, '${widget.kiosk['id']}')
                  : SlotLayoutPage(
                      widget.api,
                      '${widget.kiosk['id']}',
                      loadedSlots,
                    ),
            );
            if (mounted) await resource.currentState?.reload();
          },
        ),
      ],
    ),
    body: ResourceView(
      key: resource,
      load: () async {
        final result = await Future.wait([
          widget.api.get('/api/me/kiosks/${widget.kiosk['id']}/slots'),
          widget.api.get('/api/me/products'),
          widget.api.get('/api/sellers/${widget.session.sellerId}/kiosks'),
        ]);
        final kiosk = itemsOf(
          result[2],
        ).where((row) => row['id'] == widget.kiosk['id']).firstOrNull;
        if (kiosk == null) throw const ApiError(404, 'Không tìm thấy kiosk.');
        final products = itemsOf(result[1]);
        loadedSlots = itemsOf(result[0]);
        return {
          'kiosk': kiosk,
          'slots': [
            for (final row in loadedSlots)
              {
                ...row,
                'productName': products
                    .where((p) => p['id'] == row['productId'])
                    .firstOrNull?['name'],
              },
          ],
        };
      },
      builder: (context, data, state) {
        final payload = objectOf(data), kiosk = objectOf(payload['kiosk']);
        final slots = itemsOf(payload['slots'])
            .where(
              (row) =>
                  (filter == 'ALL' ||
                      row['zone'] == filter ||
                      (filter == 'EMPTY' &&
                          row['status'] == 'RENTED_EMPTY' &&
                          row['bouquetId'] == null) ||
                      (filter == 'FAULT' &&
                          (row['status'] == 'FAULT' ||
                              row['maintenanceStage'] == 'NeedsInspection'))) &&
                  '${row['slotCode']} ${row['productName']} ${row['qrCode']} ${row['orderCode']}'
                      .toLowerCase()
                      .contains(search.trim().toLowerCase()),
            )
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    valueOf(kiosk, 'address', 'Chưa có địa chỉ'),
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Color(0xFF617267),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                InventoryStatus(valueOf(kiosk, 'status')),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Tìm ô, hoa, đơn...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => setState(() => search = value),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                InventoryFilter(
                  value: filter,
                  options: const {
                    'ALL': 'Tất cả ô',
                    'EMPTY': 'Ô trống',
                    'WALK_IN': 'Tại chỗ',
                    'PREORDER': 'Đặt trước',
                    'FAULT': 'Cần kiểm tra',
                  },
                  onChanged: (value) => setState(() => filter = value),
                ),
              ],
            ),
            if (slots.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'Không có ô tủ phù hợp.',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final row in slots)
              InventoryTile(
                title: 'Ô ${valueOf(row, 'slotCode')}',
                description: slotZoneLabel(row['zone']),
                state: slotStateLabel(row),
                lines: [
                  if (row['bouquetId'] != null)
                    valueOf(row, 'productName', 'Đã có bó hoa')
                  else
                    'Chưa nạp hoa',
                  if (row['priceSnapshot'] != null) money(row['priceSnapshot']),
                  if (row['orderCode'] != null) 'Đơn: ${row['orderCode']}',
                ],
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SlotDetail(widget.api, widget.session, kiosk, row),
                    ),
                  );
                  if (mounted) await state.reload();
                },
              ),
          ],
        );
      },
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/inventory_widgets.dart';
import 'inventory.dart' show openPage;
import 'kiosk_application.dart';

const rentalLabels = {
  'ACTIVE': 'Đang hiệu lực',
  'PENDING_PAYMENT': 'Chờ thanh toán',
  'PAST_DUE': 'Quá hạn',
  'EXPIRED': 'Hết hạn',
  'CANCELLED': 'Đã hủy',
  'TERMINATED': 'Đã chấm dứt',
};

String rentalDate(dynamic value) {
  final date = DateTime.tryParse('$value');
  return date == null ? 'Chưa có' : DateFormat('dd/MM/yyyy').format(date);
}

class RentalStatus extends StatelessWidget {
  const RentalStatus(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) =>
      StatusChip(status, label: rentalLabels[status] ?? statusText(status));
}

Future<List<Json>> rentalPeriods(
  ApiClient api,
  String sellerId, {
  String? kioskId,
}) async {
  final rows = <Json>[];
  for (var page = 1; page <= 100000; page++) {
    final result = objectOf(
      await api.get(
        '/api/sellers/$sellerId/subscriptions?page=$page${kioskId == null ? '' : '&kioskId=${Uri.encodeQueryComponent(kioskId)}'}',
      ),
    );
    rows.addAll(itemsOf(result['subscriptions'] ?? []));
    if (result['hasMore'] != true) return rows;
  }
  throw const ApiError(400, 'Lịch sử kỳ thuê quá dài để tải đầy đủ.');
}

Json? _findPeriod(List<Json> rows, String kioskId, List<String> states) {
  for (final row in rows) {
    if (row['kioskId'] == kioskId && states.contains(row['status'])) return row;
  }
  return null;
}

Widget _card(List<Widget> children) => Card(
  margin: const EdgeInsets.only(bottom: 12),
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  ),
);

Widget _periodFacts(Json row) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    const SizedBox(height: 12),
    Text(
      '${rentalDate(row['periodFrom'])} – ${rentalDate(row['periodTo'])}',
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 8),
    Text(
      money(row['price']),
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: forest,
      ),
    ),
    if (valueOf(row, 'terminationReason', '').isNotEmpty) ...[
      const SizedBox(height: 8),
      Text(
        valueOf(row, 'terminationReason'),
        style: const TextStyle(fontSize: 13, color: Color(0xFF617568)),
      ),
    ],
  ],
);

class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  int tab = 0, visibleHistory = 15;
  Future<Json> load() async {
    final result = await Future.wait([
      widget.api.get('/api/sellers/${widget.session.sellerId}/kiosks'),
      rentalPeriods(widget.api, widget.session.sellerId!),
    ]);
    return {'kiosks': itemsOf(result[0]), 'periods': result[1]};
  }

  @override
  Widget build(BuildContext context) => ResourceView(
    load: load,
    builder: (context, data, state) {
      final rows = itemsOf(objectOf(data)['periods']);
      final kiosks = itemsOf(objectOf(data)['kiosks']);
      final history = rows
          .where(
            (r) => ![
              'ACTIVE',
              'PAST_DUE',
              'PENDING_PAYMENT',
            ].contains(r['status']),
          )
          .toList();
      Future<void> detail(Json kiosk) async {
        await openPage(
          context,
          'Chi tiết kỳ thuê',
          KioskRentalDetail(widget.api, widget.session, kiosk),
        );
        if (context.mounted) await state.reload();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () async {
              await openPage(
                context,
                'Thuê thêm kiosk',
                KioskApplicationPage(widget.api, widget.session),
              );
              if (context.mounted) await state.reload();
            },
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Thuê thêm kiosk'),
          ),
          const SizedBox(height: 14),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Kỳ thuê hiện tại')),
              ButtonSegment(value: 1, label: Text('Lịch sử')),
            ],
            selected: {tab},
            showSelectedIcon: false,
            onSelectionChanged: (values) => setState(() => tab = values.first),
          ),
          const SizedBox(height: 14),
          if (tab == 0) ...[
            if (kiosks.isEmpty) _card([const Text('Chưa có kiosk đang thuê.')]),
            for (final kiosk in kiosks)
              Builder(
                builder: (context) {
                  final id = '${kiosk['id']}';
                  final current = _findPeriod(rows, id, ['ACTIVE', 'PAST_DUE']);
                  final pending = _findPeriod(rows, id, ['PENDING_PAYMENT']);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => detail(kiosk),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            StatusHeading(
                              title: Text(
                                valueOf(kiosk, 'name'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: forest,
                                ),
                              ),
                              status: pending != null || current != null
                                  ? RentalStatus(
                                      '${pending?['status'] ?? current?['status']}',
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 10),
                            if (current != null) ...[
                              Text(
                                'Đến ${rentalDate(current['periodTo'])}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF617568),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                money(current['price']),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: forest,
                                ),
                              ),
                            ] else
                              const Text(
                                'Chưa có kỳ thuê đang hiệu lực.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF617568),
                                ),
                              ),
                            if (pending != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Gia hạn: ${money(pending['price'])}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF925B0A),
                                ),
                              ),
                            ],
                            if (kiosk['slotCount'] != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                '${kiosk['slotCount']} ô tủ',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF617568),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ] else ...[
            if (history.isEmpty)
              _card([const Text('Chưa có lịch sử kỳ thuê.')]),
            for (final row in history.take(visibleHistory))
              _card([
                StatusHeading(
                  title: Text(
                    valueOf(row, 'kioskName', valueOf(row, 'packageName')),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: forest,
                    ),
                  ),
                  status: RentalStatus(valueOf(row, 'status')),
                ),
                _periodFacts(row),
              ]),
            if (history.length > visibleHistory)
              OutlinedButton(
                onPressed: () => setState(() => visibleHistory += 15),
                child: const Text('Xem thêm'),
              ),
          ],
        ],
      );
    },
  );
}

class KioskRentalDetail extends StatelessWidget {
  const KioskRentalDetail(this.api, this.session, this.kiosk, {super.key});
  final ApiClient api;
  final Session session;
  final Json kiosk;
  String get kioskId => '${kiosk['id']}';
  String get base => '/api/sellers/${session.sellerId}/subscriptions';

  Future<List<Json>> load() =>
      rentalPeriods(api, session.sellerId!, kioskId: kioskId);

  Future<void> pay(Json pending) async {
    final fresh = await load();
    if (!fresh.any(
      (row) => row['id'] == pending['id'] && row['status'] == 'PENDING_PAYMENT',
    )) {
      throw const ApiError(
        409,
        'Kỳ gia hạn không còn chờ thanh toán. Đang cập nhật lại.',
      );
    }
    final payment = objectOf(
      await api.post('$base/${pending['id']}/payment-link'),
    );
    final url = Uri.tryParse('${payment['checkoutUrl']}');
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'pay.payos.vn' ||
        url.userInfo.isNotEmpty ||
        (url.hasPort && url.port != 443)) {
      throw const ApiError(400, 'Liên kết thanh toán PayOS không hợp lệ.');
    }
    await openSafeLink(url.toString());
  }

  @override
  Widget build(BuildContext context) => ResourceView(
    load: load,
    builder: (context, data, state) {
      final rows = itemsOf(data);
      final current = _findPeriod(rows, kioskId, ['ACTIVE', 'PAST_DUE']);
      final pending = _findPeriod(rows, kioskId, ['PENDING_PAYMENT']);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _card([
            StatusHeading(
              title: Text(
                valueOf(kiosk, 'name'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: forest,
                ),
              ),
              status: InventoryStatus(valueOf(kiosk, 'status')),
            ),
            if (valueOf(kiosk, 'address', '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                valueOf(kiosk, 'address'),
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: Color(0xFF617568),
                ),
              ),
            ],
          ]),
          if (current != null)
            _card([
              StatusHeading(
                title: const Text(
                  'Kỳ thuê hiện tại',
                  style: TextStyle(fontWeight: FontWeight.w700, color: forest),
                ),
                status: RentalStatus(valueOf(current, 'status')),
              ),
              _periodFacts(current),
            ]),
          if (pending != null)
            _card([
              const StatusHeading(
                title: Text(
                  'Kỳ gia hạn',
                  style: TextStyle(fontWeight: FontWeight.w700, color: forest),
                ),
                status: RentalStatus('PENDING_PAYMENT'),
              ),
              _periodFacts(pending),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: state.busy
                    ? null
                    : () => state.run(() => pay(pending)),
                child: const Text('Tiếp tục thanh toán'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB42318),
                  side: const BorderSide(color: Color(0xFFB42318)),
                ),
                onPressed: state.busy
                    ? null
                    : () => state.run(() async {
                        if (!await confirm(
                          context,
                          'Hủy kỳ gia hạn?',
                          'Chỉ hủy kỳ chưa thanh toán. Kỳ thuê hiện tại giữ nguyên.',
                        )) {
                          return;
                        }
                        await api.post('$base/${pending['id']}/cancel');
                        if (context.mounted) {
                          message(context, 'Đã hủy kỳ gia hạn.');
                        }
                      }),
                child: const Text('Hủy kỳ gia hạn'),
              ),
            ])
          else ...[
            if (current == null)
              _card([const Text('Chưa có kỳ thuê đang hiệu lực.')]),
            FilledButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final fresh = await load();
                      if (_findPeriod(fresh, kioskId, ['PENDING_PAYMENT']) !=
                          null) {
                        return;
                      }
                      await api.post('/api/me/kiosks/$kioskId/renewals');
                    }),
              child: const Text('Gia hạn thêm 12 tháng'),
            ),
          ],
        ],
      );
    },
  );
}

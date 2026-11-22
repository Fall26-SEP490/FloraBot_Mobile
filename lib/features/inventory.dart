import '../core/slot_labels.dart';
import 'dart:async';
import '../ui/product_tags.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';

int integerInput(String? value, {bool positive = true}) {
  final number = int.tryParse(value ?? '');
  if (number == null || (positive ? number <= 0 : number < 0)) {
    throw const ApiError(400, 'Nhập số nguyên hợp lệ.');
  }
  return number;
}

double dimensionInput(String? value) {
  final number = double.tryParse(value ?? '');
  if (number == null || !number.isFinite || number <= 0) {
    throw const ApiError(400, 'Kích thước phải lớn hơn 0.');
  }
  return number;
}

Future<T?> openPage<T>(BuildContext context, String title, Widget child) =>
    Navigator.push<T>(
      context,
      MaterialPageRoute<T>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: child,
        ),
      ),
    );

class KiosksPage extends StatelessWidget {
  const KiosksPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  Widget build(BuildContext context) => ApiListPage(
    api: api,
    path: '/api/sellers/${session.sellerId}/kiosks',
    title: 'Hoa tại tủ',
    subtitle: 'Chọn đúng kiosk để kiểm tra và thao tác ô.',
    item: (context, row, state) => RecordCard(
      title: '${valueOf(row, 'code')} • ${valueOf(row, 'name')}',
      subtitle: valueOf(row, 'address'),
      status: row['status'],
      trailing: IconButton(
        tooltip: 'Vị trí kiosk',
        icon: const Icon(Icons.location_on_outlined),
        onPressed: () => openPage(
          context,
          'Vị trí kiosk',
          KioskLocationPage(api, session, row),
        ),
      ),
      onTap: () =>
          openPage(context, valueOf(row, 'code'), SlotsPage(api, session, row)),
    ),
  );
}

class SlotsPage extends StatelessWidget {
  const SlotsPage(this.api, this.session, this.kiosk, {super.key});
  final ApiClient api;
  final Session session;
  final Json kiosk;
  @override
  Widget build(BuildContext context) => ApiListPage(
    api: api,
    path: '/api/me/kiosks/${kiosk['id']}/slots',
    title: valueOf(kiosk, 'name'),
    subtitle: valueOf(kiosk, 'address'),
    item: (context, row, state) => RecordCard(
      title: 'Ô ${row['slotCode']} • ${slotZoneLabel(row['zone'])}',
      subtitle: row['bouquetId'] == null
          ? 'Chưa có bó hoa được ghi nhận'
          : 'Bó: ${row['qrCode'] ?? row['bouquetId']}',
      status: slotStateLabel(row),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => SlotDetail(api, session, kiosk, row),
          ),
        );
        await state.reload();
      },
    ),
  );
}

class SlotDetail extends StatefulWidget {
  const SlotDetail(this.api, this.session, this.kiosk, this.slot, {super.key});
  final ApiClient api;
  final Session session;
  final Json kiosk, slot;
  @override
  State<SlotDetail> createState() => _SlotDetailState();
}

class _SlotDetailState extends State<SlotDetail> {
  final resourceKey = GlobalKey<ResourceViewState>();
  Timer? poll;
  bool activeSession = false;
  @override
  void initState() {
    super.initState();
    poll = Timer.periodic(const Duration(seconds: 3), (_) {
      final state = resourceKey.currentState;
      if (mounted &&
          activeSession &&
          state != null &&
          !state.busy &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        unawaited(state.reload());
      }
    });
  }

  @override
  void dispose() {
    poll?.cancel();
    super.dispose();
  }

  String? pendingSessionId;
  String get kioskId => '${widget.kiosk['id']}';
  String get slotId => '${widget.slot['id']}';
  String get base =>
      '/api/me/kiosks/$kioskId/slots/$slotId/maintenance-sessions';
  Future<Json> load() async {
    final slots = itemsOf(
      await widget.api.get('/api/me/kiosks/$kioskId/slots'),
    );
    final slot = slots.firstWhere(
      (s) => s['id'] == slotId,
      orElse: () => throw const ApiError(404, 'Ô không còn trong kiosk này.'),
    );
    Json? current;
    if (slot['sensorEnabled'] == true && slot['zone'] == 'WALK_IN') {
      try {
        final active = await widget.api.get('$base/active');
        current = active == null ? null : objectOf(active);
      } on ApiError catch (e) {
        if (e.status != 404) rethrow;
      }
    }
    activeSession =
        current != null &&
        ![
          'Completed',
          'Recovered',
          'SessionExpired',
        ].contains(current['stage']);
    if (!activeSession) pendingSessionId = null;
    final products = itemsOf(await widget.api.get('/api/me/products'));
    return {'slot': slot, 'current': current, 'products': products};
  }

  Future<void> issue(
    ResourceViewState state,
    Json slot,
    Json? current,
    List<Json> products,
    String operation, {
    String? action,
  }) => state.run(() async {
    String reason = 'Thao tác hoa tại kiosk từ ứng dụng di động';
    String? productId;
    if (operation == 'START') {
      final needsProduct = action == 'LOAD' || action == 'REPLACE';
      final form = await askForm(
        context,
        action == 'LOAD'
            ? 'Nạp hoa'
            : action == 'REMOVE'
            ? 'Thu hồi hoa'
            : 'Thay hoa',
        [
          if (needsProduct)
            InputSpec(
              'productId',
              'Mẫu hoa',
              choices: {
                for (final p in products.where(
                  (p) =>
                      p['status'] == 'ACTIVE' &&
                      (p['quantity'] as num? ?? 0) > 0,
                ))
                  '${p['id']}': '${p['name']} (còn ${p['quantity']})',
              },
            ),
          const InputSpec('reason', 'Lý do / ghi chú', minLength: 5, lines: 3),
        ],
        submitLabel: 'Mở ô',
      );
      if (form == null) return;
      reason = form['reason']!;
      productId = form['productId'];
    } else {
      final form = await askForm(context, 'Mở ô để tiếp tục', [
        const InputSpec('reason', 'Lý do', minLength: 5, lines: 3),
      ]);
      if (form == null) return;
      reason = form['reason']!;
    }
    pendingSessionId ??= const Uuid().v4();
    await widget.api.post('/api/me/maintenance-open', {
      'kioskId': kioskId,
      'slotId': slotId,
      'operation': operation,
      'sessionId': current?['id'] ?? pendingSessionId,
      'action': action ?? current?['action'],
      'expectedBouquetId': slot['bouquetId'],
      'productId': productId ?? current?['newProductId'],
      'reason': reason,
      if (operation == 'RETRY') 'requestId': const Uuid().v4(),
    });
    if (mounted) message(context, 'Đã gửi yêu cầu mở ô. Chờ tủ phản hồi.');
  });
  @override
  Widget build(BuildContext context) => ResourceView(
    key: resourceKey,
    title: 'Ô ${widget.slot['slotCode']}',
    load: load,
    builder: (context, data, state) {
      final payload = objectOf(data), slot = objectOf(payload['slot']);
      final current = payload['current'] as Json?;
      final products = (payload['products'] as List).map(objectOf).toList();
      final actions = (current?['availableActions'] as List? ?? [])
          .cast<String>();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageTitle('Ô ${slot['slotCode']}', valueOf(widget.kiosk, 'name')),
          StatusChip(slotStateLabel(slot)),
          if (slot['productId'] != null &&
              (slot['bouquetId'] != null || slot['qrCode'] != null))
            SlotBouquetPhoto(
              widget.api,
              '${slot['productId']}',
              products: products,
            ),

          InfoBox(
            'Loại ô: ${slotZoneLabel(slot['zone'])}\nBó hiện tại: ${slot['qrCode'] ?? 'Chưa có'}\nCảm biến: ${slot['sensorReady'] == true ? 'Đã xác minh' : 'Chưa đủ điều kiện'}',
          ),
          if (current != null) ...[
            InfoBox(
              current['stage'] == 'Completed' || current['stage'] == 'Recovered'
                  ? 'Hệ thống đã xác nhận kết quả và cập nhật ô.'
                  : current['stage'] == 'SessionExpired'
                  ? 'Phiên đã hết hạn. Liên hệ đội vận hành để kiểm tra trạng thái thực tế.'
                  : current['action'] == 'REPLACE' &&
                        current['substate'] == 'RemovalClosedEmptyConfirmed'
                  ? 'Đã lấy hoa cũ và xác nhận ô trống. Chọn Mở cửa nạp hoa mới để đặt bó mới vào ô.'
                  : current['action'] == 'LOAD' ||
                        current['stage'] == 'AwaitLoading'
                  ? 'Chờ cửa mở thực tế, đặt bó hoa đã chọn vào ô rồi đóng cửa. Hệ thống tự xác nhận cảm biến.'
                  : 'Chờ cửa mở thực tế, lấy hoa cũ ra rồi đóng cửa. Hệ thống tự xác nhận ô trống.',
            ),

            RecordCard(
              title: 'Phiên ${current['action']}',
              subtitle: 'Hết hạn: ${dateText(current['expiresAt'])}',
              status: current['stage'],
            ),
            if (current['inspectionReason'] != null)
              InfoBox(
                'Cần xử lý: ${current['inspectionReason']}',
                warning: true,
              ),
            OutlinedButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      await widget.api.post('$base/${current['id']}/check');
                    }),
              child: const Text('Kiểm tra tiến độ'),
            ),
            if (actions.contains('open-next'))
              FilledButton(
                onPressed: state.busy
                    ? null
                    : () => issue(state, slot, current, products, 'OPEN_NEXT'),
                child: const Text('Mở ô nạp hoa mới'),
              ),
            if (actions.contains('open-for-check'))
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () => issue(
                        state,
                        slot,
                        current,
                        products,
                        'OPEN_FOR_CHECK',
                      ),
                child: const Text('Mở ô kiểm tra'),
              ),
            if (slot['manualRetryEnabled'] == true &&
                current['currentCmdId'] != null &&
                (current['retryAfterSeconds'] as num? ?? 0) <= 0)
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () => issue(state, slot, current, products, 'RETRY'),
                child: const Text('Thử mở lại ô'),
              ),
            if (actions.contains('report-issue'))
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () => state.run(() async {
                        final f =
                            await askForm(context, 'Báo lỗi phiên thao tác', [
                              const InputSpec(
                                'reason',
                                'Mô tả sự cố',
                                minLength: 5,
                                lines: 4,
                              ),
                            ]);
                        if (f != null) {
                          await widget.api.post(
                            '$base/${current['id']}/report-issue',
                            {'reason': f['reason']},
                          );
                        }
                      }),
                child: const Text('Ghi nhận lỗi phiên'),
              ),
            if (current['stage'] == 'NeedsInspection')
              const InfoBox(
                'Lỗi phiên đã được ghi nhận. Hiện backend chưa tự chuyển báo lỗi phiên thành phiếu kỹ thuật; cần liên hệ Manager để xử lý.',
                warning: true,
              ),
          ],
          if (slot['sensorEnabled'] != true &&
              slot['bouquetId'] != null &&
              ['STOCKED', 'PENDING_REMOVAL'].contains(slot['status']))
            RemoveSlotFlower(
              api: widget.api,
              kioskId: kioskId,
              slot: slot,
              onRemoved: state.reload,
            ),
          if ((current == null || current['stage'] == 'Completed') &&
              slot['zone'] == 'WALK_IN' &&
              slot['sensorReady'] == true &&
              slot['sensorEnabled'] == true) ...[
            if (slot['status'] == 'RENTED_EMPTY')
              FilledButton(
                onPressed: state.busy
                    ? null
                    : () => issue(
                        state,
                        slot,
                        null,
                        products,
                        'START',
                        action: 'LOAD',
                      ),
                child: const Text('Mở ô nạp hoa'),
              ),
            if (['STOCKED', 'PENDING_REMOVAL'].contains(slot['status'])) ...[
              FilledButton(
                onPressed: state.busy
                    ? null
                    : () => issue(
                        state,
                        slot,
                        null,
                        products,
                        'START',
                        action: 'REMOVE',
                      ),
                child: const Text('Mở ô thu hồi hoa'),
              ),
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () => issue(
                        state,
                        slot,
                        null,
                        products,
                        'START',
                        action: 'REPLACE',
                      ),
                child: const Text('Mở ô thay hoa'),
              ),
            ],
          ],
          if ([
                'RENTED_EMPTY',
                'STOCKED',
                'PENDING_REMOVAL',
              ].contains(slot['status']) &&
              slot['zone'] == 'WALK_IN')
            OutlinedButton.icon(
              onPressed: state.busy
                  ? null
                  : () => assign(state, slot, products),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Giao ô này cho nhân viên'),
            ),
        ],
      );
    },
  );

  Future<void> assign(
    ResourceViewState state,
    Json slot,
    List<Json> products,
  ) => state.run(() async {
    final staff = itemsOf(
      await widget.api.get('/api/sellers/${widget.session.sellerId}/staff'),
    );
    if (!mounted) return;
    final form = await askForm(context, 'Giao thao tác ô', [
      InputSpec(
        'assigneeId',
        'Nhân viên',
        choices: {for (final p in staff) '${p['id']}': valueOf(p, 'name')},
      ),
      InputSpec(
        'action',
        'Thao tác',
        choices: slot['status'] == 'RENTED_EMPTY'
            ? {'LOAD': 'Nạp hoa'}
            : {'REMOVE': 'Thu hồi', 'REPLACE': 'Thay hoa'},
      ),
      InputSpec(
        'productId',
        'Mẫu hoa mới (nạp / thay)',
        required: false,
        choices: {
          for (final p in products.where((p) => p['status'] == 'ACTIVE'))
            '${p['id']}': valueOf(p, 'name'),
        },
      ),
      const InputSpec('instructions', 'Hướng dẫn', minLength: 10, lines: 3),
    ]);
    if (form == null) return;
    if (form['action'] != 'REMOVE' && (form['productId'] ?? '').isEmpty) {
      throw const ApiError(400, 'Chọn mẫu hoa khi nạp hoặc thay hoa.');
    }
    await widget.api.post('/api/me/inventory-tasks', {
      'id': const Uuid().v4(),
      'assigneeId': form['assigneeId'],
      'kioskId': kioskId,
      'slotId': slotId,
      'action': form['action'],
      'expectedBouquetId': slot['bouquetId'],
      'productId': form['action'] == 'REMOVE' ? null : form['productId'],
      'instructions': form['instructions'],
    });
    if (mounted) message(context, 'Đã giao việc cho nhân viên.');
  });
}

class ProductsPage extends StatelessWidget {
  const ProductsPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => api.get('/api/me/products'),
    builder: (context, data, state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageTitle(
          'Mẫu hoa',
          'Tồn tại shop được quản lý riêng với hoa đã nạp trong tủ.',
        ),
        FilledButton.icon(
          onPressed: state.busy ? null : () => edit(context, state),
          icon: const Icon(Icons.add),
          label: const Text('Tạo mẫu hoa'),
        ),
        for (final row in itemsOf(data))
          RecordCard(
            title: valueOf(row, 'name'),
            subtitle: '${money(row['price'])} • Tại shop: ${row['quantity']}',
            status: row['status'],
            onTap: () async {
              await openPage(
                context,
                'Mẫu hoa',
                ResourceView(
                  load: () => api.get('/api/me/products'),
                  builder: (context, data, detailState) {
                    final item = itemsOf(
                      data,
                    ).where((p) => p['id'] == row['id']).firstOrNull;
                    if (item == null) {
                      return const InfoBox('Mẫu hoa không còn khả dụng.');
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SlotBouquetPhoto(
                          api,
                          '${item['id']}',
                          products: [item],
                        ),
                        StatusChip(item['status']),
                        Text(
                          '${money(item['price'])} · Tại shop: ${item['quantity']}',
                        ),
                        Text(valueOf(item, 'description', '')),
                        FilledButton(
                          onPressed: detailState.busy
                              ? null
                              : () => edit(context, detailState, item),
                          child: const Text('Sửa mẫu hoa'),
                        ),
                        OutlinedButton(
                          onPressed: detailState.busy
                              ? null
                              : () => detailState.run(() async {
                                  final next = item['status'] == 'ACTIVE'
                                      ? 'INACTIVE'
                                      : 'ACTIVE';
                                  if (await confirm(
                                    context,
                                    next == 'ACTIVE'
                                        ? 'Bật bán mẫu hoa?'
                                        : 'Dừng bán mẫu hoa?',
                                    'Thay đổi trạng thái mẫu ${item['name']}.',
                                  )) {
                                    await api.post(
                                      '/api/me/flows/set_product_status',
                                      {'productId': item['id'], 'status': next},
                                    );
                                  }
                                }),
                          child: Text(
                            item['status'] == 'ACTIVE' ? 'Dừng bán' : 'Bật bán',
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
              await state.reload();
            },
            trailing: IconButton(
              tooltip: 'Thêm ảnh',
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final file = await chooseEvidence(context);
                      if (file == null) return;
                      await api.upload(
                        '/api/me/products/${row['id']}/photos',
                        file,
                      );
                      if (context.mounted) {
                        message(context, 'Đã thêm ảnh mẫu hoa.');
                      }
                    }),
              icon: const Icon(Icons.add_a_photo_outlined),
            ),
          ),
      ],
    ),
  );
  Future<void> edit(
    BuildContext context,
    ResourceViewState state, [
    Json? row,
  ]) => state.run(() async {
    if (!context.mounted) return;
    final form = await askForm(
      context,
      row == null ? 'Tạo mẫu hoa' : 'Sửa mẫu hoa',
      [
        InputSpec('name', 'Tên mẫu', initial: row?['name'] ?? '', minLength: 2),
        InputSpec(
          'description',
          'Mô tả',
          initial: row?['description'] ?? '',
          required: false,
          lines: 3,
        ),
        InputSpec(
          'price',
          'Giá (đồng)',
          initial: '${row?['price'] ?? ''}',
          numeric: true,
        ),
        InputSpec(
          'quantity',
          'Số bó tại shop',
          initial: '${row?['quantity'] ?? 0}',
          numeric: true,
        ),
        InputSpec(
          'lengthCm',
          'Chiều dài (cm)',
          initial: '${row?['lengthCm'] ?? ''}',
          numeric: true,
        ),
        InputSpec(
          'widthCm',
          'Chiều rộng (cm)',
          initial: '${row?['widthCm'] ?? ''}',
          numeric: true,
        ),
        InputSpec(
          'heightCm',
          'Chiều cao (cm)',
          initial: '${row?['heightCm'] ?? ''}',
          numeric: true,
        ),
      ],
    );
    if (form == null || !context.mounted) return;
    final tags = await chooseProductTags(
      context,
      List<String>.from(row?['tags'] ?? []),
    );
    if (tags == null) return;
    final body = {
      'name': form['name'],
      'description': form['description'],
      'price': integerInput(form['price']),
      'quantity': integerInput(form['quantity'], positive: false),
      'lengthCm': dimensionInput(form['lengthCm']),
      'widthCm': dimensionInput(form['widthCm']),
      'heightCm': dimensionInput(form['heightCm']),
      'tags': tags,
    };
    if (row == null) {
      await api.post('/api/me/products', body);
    } else {
      await api.put(
        '/api/sellers/${session.sellerId}/products/${row['id']}',
        body,
      );
    }
    if (context.mounted) message(context, 'Đã lưu mẫu hoa.');
  });
}

class RepairApprovalsPage extends StatelessWidget {
  const RepairApprovalsPage(this.api, {super.key});
  final ApiClient api;
  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => api.get('/api/me/technical-repairs'),
    builder: (context, data, state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageTitle(
          'Quyền sửa ô',
          'Duyệt đúng công việc trước khi Technical lấy OTP sửa chữa.',
        ),
        if (itemsOf(data).isEmpty) const InfoBox('Chưa có ca sửa ô cần duyệt.'),
        for (final row in itemsOf(data))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${row['kioskName']} • Ô ${row['slotCode']}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(valueOf(row, 'reason')),
                  if (row['expiresAt'] != null)
                    Text('Đã duyệt tới ${dateText(row['expiresAt'])}'),
                  if (row['expiresAt'] == null)
                    FilledButton(
                      onPressed: state.busy
                          ? null
                          : () => state.run(() async {
                              if (!await confirm(
                                context,
                                'Duyệt quyền mở ô sửa?',
                                'Chỉ duyệt khi đã xác minh đúng kỹ thuật viên và ca sửa.',
                              )) {
                                return;
                              }
                              await api.post(
                                '/api/me/technical-repairs/${row['id']}/approve',
                              );
                            }),
                      child: const Text('Duyệt quyền mở ô'),
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class StaffManagementPage extends StatelessWidget {
  const StaffManagementPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  Widget build(BuildContext context) {
    final base = '/api/sellers/${session.sellerId}/staff';
    return ResourceView(
      load: () => api.get('$base/accounts'),
      builder: (context, data, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageTitle(
            'Nhân viên shop',
            'Tài khoản thuộc shop; không được cấp quyền tài chính của chủ shop.',
          ),
          FilledButton.icon(
            onPressed: state.busy
                ? null
                : () => state.run(() async {
                    final f = await askForm(context, 'Tạo nhân viên', [
                      const InputSpec('fullName', 'Họ tên', minLength: 2),
                      const InputSpec('email', 'Email'),
                      const InputSpec(
                        'password',
                        'Mật khẩu ban đầu',
                        secret: true,
                        minLength: 12,
                      ),
                      const InputSpec(
                        'phone',
                        'Số điện thoại',
                        required: false,
                      ),
                    ]);
                    if (f != null) await api.post(base, f);
                  }),
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Tạo tài khoản nhân viên'),
          ),
          for (final row in itemsOf(data))
            RecordCard(
              title: valueOf(row, 'fullName'),
              subtitle: valueOf(row, 'email'),
              status: row['status'],
              trailing: IconButton(
                tooltip: row['status'] == 'ACTIVE'
                    ? 'Khóa tài khoản'
                    : 'Mở tài khoản',
                icon: Icon(
                  row['status'] == 'ACTIVE'
                      ? Icons.lock_outline
                      : Icons.lock_open_outlined,
                ),
                onPressed: state.busy
                    ? null
                    : () => state.run(() async {
                        final status = row['status'] == 'ACTIVE'
                            ? 'DISABLED'
                            : 'ACTIVE';
                        if (!await confirm(
                          context,
                          '${statusText(status)} tài khoản?',
                          'Quyền truy cập của nhân viên sẽ được máy chủ kiểm tra lại.',
                        )) {
                          return;
                        }
                        await api.request(
                          'PATCH',
                          '$base/${row['id']}/status',
                          body: {'status': status},
                        );
                      }),
              ),
            ),
        ],
      ),
    );
  }
}

class SlotBouquetPhoto extends StatefulWidget {
  const SlotBouquetPhoto(
    this.api,
    this.productId, {
    required this.products,
    super.key,
  });
  final ApiClient api;
  final String productId;
  final List<Json> products;
  @override
  State<SlotBouquetPhoto> createState() => _SlotBouquetPhotoState();
}

class _SlotBouquetPhotoState extends State<SlotBouquetPhoto> {
  late Future<dynamic> photos;
  Future<dynamic> load() =>
      widget.api.get('/api/me/products/${widget.productId}/photos');
  @override
  void initState() {
    super.initState();
    photos = load();
  }

  @override
  void didUpdateWidget(SlotBouquetPhoto old) {
    super.didUpdateWidget(old);
    if (old.productId != widget.productId) photos = load();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.products
        .where((p) => p['id'] == widget.productId)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (product != null)
            Text(
              valueOf(product, 'name'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          FutureBuilder<dynamic>(
            future: photos,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Column(
                  children: [
                    const Text('Chưa tải được ảnh bó hoa.'),
                    TextButton(
                      onPressed: () => setState(() {
                        photos = load();
                      }),
                      child: const Text('Tải lại ảnh'),
                    ),
                  ],
                );
              }
              final items = itemsOf(snapshot.data);
              if (items.isEmpty) {
                return const InfoBox('Mẫu hoa này chưa có ảnh.');
              }
              final cover =
                  items.where((p) => p['isCover'] == true).firstOrNull ??
                  items.first;
              final uri = Uri.tryParse('${cover['url']}');
              if (uri == null ||
                  uri.scheme != 'https' ||
                  uri.userInfo.isNotEmpty) {
                return const InfoBox('Ảnh mẫu hoa chưa khả dụng.');
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.network(
                  uri.toString(),
                  height: 240,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 120,
                    child: Center(child: Text('Không tải được ảnh bó hoa.')),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class RemoveSlotFlower extends StatefulWidget {
  const RemoveSlotFlower({
    required this.api,
    required this.kioskId,
    required this.slot,
    required this.onRemoved,
    super.key,
  });
  final ApiClient api;
  final String kioskId;
  final Json slot;
  final Future<void> Function() onRemoved;
  @override
  State<RemoveSlotFlower> createState() => _RemoveSlotFlowerState();
}

class _RemoveSlotFlowerState extends State<RemoveSlotFlower> {
  final reason = TextEditingController();
  bool confirmed = false;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> remove() async {
    if (busy || !confirmed || reason.text.trim().length < 5) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.request(
        'DELETE',
        '/api/me/kiosks/${widget.kioskId}/slots/${widget.slot['id']}/bouquet',
        body: {
          'bouquetId': widget.slot['bouquetId'],
          'reason': reason.text.trim(),
          'confirmedRemoved': confirmed,
        },
      );
      if (mounted) {
        message(
          context,
          'Đã ghi nhận thu hồi hoa. Ô đã được làm trống và giữ nguyên hình thức bán.',
        );
      }
      await widget.onRemoved();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiError && e.status == 404
              ? 'API thu hồi chưa được triển khai trên máy chủ này.'
              : '$e',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final held =
        widget.slot['bouquetStatus'] == 'HELD' ||
        widget.slot['orderStatus'] == 'AWAITING_PAYMENT';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Thu hồi hoa khỏi ô ${widget.slot['slotCode']}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const InfoBox(
          'Chỉ xác nhận sau khi đã lấy bó hoa thực tế khỏi ô. Hệ thống ghi lịch sử thu hồi, giữ nguyên vùng bán và thông tin đơn hàng, hoàn tiền liên quan.',
        ),
        if (held)
          const InfoBox(
            'Không thể thu hồi lúc này vì bó hoa đang được giữ cho một đơn hàng.',
          )
        else ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: confirmed,
            onChanged: busy
                ? null
                : (value) => setState(() => confirmed = value ?? false),
            title: const Text('Tôi đã lấy hoa thực tế khỏi ô này.'),
          ),
          TextField(
            controller: reason,
            maxLength: 500,
            maxLines: 3,
            enabled: !busy,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Lý do thu hồi',
              hintText: 'Nhập lý do, tối thiểu 5 ký tự',
            ),
          ),
          if (error != null) InfoBox(error!, warning: true),
          OutlinedButton(
            onPressed: !busy && confirmed && reason.text.trim().length >= 5
                ? remove
                : null,
            child: Text(busy ? 'Đang ghi nhận…' : 'Xác nhận đã lấy hoa khỏi ô'),
          ),
        ],
      ],
    );
  }
}

class KioskLocationPage extends StatelessWidget {
  const KioskLocationPage(this.api, this.session, this.kiosk, {super.key});
  final ApiClient api;
  final Session session;
  final Json kiosk;
  String get base => '/api/sellers/${session.sellerId}/kiosks/${kiosk['id']}';
  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => api.get('$base/location-requests'),
    builder: (context, data, state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageTitle(valueOf(kiosk, 'name'), valueOf(kiosk, 'address')),
        Text(
          'Vĩ độ: ${kiosk['latitude'] ?? 'Chưa có'} · Kinh độ: ${kiosk['longitude'] ?? 'Chưa có'}',
        ),
        OutlinedButton(
          onPressed: () => navigateAddress(valueOf(kiosk, 'address')),
          child: const Text('Xem bản đồ'),
        ),
        FilledButton(
          onPressed: state.busy
              ? null
              : () => state.run(() async {
                  final form =
                      await askForm(context, 'Đề nghị cập nhật vị trí', [
                        InputSpec(
                          'address',
                          'Địa chỉ',
                          initial: valueOf(kiosk, 'address', ''),
                          minLength: 5,
                        ),
                        InputSpec(
                          'latitude',
                          'Vĩ độ',
                          initial: '${kiosk['latitude'] ?? ''}',
                        ),
                        InputSpec(
                          'longitude',
                          'Kinh độ',
                          initial: '${kiosk['longitude'] ?? ''}',
                        ),
                        const InputSpec(
                          'reason',
                          'Lý do thay đổi',
                          minLength: 10,
                          lines: 3,
                        ),
                      ]);
                  if (form == null) return;
                  final lat = double.tryParse(form['latitude']!),
                      lon = double.tryParse(form['longitude']!);
                  if (lat == null ||
                      lon == null ||
                      !lat.isFinite ||
                      !lon.isFinite ||
                      lat < -90 ||
                      lat > 90 ||
                      lon < -180 ||
                      lon > 180) {
                    throw const ApiError(400, 'Tọa độ không hợp lệ.');
                  }
                  await api.put('$base/location', {
                    'address': form['address'],
                    'latitude': lat,
                    'longitude': lon,
                    'reason': form['reason'],
                  });
                  if (context.mounted) {
                    message(
                      context,
                      'Đã gửi cập nhật vị trí. Theo dõi trạng thái xét duyệt bên dưới.',
                    );
                  }
                }),
          child: const Text('Cập nhật vị trí kiosk'),
        ),
        for (final request in itemsOf(data))
          RecordCard(
            title: valueOf(request, 'address'),
            subtitle: valueOf(request, 'reason', ''),
            status: request['status'],
          ),
      ],
    ),
  );
}

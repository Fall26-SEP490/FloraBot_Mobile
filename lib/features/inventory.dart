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
      title:
          'Ô ${row['slotCode']} • ${row['zone'] == 'PREORDER' ? 'Đặt trước' : 'Walk-in'}',
      subtitle: row['bouquetId'] == null
          ? 'Chưa có bó hoa được ghi nhận'
          : 'Bó: ${row['qrCode'] ?? row['bouquetId']}',
      status: row['status'],
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
        current = objectOf(await widget.api.get('$base/active'));
      } on ApiError catch (e) {
        if (e.status != 404) rethrow;
      }
    }
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
        submitLabel: 'Lấy OTP thao tác',
      );
      if (form == null) return;
      reason = form['reason']!;
      productId = form['productId'];
    } else {
      final form = await askForm(context, 'Lấy mã thao tác tiếp theo', [
        const InputSpec('reason', 'Lý do', minLength: 5, lines: 3),
      ]);
      if (form == null) return;
      reason = form['reason']!;
    }
    pendingSessionId ??= const Uuid().v4();
    final result = objectOf(
      await widget.api.post('/api/me/maintenance-access', {
        'kioskId': kioskId,
        'slotId': slotId,
        'operation': operation,
        'sessionId': current?['id'] ?? pendingSessionId,
        'action': action ?? current?['action'],
        'expectedBouquetId': slot['bouquetId'],
        'productId': productId ?? current?['newProductId'],
        'reason': reason,
        if (operation == 'RETRY') 'requestId': const Uuid().v4(),
      }),
    );
    if (mounted) await showAccessCode(context, result);
  });
  @override
  Widget build(BuildContext context) => ResourceView(
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
          StatusChip(slot['status']),
          InfoBox(
            'Loại ô: ${slot['zone']}\nBó hiện tại: ${slot['qrCode'] ?? 'Chưa có'}\nCảm biến: ${slot['sensorReady'] == true ? 'Đã xác minh' : 'Chưa đủ điều kiện'}',
          ),
          if (slot['zone'] == 'PREORDER')
            const InfoBox(
              'Nạp và xác nhận đơn đặt trước tại mục Đơn hàng, gắn với đúng đơn đã thanh toán.',
            ),
          if (current != null) ...[
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
                child: const Text('OTP nạp hoa mới'),
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
                child: const Text('OTP kiểm tra ô'),
              ),
            if (slot['manualRetryEnabled'] == true &&
                current['currentCmdId'] != null &&
                (current['retryAfterSeconds'] as num? ?? 0) <= 0)
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () => issue(state, slot, current, products, 'RETRY'),
                child: const Text('Yêu cầu OTP thử lại'),
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
          if ((current == null || current['stage'] == 'Completed') &&
              slot['zone'] == 'WALK_IN' &&
              slot['sensorReady'] == true) ...[
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
                child: const Text('Lấy OTP nạp hoa'),
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
                child: const Text('Lấy OTP thu hồi hoa'),
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
                child: const Text('Lấy OTP thay hoa'),
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
          const InfoBox(
            'App không giữ API key thiết bị. OTP phải được xác nhận tại kiosk; cảm biến và backend quyết định kết quả thực tế.',
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
            onTap: () => edit(context, state, row),
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
    List<Json> kiosks = [];
    if (row == null) {
      kiosks = itemsOf(
        await api.get('/api/sellers/${session.sellerId}/kiosks'),
      );
    }
    if (!context.mounted) return;
    final form = await askForm(
      context,
      row == null ? 'Tạo mẫu hoa' : 'Sửa mẫu hoa',
      [
        if (row == null)
          InputSpec(
            'kioskId',
            'Kiosk của shop',
            choices: {
              for (final k in kiosks)
                '${k['id']}': '${k['code']} - ${k['name']}',
            },
          ),
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
        InputSpec(
          'tags',
          'Nhãn, cách nhau bởi dấu phẩy',
          initial: (row?['tags'] as List? ?? []).join(', '),
          required: false,
        ),
      ],
    );
    if (form == null) return;
    final body = {
      'name': form['name'],
      'description': form['description'],
      'price': integerInput(form['price']),
      'quantity': integerInput(form['quantity'], positive: false),
      'lengthCm': dimensionInput(form['lengthCm']),
      'widthCm': dimensionInput(form['widthCm']),
      'heightCm': dimensionInput(form['heightCm']),
      'tags': form['tags']!
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
      if (row == null) 'kioskId': form['kioskId'],
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

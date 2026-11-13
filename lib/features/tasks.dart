import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';

class TasksPage extends StatefulWidget {
  const TasksPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  String filter = '';
  int revision = 0;
  @override
  Widget build(BuildContext context) {
    final owner = widget.session.role == AppRole.seller;
    final base = owner
        ? '/api/sellers/${widget.session.sellerId}/staff-tasks'
        : '/api/staff/tasks';
    return ApiListPage(
      key: ValueKey('$filter:$revision'),
      api: widget.api,
      path: '$base${filter.isEmpty ? '' : '?status=$filter'}',
      title: owner ? 'Việc của shop' : 'Công việc của tôi',
      subtitle: owner
          ? 'Theo dõi và duyệt báo cáo nạp hoa.'
          : 'Chỉ hiển thị công việc bạn được giao.',
      actions: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final code in [
                '',
                'ASSIGNED',
                'IN_PROGRESS',
                'SUBMITTED',
                'COMPLETED',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: filter == code,
                    label: Text(code.isEmpty ? 'Tất cả' : statusText(code)),
                    onSelected: (_) => setState(() => filter = code),
                  ),
                ),
            ],
          ),
        ),
      ],
      item: (context, row, state) => RecordCard(
        title: valueOf(row, 'kioskName'),
        subtitle:
            '${row['kind'] == 'INCIDENT' ? 'Kiểm tra sự cố' : 'Nạp / giao hoa'}\n${valueOf(row, 'instructions', '')}',
        status: row['status'],
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => TaskDetailPage(widget.api, widget.session, row),
            ),
          );
          if (mounted) setState(() => revision++);
        },
      ),
    );
  }
}

class TaskDetailPage extends StatefulWidget {
  const TaskDetailPage(this.api, this.session, this.task, {super.key});
  final ApiClient api;
  final Session session;
  final Json task;
  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  final loadingAccess = <String, String>{};
  String get id => widget.task['id'] as String;
  bool get owner => widget.session.role == AppRole.seller;
  String get path => owner
      ? '/api/sellers/${widget.session.sellerId}/staff-tasks/$id'
      : '/api/staff/tasks/$id';
  Future<Json?> optional(String endpoint) async {
    try {
      return objectOf(await widget.api.get(endpoint));
    } on ApiError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<Json> load() async {
    final detail = objectOf(await widget.api.get(path));
    Json? inventory, preorders;
    if (widget.session.role == AppRole.staff) {
      inventory = await optional('/api/staff/tasks/$id/inventory-maintenance');
      if (inventory == null) {
        preorders = await optional('/api/staff/tasks/$id/preorders');
      }
    }
    return {'detail': detail, 'inventory': inventory, 'preorders': preorders};
  }

  Future<void> transition(ResourceViewState state, Json task, String status) =>
      state.run(() async {
        final form = await askForm(context, statusText(status), [
          const InputSpec(
            'report',
            'Ghi chú công việc',
            lines: 3,
            minLength: 10,
          ),
        ]);
        if (form == null) return;
        await widget.api.post('$path/transition', {
          'version': task['version'],
          'status': status,
          'report': form['report'],
        });
        if (mounted) message(context, 'Đã cập nhật công việc.');
      });
  Future<void> evidence(ResourceViewState state, Json task) =>
      state.run(() async {
        final file = await chooseEvidence(context);
        if (file == null) return;
        final upload = await widget.api.upload(
          '/api/staff/tasks/$id/evidence/upload',
          file,
        );
        await widget.api.post('/api/staff/tasks/$id/evidence', {
          'id': const Uuid().v4(),
          'version': task['version'],
          'reference': upload['reference'],
        });
        if (mounted) message(context, 'Đã gắn ảnh minh chứng vào công việc.');
      });
  Future<void> issueInventory(ResourceViewState state, String operation) =>
      state.run(() async {
        String? reason;
        if (operation == 'OPEN_FOR_CHECK') {
          final form = await askForm(context, 'Lý do kiểm tra', [
            const InputSpec('reason', 'Mô tả', minLength: 5, lines: 3),
          ]);
          if (form == null) return;
          reason = form['reason'];
        }
        if (!mounted) return;
        if (!await confirm(
          context,
          'Lấy mã thao tác ô?',
          'Bạn sẽ nhập mã tại đúng kiosk của công việc này.',
        )) {
          return;
        }
        final result = objectOf(
          await widget.api.post(
            '/api/staff/tasks/$id/inventory-maintenance/access',
            {'operation': operation, 'reason': reason},
          ),
        );
        if (mounted) await showAccessCode(context, result);
      });
  @override
  Widget build(BuildContext context) => ResourceView(
    title: 'Chi tiết công việc',
    load: load,
    builder: (context, response, state) {
      final data = objectOf(response);
      final detail = objectOf(data['detail']);
      final task = {
        ...widget.task,
        if (detail['version'] != null) 'version': detail['version'],
        if (detail['status'] != null) 'status': detail['status'],
      };
      final active = task['status'] == 'IN_PROGRESS';
      final inventory = data['inventory'] as Json?;
      final options = data['preorders'] as Json?;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageTitle(
            valueOf(task, 'kioskName'),
            valueOf(task, 'instructions', ''),
          ),
          StatusChip(task['status']),
          RecordCard(
            title: 'Địa điểm',
            subtitle: valueOf(task, 'address'),
            onTap: () =>
                state.run(() => navigateAddress(valueOf(task, 'address'))),
          ),
          Text(
            'Tủ: ${statusText(detail['kioskStatus'])} • Tín hiệu: ${dateText(detail['lastHeartbeatAt'])}',
          ),
          if (detail['slotCode'] != null)
            InfoBox(
              'Ô ${detail['slotCode']} • ${statusText(detail['slotStatus'])}',
            ),
          if (detail['incident'] is Map)
            InfoBox(
              valueOf(
                objectOf(detail['incident']),
                'reason',
                'Kiểm tra thông tin sự cố theo công việc.',
              ),
            ),
          if (!owner && task['status'] == 'ASSIGNED')
            FilledButton.icon(
              onPressed: state.busy
                  ? null
                  : () => transition(state, task, 'IN_PROGRESS'),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Bắt đầu công việc'),
            ),
          if (inventory != null) ...[
            const Divider(height: 32),
            Text(
              'Thao tác ô ${inventory['slotCode']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            InfoBox(
              'Thao tác: ${inventory['action']}\nTiến độ: ${statusText(inventory['sessionStage'])}\nMã chỉ có hiệu lực tại kiosk được giao.',
            ),
            if (active && inventory['sessionStage'] == null)
              FilledButton(
                onPressed: state.busy
                    ? null
                    : () => issueInventory(state, 'START'),
                child: const Text('Lấy OTP bắt đầu'),
              ),
            if (active &&
                inventory['sessionSubstate'] == 'RemovalClosedEmptyConfirmed')
              FilledButton(
                onPressed: state.busy
                    ? null
                    : () => issueInventory(state, 'OPEN_NEXT'),
                child: const Text('Lấy OTP nạp hoa mới'),
              ),
            if (active && inventory['sessionStage'] == 'NeedsInspection')
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () => issueInventory(state, 'OPEN_FOR_CHECK'),
                child: const Text('Yêu cầu OTP kiểm tra'),
              ),
            if (inventory['sessionStage'] == 'NeedsInspection')
              const InfoBox(
                'Chưa xác nhận được kết quả. Liên hệ chủ shop; không coi ô đã trống hoặc nạp xong.',
                warning: true,
              ),
          ],
          if (options != null && active) ...[
            const Divider(height: 32),
            const Text(
              'Đơn preorder được giao',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            for (final order in (options['preorders'] as List? ?? []).map(
              objectOf,
            ))
              RecordCard(
                title: valueOf(order, 'productName'),
                subtitle:
                    '${valueOf(order, 'orderCode')} • ${dateText(order['pickupAt'])}',
                onTap: state.busy
                    ? null
                    : () => staffPreorder(state, order, options),
              ),
          ],
          if (!owner &&
              widget.session.role == AppRole.technician &&
              active) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      if (!await confirm(
                        context,
                        'Yêu cầu mã sửa ô?',
                        'Chủ shop phải duyệt quyền trước. Backend sẽ kiểm tra lại đúng công việc và trạng thái ô.',
                      )) {
                        return;
                      }
                      final access = objectOf(
                        await widget.api.post(
                          '/api/staff/tasks/$id/repair-access',
                        ),
                      );
                      if (context.mounted) {
                        await showAccessCode(context, access);
                      }
                    }),
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Lấy OTP sửa ô'),
            ),
          ],
          if (!owner && active) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: state.busy ? null : () => evidence(state, task),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Thêm ảnh minh chứng'),
            ),
            FilledButton(
              onPressed: state.busy
                  ? null
                  : () {
                      if (widget.session.role == AppRole.technician) {
                        state.run(() async {
                          final form =
                              await askForm(context, 'Gửi báo cáo sửa chữa', [
                                const InputSpec(
                                  'report',
                                  'Kết quả kiểm tra / sửa',
                                  lines: 4,
                                  minLength: 10,
                                ),
                              ]);
                          if (form == null) return;
                          await widget.api
                              .post('/api/staff/tasks/$id/resolve-incident', {
                                'id': const Uuid().v4(),
                                'version': task['version'],
                                'report': form['report'],
                              });
                          if (context.mounted) {
                            message(context, 'Đã gửi để Manager kiểm tra.');
                          }
                        });
                      } else {
                        transition(state, task, 'SUBMITTED');
                      }
                    },
              child: const Text('Gửi báo cáo để duyệt'),
            ),
          ],
          if (owner && task['status'] == 'SUBMITTED')
            FilledButton(
              onPressed: state.busy
                  ? null
                  : () => transition(state, task, 'COMPLETED'),
              child: const Text('Duyệt hoàn tất'),
            ),
          if (owner && ['ASSIGNED', 'IN_PROGRESS'].contains(task['status']))
            TextButton(
              onPressed: state.busy
                  ? null
                  : () => transition(state, task, 'CANCELLED'),
              child: const Text('Hủy công việc theo điều kiện'),
            ),
          const Divider(height: 32),
          const Text(
            'Lịch sử',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          for (final event in (detail['history'] as List? ?? []).map(objectOf))
            RecordCard(
              title: valueOf(event, 'actorName'),
              subtitle:
                  '${valueOf(event, 'action')}\n${valueOf(event, 'report', '')}\n${dateText(event['createdAt'])}',
            ),
          if (detail['hasMore'] == true)
            const InfoBox(
              'Đang hiển thị trang lịch sử mới nhất. Lịch sử đầy đủ có trên cổng Web.',
            ),
        ],
      );
    },
  );

  Future<void> staffPreorder(
    ResourceViewState state,
    Json order,
    Json options,
  ) => state.run(() async {
    final request = order['requestId'] as String;
    final slots = (options['slots'] as List? ?? [])
        .map(objectOf)
        .where((s) => s['zone'] == 'PREORDER')
        .toList();
    final form = await askForm(
      context,
      'Nạp đơn ${valueOf(order, 'orderCode')}',
      [
        InputSpec(
          'slotId',
          'Ô PREORDER',
          choices: {for (final s in slots) '${s['id']}': '${s['slotCode']}'},
        ),
        const InputSpec(
          'operation',
          'Bước thực hiện',
          choices: {
            'OTP': 'Gửi OTP nạp qua email',
            'FULFILL': 'Xác nhận nạp sau khi đóng cửa',
          },
        ),
      ],
    );
    if (form == null) return;
    final base = '/api/staff/tasks/$id/preorders/$request';
    if (form['operation'] == 'OTP') {
      final result = objectOf(
        await widget.api.post('$base/loading-access', {
          'slotId': form['slotId'],
        }),
      );
      loadingAccess[request] = '${result['id']}';
      if (mounted) {
        await showAccessCode(context, {
          ...result,
          'message': 'OTP đã gửi đến email của tài khoản nạp hoa.',
        });
      }
    } else {
      final accessId = loadingAccess[request];
      if (accessId == null) {
        throw const ApiError(
          409,
          'Lấy quyền nạp trong phiên này trước khi xác nhận.',
        );
      }
      await widget.api.post('$base/fulfill', {
        'slotId': form['slotId'],
        'qrCode': 'FB-${const Uuid().v4()}',
        'loadingAccessId': accessId,
      });
      loadingAccess.remove(request);
      if (mounted) message(context, 'Máy chủ đã xác nhận kết quả nạp.');
    }
  });
}

class InstallationsPage extends StatelessWidget {
  const InstallationsPage(this.api, {super.key});
  final ApiClient api;
  @override
  Widget build(BuildContext context) => ApiListPage(
    api: api,
    path: '/api/staff/kiosk-installations',
    title: 'Lắp đặt kiosk',
    subtitle: 'Lịch và hồ sơ bạn được Manager phân công.',
    item: (context, row, state) => RecordCard(
      title: valueOf(row, 'shopName'),
      subtitle:
          '${valueOf(row, 'installationAddress')}\n${valueOf(row, 'scheduledDate')} • ${valueOf(row, 'timeWindow', '')}',
      status: row['status'],
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => InstallationDetail(api, '${row['id']}'),
          ),
        );
        await state.reload();
      },
    ),
  );
}

class InstallationDetail extends StatelessWidget {
  const InstallationDetail(this.api, this.id, {super.key});
  final ApiClient api;
  final String id;
  @override
  Widget build(BuildContext context) {
    final base = '/api/staff/kiosk-installations/$id';
    return ResourceView(
      title: 'Hồ sơ lắp đặt',
      load: () => api.get(base),
      builder: (context, data, state) {
        final row = objectOf(data);
        final active = row['status'] == 'INSTALLING';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageTitle(
              valueOf(row, 'shopName'),
              '${valueOf(row, 'kioskCode')} • ${valueOf(row, 'scheduledDate')}',
            ),
            StatusChip(row['status']),
            RecordCard(
              title: 'Địa chỉ lắp đặt',
              subtitle: valueOf(row, 'installationAddress'),
              onTap: () => state.run(
                () => navigateAddress(valueOf(row, 'installationAddress')),
              ),
            ),
            Text(
              'Liên hệ: ${valueOf(row, 'phone')}\n${valueOf(row, 'contactEmail')}',
            ),
            if (row['reworkReason'] != null)
              InfoBox('Yêu cầu làm lại: ${row['reworkReason']}', warning: true),
            if (row['status'] == 'SCHEDULED')
              FilledButton(
                onPressed: state.busy
                    ? null
                    : () => state.run(() async {
                        await api.post('$base/start');
                      }),
                child: const Text('Bắt đầu lắp đặt'),
              ),
            if (active) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: state.busy
                    ? null
                    : () => state.run(() async {
                        final file = await chooseEvidence(context);
                        if (file == null) return;
                        final evidence = await api.upload(
                          '$base/evidence/upload',
                          file,
                        );
                        await api.post('$base/evidence', {
                          'id': const Uuid().v4(),
                          'reference': evidence['reference'],
                        });
                      }),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Thêm bằng chứng lắp đặt'),
              ),
              FilledButton(
                onPressed: state.busy
                    ? null
                    : () => state.run(() async {
                        final form =
                            await askForm(context, 'Gửi báo cáo nghiệm thu', [
                              const InputSpec(
                                'report',
                                'Kết quả lắp đặt và kiểm tra',
                                lines: 4,
                                minLength: 10,
                              ),
                            ]);
                        if (form != null) {
                          await api.post('$base/submit', {
                            'report': form['report'],
                          });
                        }
                      }),
                child: const Text('Gửi Manager nghiệm thu'),
              ),
            ],
            if (row['technicianReport'] != null)
              InfoBox('Báo cáo: ${row['technicianReport']}'),
            Text(
              'Ảnh minh chứng đã gắn: ${(row['evidence'] as List? ?? []).length}',
            ),
            const InfoBox(
              'Chỉ Manager nghiệm thu và bàn giao. Gửi báo cáo chưa đồng nghĩa kiosk đã được bàn giao.',
            ),
          ],
        );
      },
    );
  }
}

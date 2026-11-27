import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';
import 'technician_iot_health.dart';
import 'seller_tasks.dart';
import 'task_support.dart';
import 'staff_stock.dart';
import 'preorder_support.dart' show normalizeOrderQuery;

class TasksPage extends StatefulWidget {
  const TasksPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  String filter = '', query = '', kiosk = '';
  int page = 1;
  final resourceKey = GlobalKey<ResourceViewState>();

  Future<List<Json>> load() async {
    final tasks = <String, Json>{};
    for (var number = 1; ; number++) {
      final data = await widget.api.get('/api/staff/tasks?page=$number');
      final rows = itemsOf(data);
      final before = tasks.length;
      for (final row in rows) {
        tasks[valueOf(row, 'id')] = row;
      }
      if (data is! Map || data['hasMore'] != true) return tasks.values.toList();
      if (tasks.length == before) {
        throw const ApiError(500, 'Chưa tải đủ công việc. Vui lòng thử lại.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.session.role == AppRole.seller) {
      return SellerTasksPage(widget.api, widget.session);
    }
    return ResourceView(
      key: resourceKey,
      resourceKey: widget.session.id,
      load: load,
      builder: (context, data, state) {
        final tasks = itemsOf(data);
        final kiosks = {
          for (final row in tasks)
            valueOf(row, 'kioskId'): valueOf(row, 'kioskName'),
        };
        final selectedKiosk = kiosks.containsKey(kiosk) ? kiosk : '';
        final search = normalizeOrderQuery(query);
        final rows = tasks
            .where(
              (row) =>
                  (filter.isEmpty || row['status'] == filter) &&
                  (selectedKiosk.isEmpty || row['kioskId'] == selectedKiosk) &&
                  (search.isEmpty ||
                      normalizeOrderQuery(
                        [
                          row['kioskName'],
                          row['address'],
                          row['instructions'],
                          row['report'],
                          row['id'],
                          taskKindText(row['kind']),
                        ].whereType<String>().join(' '),
                      ).contains(search)),
            )
            .toList();
        const pageSize = 10;
        final currentPage = page.clamp(
          1,
          ((rows.length + pageSize - 1) ~/ pageSize).clamp(1, 100000),
        );
        final visible = rows.skip((currentPage - 1) * pageSize).take(pageSize);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageTitle('Công việc của tôi', ''),
            Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                for (final code in [
                  '',
                  'ASSIGNED',
                  'IN_PROGRESS',
                  'SUBMITTED',
                  'COMPLETED',
                  'CANCELLED',
                ])
                  ChoiceChip(
                    selected: filter == code,
                    label: Text(
                      code.isEmpty
                          ? 'Tất cả'
                          : code == 'IN_PROGRESS'
                          ? 'Đang làm'
                          : statusText(code),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onSelected: (_) => setState(() {
                      filter = code;
                      page = 1;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Tìm công việc',
                hintText: 'Tên kiosk, nội dung hoặc mã công việc',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() {
                query = value;
                page = 1;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(selectedKiosk),
              initialValue: selectedKiosk,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Kiosk'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Tất cả kiosk')),
                for (final entry in kiosks.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() {
                kiosk = value ?? '';
                page = 1;
              }),
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty) const InfoBox('Không có công việc phù hợp.'),
            for (final row in visible)
              RecordCard(
                title: valueOf(row, 'kioskName'),
                subtitle:
                    '${taskKindText(row['kind'])}\n${valueOf(row, 'instructions', '')}',
                status: row['status'],
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          TaskDetailPage(widget.api, widget.session, row),
                    ),
                  );
                  if (mounted) await state.reload(background: true);
                },
              ),
            if (rows.length > pageSize || currentPage > 1)
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: currentPage > 1
                        ? () => setState(() => page = currentPage - 1)
                        : null,
                    child: const Text('Trang trước'),
                  ),
                  Text('Trang $currentPage'),
                  TextButton(
                    onPressed: currentPage * pageSize < rows.length
                        ? () => setState(() => page = currentPage + 1)
                        : null,
                    child: const Text('Trang sau'),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

String taskKindText(dynamic kind) => switch (kind) {
  'INCIDENT' => 'Kiểm tra sự cố',
  'KIOSK_REMOVAL' => 'Tháo dỡ kiosk',
  _ => 'Nạp / giao hoa',
};

class TaskDetailPage extends StatefulWidget {
  const TaskDetailPage(this.api, this.session, this.task, {super.key});
  final ApiClient api;
  final Session session;
  final Json task;
  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  final resourceKey = GlobalKey<ResourceViewState>();
  Timer? poll;
  @override
  void initState() {
    super.initState();
    poll = Timer.periodic(const Duration(seconds: 5), (_) {
      final state = resourceKey.currentState;
      if (mounted &&
          state != null &&
          !state.busy &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        unawaited(state.reload(background: true));
      }
    });
  }

  @override
  void dispose() {
    poll?.cancel();
    super.dispose();
  }

  final loadingAccess = <String, String>{};
  String get id => widget.task['id'] as String;
  bool get owner => widget.session.role == AppRole.seller;
  bool get qualityTask => widget.task['workType'] == 'FLOWER_QUALITY';
  String get path => owner
      ? '/api/sellers/${widget.session.sellerId}/staff-tasks/$id'
      : '/api/staff/tasks/$id';
  Future<Json?> optional(String endpoint) async {
    try {
      final result = await widget.api.get(endpoint);
      return result == null ? null : objectOf(result);
    } on ApiError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<Json> load() async {
    final detail = objectOf(await widget.api.get(path));
    Json? inventory, preorders, quality, stock;
    if (widget.session.role == AppRole.staff) {
      if (qualityTask) quality = await optional('/api/staff/tasks/$id/quality');
      inventory = await optional('/api/staff/tasks/$id/inventory-maintenance');
      if (inventory == null) {
        preorders = await optional('/api/staff/tasks/$id/preorders');
        if (!qualityTask) stock = await optional('/api/staff/tasks/$id/stock');
      }
    }
    return {
      'detail': detail,
      'inventory': inventory,
      'preorders': preorders,
      'quality': quality,
      'stock': stock,
    };
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
  Future<void> issueInventory(
    ResourceViewState state,
    String operation,
  ) => state.run(() async {
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
      qualityTask ? 'Lấy mã thao tác ô?' : 'Mở ô được giao?',
      qualityTask
          ? 'Đứng cạnh đúng ô tủ và nhập mã ngay trong ứng dụng.'
          : 'Đứng cạnh đúng ô tủ trước khi xác nhận mở.',
    )) {
      return;
    }
    final result = objectOf(
      await widget.api.post(
        '/api/staff/tasks/$id/inventory-maintenance/${qualityTask ? 'access' : 'open'}',
        {'operation': operation, 'reason': reason},
      ),
    );
    if (mounted) {
      if (qualityTask) {
        await showAccessCode(context, result, api: widget.api);
      } else {
        message(context, 'Đã gửi yêu cầu mở ô. Chờ tủ phản hồi.');
      }
    }
  });
  @override
  Widget build(BuildContext context) => owner
      ? SellerTaskDetailPage(widget.api, widget.session, widget.task)
      : ResourceView(
          key: resourceKey,
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
                  status: StatusChip(task['status']),
                ),
                if (data['quality'] is Map) ...[
                  StatusHeading(
                    title: const Text(
                      'Phản ánh chất lượng',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    status: StatusChip(data['quality']['handlingState']),
                  ),
                  InfoBox('${data['quality']['reason']}'),
                  if (data['quality']['replacement'] is Map)
                    InfoBox(
                      'Hoa thay: ${data['quality']['replacement']['state']} · Ô ${data['quality']['replacement']['slotCode']}',
                    ),
                ],

                RecordCard(
                  title: 'Địa điểm',
                  subtitle: valueOf(task, 'address'),
                  onTap: () => state.run(
                    () => navigateAddress(valueOf(task, 'address')),
                  ),
                ),
                Text(
                  'Tủ: ${statusText(detail['kioskStatus'])} • Tín hiệu: ${dateText(detail['lastHeartbeatAt'])}',
                ),
                if (detail['slotCode'] != null)
                  InfoBox(
                    'Ô ${detail['slotCode']} • ${statusText(detail['slotStatus'])}',
                  ),
                if (widget.session.role == AppRole.technician)
                  TechnicianIoTHealth(api: widget.api, taskId: id),
                if (detail['incident'] is Map)
                  InfoBox(
                    valueOf(
                      objectOf(detail['incident']),
                      'reason',
                      'Kiểm tra thông tin sự cố theo công việc.',
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => openTaskPage(
                    context,
                    EvidenceGallery(widget.api, '$path/evidence'),
                  ),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Xem ảnh minh chứng'),
                ),
                if (widget.session.role == AppRole.technician &&
                    task['kind'] == 'INCIDENT' &&
                    detail['slotCode'] != null &&
                    active)
                  RepairReadinessPanel(widget.api, id),
                if (active && data['stock'] is Map)
                  OutlinedButton.icon(
                    onPressed: () async {
                      await openTaskPage(
                        context,
                        StaffStockPage(widget.api, id),
                      );
                      if (mounted) await state.reload(background: true);
                    },
                    icon: const Icon(Icons.local_florist_outlined),
                    label: const Text('Nạp hoa bán tại tủ'),
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
                    'Thao tác: ${inventory['action']}\nTiến độ: ${statusText(inventory['sessionStage'])}\nThao tác tại đúng ô tủ được giao.',
                  ),
                  if (active && inventory['sessionStage'] == null)
                    FilledButton(
                      onPressed: state.busy
                          ? null
                          : () => issueInventory(state, 'START'),
                      child: Text(qualityTask ? 'Lấy OTP bắt đầu' : 'Mở ô'),
                    ),
                  if (active &&
                      inventory['sessionSubstate'] ==
                          'RemovalClosedEmptyConfirmed')
                    FilledButton(
                      onPressed: state.busy
                          ? null
                          : () => issueInventory(state, 'OPEN_NEXT'),
                      child: Text(
                        qualityTask
                            ? 'Lấy OTP nạp hoa mới'
                            : 'Mở ô nạp hoa mới',
                      ),
                    ),
                  if (active && inventory['sessionStage'] == 'NeedsInspection')
                    OutlinedButton(
                      onPressed: state.busy
                          ? null
                          : () => issueInventory(state, 'OPEN_FOR_CHECK'),
                      child: Text(
                        qualityTask ? 'Yêu cầu OTP kiểm tra' : 'Mở ô kiểm tra',
                      ),
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
                    task['kind'] == 'INCIDENT' &&
                    detail['slotCode'] != null &&
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
                              await showAccessCode(
                                context,
                                access,
                                api: widget.api,
                              );
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
                            if (widget.session.role == AppRole.technician &&
                                task['kind'] == 'INCIDENT') {
                              state.run(() async {
                                final form = await askForm(
                                  context,
                                  'Gửi báo cáo sửa chữa',
                                  [
                                    const InputSpec(
                                      'report',
                                      'Kết quả kiểm tra / sửa',
                                      lines: 4,
                                      minLength: 10,
                                    ),
                                  ],
                                );
                                if (form == null) return;
                                await widget.api.post(
                                  '/api/staff/tasks/$id/resolve-incident',
                                  {
                                    'id': const Uuid().v4(),
                                    'version': task['version'],
                                    'report': form['report'],
                                  },
                                );
                                if (context.mounted) {
                                  message(
                                    context,
                                    'Đã gửi để Manager kiểm tra.',
                                  );
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
                if (owner &&
                    ['ASSIGNED', 'IN_PROGRESS'].contains(task['status']))
                  TextButton(
                    onPressed: state.busy
                        ? null
                        : () => transition(state, task, 'CANCELLED'),
                    child: const Text('Hủy công việc theo điều kiện'),
                  ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Lịch sử công việc'),
                  children: [
                    for (final event in (detail['history'] as List? ?? []).map(
                      objectOf,
                    ))
                      RecordCard(
                        title: valueOf(event, 'actorName'),
                        subtitle:
                            '${valueOf(event, 'action')}\n${valueOf(event, 'report', '')}\n${dateText(event['createdAt'])}',
                      ),
                    if (detail['hasMore'] == true)
                      TextButton(
                        onPressed: () => openTaskPage(
                          context,
                          TaskHistoryPage(widget.api, path),
                        ),
                        child: const Text('Xem toàn bộ lịch sử'),
                      ),
                  ],
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
      if (mounted) {
        final confirmed = result['requiresCode'] == false
            ? result
            : await showAccessCode(context, {
                ...result,
                'message': 'OTP đã gửi đến email của tài khoản nạp hoa.',
              }, api: widget.api);
        if (confirmed != null) loadingAccess[request] = '${result['id']}';
      }
    } else {
      var accessId = loadingAccess[request];
      if (accessId == null) {
        final recovered = objectOf(
          await widget.api.post('$base/loading-access', {
            'slotId': form['slotId'],
          }),
        );
        accessId = '${recovered['id']}';
        loadingAccess[request] = accessId;
        if (recovered['requiresCode'] != false) {
          throw const ApiError(
            409,
            'Đã gửi quyền nạp mới qua email. Hoàn thành nạp tại kiosk trước khi xác nhận lại.',
          );
        }
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
              status: StatusChip(row['status']),
            ),
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
            OutlinedButton.icon(
              onPressed: () =>
                  openTaskPage(context, EvidenceGallery(api, '$base/evidence')),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(
                'Ảnh minh chứng (${(row['evidence'] as List? ?? []).length})',
              ),
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

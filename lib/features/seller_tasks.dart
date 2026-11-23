import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/team_widgets.dart';
import 'complaints.dart';
import 'inventory.dart' show openPage;

Set<String> sellerTaskTransitions(Json task) => {
  if (['ASSIGNED', 'IN_PROGRESS'].contains(task['status'])) 'CANCELLED',
  if (task['status'] == 'SUBMITTED' &&
      task['workType'] != 'FLOWER_QUALITY') ...[
    'COMPLETED',
    'IN_PROGRESS',
    'CANCELLED',
  ],
};

Future<Json?> findSellerTask(ApiClient api, String base, String id) async {
  final seen = <String>{};
  for (var page = 1; ; page++) {
    final data = await api.get('$base?page=$page');
    final rows = itemsOf(data);
    final row = rows.where((r) => '${r['id']}' == id).firstOrNull;
    if (row != null) return row;
    final before = seen.length;
    seen.addAll(rows.map((r) => '${r['id']}'));
    if (data is! Map ||
        data['hasMore'] != true ||
        rows.isEmpty ||
        seen.length == before) {
      return null;
    }
  }
}

class SellerTasksPage extends StatefulWidget {
  const SellerTasksPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  State<SellerTasksPage> createState() => _SellerTasksPageState();
}

class _SellerTasksPageState extends State<SellerTasksPage> {
  int page = 1;
  String query = '', filter = '';
  String? attemptId, signature;
  Json? draft;
  String get seller => '/api/sellers/${widget.session.sellerId}';

  Future<void> create(ResourceViewState state) => state.run(() async {
    final data = await Future.wait([
      widget.api.get('$seller/staff'),
      widget.api.get('$seller/staff-delivery-scopes'),
    ]);
    final staff = itemsOf(data[0]), scopes = itemsOf(data[1]);
    if (!mounted) return;
    if (staff.isEmpty || scopes.isEmpty) {
      message(
        context,
        staff.isEmpty
            ? 'Chưa có nhân viên đang hoạt động.'
            : 'Chưa có kiosk đủ điều kiện giao hoa.',
      );
      return;
    }
    final form = await askForm(context, 'Giao công việc', [
      InputSpec(
        'assigneeId',
        'Nhân viên phụ trách',
        initial: '${draft?['assigneeId'] ?? ''}',
        choices: {for (final s in staff) '${s['id']}': valueOf(s, 'name')},
      ),
      InputSpec(
        'kioskId',
        'Tủ giao hoa',
        initial: '${draft?['kioskId'] ?? ''}',
        choices: {
          for (final s in scopes)
            '${s['kioskId']}': '${s['kioskName']} · ${s['address']}',
        },
      ),
      InputSpec(
        'instructions',
        'Hướng dẫn công việc',
        initial: '${draft?['instructions'] ?? ''}',
        minLength: 10,
        lines: 3,
      ),
    ], submitLabel: 'Giao công việc');
    if (form == null) return;
    if (form['instructions']!.length > 2000) {
      throw const ApiError(400, 'Hướng dẫn tối đa 2.000 ký tự.');
    }
    draft = Map<String, dynamic>.from(form);
    final key = jsonEncode(form);
    if (signature != key) {
      signature = key;
      attemptId = const Uuid().v4();
    }
    try {
      await widget.api.request(
        'POST',
        '/api/me/staff-tasks',
        body: draft,
        idempotencyKey: attemptId,
      );
      attemptId = signature = null;
      draft = null;
    } on ApiError catch (error) {
      if ([400, 403, 404, 409, 422].contains(error.status)) {
        attemptId = signature = null;
      }
      rethrow;
    }
    if (mounted) message(context, 'Đã giao công việc.');
  });

  @override
  Widget build(BuildContext context) => ResourceView(
    resourceKey: '$page:$filter',
    load: () => widget.api.get(
      '$seller/staff-tasks?${Uri(queryParameters: {'page': '$page', if (filter.isNotEmpty) 'status': filter}).query}',
    ),
    builder: (context, data, state) {
      final rows = itemsOf(data).where(
        (r) =>
            '${r['kioskName']} ${r['assigneeName']} ${r['id']} ${r['instructions']}'
                .toLowerCase()
                .contains(query.trim().toLowerCase()),
      );
      final more = data is Map && data['hasMore'] == true;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamToolbar(
            hint: 'Kiosk, nhân viên hoặc công việc',
            filter: filter,
            labels: teamTaskLabels,
            onQuery: (value) => setState(() => query = value),
            onFilter: (value) => setState(() {
              filter = value;
              page = 1;
            }),
            createLabel: 'Giao việc mới',
            onCreate: state.busy ? null : () => create(state),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: Text('Không có công việc phù hợp.')),
            ),
          for (final row in rows)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SellerTaskDetailPage(widget.api, widget.session, row),
                    ),
                  );
                  await state.reload();
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusHeading(
                        title: Text(
                          teamTaskName(row),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: forest,
                          ),
                        ),
                        status: TeamStatus(valueOf(row, 'status')),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        valueOf(row, 'kioskName'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Phụ trách: ${valueOf(row, 'assigneeName')}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF617568),
                        ),
                      ),
                      if (valueOf(row, 'report', '').trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            valueOf(row, 'report'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (page > 1 || more)
            TeamPaging(
              page: page,
              more: more,
              busy: state.busy,
              onPage: (value) => setState(() => page = value),
            ),
        ],
      );
    },
  );
}

class SellerTaskDetailPage extends StatefulWidget {
  const SellerTaskDetailPage(this.api, this.session, this.seed, {super.key});
  final ApiClient api;
  final Session session;
  final Json seed;
  @override
  State<SellerTaskDetailPage> createState() => _SellerTaskDetailPageState();
}

class _SellerTaskDetailPageState extends State<SellerTaskDetailPage> {
  int historyPage = 1;
  bool blocked = false;
  String get base => '/api/sellers/${widget.session.sellerId}/staff-tasks';
  String get id => '${widget.seed['id']}';

  Future<dynamic> load() => Future.wait([
    widget.api.get('$base/$id?page=$historyPage'),
    findSellerTask(widget.api, base, id),
  ]);

  Future<void> write(String method, String path, Json body) async {
    if (blocked) return;
    try {
      await widget.api.request(method, path, body: body);
    } on ApiError catch (e) {
      if (mounted &&
          (e.ambiguous ||
              e.status == 409 ||
              e.status == 0 ||
              e.status >= 500)) {
        setState(() => blocked = true);
      }
      rethrow;
    }
  }

  Future<void> transition(ResourceViewState state, Json row, String status) =>
      state.run(() async {
        if (!sellerTaskTransitions(row).contains(status)) return;
        final label = status == 'COMPLETED'
            ? 'Duyệt hoàn tất'
            : status == 'IN_PROGRESS'
            ? 'Trả báo cáo'
            : 'Hủy công việc';
        final form = await askForm(context, label, [
          const InputSpec(
            'report',
            'Nội dung phản hồi',
            minLength: 10,
            lines: 3,
          ),
        ]);
        if (form == null) return;
        if (form['report']!.length > 2000) {
          throw const ApiError(400, 'Nội dung tối đa 2.000 ký tự.');
        }
        if (status == 'CANCELLED') {
          if (!mounted ||
              !await confirm(
                context,
                'Hủy công việc?',
                'Nhân viên sẽ không tiếp tục thao tác công việc này.',
              )) {
            return;
          }
        }
        await write('POST', '$base/$id/transition', {
          'version': row['version'],
          'status': status,
          'report': form['report'],
        });
      });

  Future<void> reassign(ResourceViewState state, Json row) => state.run(
    () async {
      final staff = itemsOf(
        await widget.api.get('/api/sellers/${widget.session.sellerId}/staff'),
      ).where((s) => s['id'] != row['assigneeId']).toList();
      if (!mounted) return;
      if (staff.isEmpty) {
        message(context, 'Chưa có nhân viên khác đang hoạt động.');
        return;
      }
      final form = await askForm(context, 'Đổi người phụ trách', [
        InputSpec(
          'assigneeId',
          'Nhân viên mới',
          choices: {for (final s in staff) '${s['id']}': valueOf(s, 'name')},
        ),
        const InputSpec('reason', 'Lý do bàn giao', minLength: 10, lines: 3),
      ]);
      if (form == null) return;
      if (form['reason']!.length > 2000) {
        throw const ApiError(400, 'Lý do tối đa 2.000 ký tự.');
      }
      if (!mounted ||
          !await confirm(
            context,
            'Xác nhận bàn giao?',
            'Người cũ mất quyền thao tác; người mới cần bắt đầu lại công việc.',
          )) {
        return;
      }
      await write('POST', '$base/$id/reassign', {
        'version': row['version'],
        ...form,
      });
    },
  );

  @override
  Widget build(BuildContext context) => ResourceView(
    title: 'Chi tiết công việc',
    resourceKey: historyPage,
    load: load,
    builder: (context, data, state) {
      final result = data as List<dynamic>;
      final detail = objectOf(result[0]);
      final fresh = result[1] as Json?;
      final row = <String, dynamic>{
        ...widget.seed,
        ...?fresh,
        if (detail['version'] != null) 'version': detail['version'],
        if (detail['status'] != null) 'status': detail['status'],
      };
      // Metadata and detail are separate reads. A mismatched version needs a refresh.
      final current =
          fresh != null &&
          fresh['version'] == detail['version'] &&
          fresh['status'] == detail['status'];
      final disabled = state.busy || blocked || !current;
      final open = ['ASSIGNED', 'IN_PROGRESS'].contains(row['status']);
      final quality = row['workType'] == 'FLOWER_QUALITY';
      final transitions = sellerTaskTransitions(row);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamSection(
            children: [
              StatusHeading(
                title: Text(
                  teamTaskName(row),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: forest,
                  ),
                ),
                status: TeamStatus(valueOf(row, 'status')),
              ),
              const SizedBox(height: 20),
              TeamFact('Người phụ trách', valueOf(row, 'assigneeName')),
              TeamFact('Kiosk', valueOf(row, 'kioskName')),
              if (valueOf(row, 'address', '').isNotEmpty)
                TeamFact('Địa chỉ', valueOf(row, 'address')),
              TeamFact('Ghi chú từ shop', valueOf(row, 'instructions')),
              if (valueOf(row, 'report', '').isNotEmpty)
                TeamFact('Báo cáo gần nhất', valueOf(row, 'report')),
            ],
          ),
          if (blocked || !current) ...[
            const Text(
              'Tải lại công việc để cập nhật trạng thái trước khi thao tác.',
              style: TextStyle(color: Color(0xFFB42318)),
            ),
            TextButton.icon(
              onPressed: state.busy
                  ? null
                  : () async {
                      await state.reload();
                      if (mounted) setState(() => blocked = false);
                    },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tải lại công việc'),
            ),
          ],
          if (quality && row['complaintId'] != null) ...[
            FilledButton(
              onPressed: state.busy
                  ? null
                  : () async {
                      await openPage(
                        context,
                        'Phản ánh chất lượng',
                        ComplaintDetail(
                          widget.api,
                          widget.session,
                          '${row['complaintId']}',
                        ),
                      );
                      await state.reload();
                    },
              child: const Text('Duyệt / trả báo cáo'),
            ),
            const SizedBox(height: 10),
          ],
          if (transitions.contains('COMPLETED')) ...[
            FilledButton(
              onPressed: disabled
                  ? null
                  : () => transition(state, row, 'COMPLETED'),
              child: const Text('Duyệt hoàn tất'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: disabled
                  ? null
                  : () => transition(state, row, 'IN_PROGRESS'),
              child: const Text('Trả báo cáo để bổ sung'),
            ),
            const SizedBox(height: 10),
          ],
          if (open) ...[
            OutlinedButton.icon(
              onPressed: disabled ? null : () => reassign(state, row),
              icon: const Icon(Icons.swap_horiz_rounded, size: 19),
              label: const Text('Đổi người phụ trách'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: disabled
                  ? null
                  : () => state.run(() async {
                      final form =
                          await askForm(context, 'Sửa hướng dẫn công việc', [
                            InputSpec(
                              'instructions',
                              'Hướng dẫn',
                              initial: valueOf(row, 'instructions', ''),
                              minLength: 10,
                              lines: 3,
                            ),
                          ], submitLabel: 'Lưu thay đổi');
                      if (form == null) return;
                      if (form['instructions']!.length > 2000) {
                        throw const ApiError(
                          400,
                          'Hướng dẫn tối đa 2.000 ký tự.',
                        );
                      }
                      await write('PATCH', '/api/me/staff-tasks/$id', {
                        'version': row['version'],
                        'instructions': form['instructions'],
                      });
                    }),
              icon: const Icon(Icons.edit_outlined, size: 19),
              label: const Text('Sửa hướng dẫn'),
            ),
            const SizedBox(height: 10),
          ],
          if (transitions.contains('CANCELLED')) ...[
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB42318),
              ),
              onPressed: disabled
                  ? null
                  : () => transition(state, row, 'CANCELLED'),
              child: const Text('Hủy công việc'),
            ),
            const SizedBox(height: 16),
          ],
          _TaskEvidence(
            widget.api,
            '$base/$id/evidence',
            key: ValueKey(row['version']),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              title: const Text(
                'Thông tin tủ và lịch sử',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: forest,
                ),
              ),
              childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                TeamFact(
                  'Trạng thái kiosk',
                  const {
                        'ONLINE': 'Trực tuyến',
                        'OFFLINE': 'Ngoại tuyến',
                        'FAULT': 'Sự cố',
                        'MAINTENANCE': 'Đang bảo trì',
                        'DISABLED': 'Ngừng hoạt động',
                      }[detail['kioskStatus']] ??
                      valueOf(detail, 'kioskStatus'),
                ),
                if (detail['lastHeartbeatAt'] != null)
                  TeamFact(
                    'Tín hiệu gần nhất',
                    dateText(detail['lastHeartbeatAt']),
                  ),
                for (final event in itemsOf(detail['history'] ?? []))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 5),
                          child: Icon(Icons.circle, size: 6, color: forest),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                const {
                                      'STAFF_TASK_ASSIGNED':
                                          'Phân công công việc',
                                      'STAFF_TASK_UPDATED':
                                          'Cập nhật công việc',
                                      'STAFF_TASK_INSTRUCTIONS_EDITED':
                                          'Sửa hướng dẫn',
                                      'STAFF_TASK_STOCKED': 'Ghi nhận nạp hoa',
                                      'STAFF_TASK_REASSIGNED':
                                          'Bàn giao công việc',
                                      'STAFF_TASK_EVIDENCE_ADDED':
                                          'Thêm ảnh minh chứng',
                                    }[event['action']] ??
                                    valueOf(event, 'action'),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: forest,
                                ),
                              ),
                              Text(
                                '${event['actorName']} · ${dateText(event['createdAt'])}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  height: 1.6,
                                  color: Color(0xFF617568),
                                ),
                              ),
                              if (event['toStatus'] != null)
                                Text(
                                  '${teamTaskLabels[event['fromStatus']] ?? event['fromStatus'] ?? ''} → ${teamTaskLabels[event['toStatus']] ?? event['toStatus']}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                              if (event['report'] != null)
                                Text(
                                  '${event['report']}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (historyPage > 1 || detail['hasMore'] == true)
                  TeamPaging(
                    page: historyPage,
                    more: detail['hasMore'] == true,
                    busy: state.busy,
                    onPage: (value) => setState(() => historyPage = value),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _TaskEvidence extends StatefulWidget {
  const _TaskEvidence(this.api, this.path, {super.key});
  final ApiClient api;
  final String path;
  @override
  State<_TaskEvidence> createState() => _TaskEvidenceState();
}

class _TaskEvidenceState extends State<_TaskEvidence> {
  int page = 1;
  Future<dynamic>? photos;
  void load() =>
      setState(() => photos = widget.api.get('${widget.path}?page=$page'));
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      title: const Text(
        'Ảnh minh chứng',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: forest,
        ),
      ),
      onExpansionChanged: (open) {
        if (open && photos == null) load();
      },
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        if (photos != null)
          FutureBuilder<dynamic>(
            future: photos,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return TextButton(
                  onPressed: load,
                  child: const Text('Tải lại ảnh'),
                );
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              }
              final rows = itemsOf(snapshot.data);
              final more =
                  snapshot.data is Map && snapshot.data['hasMore'] == true;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (rows.isEmpty)
                    const Text(
                      'Chưa có ảnh minh chứng.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF617568)),
                    ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 12,
                    children: [
                      for (final photo in rows)
                        _TaskPhoto(
                          widget.api,
                          '${widget.path}/${photo['id']}',
                          photo,
                          key: ValueKey(photo['id']),
                        ),
                    ],
                  ),
                  if (page > 1 || more)
                    TeamPaging(
                      page: page,
                      more: more,
                      onPage: (value) {
                        page = value;
                        load();
                      },
                    ),
                ],
              );
            },
          ),
      ],
    ),
  );
}

class _TaskPhoto extends StatefulWidget {
  const _TaskPhoto(this.api, this.path, this.row, {super.key});
  final ApiClient api;
  final String path;
  final Json row;
  @override
  State<_TaskPhoto> createState() => _TaskPhotoState();
}

class _TaskPhotoState extends State<_TaskPhoto> {
  late Future<Uint8List> bytes = widget.api.imageBytes(widget.path);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 112,
    child: Column(
      children: [
        SizedBox(
          height: 104,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: FutureBuilder<Uint8List>(
              future: bytes,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return IconButton(
                    tooltip: 'Tải lại ảnh',
                    onPressed: () => setState(
                      () => bytes = widget.api.imageBytes(widget.path),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                return Semantics(
                  label: 'Xem ảnh minh chứng',
                  button: true,
                  child: InkWell(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (dialogContext) => Dialog(
                        insetPadding: const EdgeInsets.all(16),
                        child: SizedBox(
                          height: MediaQuery.sizeOf(context).height * .7,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: InteractiveViewer(
                                  child: Image.memory(
                                    snapshot.data!,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: IconButton(
                                  tooltip: 'Đóng ảnh',
                                  onPressed: () => Navigator.pop(dialogContext),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    child: Image.memory(
                      snapshot.data!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          dateText(widget.row['createdAt']),
          style: const TextStyle(fontSize: 10, color: Color(0xFF617568)),
        ),
      ],
    ),
  );
}

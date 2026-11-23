import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';
import 'inventory.dart' show openPage;

const complaintLabels = {
  'REPORTED': 'Chờ tiếp nhận',
  'ACCEPTED': 'Đã tiếp nhận',
  'IN_PROGRESS': 'Đang kiểm tra',
  'REVIEW_REQUIRED': 'Chờ duyệt báo cáo',
  'REPLACEMENT_READY': 'Sẵn sàng nhận hoa thay',
  'ATTENTION_REQUIRED': 'Cần xử lý tiếp',
  'REFUND_REVIEW': 'Chờ xét hoàn tiền',
  'RESOLVED': 'Đã xử lý',
};
const replacementLabels = {
  'PLANNED': 'Chờ nạp hoa thay',
  'LOADED': 'Đã nạp, chờ duyệt',
  'READY': 'Sẵn sàng nhận hoa thay',
  'COLLECTED': 'Đã nhận hoa thay',
  'EXPIRED': 'Hết hạn nhận hoa thay',
  'CANCELLED': 'Đã hủy phương án',
};
String complaintState(Json row) =>
    valueOf(row, 'handlingState', '${row['status'] ?? ''}');
bool activeComplaintReplacement(Json row) => [
  'PLANNED',
  'LOADED',
  'READY',
].contains((row['replacement'] as Map?)?['state']);

Set<String> complaintActions(Json row) {
  if (row['status'] != 'OPEN') return {};
  final handling = complaintState(row);
  final task = row['task'] as Map?;
  final active = activeComplaintReplacement(row);
  return {
    if (handling == 'REPORTED') 'accept',
    if (row['acceptedAt'] != null &&
        ['ACCEPTED', 'IN_PROGRESS', 'ATTENTION_REQUIRED'].contains(handling) &&
        !active &&
        (task == null ||
            ![
              'ASSIGNED',
              'IN_PROGRESS',
              'SUBMITTED',
            ].contains(task['status'])) &&
        itemsOf(row['items'] ?? []).isNotEmpty)
      'assignment',
    if (task != null &&
        ['ASSIGNED', 'IN_PROGRESS'].contains(task['status']) &&
        row['replacement'] == null &&
        ['IN_PROGRESS', 'ACCEPTED', 'ATTENTION_REQUIRED'].contains(handling))
      'replacement-plan',
    if (task?['status'] == 'SUBMITTED') 'review',
    if (active) 'replacement/cancel',
  };
}

Color complaintColor(String status) => switch (status) {
  'RESOLVED' || 'COLLECTED' => forest,
  'IN_PROGRESS' ||
  'ACCEPTED' ||
  'REPLACEMENT_READY' ||
  'READY' => const Color(0xFF175CD3),
  'ATTENTION_REQUIRED' || 'EXPIRED' || 'CANCELLED' => const Color(0xFFB42318),
  _ => const Color(0xFF9A6700),
};

class _ComplaintStatus extends StatelessWidget {
  const _ComplaintStatus(this.status);
  final String status;
  @override
  Widget build(BuildContext context) => Text(
    complaintLabels[status] ?? replacementLabels[status] ?? status,
    style: TextStyle(
      fontSize: 12,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: complaintColor(status),
    ),
  );
}

class ComplaintsPage extends StatefulWidget {
  const ComplaintsPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  State<ComplaintsPage> createState() => _ComplaintsPageState();
}

class _ComplaintsPageState extends State<ComplaintsPage> {
  int page = 1;
  String filter = '', query = '';
  @override
  Widget build(BuildContext context) => ResourceView(
    resourceKey: '$page:$filter',
    load: () => widget.api.get(
      '/api/me/complaints?${Uri(queryParameters: {'page': '$page', if (filter.isNotEmpty) 'state': filter}).query}',
    ),
    builder: (context, data, state) {
      final rows = itemsOf(data)
          .where(
            (row) =>
                '${row['orderCode']} ${row['reason']} ${itemsOf(row['items'] ?? []).map((r) => r['name']).join(' ')}'
                    .toLowerCase()
                    .contains(query.trim().toLowerCase()),
          )
          .toList();
      final more = data is Map && data['hasMore'] == true;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Mã đơn, nội dung hoặc tên hoa',
                    prefixIcon: Icon(Icons.search_rounded, size: 21),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: 'Lọc phản ánh',
                initialValue: filter,
                icon: Icon(
                  filter.isEmpty
                      ? Icons.filter_list_rounded
                      : Icons.filter_alt_rounded,
                  color: forest,
                ),
                onSelected: (value) => setState(() {
                  filter = value;
                  page = 1;
                }),
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: '',
                    checked: filter.isEmpty,
                    child: const Text('Tất cả trạng thái'),
                  ),
                  for (final entry in complaintLabels.entries)
                    CheckedPopupMenuItem(
                      value: entry.key,
                      checked: filter == entry.key,
                      child: Text(entry.value),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text('Không có phản ánh phù hợp.')),
            ),
          for (final row in rows)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () async {
                  await openPage(
                    context,
                    'Chi tiết phản ánh',
                    ComplaintDetail(widget.api, widget.session, '${row['id']}'),
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
                          'Đơn ${row['orderCode']}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: forest,
                          ),
                        ),
                        status: _ComplaintStatus(complaintState(row)),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        valueOf(row, 'reason'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                      if (row['createdAt'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            dateText(row['createdAt']),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF617568),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (page > 1 || more)
            _ComplaintPaging(
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

class _ComplaintPaging extends StatelessWidget {
  const _ComplaintPaging({
    required this.page,
    required this.more,
    required this.busy,
    required this.onPage,
  });
  final int page;
  final bool more, busy;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: page > 1 && !busy ? () => onPage(page - 1) : null,
          child: const Text('Trước'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Trang $page',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(
          onPressed: more && !busy ? () => onPage(page + 1) : null,
          child: const Text('Sau'),
        ),
      ],
    ),
  );
}

class ComplaintDetail extends StatefulWidget {
  const ComplaintDetail(this.api, this.session, this.id, {super.key});
  final ApiClient api;
  final Session session;
  final String id;
  @override
  State<ComplaintDetail> createState() => _ComplaintDetailState();
}

class _ComplaintDetailState extends State<ComplaintDetail> {
  int evidencePage = 1;
  bool blocked = false;
  String? assignmentSignature, assignmentId;
  ApiClient get api => widget.api;
  String get base => '/api/me/complaints/${widget.id}';

  Future<void> mutate(String action, Json payload) async {
    if (blocked) return;
    try {
      await api.post('$base/$action', payload);
    } on ApiError catch (error) {
      if (error.ambiguous ||
          error.status >= 500 ||
          error.status == 409 ||
          error.status == 0) {
        if (mounted) setState(() => blocked = true);
      }
      rethrow;
    }
  }

  Future<void> perform(
    String action,
    Json item,
    ResourceViewState state,
  ) => state.run(() async {
    if (blocked || !complaintActions(item).contains(action)) return;
    final task = objectOf(item['task'] ?? <String, dynamic>{});
    final version = item['version'];
    if (action == 'accept') {
      await mutate(action, {'version': version});
      return;
    }
    if (action == 'assignment') {
      final staff = itemsOf(
        await api.get('/api/sellers/${widget.session.sellerId}/staff'),
      );
      if (!mounted) return;
      if (staff.isEmpty) {
        message(context, 'Chưa có nhân viên đang hoạt động.');
        return;
      }
      final form = await askForm(context, 'Giao nhân viên kiểm tra', [
        InputSpec(
          'assigneeId',
          'Nhân viên',
          choices: {for (final s in staff) '${s['id']}': valueOf(s, 'name')},
        ),
        InputSpec(
          'orderItemId',
          'Hoa cần kiểm tra',
          choices: {
            for (final s in itemsOf(item['items'] ?? []))
              '${s['orderItemId']}': valueOf(s, 'name'),
          },
        ),
        const InputSpec('instructions', 'Hướng dẫn', minLength: 10, lines: 3),
      ], submitLabel: 'Giao việc');
      if (form == null || !mounted) return;
      if (form['instructions']!.length > 500) {
        throw const ApiError(400, 'Hướng dẫn tối đa 500 ký tự.');
      }
      final signature = jsonEncode(form);
      if (assignmentSignature != signature) {
        assignmentSignature = signature;
        assignmentId = const Uuid().v4();
      }
      await mutate(action, {
        'version': version,
        'taskId': assignmentId,
        ...form,
      });
      assignmentId = assignmentSignature = null;
      return;
    }
    if (action == 'replacement-plan') {
      final choices = await Future.wait([
        api.get('/api/me/products'),
        api.get('/api/me/kiosks/${item['kioskId']}/slots'),
      ]);
      final products = itemsOf(choices[0]).where(
        (p) =>
            p['status'] == 'ACTIVE' &&
            (num.tryParse('${p['quantity']}') ?? 0) > 0,
      );
      final slots = itemsOf(choices[1]).where(
        (s) =>
            s['kioskId'] == item['kioskId'] &&
            ['WALK_IN', 'PREORDER'].contains(s['zone']) &&
            s['status'] == 'RENTED_EMPTY' &&
            s['bouquetId'] == null &&
            s['sensorReady'] == true,
      );
      if (!mounted) return;
      if (products.isEmpty || slots.isEmpty) {
        message(
          context,
          'Chưa có mẫu còn tồn hoặc ô trống có cảm biến sẵn sàng tại kiosk gốc.',
        );
        return;
      }
      final form = await askForm(context, 'Chọn hoa thay và ô tủ', [
        InputSpec(
          'productId',
          'Mẫu hoa còn tồn',
          choices: {
            for (final p in products)
              '${p['id']}': '${p['name']} · Còn ${p['quantity']}',
          },
        ),
        InputSpec(
          'slotId',
          'Ô trống tại kiosk gốc',
          choices: {
            for (final s in slots)
              '${s['id']}':
                  '${s['slotCode']} · ${s['zone'] == 'PREORDER' ? 'Đặt trước' : 'Tại chỗ'}',
          },
        ),
      ]);
      if (form == null) return;
      await mutate(action, {
        'version': version,
        'taskVersion': task['version'],
        ...form,
      });
      return;
    }
    if (action == 'review') {
      final replacement = objectOf(item['replacement'] ?? <String, dynamic>{});
      final active = activeComplaintReplacement(item);
      final form = await askForm(context, 'Duyệt báo cáo', [
        InputSpec(
          'outcome',
          'Kết quả xử lý',
          choices: {
            'RETURN': 'Trả việc để bổ sung',
            if (!active) 'EXPLANATION': 'Gửi giải thích cho khách',
            if (replacement['state'] == 'LOADED')
              'REPLACEMENT': 'Cho khách nhận hoa thay',
            if (!active) 'REFUND_REVIEW': 'Chuyển xét hoàn tiền',
          },
        ),
        const InputSpec(
          'resolution',
          'Nội dung phản hồi',
          minLength: 10,
          lines: 3,
        ),
      ]);
      if (form == null) return;
      if (form['resolution']!.length > 2000) {
        throw const ApiError(400, 'Nội dung phản hồi tối đa 2.000 ký tự.');
      }
      await mutate(action, {
        'version': version,
        'taskVersion': task['version'],
        ...form,
      });
      return;
    }
    final form = await askForm(
      context,
      'Hủy phương án hoa thay',
      [const InputSpec('reason', 'Lý do hủy', minLength: 10, lines: 3)],
      description:
          'Khách sẽ mất quyền nhận hoa thay. Hoa đã nạp cần được thu hồi qua luồng tại tủ.',
    );
    if (form == null) return;
    if (form['reason']!.length > 2000) {
      throw const ApiError(400, 'Lý do tối đa 2.000 ký tự.');
    }
    await mutate(action, {'version': version, ...form});
  });

  Widget section(String title, List<Widget> children, {Widget? status}) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatusHeading(
            title: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: forest,
              ),
            ),
            status: status,
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  Widget fact(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF617568)),
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, height: 1.5)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        labelStyle: const TextStyle(fontSize: 13),
      ),
    ),
    child: ResourceView(
      resourceKey: evidencePage,
      load: () => api.get('$base?evidencePage=$evidencePage'),
      builder: (context, data, state) {
        final item = objectOf(data);
        final task = objectOf(item['task'] ?? <String, dynamic>{}),
            replacement = objectOf(item['replacement'] ?? <String, dynamic>{});
        final evidence = item['evidence'] ?? {'items': []};
        final photos = itemsOf(evidence);
        final actions = complaintActions(item);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            section('Đơn ${item['orderCode']}', [
              if (item['createdAt'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    'Gửi ${dateText(item['createdAt'])}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF617568),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                valueOf(item, 'reason'),
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
              if (itemsOf(item['items'] ?? []).isNotEmpty) ...[
                const SizedBox(height: 16),
                for (final flower in itemsOf(item['items']))
                  fact(
                    'Hoa trong đơn${flower['slotCode'] == null ? '' : ' · Ô ${flower['slotCode']}'}',
                    valueOf(flower, 'name'),
                  ),
              ],
            ], status: _ComplaintStatus(complaintState(item))),
            if (task.isNotEmpty || item['resolution'] != null)
              section('Xử lý phản ánh', [
                if (task.isNotEmpty) ...[
                  fact(
                    'Tiến độ công việc',
                    const {
                          'ASSIGNED': 'Chờ bắt đầu',
                          'IN_PROGRESS': 'Đang thực hiện',
                          'SUBMITTED': 'Chờ duyệt báo cáo',
                          'COMPLETED': 'Đã hoàn thành',
                          'CANCELLED': 'Đã hủy',
                        }[task['status']] ??
                        valueOf(task, 'status'),
                  ),
                  fact(
                    'Việc được giao',
                    valueOf(task, 'instructions', 'Chưa có hướng dẫn'),
                  ),
                  if (task['report'] != null)
                    fact('Báo cáo nhân viên', valueOf(task, 'report')),
                ],
                if (item['resolution'] != null)
                  fact('Kết quả xử lý', valueOf(item, 'resolution')),
                if (item['outcome'] == 'REFUND_REVIEW' &&
                    item['status'] == 'OPEN')
                  const Text(
                    'Đã chuyển xét duyệt; khoản hoàn chưa được chi.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF9A6700)),
                  ),
              ]),
            if (replacement.isNotEmpty)
              section('Hoa thay thế', [
                const SizedBox(height: 12),
                fact('Ô nhận hoa', valueOf(replacement, 'slotCode')),
                if (replacement['expiresAt'] != null)
                  fact('Hạn giữ hoa', dateText(replacement['expiresAt'])),
                if (replacement['state'] == 'READY')
                  const Text(
                    'Khách nhận tại kiosk của đơn gốc, không thanh toán thêm.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Color(0xFF617568),
                    ),
                  ),
              ], status: _ComplaintStatus(valueOf(replacement, 'state'))),
            if (blocked) ...[
              const Text(
                'Tải lại hồ sơ để kiểm tra kết quả trước khi thao tác tiếp.',
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
                label: const Text('Tải lại hồ sơ'),
              ),
            ],
            for (final action in actions)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: action == 'accept' || action == 'review'
                    ? FilledButton(
                        onPressed: state.busy || blocked
                            ? null
                            : () => perform(action, item, state),
                        child: Text(
                          action == 'accept' ? 'Tiếp nhận' : 'Duyệt báo cáo',
                        ),
                      )
                    : OutlinedButton(
                        style: action == 'replacement/cancel'
                            ? OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFB42318),
                              )
                            : null,
                        onPressed: state.busy || blocked
                            ? null
                            : () => perform(action, item, state),
                        child: Text(
                          const {
                            'assignment': 'Giao nhân viên kiểm tra',
                            'replacement-plan': 'Chọn hoa thay và ô tủ',
                            'replacement/cancel': 'Hủy phương án hoa thay',
                          }[action]!,
                        ),
                      ),
              ),
            if (actions.isNotEmpty) const SizedBox(height: 4),
            section('Ảnh minh chứng', [
              if (photos.isEmpty)
                const Text(
                  'Chưa có ảnh minh chứng.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF617568)),
                ),
              Wrap(
                spacing: 10,
                runSpacing: 14,
                children: [
                  for (final photo in photos)
                    _ComplaintPhoto(
                      api,
                      photo,
                      key: ValueKey(photo['id'] ?? photo['url']),
                    ),
                ],
              ),
              if (evidencePage > 1 ||
                  (evidence is Map && evidence['hasMore'] == true))
                _ComplaintPaging(
                  page: evidencePage,
                  more: evidence is Map && evidence['hasMore'] == true,
                  busy: state.busy,
                  onPage: (page) => setState(() => evidencePage = page),
                ),
            ]),
          ],
        );
      },
    ),
  );
}

class _ComplaintPhoto extends StatefulWidget {
  const _ComplaintPhoto(this.api, this.photo, {super.key});
  final ApiClient api;
  final Json photo;
  @override
  State<_ComplaintPhoto> createState() => _ComplaintPhotoState();
}

class _ComplaintPhotoState extends State<_ComplaintPhoto> {
  late Future<Uint8List> bytes = widget.api.imageBytes(
    '${widget.photo['url']}',
  );
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 112,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<Uint8List>(
          future: bytes,
          builder: (context, snapshot) => SizedBox(
            height: 104,
            width: 112,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ColoredBox(
                color: const Color(0xFFF2F5F0),
                child: snapshot.hasError
                    ? IconButton(
                        tooltip: 'Tải lại ảnh',
                        onPressed: () => setState(
                          () => bytes = widget.api.imageBytes(
                            '${widget.photo['url']}',
                          ),
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                      )
                    : snapshot.hasData
                    ? Semantics(
                        button: true,
                        label: 'Xem ảnh minh chứng',
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
                                          errorBuilder: (_, _, _) =>
                                              const Center(
                                                child: Text(
                                                  'Không tải được ảnh.',
                                                ),
                                              ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: IconButton(
                                        tooltip: 'Đóng ảnh',
                                        onPressed: () =>
                                            Navigator.pop(dialogContext),
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
                      )
                    : const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.photo['source'] == 'STAFF_TASK' ? 'Nhân viên' : 'Khách hàng',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: forest,
          ),
        ),
        if (widget.photo['createdAt'] != null)
          Text(
            dateText(widget.photo['createdAt']),
            style: const TextStyle(
              fontSize: 10,
              height: 1.4,
              color: Color(0xFF617568),
            ),
          ),
      ],
    ),
  );
}

import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/team_widgets.dart';
import 'inventory.dart' show openPage;

bool repairApprovalActive(Json row, DateTime now) =>
    DateTime.tryParse('${row['expiresAt']}')?.isAfter(now) ?? false;

class RepairApprovalsPage extends StatefulWidget {
  const RepairApprovalsPage(this.api, {super.key});
  final ApiClient api;
  @override
  State<RepairApprovalsPage> createState() => _RepairApprovalsPageState();
}

class _RepairApprovalsPageState extends State<RepairApprovalsPage> {
  String query = '', filter = '';
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => widget.api.get('/api/me/technical-repairs'),
    builder: (context, data, state) {
      final now = DateTime.now();
      final rows = itemsOf(data).where((r) {
        final active = repairApprovalActive(r, now);
        return (filter.isEmpty || (filter == 'APPROVED' ? active : !active)) &&
            '${r['kioskName']} ${r['slotCode']} ${r['reason']}'
                .toLowerCase()
                .contains(query.trim().toLowerCase());
      }).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (value) => setState(() => query = value),
                  decoration: const InputDecoration(
                    hintText: 'Kiosk, ô tủ hoặc sự cố',
                    prefixIcon: Icon(Icons.search_rounded, size: 21),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Lọc yêu cầu sửa chữa',
                initialValue: filter,
                onSelected: (value) => setState(() => filter = value),
                icon: Icon(
                  filter.isEmpty
                      ? Icons.filter_list_rounded
                      : Icons.filter_alt_rounded,
                  color: forest,
                ),
                itemBuilder: (_) => [
                  for (final entry in const {
                    '': 'Tất cả',
                    'PENDING': 'Chờ duyệt',
                    'APPROVED': 'Đã duyệt',
                  }.entries)
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
              child: Center(
                child: Text(
                  'Không có yêu cầu sửa chữa phù hợp.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          for (final row in rows)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () async {
                  await openPage(
                    context,
                    'Yêu cầu sửa chữa',
                    _RepairDetail(widget.api, '${row['id']}'),
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
                          valueOf(row, 'kioskName'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: forest,
                          ),
                        ),
                        status: _RepairStatus(
                          active: repairApprovalActive(row, now),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Ô ${row['slotCode']}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF617568),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        valueOf(row, 'reason'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                      if (repairApprovalActive(row, now))
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'Quyền mở ô đến ${dateText(row['expiresAt'])}',
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
        ],
      );
    },
  );
}

class _RepairStatus extends StatelessWidget {
  const _RepairStatus({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) => Text(
    active ? 'Đã duyệt' : 'Chờ duyệt',
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: active ? forest : const Color(0xFF9A6700),
    ),
  );
}

class _RepairDetail extends StatefulWidget {
  const _RepairDetail(this.api, this.id);
  final ApiClient api;
  final String id;
  @override
  State<_RepairDetail> createState() => _RepairDetailState();
}

class _RepairDetailState extends State<_RepairDetail> {
  Timer? timer;
  bool blocked = false;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => widget.api.get('/api/me/technical-repairs'),
    builder: (context, data, state) {
      final row = itemsOf(
        data,
      ).where((r) => '${r['id']}' == widget.id).firstOrNull;
      if (row == null) {
        return const TeamSection(
          children: [
            Text(
              'Ca sửa này không còn cần shop duyệt quyền mở ô.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
          ],
        );
      }
      final active = repairApprovalActive(row, DateTime.now());
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamSection(
            children: [
              StatusHeading(
                title: Text(
                  valueOf(row, 'kioskName'),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: forest,
                  ),
                ),
                status: _RepairStatus(active: active),
              ),
              const SizedBox(height: 20),
              TeamFact('Ô cần sửa', valueOf(row, 'slotCode')),
              TeamFact('Nội dung sự cố', valueOf(row, 'reason')),
              if (active)
                TeamFact(
                  'Quyền mở ô có hiệu lực đến',
                  dateText(row['expiresAt']),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Duyệt để kỹ thuật viên được lấy OTP mở đúng ô trong ca sửa này.',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Color(0xFF617568),
              ),
            ),
          ),
          if (blocked) ...[
            const Text(
              'Chưa xác nhận được kết quả. Tải lại trước khi duyệt tiếp.',
              style: TextStyle(color: Color(0xFFB42318)),
            ),
            TextButton.icon(
              onPressed: state.busy
                  ? null
                  : () async {
                      try {
                        // Only unlock actions after a successful fresh read.
                        await widget.api.get('/api/me/technical-repairs');
                        await state.reload();
                        if (mounted) setState(() => blocked = false);
                      } catch (error) {
                        if (context.mounted) message(context, '$error');
                      }
                    },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tải lại yêu cầu'),
            ),
          ],
          if (!active)
            FilledButton.icon(
              onPressed: state.busy || blocked
                  ? null
                  : () => state.run(() async {
                      if (!await confirm(
                        context,
                        'Duyệt quyền mở ô?',
                        '${row['kioskName']} · Ô ${row['slotCode']}. Kỹ thuật viên sẽ được phép lấy OTP để sửa ô này.',
                      )) {
                        return;
                      }
                      try {
                        await widget.api.post(
                          '/api/me/technical-repairs/${widget.id}/approve',
                        );
                      } on ApiError catch (error) {
                        if (mounted &&
                            (error.ambiguous ||
                                error.status == 0 ||
                                error.status == 409 ||
                                error.status >= 500)) {
                          setState(() => blocked = true);
                        }
                        rethrow;
                      }
                      if (context.mounted) {
                        message(context, 'Đã duyệt quyền mở ô sửa chữa.');
                      }
                    }),
              icon: const Icon(Icons.verified_user_outlined, size: 19),
              label: const Text('Duyệt quyền mở ô'),
            ),
        ],
      );
    },
  );
}

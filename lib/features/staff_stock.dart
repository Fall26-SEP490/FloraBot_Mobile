import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';

class StaffStockPage extends StatefulWidget {
  const StaffStockPage(this.api, this.taskId, {super.key});
  final ApiClient api;
  final String taskId;
  @override
  State<StaffStockPage> createState() => _StaffStockPageState();
}

class _StaffStockPageState extends State<StaffStockPage> {
  Json? attempt;
  String get path => '/api/staff/tasks/${widget.taskId}/stock';
  Future<void> submit(ResourceViewState state, Json options) => state.run(
    () async {
      if (attempt != null) {
        final current = objectOf(await widget.api.get(path));
        if (itemsOf(
          current['actions'] ?? [],
        ).any((row) => row['id'] == attempt!['id'])) {
          attempt = null;
          if (mounted) message(context, 'Đã xác nhận nạp hoa thành công.');
          return;
        }
        if (!mounted ||
            !await confirm(
              context,
              'Gửi lại thao tác nạp?',
              'Chưa ghi nhận kết quả. Gửi lại đúng mã bó hoa và ô đã chọn?',
            )) {
          return;
        }
      } else {
        final products = itemsOf(options['products'] ?? []);
        final slots = itemsOf(
          options['slots'] ?? [],
        ).where((s) => s['zone'] == 'WALK_IN').toList();
        if (products.isEmpty || slots.isEmpty) return;
        final form = await askForm(context, 'Nạp hoa bán tại tủ', [
          InputSpec(
            'productId',
            'Mẫu hoa',
            choices: {
              for (final row in products) '${row['id']}': valueOf(row, 'name'),
            },
          ),
          InputSpec(
            'slotId',
            'Ô tủ',
            choices: {
              for (final row in slots) '${row['id']}': valueOf(row, 'code'),
            },
          ),
          const InputSpec('qrCode', 'Mã QR trên bó hoa'),
        ]);
        if (form == null || !mounted) return;
        if (!await confirm(
          context,
          'Xác nhận đã nạp hoa?',
          'Kiểm tra đúng bó hoa, đúng ô và đã đóng cửa tủ.',
        )) {
          return;
        }
        attempt = {'id': const Uuid().v4(), ...form};
      }
      await widget.api.post(path, attempt);
      attempt = null;
      if (mounted) message(context, 'Đã nạp hoa.');
    },
  );
  @override
  Widget build(BuildContext context) => ResourceView(
    title: 'Nạp hoa bán tại tủ',
    load: () => widget.api.get(path),
    builder: (context, data, state) {
      final options = objectOf(data);
      final available =
          itemsOf(options['products'] ?? []).isNotEmpty &&
          itemsOf(
            options['slots'] ?? [],
          ).any((row) => row['zone'] == 'WALK_IN');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!available)
            const InfoBox('Chưa có mẫu hoa hoặc ô bán sẵn phù hợp.'),
          FilledButton.icon(
            onPressed: !state.busy && (available || attempt != null)
                ? () => submit(state, options)
                : null,
            icon: const Icon(Icons.local_florist),
            label: Text(attempt == null ? 'Nạp hoa' : 'Kiểm tra kết quả nạp'),
          ),
          const SizedBox(height: 16),
          for (final action in itemsOf(options['actions'] ?? []))
            RecordCard(
              title: valueOf(action, 'qrCode'),
              subtitle: dateText(action['createdAt']),
            ),
        ],
      );
    },
  );
}

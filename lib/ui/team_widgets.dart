import 'package:flutter/material.dart';
import 'common.dart';
import '../core/models.dart';

const staffAccountLabels = {
  'ACTIVE': 'Đang hoạt động',
  'LOCKED': 'Tạm khóa',
  'DISABLED': 'Đã vô hiệu hóa',
};
const teamTaskLabels = {
  'ASSIGNED': 'Chờ bắt đầu',
  'IN_PROGRESS': 'Đang thực hiện',
  'SUBMITTED': 'Chờ duyệt báo cáo',
  'COMPLETED': 'Đã hoàn thành',
  'CANCELLED': 'Đã hủy',
};
String teamTaskName(Map<String, dynamic> row) =>
    row['workType'] == 'FLOWER_QUALITY'
    ? 'Xử lý chất lượng hoa'
    : row['workType'] == 'INVENTORY_MAINTENANCE'
    ? 'Thao tác ô tủ'
    : 'Giao hoa';

class TeamStatus extends StatelessWidget {
  const TeamStatus(this.value, {super.key});
  final String value;
  @override
  Widget build(BuildContext context) => StatusChip(
    value == 'LOCKED' ? 'DISABLED' : value,
    label:
        staffAccountLabels[value] ?? teamTaskLabels[value] ?? statusText(value),
  );
}

class TeamToolbar extends StatelessWidget {
  const TeamToolbar({
    required this.hint,
    required this.filter,
    required this.labels,
    required this.onQuery,
    required this.onFilter,
    required this.onCreate,
    required this.createLabel,
    super.key,
  });
  final String hint, filter, createLabel;
  final Map<String, String> labels;
  final ValueChanged<String> onQuery, onFilter;
  final VoidCallback? onCreate;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: onQuery,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: const Icon(Icons.search_rounded, size: 21),
            ),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Lọc trạng thái',
          initialValue: filter,
          icon: Icon(
            filter.isEmpty
                ? Icons.filter_list_rounded
                : Icons.filter_alt_rounded,
            color: forest,
          ),
          onSelected: onFilter,
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: '',
              checked: filter.isEmpty,
              child: const Text('Tất cả trạng thái'),
            ),
            for (final entry in labels.entries)
              CheckedPopupMenuItem(
                value: entry.key,
                checked: filter == entry.key,
                child: Text(entry.value),
              ),
          ],
        ),
        IconButton.filled(
          tooltip: createLabel,
          onPressed: onCreate,
          style: IconButton.styleFrom(
            backgroundColor: forest,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    ),
  );
}

class TeamSection extends StatelessWidget {
  const TeamSection({this.title, required this.children, super.key});
  final String? title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: forest,
              ),
            ),
            const SizedBox(height: 14),
          ],
          ...children,
        ],
      ),
    ),
  );
}

class TeamFact extends StatelessWidget {
  const TeamFact(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF617568)),
        ),
        const SizedBox(height: 4),
        Text(
          value.trim().isEmpty ? 'Chưa cập nhật' : value,
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
      ],
    ),
  );
}

class TeamPaging extends StatelessWidget {
  const TeamPaging({
    required this.page,
    required this.more,
    required this.onPage,
    this.busy = false,
    super.key,
  });
  final int page;
  final bool more, busy;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 4,
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

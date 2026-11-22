import 'package:flutter/material.dart';

const productTagGroups = {
  'flower': {
    'rose': 'Hoa hồng',
    'sunflower': 'Hướng dương',
    'tulip': 'Tulip',
    'chrysanthemum': 'Hoa cúc',
    'gerbera': 'Đồng tiền',
    'lisianthus': 'Cát tường',
    'carnation': 'Cẩm chướng',
    'hydrangea': 'Cẩm tú cầu',
    'lily': 'Hoa ly',
    'orchid': 'Hoa lan',
    'peony': 'Mẫu đơn',
    'babys-breath': 'Hoa baby',
    'other': 'Loại khác',
  },
  'color': {
    'red': 'Đỏ',
    'pink': 'Hồng',
    'white': 'Trắng',
    'yellow': 'Vàng',
    'orange': 'Cam',
    'purple': 'Tím',
    'blue': 'Xanh',
    'multicolor': 'Nhiều màu',
  },
  'material': {
    'wax': 'Sáp',
    'fabric': 'Lụa/vải',
    'yarn': 'Len',
    'paper': 'Giấy',
    'plastic': 'Nhựa',
    'other': 'Khác',
  },
};
const productTagLabels = {
  'flower': 'Loại hoa',
  'color': 'Màu chủ đạo',
  'material': 'Chất liệu',
};
bool knownProductTag(String tag) {
  final parts = tag.split(':');
  return parts.length == 2 &&
      (productTagGroups[parts[0]]?.containsKey(parts[1]) ?? false);
}

Future<List<String>?> chooseProductTags(
  BuildContext context,
  List<String> current,
) {
  final selected = current.where(knownProductTag).toSet();
  var custom = current.where((tag) => !knownProductTag(tag)).toList();
  return showDialog<List<String>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('Đặc điểm mẫu hoa'),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final group in productTagGroups.entries) ...[
                  Text(
                    productTagLabels[group.key]!,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final item in group.value.entries)
                        FilterChip(
                          label: Text(item.value),
                          selected: selected.contains(
                            '${group.key}:${item.key}',
                          ),
                          onSelected: (value) => update(() {
                            final tag = '${group.key}:${item.key}';
                            if (value) {
                              if (group.key == 'material') {
                                selected.removeWhere(
                                  (t) => t.startsWith('material:'),
                                );
                              }
                              selected.add(tag);
                            } else {
                              selected.remove(tag);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  initialValue: custom.join(', '),
                  decoration: const InputDecoration(
                    labelText: 'Từ khóa tìm kiếm',
                    hintText: 'Ví dụ: pastel, tối giản',
                    helperText: 'Ngăn cách từ khóa bằng dấu phẩy.',
                  ),
                  onChanged: (value) => update(() {
                    custom = value
                        .split(',')
                        .map((t) => t.trim())
                        .where((t) => t.isNotEmpty && !knownProductTag(t))
                        .toSet()
                        .toList();
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  'Chọn ít nhất một loại hoa và một màu. Tối đa 20 nhãn, mỗi nhãn tối đa 64 ký tự.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed:
                selected.length + custom.length <= 20 &&
                    custom.every((tag) => tag.length <= 64) &&
                    selected.any((t) => t.startsWith('flower:')) &&
                    selected.any((t) => t.startsWith('color:'))
                ? () => Navigator.pop(context, [...selected, ...custom])
                : null,
            child: const Text('Lưu đặc điểm'),
          ),
        ],
      ),
    ),
  );
}

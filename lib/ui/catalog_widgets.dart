import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/models.dart';
import 'common.dart';
import 'product_tags.dart';

String catalogStatus(String status) => switch (status) {
  'ACTIVE' => 'Đang bán',
  'INACTIVE' => 'Ngừng bán',
  'DRAFT' => 'Bản mẫu',
  _ => status,
};

class CatalogStatus extends StatelessWidget {
  const CatalogStatus(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) => Text(
    catalogStatus(status),
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: status == 'ACTIVE'
          ? forest
          : status == 'INACTIVE'
          ? const Color(0xFFB42318)
          : const Color(0xFF9A6700),
    ),
  );
}

class CatalogToolbar extends StatelessWidget {
  const CatalogToolbar({
    required this.query,
    required this.status,
    required this.onQuery,
    required this.onStatus,
    required this.onCreate,
    required this.accessory,
    super.key,
  });
  final String query, status;
  final ValueChanged<String> onQuery, onStatus;
  final VoidCallback? onCreate;
  final bool accessory;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            style: const TextStyle(fontSize: 14),
            onChanged: onQuery,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              hintText: accessory ? 'Tìm phụ kiện' : 'Tìm mẫu hoa',
              prefixIcon: const Icon(Icons.search_rounded, size: 21),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          tooltip: 'Lọc trạng thái',
          initialValue: status,
          icon: Icon(
            status == 'ALL'
                ? Icons.filter_list_rounded
                : Icons.filter_alt_rounded,
            color: forest,
            size: 22,
          ),
          onSelected: onStatus,
          itemBuilder: (_) => [
            for (final value in [
              'ALL',
              'ACTIVE',
              'INACTIVE',
              if (!accessory) 'DRAFT',
            ])
              CheckedPopupMenuItem(
                value: value,
                checked: value == status,
                child: Text(value == 'ALL' ? 'Tất cả' : catalogStatus(value)),
              ),
          ],
        ),
        IconButton.filled(
          tooltip: accessory ? 'Tạo phụ kiện' : 'Tạo mẫu hoa',
          onPressed: onCreate,
          style: IconButton.styleFrom(
            backgroundColor: forest,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.add_rounded, size: 23),
        ),
      ],
    ),
  );
}

class CatalogListItem extends StatelessWidget {
  const CatalogListItem({
    required this.item,
    required this.onTap,
    this.accessory = false,
    super.key,
  });
  final Json item;
  final VoidCallback onTap;
  final bool accessory;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusHeading(
              title: Text(
                valueOf(item, 'name'),
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: forest,
                ),
              ),
              status: CatalogStatus(valueOf(item, 'status')),
            ),
            const SizedBox(height: 7),
            Text(
              money(item['price']),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: forest,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tồn tại shop: ${item[accessory ? 'stockQuantity' : 'quantity'] ?? 0}${accessory ? '' : ' bó'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF617568),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Returns validated metadata; the caller owns the API mutation and refresh.
Future<Json?> showCatalogEditor(
  BuildContext context, {
  Json? item,
  bool accessory = false,
}) => Navigator.push<Json>(
  context,
  MaterialPageRoute(
    builder: (_) => _CatalogEditor(item: item, accessory: accessory),
  ),
);

class _CatalogEditor extends StatefulWidget {
  const _CatalogEditor({this.item, required this.accessory});
  final Json? item;
  final bool accessory;
  @override
  State<_CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<_CatalogEditor> {
  final form = GlobalKey<FormState>();
  late final fields = <String, TextEditingController>{
    for (final key in [
      'name',
      'price',
      if (!widget.accessory) ...[
        'quantity',
        'lengthCm',
        'widthCm',
        'heightCm',
        'description',
      ],
    ])
      key: TextEditingController(
        text: '${widget.item?[key] ?? (key == 'quantity' ? 0 : '')}',
      ),
  };
  late final tags = List<String>.from(widget.item?['tags'] ?? []);
  late final custom = TextEditingController(
    text: tags.where((t) => !knownProductTag(t)).join(', '),
  );
  String? classificationError;

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    custom.dispose();
    super.dispose();
  }

  Widget field(
    String key,
    String label, {
    bool required = true,
    int? maxLength,
    int lines = 1,
    bool decimal = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: label,
            children: [
              if (required)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: Color(0xFFB42318)),
                ),
            ],
          ),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: forest,
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: fields[key],
          style: const TextStyle(fontSize: 14),
          maxLines: lines,
          maxLength: maxLength,
          keyboardType: ['name', 'description'].contains(key)
              ? TextInputType.text
              : TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: ['name', 'description'].contains(key)
              ? null
              : decimal
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
              : [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            counterText: '',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          validator: (raw) {
            final value = (raw ?? '').trim();
            if (required && value.isEmpty) {
              return 'Nhập ${label.toLowerCase()}.';
            }
            if (maxLength != null && value.length > maxLength) {
              return 'Tối đa $maxLength ký tự.';
            }
            if (key == 'name' && widget.accessory && value.length < 2) {
              return 'Tên từ 2 đến 120 ký tự.';
            }
            if (key == 'price') {
              final n = int.tryParse(value);
              if (n == null || n < 1 || n > 9007199254740991) {
                return 'Nhập giá nguyên lớn hơn 0.';
              }
            }
            if (key == 'quantity') {
              final n = int.tryParse(value);
              if (n == null || n < 0 || n > 2147483647) {
                return 'Tồn kho từ 0 đến 2.147.483.647.';
              }
            }
            if (decimal) {
              final n = double.tryParse(value.replaceAll(',', '.'));
              if (n == null ||
                  !n.isFinite ||
                  n < .01 ||
                  n > 1000 ||
                  !RegExp(r'^\d+([.,]\d{1,2})?$').hasMatch(value)) {
                return 'Từ 0,01–1.000 cm, tối đa 2 số lẻ.';
              }
            }
            return null;
          },
        ),
      ],
    ),
  );

  void submit() {
    final valid = form.currentState!.validate();
    final selected = {
      ...tags.where(knownProductTag),
      ...custom.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty),
    }.toList();
    String? error;
    if (!widget.accessory) {
      if (widget.item == null &&
          (!selected.any(
                (t) => t.startsWith('flower:') && knownProductTag(t),
              ) ||
              !selected.any(
                (t) => t.startsWith('color:') && knownProductTag(t),
              ))) {
        error = 'Chọn ít nhất một loại hoa và một màu.';
      } else if (selected.length > 20 ||
          selected.any((t) => t.length > 64) ||
          selected.join(',').length > 1500) {
        error = 'Tối đa 20 từ khóa, mỗi từ khóa tối đa 64 ký tự.';
      }
    }
    setState(() => classificationError = error);
    if (!valid || error != null) return;
    Navigator.pop(context, <String, dynamic>{
      'name': fields['name']!.text.trim(),
      'price': int.parse(fields['price']!.text),
      if (!widget.accessory) ...{
        'description': fields['description']!.text.trim(),
        'quantity': int.parse(fields['quantity']!.text),
        for (final key in ['lengthCm', 'widthCm', 'heightCm'])
          key: double.parse(fields[key]!.text.replaceAll(',', '.')),
        'tags': selected,
      },
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '${widget.item == null ? 'Tạo' : 'Sửa'} ${widget.accessory ? 'phụ kiện' : 'mẫu hoa'}',
      ),
    ),
    body: SafeArea(
      child: Form(
        key: form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      field(
                        'name',
                        widget.accessory ? 'Tên phụ kiện' : 'Tên mẫu hoa',
                        maxLength: 120,
                      ),
                      if (widget.accessory)
                        field('price', 'Giá bán (đ)')
                      else ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: field('price', 'Giá bán (đ)')),
                            const SizedBox(width: 12),
                            Expanded(
                              child: field('quantity', 'Tồn tại shop (bó)'),
                            ),
                          ],
                        ),
                        const Text(
                          'Kích thước đóng gói (cm)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: forest,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: field('lengthCm', 'Dài', decimal: true),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: field('widthCm', 'Rộng', decimal: true),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: field('heightCm', 'Cao', decimal: true),
                            ),
                          ],
                        ),
                        field(
                          'description',
                          'Mô tả',
                          required: false,
                          lines: 3,
                          maxLength: 2000,
                        ),
                        for (final group in productTagGroups.entries)
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: const EdgeInsets.only(bottom: 12),
                            initiallyExpanded: group.key != 'material',
                            shape: const Border(),
                            collapsedShape: const Border(),
                            title: Text(
                              productTagLabels[group.key]!,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: forest,
                              ),
                            ),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 2,
                                  children: [
                                    for (final option in group.value.entries)
                                      FilterChip(
                                        label: Text(
                                          option.value,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        selected: tags.contains(
                                          '${group.key}:${option.key}',
                                        ),
                                        onSelected: (value) => setState(() {
                                          final tag =
                                              '${group.key}:${option.key}';
                                          if (value) {
                                            if (group.key == 'material') {
                                              tags.removeWhere(
                                                (t) =>
                                                    t.startsWith('material:'),
                                              );
                                            }
                                            tags.add(tag);
                                          } else {
                                            tags.remove(tag);
                                          }
                                        }),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        if (classificationError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              classificationError!,
                              style: const TextStyle(color: Color(0xFFB42318)),
                            ),
                          ),
                        TextField(
                          controller: custom,
                          style: const TextStyle(fontSize: 14),
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            labelText: 'Từ khóa khác',
                            hintText: 'pastel, tối giản',
                            isDense: true,
                          ),
                        ),
                        if (widget.item == null)
                          const Padding(
                            padding: EdgeInsets.only(top: 14),
                            child: Text(
                              'Tạo bản mẫu, sau đó thêm ảnh và bật bán.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF617568),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: submit,
                child: Text(
                  widget.item == null
                      ? 'Tạo ${widget.accessory ? 'phụ kiện' : 'mẫu hoa'}'
                      : 'Lưu thay đổi',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

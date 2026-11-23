import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import 'catalog_widgets.dart';
import 'common.dart';
import 'product_tags.dart';

class ProductDetailView extends StatelessWidget {
  const ProductDetailView({
    required this.api,
    required this.item,
    required this.busy,
    required this.onEdit,
    required this.onPhoto,
    required this.onStatus,
    super.key,
  });
  final ApiClient api;
  final Json item;
  final bool busy;
  final VoidCallback onEdit, onPhoto, onStatus;

  Widget section(List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  Widget label(String text) => Text(
    text,
    style: const TextStyle(fontSize: 12, color: Color(0xFF617568)),
  );

  String tagLabel(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return value;
    final group = productTagGroups[parts[0]];
    if (group == null) return value;
    return group[parts[1]] ?? value;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      section([
        StatusHeading(
          title: Text(
            valueOf(item, 'name'),
            style: const TextStyle(
              fontSize: 21,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: forest,
            ),
          ),
          status: CatalogStatus(valueOf(item, 'status')),
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label('Giá bán'),
                  const SizedBox(height: 5),
                  Text(
                    money(item['price']),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: forest,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label('Tồn tại shop'),
                  const SizedBox(height: 5),
                  Text(
                    '${item['quantity'] ?? 0} bó',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: forest,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ]),
      section([
        Row(
          children: [
            const Expanded(
              child: Text(
                'Ảnh mẫu hoa',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: forest,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Thêm ảnh',
              onPressed: busy ? null : onPhoto,
              icon: const Icon(Icons.add_a_photo_outlined, size: 21),
              color: forest,
            ),
          ],
        ),
        _ProductGallery(
          api: api,
          productId: '${item['id']}',
          key: ObjectKey(item),
        ),
      ]),
      section([
        const Text(
          'Thông tin mẫu hoa',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: forest,
          ),
        ),
        const SizedBox(height: 16),
        label('Kích thước đóng gói · Dài × Rộng × Cao'),
        const SizedBox(height: 5),
        Text(
          '${item['lengthCm'] ?? '—'} × ${item['widthCm'] ?? '—'} × ${item['heightCm'] ?? '—'} cm',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        if (item['tags'] is List && (item['tags'] as List).isNotEmpty) ...[
          const SizedBox(height: 16),
          label('Đặc điểm'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in item['tags'] as List)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF1E7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tagLabel('$tag'),
                    style: const TextStyle(fontSize: 12, color: forest),
                  ),
                ),
            ],
          ),
        ],
        if (valueOf(item, 'description', '').trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          label('Mô tả'),
          const SizedBox(height: 5),
          Text(
            valueOf(item, 'description'),
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ],
      ]),
      FilledButton.icon(
        onPressed: busy ? null : onEdit,
        icon: const Icon(Icons.edit_outlined, size: 19),
        label: const Text('Chỉnh sửa mẫu hoa'),
      ),
      const SizedBox(height: 10),
      OutlinedButton(
        style: item['status'] == 'ACTIVE'
            ? OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB42318))
            : null,
        onPressed: busy ? null : onStatus,
        child: Text(
          item['status'] == 'ACTIVE' ? 'Ngừng bán mẫu hoa' : 'Bật bán mẫu hoa',
        ),
      ),
    ],
  );
}

class _ProductGallery extends StatefulWidget {
  const _ProductGallery({
    required this.api,
    required this.productId,
    super.key,
  });
  final ApiClient api;
  final String productId;
  @override
  State<_ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends State<_ProductGallery> {
  late Future<dynamic> photos = load();
  int selected = 0;
  Future<dynamic> load() =>
      widget.api.get('/api/me/products/${widget.productId}/photos?page=1');

  Widget photo(Json row, BoxFit fit) {
    final uri = Uri.tryParse('${row['url']}');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return const Center(
        child: Icon(Icons.broken_image_outlined, color: forest),
      );
    }
    return Image.network(
      uri.toString(),
      fit: fit,
      errorBuilder: (_, _, _) =>
          const Center(child: Icon(Icons.broken_image_outlined, color: forest)),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: photos,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      }
      if (snapshot.hasError) {
        return TextButton.icon(
          onPressed: () => setState(() => photos = load()),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Tải lại ảnh'),
        );
      }
      final rows = itemsOf(snapshot.data);
      if (rows.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Icon(Icons.image_outlined, size: 30, color: Color(0xFF617568)),
              SizedBox(height: 8),
              Text(
                'Chưa có ảnh mẫu hoa',
                style: TextStyle(fontSize: 13, color: Color(0xFF617568)),
              ),
            ],
          ),
        );
      }
      final ordered = [
        ...rows.where((r) => r['isCover'] == true),
        ...rows.where((r) => r['isCover'] != true),
      ];
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 1.4,
              child: Material(
                color: const Color(0xFFF2F5F0),
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
                                child: photo(ordered[selected], BoxFit.contain),
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
                  child: photo(ordered[selected], BoxFit.contain),
                ),
              ),
            ),
          ),
          if (ordered.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 58,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: ordered.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, index) => Semantics(
                  label: 'Ảnh ${index + 1}',
                  selected: selected == index,
                  button: true,
                  child: GestureDetector(
                    onTap: () => setState(() => selected = index),
                    child: Container(
                      width: 58,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selected == index
                              ? forest
                              : const Color(0xFFE0E8DC),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: photo(ordered[index], BoxFit.cover),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}

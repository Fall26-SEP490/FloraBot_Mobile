import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';
import 'task_support.dart' show ApiPhoto;

String encodeReviewPhoto(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
    throw const ApiError(400, 'Ảnh tối đa 2 MB.');
  }
  final jpeg =
      bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255;
  final png =
      bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71;
  final webp =
      bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
  if (!jpeg && !png && !webp) {
    throw const ApiError(400, 'Chọn ảnh JPEG, PNG hoặc WebP.');
  }
  return base64Encode(bytes);
}

class CustomerReviewsPage extends StatefulWidget {
  const CustomerReviewsPage(
    this.api, {
    required this.productId,
    required this.sellerId,
    this.canReview = false,
    super.key,
  });
  final ApiClient api;
  final String productId, sellerId;
  final bool canReview;
  @override
  State<CustomerReviewsPage> createState() => _CustomerReviewsPageState();
}

class _CustomerReviewsPageState extends State<CustomerReviewsPage> {
  int scope = 0, page = 1;
  bool sent = false;
  String get product => '/api/shop/products/${widget.productId}';
  Future<Json> load() async {
    final data = objectOf(
      await widget.api.get(
        scope == 0
            ? '$product/reviews?page=$page'
            : '/api/shop/sellers/${widget.sellerId}/reviews?page=$page',
      ),
    );
    bool eligible = false;
    String? eligibilityError;
    if (scope == 0 && widget.canReview && !sent) {
      try {
        eligible =
            objectOf(
              await widget.api.get('$product/review-eligibility'),
            )['eligible'] ==
            true;
      } catch (e) {
        eligibilityError = '$e';
      }
    }
    return {
      ...data,
      'eligible': eligible,
      'eligibilityError': eligibilityError,
    };
  }

  Future<void> write(ResourceViewState state) => state.run(() async {
    final input = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ReviewEditor(),
    );
    if (input == null) return;
    try {
      await widget.api.post('$product/reviews', input);
      sent = true;
      page = 1;
      if (mounted) message(context, 'Đã gửi đánh giá.');
    } on ApiError catch (e) {
      if (e.ambiguous || e.status == 409) {
        final permission = objectOf(
          await widget.api.get('$product/review-eligibility'),
        );
        if (permission['eligible'] == false) {
          sent = true;
          page = 1;
        }
      }
      rethrow;
    }
  });
  @override
  Widget build(BuildContext context) => ResourceView(
    title: 'Đánh giá khách hàng',
    resourceKey: '$scope:$page',
    load: load,
    builder: (context, response, state) {
      final data = objectOf(response);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.sellerId.isNotEmpty)
            SegmentedButton<int>(
              segments: [
                const ButtonSegment(value: 0, label: Text('Mẫu hoa')),
                if (widget.sellerId.isNotEmpty)
                  const ButtonSegment(value: 1, label: Text('Cả shop')),
              ],
              selected: {scope},
              onSelectionChanged: (value) => setState(() {
                scope = value.first;
                page = 1;
              }),
            ),
          const SizedBox(height: 12),
          if (data['eligibilityError'] != null)
            InfoBox('${data['eligibilityError']}', warning: true),
          if (scope == 0 && data['eligible'] == true)
            FilledButton.icon(
              onPressed: state.busy ? null : () => write(state),
              icon: const Icon(Icons.rate_review_outlined),
              label: const Text('Viết đánh giá'),
            ),
          if (itemsOf(data).isEmpty) const InfoBox('Chưa có đánh giá.'),
          for (final row in itemsOf(data))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      valueOf(row, 'reviewerName', 'Khách hàng'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${'★' * (row['stars'] as num? ?? 0).toInt()} · ${dateText(row['createdAt'])}',
                      style: const TextStyle(color: Color(0xFF966408)),
                    ),
                    if (scope == 1) Text(valueOf(row, 'productName')),
                    if (row['comment'] != null) Text('${row['comment']}'),
                    if (row['photoUrl'] != null)
                      ApiPhoto(
                        widget.api,
                        '/api/shop/products/${row['productId'] ?? widget.productId}/reviews/${row['id']}/photo',
                      ),
                  ],
                ),
              ),
            ),
          if (page > 1 || data['hasMore'] == true)
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: page > 1 && !state.busy
                      ? () => setState(() => page--)
                      : null,
                  child: const Text('Trang trước'),
                ),
                Text('Trang $page'),
                TextButton(
                  onPressed: data['hasMore'] == true && !state.busy
                      ? () => setState(() => page++)
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

class _ReviewEditor extends StatefulWidget {
  const _ReviewEditor();
  @override
  State<_ReviewEditor> createState() => _ReviewEditorState();
}

class _ReviewEditorState extends State<_ReviewEditor> {
  final comment = TextEditingController();
  int stars = 0;
  Uint8List? photo;
  String? photoBase64, error;
  bool choosing = false;
  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Future<void> choose() async {
    setState(() => choosing = true);
    try {
      final file = await chooseEvidence(context);
      if (file == null) return;
      if (await file.length() > 2 * 1024 * 1024) {
        throw const ApiError(400, 'Ảnh tối đa 2 MB.');
      }
      final bytes = await file.readAsBytes();
      final encoded = encodeReviewPhoto(bytes);
      if (mounted) {
        setState(() {
          photo = bytes;
          photoBase64 = encoded;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => choosing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Đánh giá của bạn',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  tooltip: '$i sao',
                  onPressed: () => setState(() => stars = i),
                  icon: Icon(
                    i <= stars ? Icons.star : Icons.star_border,
                    color: const Color(0xFFAB750C),
                  ),
                ),
            ],
          ),
          TextField(
            controller: comment,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Nhận xét (tùy chọn)'),
          ),
          if (photo != null) Image.memory(photo!, height: 120),
          Row(
            children: [
              TextButton.icon(
                onPressed: choosing ? null : choose,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(choosing ? 'Đang chọn…' : 'Ảnh (tùy chọn)'),
              ),
              if (photo != null)
                TextButton(
                  onPressed: () => setState(() {
                    photo = null;
                    photoBase64 = null;
                  }),
                  child: const Text('Bỏ ảnh'),
                ),
            ],
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          FilledButton(
            onPressed: stars == 0 || choosing
                ? null
                : () => Navigator.pop(context, <String, dynamic>{
                    'stars': stars,
                    'comment': comment.text.trim().isEmpty
                        ? null
                        : comment.text.trim(),
                    'photoBase64': photoBase64,
                  }),
            child: const Text('Gửi đánh giá'),
          ),
        ],
      ),
    ),
  );
}

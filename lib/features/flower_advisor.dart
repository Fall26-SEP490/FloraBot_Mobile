import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/product_tags.dart';

Future<Json> verifyFlowerSuggestions(
  ApiClient api,
  Json answer,
  Map<String, String> preferences,
  int budget,
) async {
  final requiredTags = preferences.entries
      .where((entry) => entry.value.isNotEmpty)
      .map((entry) => '${entry.key}:${entry.value}')
      .toSet();
  final suggestions = itemsOf(answer['suggestions'] ?? []);
  final filtered = <Json>[];
  for (final suggestion in suggestions) {
    final price = num.tryParse('${suggestion['price']}');
    if (price == null || price > budget) continue;
    if (requiredTags.isEmpty) {
      filtered.add(suggestion);
      continue;
    }
    final name = valueOf(suggestion, 'name');
    final search = name.length > 100 ? name.substring(0, 100) : name;
    var found = false;
    for (var page = 1; page <= 10 && !found; page++) {
      final data = objectOf(
        await api.get(
          '/api/shop/catalog?availablePreorderOnly=true&search=${Uri.encodeQueryComponent(search)}&page=$page',
        ),
      );
      for (final product in itemsOf(data)) {
        if (product['productId'] != suggestion['productId'] ||
            product['kioskId'] != suggestion['kioskId']) {
          continue;
        }
        found = true;
        final tags = Set<String>.from(product['tags'] ?? []);
        final currentPrice = num.tryParse('${product['price']}');
        if (tags.containsAll(requiredTags) &&
            currentPrice != null &&
            currentPrice <= budget) {
          filtered.add({...suggestion, 'price': product['price']});
        }
        break;
      }
      if (data['hasMore'] != true) break;
    }
  }
  return {
    ...answer,
    'suggestions': filtered,
    if (suggestions.isNotEmpty && filtered.isEmpty)
      'message':
          'Chưa có gợi ý khớp đặc điểm và ngân sách bạn chọn. Bạn có thể đổi tiêu chí hoặc xem danh mục.',
  };
}

class FlowerAdvisorPage extends StatefulWidget {
  const FlowerAdvisorPage(this.api, {super.key});
  final ApiClient api;
  @override
  State<FlowerAdvisorPage> createState() => _FlowerAdvisorPageState();
}

class _FlowerAdvisorPageState extends State<FlowerAdvisorPage> {
  final question = TextEditingController();
  final budget = TextEditingController(text: '300000');
  final preferences = <String, String>{
    'flower': '',
    'color': '',
    'material': '',
  };
  bool busy = false;
  String? error;
  Json? answer;
  @override
  void dispose() {
    question.dispose();
    budget.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    final amount = int.tryParse(budget.text);
    if (question.text.trim().isEmpty ||
        amount == null ||
        amount < 1 ||
        amount > 1000000000) {
      setState(() => error = 'Nhập mong muốn và ngân sách hợp lệ.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      answer = null;
    });
    try {
      final filters = preferences.entries
          .where((p) => p.value.isNotEmpty)
          .map(
            (p) =>
                '${productTagLabels[p.key]}: ${productTagGroups[p.key]![p.value]}',
          )
          .join(', ');
      final result = objectOf(
        await widget.api.post('/api/shop/flower-chat', {
          'question':
              '${question.text.trim()}${filters.isEmpty ? '' : '. Yêu cầu: $filters'}',
          'mode': 'PREORDER',
          'budget': amount,
        }),
      );
      final verified = await verifyFlowerSuggestions(
        widget.api,
        result,
        Map.of(preferences),
        amount,
      );
      if (mounted) setState(() => answer = verified);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageTitle(
          'Gợi ý chọn hoa',
          'Mô tả dịp tặng, người nhận và đặc điểm bạn thích.',
        ),
        TextField(
          controller: question,
          maxLength: 700,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Bạn muốn tìm hoa như thế nào?',
          ),
        ),
        for (final group in productTagGroups.entries)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: DropdownButtonFormField<String>(
              initialValue: preferences[group.key],
              decoration: InputDecoration(
                labelText: productTagLabels[group.key],
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('Không yêu cầu')),
                for (final entry in group.value.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: busy
                  ? null
                  : (value) =>
                        setState(() => preferences[group.key] = value ?? ''),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: budget,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Ngân sách tối đa (đồng)',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(busy ? 'Đang tìm hoa…' : 'Tìm hoa phù hợp'),
        ),
        if (error != null) InfoBox(error!, warning: true),
        if (answer != null) ...[
          InfoBox(valueOf(answer!, 'message', '')),
          for (final item in itemsOf(answer!['suggestions'] ?? []))
            RecordCard(
              title: valueOf(item, 'name'),
              subtitle:
                  '${money(item['price'])} · ${item['shopName'] ?? ''}\n${item['reason'] ?? ''}',
              trailing: TextButton(
                onPressed: () => Navigator.pop(context, '${item['name']}'),
                child: const Text('Xem mẫu'),
              ),
            ),
        ],
      ],
    ),
  );
}

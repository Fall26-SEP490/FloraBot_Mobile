import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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
  const FlowerAdvisorPage(this.api, {this.onViewSuggestion, super.key});
  final ApiClient api;
  final Future<void> Function(Json)? onViewSuggestion;
  @override
  State<FlowerAdvisorPage> createState() => _FlowerAdvisorPageState();
}

class _FlowerAdvisorPageState extends State<FlowerAdvisorPage> {
  final question = TextEditingController();
  final budget = TextEditingController(text: '300.000');
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
    final amount = int.tryParse(budget.text.replaceAll('.', ''));
    if (question.text.trim().isEmpty ||
        amount == null ||
        amount < 1 ||
        amount > 1000000000) {
      setState(() => error = 'Nhập mong muốn và ngân sách hợp lệ.');
      return;
    }
    FocusScope.of(context).unfocus();
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

  Future<void> choosePreference(String group) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .65,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      productTagLabels[group]!,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: forest,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng lựa chọn',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final entry in {
                    '': 'Không yêu cầu',
                    ...productTagGroups[group]!,
                  }.entries)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                      ),
                      title: Text(
                        entry.value,
                        style: const TextStyle(fontSize: 16),
                      ),
                      selected: preferences[group] == entry.key,
                      selectedTileColor: const Color(0xFFEDF4EF),
                      trailing: preferences[group] == entry.key
                          ? const Icon(Icons.check_rounded, color: forest)
                          : null,
                      onTap: () => Navigator.pop(sheetContext, entry.key),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (mounted && chosen != null) setState(() => preferences[group] = chosen);
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Bạn muốn tìm hoa thế nào?',
                  style: TextStyle(
                    fontSize: 23,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: forest,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: question,
                  enabled: !busy,
                  maxLength: 700,
                  minLines: 3,
                  maxLines: 5,
                  style: const TextStyle(fontSize: 16, height: 1.5),
                  decoration: const InputDecoration(
                    hintText: 'Bạn muốn tìm hoa như thế nào?',
                    hintStyle: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Color(0xFF738077),
                    ),
                    counterText: '',
                    filled: true,
                    fillColor: Color(0xFFF5F8F4),
                    contentPadding: EdgeInsets.all(16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                      borderSide: BorderSide(color: Color(0xFFDCE5DE)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                      borderSide: BorderSide(color: Color(0xFFDCE5DE)),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Ngân sách tối đa',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: forest,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: budget,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: forest,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      final amount = int.tryParse(newValue.text);
                      final formatted = amount == null
                          ? ''
                          : NumberFormat.decimalPattern('vi').format(amount);
                      return TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(
                          offset: formatted.length,
                        ),
                      );
                    }),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    suffixText: 'đ',
                    prefixIcon: Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 21,
                      color: forest,
                    ),
                    filled: true,
                    fillColor: Color(0xFFF5F8F4),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                      borderSide: BorderSide(color: Color(0xFFDCE5DE)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                      borderSide: BorderSide(color: Color(0xFFDCE5DE)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final amount in [200000, 300000, 500000])
                      ChoiceChip(
                        label: Text(
                          money(amount),
                          style: const TextStyle(fontSize: 13),
                        ),
                        selected:
                            int.tryParse(budget.text.replaceAll('.', '')) ==
                            amount,
                        showCheckmark: false,
                        selectedColor: const Color(0xFFE3EFE6),
                        onSelected: busy
                            ? null
                            : (_) => setState(
                                () => budget.text = NumberFormat.decimalPattern(
                                  'vi',
                                ).format(amount),
                              ),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                const Text(
                  'Sở thích',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: forest,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final group in productTagGroups.keys)
                      InputChip(
                        label: Text(
                          preferences[group]!.isEmpty
                              ? productTagLabels[group]!
                              : productTagGroups[group]![preferences[group]]!,
                          style: const TextStyle(fontSize: 14),
                        ),
                        selected: preferences[group]!.isNotEmpty,
                        showCheckmark: false,
                        selectedColor: const Color(0xFFE3EFE6),
                        avatar: const Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: forest,
                        ),
                        onPressed: busy ? null : () => choosePreference(group),
                        onDeleted: busy || preferences[group]!.isEmpty
                            ? null
                            : () => setState(() => preferences[group] = ''),
                        deleteButtonTooltipMessage:
                            'Bỏ ${productTagLabels[group]!.toLowerCase()}',
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                  ],
                ),
                if (error != null) InfoBox(error!, warning: true),
                if (answer != null) ...[
                  const SizedBox(height: 20),
                  if (valueOf(answer!, 'message', '').isNotEmpty)
                    InfoBox(valueOf(answer!, 'message', '')),
                  for (final item in itemsOf(answer!['suggestions'] ?? []))
                    RecordCard(
                      title: valueOf(item, 'name'),
                      subtitle:
                          '${money(item['price'])} · ${item['shopName'] ?? ''}\n${item['reason'] ?? ''}',
                      trailing: TextButton(
                        onPressed: () async {
                          if (widget.onViewSuggestion != null) {
                            await widget.onViewSuggestion!(item);
                          } else {
                            Navigator.pop(context, '${item['name']}');
                          }
                        },
                        child: const Text('Xem mẫu'),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFEDF1EE))),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: busy ? null : submit,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search_rounded, size: 21),
                  label: Text(
                    busy ? 'Đang tìm hoa…' : 'Tìm hoa phù hợp',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

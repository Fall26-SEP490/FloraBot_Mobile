import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<String?> pickVietnamBank(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _BankPicker());

String _fold(String value) {
  var result = value.toLowerCase();
  const accents = {
    'àáạảãâầấậẩẫăằắặẳẵ': 'a',
    'èéẹẻẽêềếệểễ': 'e',
    'ìíịỉĩ': 'i',
    'òóọỏõôồốộổỗơờớợởỡ': 'o',
    'ùúụủũưừứựửữ': 'u',
    'ỳýỵỷỹ': 'y',
    'đ': 'd',
  };
  for (final entry in accents.entries) {
    result = result.replaceAll(RegExp('[${entry.key}]'), entry.value);
  }
  return result;
}

class _Bank {
  _Bank(this.name, this.code, String englishName)
    : search = _fold('$name $code $englishName');

  final String name, code, search;
}

Future<List<_Bank>> _loadBanks() async {
  final json = await rootBundle.loadString(
    'assets/data/vietnam_bank_list.json',
  );
  return (jsonDecode(json) as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .map(
        (item) => _Bank(
          item['name'] as String,
          item['code'] as String? ?? '',
          item['nameEn'] as String? ?? '',
        ),
      )
      .toList(growable: false);
}

class _BankPicker extends StatefulWidget {
  const _BankPicker();

  @override
  State<_BankPicker> createState() => _BankPickerState();
}

class _BankPickerState extends State<_BankPicker> {
  late Future<List<_Bank>> _banks = _loadBanks();
  String _search = '';

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 420,
      height: 470,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Chọn ngân hàng',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Tìm theo tên hoặc mã ngân hàng',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _search = _fold(value)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<_Bank>>(
                future: _banks,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: TextButton(
                        onPressed: () => setState(() => _banks = _loadBanks()),
                        child: const Text('Chưa tải được danh sách. Thử lại'),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final tokens = _search.trim().split(RegExp(r'\s+'));
                  final matches = snapshot.data!
                      .where((bank) => tokens.every(bank.search.contains))
                      .toList();
                  if (matches.isEmpty) {
                    return const Center(
                      child: Text('Không tìm thấy ngân hàng.'),
                    );
                  }
                  return ListView.builder(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final bank = matches[index];
                      return ListTile(
                        title: Text(bank.name),
                        subtitle: bank.code.isEmpty ? null : Text(bank.code),
                        onTap: () => Navigator.pop(context, bank.name),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

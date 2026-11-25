import 'package:flutter/material.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/product_tags.dart';

const customerPriceTiers = {
  'all': 'Tất cả mức giá',
  'under300': 'Dưới 300.000 đ',
  '300to600': '300.000 đ – 600.000 đ',
  '600to1000': '600.000 đ – 1.000.000 đ',
  'over1000': 'Trên 1.000.000 đ',
};

class CustomerCatalogFilters {
  const CustomerCatalogFilters({
    this.flower = 'all',
    this.price = 'all',
    this.availability = 'all',
    this.kiosk = 'all',
    this.shop = 'all',
  });
  final String flower, price, availability, kiosk, shop;
  bool get active =>
      [flower, price, availability, kiosk, shop].any((value) => value != 'all');
  CustomerCatalogFilters copyWith({
    String? flower,
    String? price,
    String? availability,
    String? kiosk,
    String? shop,
  }) => CustomerCatalogFilters(
    flower: flower ?? this.flower,
    price: price ?? this.price,
    availability: availability ?? this.availability,
    kiosk: kiosk ?? this.kiosk,
    shop: shop ?? this.shop,
  );
}

String _normalize(String text) {
  var value = text.toLowerCase().trim();
  const folds = {
    '[àáạảãâầấậẩẫăằắặẳẵ]': 'a',
    '[èéẹẻẽêềếệểễ]': 'e',
    '[ìíịỉĩ]': 'i',
    '[òóọỏõôồốộổỗơờớợởỡ]': 'o',
    '[ùúụủũưừứựửữ]': 'u',
    '[ỳýỵỷỹ]': 'y',
    'đ': 'd',
  };
  for (final entry in folds.entries) {
    value = value.replaceAll(RegExp(entry.key), entry.value);
  }
  return value.replaceAll(RegExp(r'\s+'), ' ');
}

Set<String> customerFlowerTypes(Json item) {
  final result = <String>{};
  for (final tag in (item['tags'] as List? ?? []).whereType<String>()) {
    final value = tag.trim().toLowerCase();
    if (value.contains(':')) {
      final parts = value.split(':');
      if (parts.length == 2 &&
          parts[0] == 'flower' &&
          productTagGroups['flower']!.containsKey(parts[1])) {
        result.add(parts[1]);
      }
    } else {
      final normalized = _normalize(value);
      for (final entry in productTagGroups['flower']!.entries) {
        if (entry.key != 'other' &&
            [
              entry.key,
              _normalize(entry.value),
              'hoa ${_normalize(entry.value)}',
            ].contains(normalized)) {
          result.add(entry.key);
        }
      }
    }
  }
  return result;
}

bool customerPriceMatches(num price, String filter) => switch (filter) {
  'under300' => price < 300000,
  '300to600' => price >= 300000 && price <= 600000,
  '600to1000' => price > 600000 && price <= 1000000,
  'over1000' => price > 1000000,
  _ => true,
};

List<Json> uniqueCustomerFlowers(Iterable<Json> rows) {
  final seen = <String>{};
  return rows.where((row) {
    final preorder = row['zone'] == null || row['zone'] == 'PREORDER';
    // Old fixtures may omit IDs; real catalog cards are scoped by seller/product.
    final product =
        '${row['sellerId'] ?? row['shopName']}:${row['productId'] ?? row['name']}';
    return seen.add(
      preorder
          ? '$product:PREORDER'
          : '$product:${row['kioskId']}:${row['zone']}',
    );
  }).toList();
}

List<Json> filterCustomerFlowers(
  List<Json> rows,
  CustomerCatalogFilters filters,
  String search,
) => uniqueCustomerFlowers(
  rows.where((row) {
    final price = row['price'];
    if (price is! num ||
        !price.isFinite ||
        !customerPriceMatches(price, filters.price)) {
      return false;
    }
    if (filters.flower != 'all' &&
        !customerFlowerTypes(row).contains(filters.flower)) {
      return false;
    }
    if (filters.shop != 'all' && row['shopName'] != filters.shop) {
      return false;
    }
    if (filters.kiosk != 'all' && row['kioskName'] != filters.kiosk) {
      return false;
    }
    if (filters.availability == 'stock' && row['zone'] != 'WALK_IN') {
      return false;
    }
    if (filters.availability == 'custom' &&
        row['zone'] != null &&
        row['zone'] != 'PREORDER') {
      return false;
    }
    final query = _normalize(search);
    return query.isEmpty ||
        [
          'name',
          'shopName',
          'kioskName',
          'address',
          'description',
        ].any((key) => _normalize('${row[key] ?? ''}').contains(query));
  }),
);

typedef CustomerCatalogFilterSelection = ({
  CustomerCatalogFilters filters,
  bool clearSearch,
});

Future<CustomerCatalogFilterSelection?> showCustomerCatalogFilters(
  BuildContext context,
  List<Json> rows,
  CustomerCatalogFilters current,
) => showModalBottomSheet<CustomerCatalogFilterSelection>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: Colors.white,
  builder: (_) => _CustomerCatalogFilterSheet(rows: rows, initial: current),
);

class _CustomerCatalogFilterSheet extends StatefulWidget {
  const _CustomerCatalogFilterSheet({
    required this.rows,
    required this.initial,
  });
  final List<Json> rows;
  final CustomerCatalogFilters initial;
  @override
  State<_CustomerCatalogFilterSheet> createState() =>
      _CustomerCatalogFilterSheetState();
}

class _CustomerCatalogFilterSheetState
    extends State<_CustomerCatalogFilterSheet> {
  late CustomerCatalogFilters draft = widget.initial;
  bool clearSearch = false;
  Widget field(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> change, {
    Set<String> disabled = const {},
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, color: forest),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in {
              if (!options.containsKey(value)) value: value,
              ...options,
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: value == entry.key,
                showCheckmark: false,
                selectedColor: const Color(0xFFE4EFE8),
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: value == entry.key ? forest : const Color(0xFFD6E1D8),
                ),
                labelStyle: TextStyle(
                  color: disabled.contains(entry.key)
                      ? const Color(0xFF8A968E)
                      : forest,
                ),
                onSelected: disabled.contains(entry.key)
                    ? null
                    : (_) => setState(() => change(entry.key)),
              ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cards = uniqueCustomerFlowers(widget.rows);
    final flowerCounts = <String, int>{};
    for (final row in cards) {
      for (final code in customerFlowerTypes(row)) {
        flowerCounts.update(code, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final flowers = {
      'all': 'Tất cả loại hoa',
      for (final entry in productTagGroups['flower']!.entries)
        if ((flowerCounts[entry.key] ?? 0) > 0 || draft.flower == entry.key)
          entry.key: '${entry.value} (${flowerCounts[entry.key] ?? 0})',
    };
    Map<String, String> choices(String key, String all) => {
      'all': all,
      for (final name
          in widget.rows
              .map((row) => '${row[key] ?? ''}')
              .where((name) => name.isNotEmpty)
              .toSet())
        name: name,
    };
    final kiosks = choices('kioskName', 'Tất cả tủ kiosk');
    final shops = choices('shopName', 'Tất cả cửa hàng');
    final hasStock = cards.any((row) => row['zone'] == 'WALK_IN');
    final hasPreorder = cards.any(
      (row) => row['zone'] == null || row['zone'] == 'PREORDER',
    );
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Bộ lọc',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: forest,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    draft = const CustomerCatalogFilters();
                    clearSearch = true;
                  }),
                  child: const Text('Đặt lại'),
                ),
                IconButton(
                  tooltip: 'Đóng bộ lọc',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field(
                    'Loại hoa',
                    draft.flower,
                    flowers,
                    (value) => draft = draft.copyWith(flower: value),
                  ),
                  field(
                    'Hình thức nhận hoa',
                    draft.availability,
                    const {
                      'all': 'Tất cả hình thức',
                      'stock': 'Mua trực tiếp tại tủ',
                      'custom': 'Đặt trước',
                    },
                    (value) => draft = draft.copyWith(availability: value),
                    disabled: {
                      if (!hasStock) 'stock',
                      if (!hasPreorder) 'custom',
                    },
                  ),
                  field(
                    'Khoảng giá',
                    draft.price,
                    customerPriceTiers,
                    (value) => draft = draft.copyWith(price: value),
                  ),
                  if (kiosks.length > 2 || draft.kiosk != 'all')
                    field(
                      'Tủ nhận hoa',
                      draft.kiosk,
                      kiosks,
                      (value) => draft = draft.copyWith(kiosk: value),
                    ),
                  if (shops.length > 2 || draft.shop != 'all')
                    field(
                      'Cửa hàng',
                      draft.shop,
                      shops,
                      (value) => draft = draft.copyWith(shop: value),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              MediaQuery.paddingOf(context).bottom + 16,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, (
                  filters: draft,
                  clearSearch: clearSearch,
                )),
                child: const Text('Áp dụng bộ lọc'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

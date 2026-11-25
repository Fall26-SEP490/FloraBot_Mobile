import 'package:flutter_test/flutter_test.dart';
import 'package:florabot_mobile/features/customer_catalog_filters.dart';
import 'package:florabot_mobile/ui/customer_flower_card.dart';

void main() {
  test('price tier boundaries match web without overlap', () {
    expect(customerPriceMatches(299999, 'under300'), isTrue);
    expect(customerPriceMatches(300000, 'under300'), isFalse);
    expect(customerPriceMatches(300000, '300to600'), isTrue);
    expect(customerPriceMatches(600000, '300to600'), isTrue);
    expect(customerPriceMatches(600000, '600to1000'), isFalse);
    expect(customerPriceMatches(600001, '600to1000'), isTrue);
    expect(customerPriceMatches(1000000, '600to1000'), isTrue);
    expect(customerPriceMatches(1000000, 'over1000'), isFalse);
    expect(customerPriceMatches(1000001, 'over1000'), isTrue);
    expect(customerPriceTiers['300to600'], '300.000 đ – 600.000 đ');
    expect(customerPriceTiers['600to1000'], '600.000 đ – 1.000.000 đ');
  });
  test('search matches Vietnamese text without accents', () {
    final rows = [
      {
        'sellerId': 'shop',
        'productId': 'rose',
        'name': 'Bó hồng pastel',
        'price': 250000,
        'shopName': 'Tiệm Hoa Đà Lạt',
        'kioskName': 'Kiosk Hòa Lạc',
        'address': 'Thạch Thất, Hà Nội',
      },
    ];
    expect(
      filterCustomerFlowers(
        rows,
        const CustomerCatalogFilters(),
        'hong pastel',
      ).length,
      1,
    );
    expect(
      filterCustomerFlowers(
        rows,
        const CustomerCatalogFilters(),
        'da lat',
      ).length,
      1,
    );
    expect(
      filterCustomerFlowers(
        rows,
        const CustomerCatalogFilters(),
        'hoa lac',
      ).length,
      1,
    );
  });
  test('flower status helpers match preorder, sold-out, and walk-in states', () {
    expect(
      customerFlowerStatusLabel({'zone': 'PREORDER', 'preorderAvailable': true}),
      'Đặt trước',
    );
    expect(
      canCustomerPreorder({'zone': 'PREORDER', 'preorderAvailable': true}),
      isTrue,
    );
    expect(
      customerFlowerStatusLabel({
        'zone': 'PREORDER',
        'preorderAvailable': false,
      }),
      'Hết hàng',
    );
    expect(
      canCustomerPreorder({'zone': 'PREORDER', 'preorderAvailable': false}),
      isFalse,
    );
    expect(
      customerFlowerStatusLabel({'zone': 'WALK_IN', 'preorderAvailable': false}),
      'Mua tại kiosk',
    );
    expect(canCustomerPreorder({'zone': 'WALK_IN'}), isFalse);
  });
  test(
    'flower status helpers match preorder, sold-out, and walk-in states',
    () {
      expect(
        customerFlowerStatusLabel({
          'zone': 'PREORDER',
          'preorderAvailable': true,
        }),
        'Đặt trước',
      );
      expect(
        canCustomerPreorder({'zone': 'PREORDER', 'preorderAvailable': true}),
        isTrue,
      );
      expect(
        customerFlowerStatusLabel({
          'zone': 'PREORDER',
          'preorderAvailable': false,
        }),
        'Hết hàng',
      );
      expect(
        canCustomerPreorder({'zone': 'PREORDER', 'preorderAvailable': false}),
        isFalse,
      );
      expect(
        customerFlowerStatusLabel({
          'zone': 'WALK_IN',
          'preorderAvailable': false,
        }),
        'Mua tại kiosk',
      );
      expect(canCustomerPreorder({'zone': 'WALK_IN'}), isFalse);
    },
  );
  test(
    'type filters recognize exact legacy labels and never infer from names or color',
    () {
      expect(
        customerFlowerTypes({
          'name': 'Hoa hồng',
          'tags': ['color:red', 'khác'],
        }),
        isEmpty,
      );
      expect(
        customerFlowerTypes({
          'tags': ['flower:rose', 'Hoa Hồng', 'huong duong'],
        }),
        {'rose', 'sunflower'},
      );
    },
  );
  test('combined filters run before deduplicating products across kiosks', () {
    final rose = {
      'sellerId': 'shop',
      'productId': 'rose',
      'name': 'Bó hồng',
      'shopName': 'Tiệm Hoa',
      'price': 350000,
      'tags': ['flower:rose'],
      'zone': 'PREORDER',
    };
    final rows = [
      {...rose, 'kioskId': 'a', 'kioskName': 'Kiosk A'},
      {...rose, 'kioskId': 'b', 'kioskName': 'Kiosk B'},
      {
        ...rose,
        'sellerId': 'other',
        'kioskId': 'b',
        'kioskName': 'Kiosk B',
        'shopName': 'Shop Khác',
      },
      {
        ...rose,
        'productId': 'sunflower',
        'kioskId': 'b',
        'kioskName': 'Kiosk B',
        'tags': ['flower:sunflower'],
      },
    ];
    expect(
      filterCustomerFlowers(rows, const CustomerCatalogFilters(), '').length,
      3,
    );
    final selected = filterCustomerFlowers(
      rows,
      const CustomerCatalogFilters(
        flower: 'rose',
        price: '300to600',
        kiosk: 'Kiosk B',
        shop: 'Tiệm Hoa',
        availability: 'custom',
      ),
      'hồng',
    );
    expect(selected.length, 1);
    expect(selected.single['kioskId'], 'b');
    expect(
      filterCustomerFlowers(
        rows,
        const CustomerCatalogFilters(availability: 'stock'),
        '',
      ),
      isEmpty,
    );
  });
}

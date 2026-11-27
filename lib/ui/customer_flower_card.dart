import 'package:flutter/material.dart';
import '../core/models.dart';
import 'common.dart';

bool isCustomerFlowerWalkIn(Json item) => item['zone'] == 'WALK_IN';

bool isCustomerFlowerPreorder(Json item) =>
    item['zone'] == null || item['zone'] == 'PREORDER';

bool isCustomerFlowerSoldOut(Json item) =>
    isCustomerFlowerPreorder(item) &&
    (item['preorderAvailable'] == false ||
        item['availablePreorder'] == false ||
        item['soldOut'] == true);

bool canCustomerPreorder(Json item) =>
    isCustomerFlowerPreorder(item) && !isCustomerFlowerSoldOut(item);

String customerFlowerStatusLabel(Json item) {
  if (isCustomerFlowerWalkIn(item)) return 'Mua tại kiosk';
  if (isCustomerFlowerSoldOut(item)) return 'Hết hàng';
  return 'Đặt trước';
}

class CustomerFlowerStatusBadge extends StatelessWidget {
  const CustomerFlowerStatusBadge(this.item, {super.key});
  final Json item;

  @override
  Widget build(BuildContext context) {
    final walkIn = isCustomerFlowerWalkIn(item);
    final soldOut = isCustomerFlowerSoldOut(item);
    final bg = walkIn
        ? forest
        : soldOut
        ? const Color(0xFFFEF2F2)
        : const Color(0xF2FFFFFF);
    final fg = walkIn
        ? Colors.white
        : soldOut
        ? const Color(0xFFB91C1C)
        : forest;
    final border = walkIn
        ? forest
        : soldOut
        ? const Color(0xFFFECACA)
        : const Color(0xFFD0DFD2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!walkIn) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            customerFlowerStatusLabel(item),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class CustomerFlowerPhoto extends StatelessWidget {
  const CustomerFlowerPhoto(this.item, {super.key});
  final Json item;
  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: Color(0xFFF0F5ED),
      child: Center(
        child: Icon(Icons.local_florist_outlined, size: 44, color: forest),
      ),
    );
    final photo = Uri.tryParse('${item['photo'] ?? ''}');
    return AspectRatio(
      aspectRatio: 1,
      child: photo?.scheme == 'https'
          ? Image.network(
              photo.toString(),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : placeholder,
            )
          : placeholder,
    );
  }
}

class CustomerFlowerCard extends StatelessWidget {
  const CustomerFlowerCard({
    required this.item,
    required this.onOpen,
    required this.onOrder,
    super.key,
  });
  final Json item;
  final VoidCallback? onOpen, onOrder;
  @override
  Widget build(BuildContext context) {
    final soldOut = isCustomerFlowerSoldOut(item);
    final walkIn = isCustomerFlowerWalkIn(item);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE0E8DC)),
      ),
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                Opacity(
                  opacity: soldOut ? 0.6 : 1,
                  child: CustomerFlowerPhoto(item),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: CustomerFlowerStatusBadge(item),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height:
                        MediaQuery.textScalerOf(context).scale(14) * 1.3 * 2,
                    child: Text(
                      valueOf(item, 'name'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: forest,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    valueOf(item, 'shopName'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF617568),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      money(item['price']),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: forest,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: walkIn ? const Color(0xFFEAF3EC) : forest,
                  foregroundColor: walkIn ? forest : Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: soldOut
                    ? null
                    : walkIn
                    ? onOpen
                    : onOrder,
                child: Text(
                  soldOut
                      ? 'Hết hàng'
                      : walkIn
                      ? 'Xem tủ'
                      : 'Đặt trước',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerFlowerDetail extends StatelessWidget {
  const CustomerFlowerDetail({
    required this.item,
    this.onChat,
    this.onReviews,
    super.key,
  });
  final Json item;
  final VoidCallback? onChat;
  final VoidCallback? onReviews;

  @override
  Widget build(BuildContext context) {
    final soldOut = isCustomerFlowerSoldOut(item);
    final walkIn = isCustomerFlowerWalkIn(item);
    final canOrder = canCustomerPreorder(item);
    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết mẫu hoa')),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE0E8DC))),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      walkIn ? 'Giá tại tủ' : 'Giá mẫu',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF476451),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        money(item['price']),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: forest,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (onChat != null) ...[
                      OutlinedButton(
                        onPressed: onChat,
                        child: const Text('Nhắn shop'),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: FilledButton(
                        onPressed: canOrder
                            ? () => Navigator.pop(context, true)
                            : null,
                        child: Text(
                          soldOut
                              ? 'Hết hàng'
                              : walkIn
                              ? 'Mua tại kiosk'
                              : 'Đặt trước',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.paddingOf(context).bottom + 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Opacity(
                opacity: soldOut ? 0.65 : 1,
                child: CustomerFlowerPhoto(item),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: CustomerFlowerStatusBadge(item),
            ),
            const SizedBox(height: 8),
            Text(
              valueOf(item, 'name'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: forest,
              ),
            ),
            const SizedBox(height: 10),
            Text(valueOf(item, 'shopName')),
            if (onReviews != null)
              TextButton.icon(
                onPressed: onReviews,
                icon: const Icon(Icons.star_outline),
                label: const Text('Đánh giá khách hàng'),
              ),
            const SizedBox(height: 6),
            Text(
              '${valueOf(item, 'kioskName')}\n${valueOf(item, 'address')}',
              style: const TextStyle(color: Color(0xFF617568), height: 1.5),
            ),
            const SizedBox(height: 12),
            Text(
              soldOut
                  ? 'Mẫu này tạm hết hàng.'
                  : walkIn
                  ? 'Chỉ mua trực tiếp tại kiosk.'
                  : 'Giá tham khảo. Shop sẽ báo giá trước khi bạn thanh toán.',
              style: TextStyle(
                fontSize: 13,
                color: soldOut
                    ? const Color(0xFFB91C1C)
                    : const Color(0xFF617568),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../core/models.dart';
import 'common.dart';

class InventoryFilter extends StatelessWidget {
  const InventoryFilter({
    required this.value,
    required this.options,
    required this.onChanged,
    this.showLabel = false,
    super.key,
  });
  final String value;
  final bool showLabel;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Lọc trạng thái: ${options[value]}',
    initialValue: value,
    onSelected: onChanged,
    position: PopupMenuPosition.under,
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    constraints: const BoxConstraints(minWidth: 180, maxWidth: 200),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    itemBuilder: (_) => [
      for (final entry in options.entries)
        PopupMenuItem(
          value: entry.key,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 14,
                    color: forest,
                    fontWeight: entry.key == value
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
              if (entry.key == value)
                const Icon(Icons.check, size: 18, color: forest),
            ],
          ),
        ),
    ],
    child: Container(
      width: showLabel ? null : 44,
      height: showLabel ? 48 : 44,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD4E0D4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: showLabel
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.filter_list_rounded, size: 20, color: forest),
                const SizedBox(width: 8),
                Text(
                  options[value] ?? '',
                  style: const TextStyle(fontSize: 14, color: forest),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more_rounded, size: 18, color: forest),
              ],
            )
          : const Center(
              child: Icon(Icons.filter_list, size: 24, color: forest),
            ),
    ),
  );
}

Color inventoryColor(String state) {
  if ([
    'OFFLINE',
    'FAULT',
    'ERROR',
    'CANCELLED',
    'REJECTED',
    'EXPIRED',
    'DISPENSE_FAILED',
    'Có sự cố',
    'Cần kiểm tra ô',
    'Cần kiểm tra dữ liệu ô',
    'Nhận hoa thất bại — cần xử lý',
  ].contains(state)) {
    return const Color(0xFFB42318);
  }
  if ([
    'ONLINE',
    'ACTIVE',
    'COMPLETED',
    'APPROVED',
    'Đang bán',
  ].contains(state)) {
    return forest;
  }
  if ([
    'RENTED_EMPTY',
    'Ô trống',
    'Đã bán — chờ khách nhận',
    'Đã bán — đang xử lý nhận hoa',
  ].contains(state)) {
    return const Color(0xFF075985);
  }
  return const Color(0xFF925B0A);
}

class InventoryStatus extends StatelessWidget {
  const InventoryStatus(this.state, {super.key});
  final String state;
  @override
  Widget build(BuildContext context) => Text(
    statusText(state),
    style: TextStyle(
      fontSize: 12,
      height: 1.5,
      fontWeight: FontWeight.w700,
      color: inventoryColor(state),
    ),
  );
}

class InventoryTile extends StatelessWidget {
  const InventoryTile({
    required this.title,
    required this.description,
    required this.state,
    required this.onTap,
    this.lines = const [],
    this.action,
    super.key,
  });
  final String title, description, state;
  final List<String> lines;
  final VoidCallback onTap;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFDDE6DF)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                        color: forest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: InventoryStatus(state),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF617267),
                  height: 1.5,
                ),
              ),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    line,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Color(0xFF203E2D),
                    ),
                  ),
                ),
              if (action != null)
                Align(alignment: Alignment.centerRight, child: action!),
            ],
          ),
        ),
      ),
    ),
  );
}

class InventoryField extends StatelessWidget {
  const InventoryField(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              height: 1.6,
              color: Color(0xFF617267),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: forest,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

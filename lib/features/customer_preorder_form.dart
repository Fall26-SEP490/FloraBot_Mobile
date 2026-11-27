import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/customer_flower_card.dart';
import 'chat.dart';

enum CustomerPreorderResult { submitted, viewOrders }

const _briefSuggestions = [
  (label: 'Sinh nhật', text: 'Tặng sinh nhật, hoa tông pastel'),
  (label: 'Kỷ niệm', text: 'Kỷ niệm ngày cưới, hoa hồng đỏ'),
  (label: 'Khai trương', text: 'Chúc mừng khai trương, hoa màu tươi sáng'),
  (label: 'Tặng gia đình', text: 'Tặng gia đình, hoa tông ấm'),
];

final List<String> _pickupTimeSlots = List.generate(48, (index) {
  final hour = (index ~/ 2).toString().padLeft(2, '0');
  final minute = index.isOdd ? '30' : '00';
  return '$hour:$minute';
});

bool _isPreorderRow(Json row) => isCustomerFlowerPreorder(row);

bool _isPreorderSoldOut(Json row) => isCustomerFlowerSoldOut(row);

bool isValidPreorderPickup(DateTime pickup, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final delay = pickup.difference(current);
  return delay > Duration.zero && delay <= const Duration(days: 30);
}

Future<CustomerPreorderResult?> openCustomerPreorderForm(
  BuildContext context, {
  required ApiClient api,
  required Json item,
  List<Json> catalogRows = const [],
}) => Navigator.of(context).push<CustomerPreorderResult>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => CustomerPreorderFormPage(
      api: api,
      item: item,
      catalogRows: catalogRows,
    ),
  ),
);

class CustomerPreorderFormPage extends StatefulWidget {
  const CustomerPreorderFormPage({
    required this.api,
    required this.item,
    this.catalogRows = const [],
    super.key,
  });

  final ApiClient api;
  final Json item;
  final List<Json> catalogRows;

  @override
  State<CustomerPreorderFormPage> createState() =>
      _CustomerPreorderFormPageState();
}

class _CustomerPreorderFormPageState extends State<CustomerPreorderFormPage> {
  final _instructionsController = TextEditingController();

  // Kiosk selection & initial availability
  List<Json> _eligibleKiosks = const [];
  bool _kiosksLoading = true;
  bool _kiosksError = false;
  String? _chosenKioskId;

  // Accessories
  List<Json> _accessories = const [];
  bool _accessoriesLoading = false;
  bool _accessoriesError = false;
  bool _accessoriesLoaded = false;
  final Map<String, int> _selectedAccessories = {};

  // Pickup date & time + live availability
  DateTime? _pickupDay;
  String? _pickupTime;
  bool _checkingSlotAvailability = false;
  bool? _slotAvailable;
  String? _slotAvailabilityMessage;
  bool _slotAvailabilityError = false;
  int _availabilityCheckSeq = 0;

  // Form submission & validation state
  bool _busy = false;
  bool _openingChat = false;
  bool _uncertain = false;
  bool _done = false;
  String? _stockConflictKioskId;
  String _error = '';
  String _pickupError = '';
  String _briefError = '';
  Json? _pendingPayload;

  String get _sellerId => '${widget.item['sellerId'] ?? ''}';
  String get _productId => '${widget.item['productId'] ?? ''}';
  num get _basePrice => num.tryParse('${widget.item['price'] ?? 0}') ?? 0;

  Json? get _selectedKiosk {
    if (_eligibleKiosks.isEmpty) return null;
    if (_chosenKioskId != null) {
      for (final entry in _eligibleKiosks) {
        if ('${entry['kioskId']}' == _chosenKioskId) return entry;
      }
    }
    if (_eligibleKiosks.length == 1) return _eligibleKiosks.first;
    final initialId = '${widget.item['kioskId'] ?? ''}';
    for (final entry in _eligibleKiosks) {
      if ('${entry['kioskId']}' == initialId) return entry;
    }
    return null;
  }

  String get _selectedKioskId => '${_selectedKiosk?['kioskId'] ?? ''}';

  DateTime? get _pickupDateTime {
    final day = _pickupDay;
    final time = _pickupTime;
    if (day == null || time == null || !time.contains(':')) return null;
    final parts = time.split(':');
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  bool get _noKiosksAvailable =>
      !_kiosksLoading && !_kiosksError && _eligibleKiosks.isEmpty;

  bool get _soldOut =>
      !_uncertain &&
      ((_stockConflictKioskId != null &&
              (_selectedKioskId.isEmpty ||
                  _stockConflictKioskId == _selectedKioskId)) ||
          _isPreorderSoldOut(_selectedKiosk ?? widget.item));

  bool get _invalidAccessories {
    if (_selectedAccessories.isEmpty) return false;
    for (final entry in _selectedAccessories.entries) {
      final found = _findAccessory(entry.key);
      if (found == null) return true;
      final available = _accessoryAvailable(found);
      if (entry.value > available) return true;
    }
    return false;
  }

  num? get _accessorySubtotal {
    if (_invalidAccessories ||
        (_accessoriesError && _selectedAccessories.isNotEmpty)) {
      return null;
    }
    num sum = 0;
    for (final entry in _selectedAccessories.entries) {
      final found = _findAccessory(entry.key);
      if (found == null) return null;
      final price = num.tryParse('${found['price'] ?? 0}') ?? 0;
      sum += price * entry.value;
    }
    return sum;
  }

  bool get _dirty =>
      !_done &&
      (_pickupDay != null ||
          _pickupTime != null ||
          _instructionsController.text.isNotEmpty ||
          _chosenKioskId != null ||
          _selectedAccessories.isNotEmpty);

  Json? _findAccessory(String id) {
    for (final item in _accessories) {
      if ('${item['id']}' == id) return item;
    }
    return null;
  }

  int _accessoryAvailable(Json entry) {
    final raw = int.tryParse('${entry['availableQuantity'] ?? 0}') ?? 0;
    if (raw < 0) return 0;
    return raw > 2147483647 ? 2147483647 : raw;
  }

  @override
  void initState() {
    super.initState();
    _loadKiosks(useInitialRows: true);
    if (_sellerId.isNotEmpty && _isPreorderRow(widget.item)) {
      _loadAccessories();
    }
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  List<Json> _extractCandidateKiosks(Iterable<Json> rows) {
    final matches = <String, Json>{};
    for (final entry in rows) {
      final kid = '${entry['kioskId'] ?? ''}';
      if (kid.isEmpty) continue;
      if ('${entry['productId'] ?? ''}' == _productId &&
          '${entry['sellerId'] ?? ''}' == _sellerId &&
          _isPreorderRow(entry) &&
          !_isPreorderSoldOut(entry)) {
        matches[kid] = entry;
      }
    }
    final fallbackId = '${widget.item['kioskId'] ?? ''}';
    if (matches.isEmpty &&
        fallbackId.isNotEmpty &&
        _isPreorderRow(widget.item) &&
        !_isPreorderSoldOut(widget.item)) {
      matches[fallbackId] = widget.item;
    }
    return matches.values.toList();
  }

  Future<void> _loadKiosks({required bool useInitialRows}) async {
    if (!mounted) return;
    setState(() {
      _kiosksLoading = true;
      _kiosksError = false;
    });
    try {
      List<Json> candidates;
      if (useInitialRows && widget.catalogRows.isNotEmpty) {
        candidates = _extractCandidateKiosks(widget.catalogRows);
      } else {
        final fetched = <Json>[];
        var page = 1;
        while (mounted && page <= 20) {
          final result = await widget.api.get(
            '/api/shop/catalog?page=$page&search=${Uri.encodeQueryComponent(valueOf(widget.item, 'name', ''))}',
          );
          final rows = itemsOf(result);
          fetched.addAll(rows);
          if (result is! Map || result['hasMore'] != true || rows.isEmpty) {
            break;
          }
          page++;
        }
        candidates = _extractCandidateKiosks(fetched);
      }

      if (candidates.isEmpty) {
        if (!mounted) return;
        setState(() {
          _eligibleKiosks = const [];
          _kiosksLoading = false;
        });
        return;
      }

      final eligible = <Json>[];
      var failedChecks = 0;
      await Future.wait(
        candidates.map((entry) async {
          final kid = '${entry['kioskId']}';
          try {
            final resp = objectOf(
              await widget.api.get('/api/kiosks/$kid/preorder-availability'),
            );
            // Real backend always includes `available`; treat absent field in minimal mocks as available.
            final isAvailable = resp.containsKey('available')
                ? resp['available'] == true
                : true;
            if (isAvailable) eligible.add(entry);
          } catch (_) {
            failedChecks++;
          }
        }),
      );

      if (!mounted) return;
      if (failedChecks == candidates.length) {
        setState(() {
          _eligibleKiosks = const [];
          _kiosksError = true;
          _kiosksLoading = false;
        });
        return;
      }

      eligible.sort(
        (a, b) => '${a['kioskName'] ?? ''}'.toLowerCase().compareTo(
          '${b['kioskName'] ?? ''}'.toLowerCase(),
        ),
      );
      setState(() {
        _eligibleKiosks = eligible;
        _kiosksLoading = false;
      });
      _triggerSlotAvailabilityCheck();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _eligibleKiosks = const [];
        _kiosksError = true;
        _kiosksLoading = false;
      });
    }
  }

  Future<void> _loadAccessories() async {
    if (!mounted) return;
    setState(() {
      _accessoriesLoading = true;
      _accessoriesError = false;
    });
    try {
      final result = await widget.api.get(
        '/api/member/sellers/$_sellerId/catalog/accessories',
      );
      final parsed = result is List
          ? result
                .whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList()
          : result is Map && result['items'] is List
          ? itemsOf(result)
          : <Json>[];
      if (!mounted) return;
      setState(() {
        _accessories = parsed;
        _accessoriesLoading = false;
        _accessoriesLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _accessoriesLoading = false;
        _accessoriesError = true;
      });
    }
  }

  Future<void> _triggerSlotAvailabilityCheck() async {
    final kioskId = _selectedKioskId;
    final pickup = _pickupDateTime;
    if (kioskId.isEmpty || pickup == null) {
      if (mounted) {
        setState(() {
          _checkingSlotAvailability = false;
          _slotAvailable = null;
          _slotAvailabilityMessage = null;
          _slotAvailabilityError = false;
        });
      }
      return;
    }
    final seq = ++_availabilityCheckSeq;
    setState(() {
      _checkingSlotAvailability = true;
      _slotAvailable = null;
      _slotAvailabilityMessage = null;
      _slotAvailabilityError = false;
    });
    try {
      final resp = objectOf(
        await widget.api.get(
          '/api/kiosks/$kioskId/preorder-availability?pickupAt=${Uri.encodeQueryComponent(pickup.toUtc().toIso8601String())}',
        ),
      );
      if (!mounted || seq != _availabilityCheckSeq) return;
      final isAvailable = resp.containsKey('available')
          ? resp['available'] == true
          : true;
      setState(() {
        _checkingSlotAvailability = false;
        _slotAvailable = isAvailable;
        _slotAvailabilityMessage = resp['message'] is String
            ? resp['message'] as String
            : null;
      });
    } catch (_) {
      if (!mounted || seq != _availabilityCheckSeq) return;
      setState(() {
        _checkingSlotAvailability = false;
        _slotAvailabilityError = true;
      });
    }
  }

  void _setAccessoryQuantity(String accessoryId, int quantity) {
    setState(() {
      if (quantity <= 0) {
        _selectedAccessories.remove(accessoryId);
      } else {
        _selectedAccessories[accessoryId] = quantity;
      }
      _error = '';
    });
  }

  Future<void> _pickDate() async {
    if (_busy || _uncertain) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickupDay ?? today.add(const Duration(days: 1)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 30)),
      helpText: 'Chọn ngày nhận hoa',
    );
    if (picked != null && mounted) {
      setState(() {
        _pickupDay = picked;
        _pickupError = '';
        _error = '';
      });
      await _triggerSlotAvailabilityCheck();
    }
  }

  Future<bool> _confirmDiscard({required bool forChat}) async {
    if (_busy) return false;
    if (!_dirty && !_uncertain) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(forChat ? 'Mở tin nhắn?' : 'Đóng form?'),
        content: Text(
          _uncertain
              ? 'Chưa rõ kết quả gửi. Hãy kiểm tra Đơn đặt trước.'
              : 'Thông tin chưa gửi sẽ không được lưu.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Ở lại'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(forChat ? 'Mở tin nhắn' : 'Đóng'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  Future<void> _requestClose() async {
    if (await _confirmDiscard(forChat: false) && mounted) {
      Navigator.pop(context, _done ? CustomerPreorderResult.submitted : null);
    }
  }

  Future<void> _openChat() async {
    if (_busy || _openingChat || _sellerId.isEmpty) return;
    if (!await _confirmDiscard(forChat: true) || !mounted) return;
    setState(() => _openingChat = true);
    try {
      await openCustomerChat(
        context,
        widget.api,
        _sellerId,
        productId: _productId.isEmpty ? null : _productId,
      );
    } catch (err) {
      if (mounted) message(context, '$err');
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _soldOut || !_isPreorderRow(widget.item)) return;
    setState(() {
      _error = '';
      _pickupError = '';
      _briefError = '';
    });

    if (_pendingPayload == null) {
      final kiosk = _selectedKiosk;
      if (kiosk == null || _kiosksLoading || _kiosksError) {
        setState(() => _error = 'Chưa chọn được tủ nhận. Hãy thử tải lại.');
        return;
      }
      if (_invalidAccessories ||
          (_accessoriesError && _selectedAccessories.isNotEmpty)) {
        setState(() => _error = 'Kiểm tra lại phụ kiện đã chọn.');
        return;
      }
      final pickup = _pickupDateTime;
      if (pickup == null || !isValidPreorderPickup(pickup)) {
        setState(() => _pickupError = 'Chọn ngày giờ nhận (tối đa 30 ngày).');
        return;
      }
      if (_slotAvailable == false) {
        setState(
          () =>
              _error = _slotAvailabilityMessage ?? 'Tủ hết chỗ khung giờ này.',
        );
        return;
      }
      final brief = _instructionsController.text.trim();
      if (brief.length < 10 || brief.length > 2000) {
        setState(() => _briefError = 'Nhập ít nhất 10 ký tự.');
        return;
      }
      _pendingPayload = {
        'id': const Uuid().v4(),
        'kind': 'CUSTOM',
        'productId': _productId,
        'kioskId': '${kiosk['kioskId']}',
        'pickupAt': pickup.toUtc().toIso8601String(),
        'instructions': brief,
        'accessories': [
          for (final entry in _selectedAccessories.entries)
            {'accessoryId': entry.key, 'quantity': entry.value},
        ],
      };
    }

    setState(() => _busy = true);
    try {
      await widget.api.post('/api/member/preorders', _pendingPayload);
      if (!mounted) return;
      setState(() {
        _done = true;
        _uncertain = false;
      });
    } on ApiError catch (err) {
      if (!mounted) return;
      if (err.status == 409 && err.code == 'PREORDER_PRODUCT_OUT_OF_STOCK') {
        setState(() {
          _stockConflictKioskId =
              '${_pendingPayload?['kioskId'] ?? _selectedKioskId}';
          _pendingPayload = null;
          _uncertain = false;
        });
        _loadKiosks(useInitialRows: false);
      } else {
        if (err.status == 409 && _selectedAccessories.isNotEmpty) {
          _loadAccessories();
        }
        final clientError =
            err.status >= 400 && err.status < 500 && err.status != 408;
        setState(() {
          _error = err.code == 'PREORDER_ACCESSORY_NOT_IN_SHOP'
              ? 'Phụ kiện không còn thuộc shop.'
              : err.message;
          if (clientError) {
            _pendingPayload = null;
            _uncertain = false;
          } else {
            _uncertain = true;
          }
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Chưa rõ kết quả. Thử gửi lại hoặc kiểm tra Đơn đặt.';
        _uncertain = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildHeaderThumb() {
    final photo = Uri.tryParse('${widget.item['photo'] ?? ''}');
    const fallback = ColoredBox(
      color: Color(0xFFF0F5ED),
      child: Center(
        child: Icon(Icons.local_florist_outlined, size: 20, color: forest),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 40,
        height: 40,
        child: photo?.scheme == 'https'
            ? Image.network(
                photo.toString(),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }

  Widget _buildDoneBody() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0xFFE4EFE8),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, size: 30, color: forest),
          ),
          const SizedBox(height: 16),
          const Text(
            'Đã gửi yêu cầu',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: forest,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Shop sẽ báo giá sớm. Mã nhận hoa sẽ gửi qua email khi sẵn sàng.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF476451), height: 1.5),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () =>
                  Navigator.pop(context, CustomerPreorderResult.viewOrders),
              child: const Text('Xem đơn đặt'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () =>
                  Navigator.pop(context, CustomerPreorderResult.submitted),
              child: const Text('Đóng'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildAccessoriesSection(bool locked) {
    final shouldShow =
        _sellerId.isNotEmpty &&
        (!_accessoriesLoaded ||
            _accessories.isNotEmpty ||
            _selectedAccessories.isNotEmpty);
    if (!shouldShow) return const SizedBox.shrink();

    final subtotal = _accessorySubtotal;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E8DC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 18, color: forest),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Phụ kiện',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: forest,
                    fontSize: 14.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F5ED),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Tùy chọn',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF476451),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_accessoriesLoading)
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đang tải phụ kiện…',
                    style: TextStyle(fontSize: 13, color: Color(0xFF476451)),
                  ),
                ),
              ],
            )
          else if (_accessoriesError) ...[
            const Text(
              'Chưa tải được phụ kiện.',
              style: TextStyle(fontSize: 13, color: Color(0xFF476451)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: locked ? null : _loadAccessories,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Thử lại'),
            ),
          ] else ...[
            for (var i = 0; i < _accessories.length; i++) ...[
              if (i > 0) const Divider(height: 16, color: Color(0xFFEAF0E7)),
              _buildAccessoryRow(_accessories[i], locked),
            ],
            if (_selectedAccessories.length >= 20) ...[
              const SizedBox(height: 8),
              const Text(
                'Tối đa 20 loại phụ kiện.',
                style: TextStyle(fontSize: 12, color: Color(0xFF476451)),
              ),
            ],
          ],
          if (_invalidAccessories) ...[
            const SizedBox(height: 8),
            const Text(
              'Tồn kho phụ kiện đã thay đổi.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFFB91C1C)),
            ),
          ],
          if (_selectedAccessories.isNotEmpty) ...[
            const Divider(height: 20, color: Color(0xFFE0E8DC)),
            Row(
              children: [
                Expanded(
                  child: Text(
                    subtotal == null
                        ? 'Chưa tính được tiền phụ kiện'
                        : 'Phụ kiện: ${money(subtotal)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: forest,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: locked
                      ? null
                      : () => setState(() {
                          _selectedAccessories.clear();
                          _error = '';
                        }),
                  child: const Text('Bỏ chọn'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccessoryRow(Json entry, bool locked) {
    final id = '${entry['id'] ?? ''}';
    final name = valueOf(entry, 'name');
    final available = _accessoryAvailable(entry);
    final qty = _selectedAccessories[id] ?? 0;
    final atLimit =
        qty >= available || (qty == 0 && _selectedAccessories.length >= 20);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: forest,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                money(entry['price']),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF476451),
                ),
              ),
              if (qty > 0 && qty == available)
                const Text(
                  'Đã chọn tối đa',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF617568)),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (qty == 0)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              side: const BorderSide(color: Color(0xFFD5E2D5)),
            ),
            onPressed: locked || atLimit
                ? null
                : () => _setAccessoryQuantity(id, 1),
            icon: available > 0
                ? const Icon(Icons.add, size: 16)
                : const SizedBox.shrink(),
            label: Text(available > 0 ? 'Thêm' : 'Hết hàng'),
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: IconButton(
                  tooltip: 'Giảm số lượng $name',
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: const BorderSide(color: Color(0xFFD5E2D5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: locked
                      ? null
                      : () => _setAccessoryQuantity(id, qty - 1),
                  icon: const Icon(Icons.remove, size: 16),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '$qty',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: forest,
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                height: 36,
                child: IconButton(
                  tooltip: 'Tăng số lượng $name',
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: const BorderSide(color: Color(0xFFD5E2D5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: locked || atLimit
                      ? null
                      : () => _setAccessoryQuantity(id, qty + 1),
                  icon: const Icon(Icons.add, size: 16),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildKioskSection(bool locked) {
    final selected = _selectedKiosk;
    final disabled =
        locked || _kiosksLoading || _kiosksError || _noKiosksAvailable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tủ nhận hoa',
          style: TextStyle(fontWeight: FontWeight.w700, color: forest),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey('${_eligibleKiosks.length}-${selected?['kioskId']}'),
          initialValue: selected == null ? null : '${selected['kioskId']}',
          isExpanded: true,
          hint: Text(
            _noKiosksAvailable ? 'Chưa có tủ khả dụng' : 'Chọn tủ',
            overflow: TextOverflow.ellipsis,
          ),
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: [
            for (final entry in _eligibleKiosks)
              DropdownMenuItem<String>(
                value: '${entry['kioskId']}',
                child: Text(
                  valueOf(entry, 'kioskName'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: disabled
              ? null
              : (value) {
                  if (value == null || value == _selectedKioskId) return;
                  setState(() {
                    _chosenKioskId = value;
                    _error = '';
                  });
                  _triggerSlotAvailabilityCheck();
                },
        ),
        if (_kiosksLoading) ...[
          const SizedBox(height: 6),
          const Text(
            'Đang kiểm tra tủ…',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF476451)),
          ),
        ],
        if (_kiosksError) ...[
          const SizedBox(height: 6),
          const Text(
            'Chưa tải được tủ nhận.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFFB91C1C)),
          ),
        ],
        if (_noKiosksAvailable) ...[
          const SizedBox(height: 6),
          const Text(
            'Hiện chưa có tủ khả dụng.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFFB91C1C)),
          ),
        ],
        if (_kiosksError || _noKiosksAvailable) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: locked ? null : () => _loadKiosks(useInitialRows: false),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Thử lại'),
          ),
        ],
        if (selected != null && '${selected['address'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: Color(0xFF476451),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${selected['address']}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF476451),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildPickupSection(bool locked) {
    final dayLabel = _pickupDay == null
        ? 'Chọn ngày'
        : DateFormat('dd/MM/yyyy').format(_pickupDay!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ngày nhận',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: forest,
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: locked ? null : _pickDate,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        suffixIcon: const Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: Color(0xFF476451),
                        ),
                        suffixIconConstraints: const BoxConstraints(
                          minWidth: 34,
                          minHeight: 34,
                        ),
                        enabledBorder: _pickupError.isNotEmpty
                            ? OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFB91C1C),
                                ),
                              )
                            : null,
                      ),
                      child: Text(
                        dayLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: _pickupDay == null
                              ? const Color(0xFF617568)
                              : forest,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Giờ nhận',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: forest,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('preorder-time-dropdown'),
                    initialValue: _pickupTime,
                    isExpanded: true,
                    menuMaxHeight: 320,
                    hint: const Text(
                      'Chọn giờ',
                      overflow: TextOverflow.ellipsis,
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      enabledBorder: _pickupError.isNotEmpty
                          ? OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFFB91C1C),
                              ),
                            )
                          : null,
                    ),
                    items: [
                      for (final slot in _pickupTimeSlots)
                        DropdownMenuItem<String>(
                          value: slot,
                          child: Text(slot),
                        ),
                    ],
                    onChanged: locked
                        ? null
                        : (value) {
                            setState(() {
                              _pickupTime = value;
                              _pickupError = '';
                              _error = '';
                            });
                            _triggerSlotAvailabilityCheck();
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_pickupError.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _pickupError,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFFB91C1C)),
          ),
        ],
        if (_checkingSlotAvailability) ...[
          const SizedBox(height: 6),
          const Text(
            'Đang kiểm tra chỗ trống…',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF476451)),
          ),
        ],
        if (_slotAvailable == false) ...[
          const SizedBox(height: 6),
          Text(
            _slotAvailabilityMessage ?? 'Tủ hết chỗ khung giờ này.',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFFB91C1C)),
          ),
        ],
        if (_slotAvailabilityError) ...[
          const SizedBox(height: 6),
          const Text(
            'Chưa kiểm tra được chỗ trống.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF476451)),
          ),
        ],
      ],
    );
  }

  Widget _buildBriefSection(bool locked) {
    final currentText = _instructionsController.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Yêu cầu bó hoa',
          style: TextStyle(fontWeight: FontWeight.w700, color: forest),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _instructionsController,
          enabled: !locked,
          minLines: 3,
          maxLines: 5,
          maxLength: 2000,
          decoration: InputDecoration(
            hintText: 'Dịp tặng, màu sắc, ngân sách…',
            counterText: '',
            alignLabelWithHint: true,
            enabledBorder: _briefError.isNotEmpty
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFB91C1C)),
                  )
                : null,
          ),
          onChanged: (_) => setState(() {
            _briefError = '';
            _error = '';
          }),
        ),
        if (_briefError.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _briefError,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFFB91C1C)),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final suggestion in _briefSuggestions)
              Builder(
                builder: (_) {
                  final added = currentText.toLowerCase().contains(
                    suggestion.text.toLowerCase(),
                  );
                  final next = currentText.trim().isNotEmpty
                      ? '${currentText.trimRight()}\n${suggestion.text}'
                      : suggestion.text;
                  final disabled = locked || added || next.length > 2000;
                  return ActionChip(
                    avatar: Icon(
                      added ? Icons.check_rounded : Icons.add_rounded,
                      size: 16,
                      color: forest,
                    ),
                    label: Text(suggestion.label),
                    backgroundColor: added
                        ? const Color(0xFFE4EFE8)
                        : const Color(0xFFF7FAF6),
                    side: BorderSide(
                      color: added ? forest : const Color(0xFFD5E2D5),
                    ),
                    labelStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: forest,
                    ),
                    onPressed: disabled
                        ? null
                        : () {
                            _instructionsController.text = next;
                            _instructionsController.selection =
                                TextSelection.collapsed(offset: next.length);
                            setState(() {
                              _briefError = '';
                              _error = '';
                            });
                          },
                  );
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildFooter() {
    final subtotal = _accessorySubtotal;
    final hasAccessories = _selectedAccessories.isNotEmpty;
    final submitDisabled =
        _busy ||
        _soldOut ||
        (!_uncertain &&
            (_selectedKiosk == null || _kiosksLoading || _kiosksError));
    return Container(
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
              if (_soldOut) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: const Text(
                    'Mẫu hoa đã hết hàng.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFFB91C1C)),
                  ),
                ),
              ],
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasAccessories ? 'Tạm tính' : 'Giá mẫu',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF476451),
                          ),
                        ),
                        Text(
                          subtotal == null ? '—' : money(_basePrice + subtotal),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: forest,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          size: 15,
                          color: forest,
                        ),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Chưa cần thanh toán',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF476451),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (_sellerId.isNotEmpty) ...[
                    OutlinedButton(
                      onPressed: _busy || _openingChat ? null : _openChat,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: Text(_openingChat ? 'Đang mở…' : 'Nhắn shop'),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: submitDisabled ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      child: Text(
                        _busy
                            ? 'Đang gửi…'
                            : _uncertain
                            ? 'Gửi lại'
                            : 'Gửi yêu cầu',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              if (_uncertain && !_busy) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, CustomerPreorderResult.viewOrders),
                  child: const Text('Kiểm tra đơn đặt'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locked = _busy || _uncertain;
    return PopScope<CustomerPreorderResult>(
      canPop: !_dirty && !_uncertain && !_busy && !_done,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _requestClose();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          leading: IconButton(
            tooltip: 'Đóng yêu cầu đặt trước',
            onPressed: _busy ? null : _requestClose,
            icon: const Icon(Icons.close),
          ),
          titleSpacing: 0,
          title: Row(
            children: [
              _buildHeaderThumb(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Yêu cầu đặt trước',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: forest,
                      ),
                    ),
                    Text(
                      '${valueOf(widget.item, 'name')} · ${valueOf(widget.item, 'shopName')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF476451),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: Color(0xFFE0E8DC)),
          ),
        ),
        bottomNavigationBar: _done || !_isPreorderRow(widget.item)
            ? null
            : _buildFooter(),
        body: _done
            ? _buildDoneBody()
            : !_isPreorderRow(widget.item)
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: InfoBox(
                  'Chỉ mua tại kiosk: ${valueOf(widget.item, 'kioskName')} — ${valueOf(widget.item, 'address')}',
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildAccessoriesSection(locked),
                    _buildKioskSection(locked),
                    const SizedBox(height: 18),
                    _buildPickupSection(locked),
                    const SizedBox(height: 18),
                    _buildBriefSection(locked),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Text(
                          _error,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFB91C1C),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

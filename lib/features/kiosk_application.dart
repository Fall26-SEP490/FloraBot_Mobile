import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/goong.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/vietnam_bank_picker.dart';
import '../ui/location_picker.dart';
import 'inventory.dart' show openPage;
import 'payment_channel.dart';
import 'subscriptions.dart' show rentalDate;

const applicationLabels = {
  'AWAITING_PAYMENT': 'Chờ thanh toán',
  'PAID_REVIEW': 'Chờ duyệt',
  'UNDER_REVIEW': 'Đang xem xét',
  'CONFIRMED': 'Chờ xếp lịch',
  'SCHEDULED': 'Đã xếp lịch',
  'INSTALLING': 'Đang lắp đặt',
  'AWAITING_HANDOVER': 'Chờ bàn giao',
  'ACTIVE': 'Đã bàn giao',
  'CANCELLED': 'Đã hủy',
  'REJECTED': 'Từ chối',
  'REFUND_PENDING': 'Chờ hoàn tiền',
  'REFUNDED': 'Đã hoàn tiền',
};

bool _inProgress(Json? app) =>
    app != null &&
    !['ACTIVE', 'CANCELLED', 'REJECTED', 'REFUNDED'].contains(app['status']);

class KioskApplicationPage extends StatefulWidget {
  const KioskApplicationPage(
    this.api,
    this.session, {
    this.locationPicker,
    this.onActivateShop,
    this.placesClient,
    super.key,
  });
  final Future<void> Function()? onActivateShop;
  final ApiClient api;
  final Session session;
  final Future<KioskLocation?> Function(BuildContext, KioskPoint?, String)?
  locationPicker;
  final GoongPlacesClient? placesClient;
  @override
  State<KioskApplicationPage> createState() => _KioskApplicationPageState();
}

class _KioskApplicationPageState extends State<KioskApplicationPage>
    with WidgetsBindingObserver {
  final address = TextEditingController();
  final customerFields = {
    for (final key in [
      'shopName',
      'phone',
      'contactEmail',
      'bankName',
      'bankHolder',
      'bankAccountNumber',
    ])
      key: TextEditingController(),
  };
  bool get customer => widget.session.role == AppRole.customer;
  final form = GlobalKey<FormState>();
  Json? application, pricing, bank, shop;
  KioskPoint? point;
  GoongPlacesClient? _places;
  List<Json> _predictions = [];
  Object? loadError, setupError;
  String? error, notice, _addressSearchError;
  bool loading = true,
      busy = false,
      accepted = false,
      polling = false,
      resumed = true,
      _searchingAddress = false,
      _resolvingAddress = false,
      _showSuggestions = false,
      _searchEmpty = false,
      _pinnedFromSuggestion = false;
  int walk = 1, preorder = 0, epoch = 0, _searchId = 0, _detailId = 0;
  Timer? timer, _searchDebounce;
  ApiClient get api => widget.api;
  String get currentPath => '/api/member/kiosk-applications/current';
  int get totalSlots => walk + preorder;
  num get unitPrice => pricing?['annualSlotPrice'] as num? ?? 0;
  bool get ready =>
      setupError == null &&
      pricing?['configured'] == true &&
      unitPrice > 0 &&
      (pricing?['version'] as int? ?? 0) > 0 &&
      (customer || bank?['status'] == 'READY');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.placesClient != null) {
      _places = widget.placesClient;
    } else {
      unawaited(_loadPlaces());
    }
    unawaited(refresh());
    timer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted ||
          busy ||
          loading ||
          polling ||
          !resumed ||
          !_inProgress(application) ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      polling = true;
      final generation = ++epoch;
      try {
        final next = await readCurrent();
        if (mounted && generation == epoch) setState(() => application = next);
      } catch (_) {
        /* Keep the last known status; explicit refresh exposes errors. */
      } finally {
        polling = false;
      }
    });
  }

  Future<void> _loadPlaces() async {
    final config = await GoongConfig.load();
    if (!mounted || widget.placesClient != null || config.apiKey.isEmpty) {
      return;
    }
    setState(() => _places = GoongPlacesClient(config.apiKey));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    resumed = state == AppLifecycleState.resumed;
    if (resumed &&
        mounted &&
        !busy &&
        !loading &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    epoch++;
    _searchId++;
    _detailId++;
    timer?.cancel();
    _searchDebounce?.cancel();
    if (widget.placesClient == null) _places?.dispose();
    address.dispose();
    for (final controller in customerFields.values) {
      controller.clear();
      controller.dispose();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<Json?> readCurrent() async {
    try {
      return objectOf(await api.get(currentPath));
    } on ApiError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<void> refresh() async {
    final generation = ++epoch;
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final current = await readCurrent();
      if (!mounted || generation != epoch) return;
      setState(() => application = current);
      try {
        final result = await Future.wait([
          api.get('/api/kiosk-packages'),
          if (!customer)
            api.get('/api/sellers/${widget.session.sellerId}/bank'),
          if (!customer) api.get('/api/me/shop'),
        ]);
        if (!mounted || generation != epoch) return;
        setState(() {
          final nextPricing = objectOf(result[0]);
          if (pricing?['version'] != nextPricing['version']) accepted = false;
          pricing = nextPricing;
          if (!customer) {
            bank = objectOf(result[1]);
            shop = objectOf(result[2]);
          }
          setupError = null;
        });
      } catch (e) {
        if (mounted && generation == epoch) setState(() => setupError = e);
      }
    } catch (e) {
      if (mounted && generation == epoch) setState(() => loadError = e);
    } finally {
      if (mounted && generation == epoch) setState(() => loading = false);
    }
  }

  Future<void> action(Future<void> Function() run) async {
    if (busy) return;
    epoch++;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await run();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = switch (e is ApiError ? e.message : '$e') {
            'Seller is not active' ||
            'Seller is not eligible to request a kiosk' =>
              'Shop chưa đủ điều kiện thuê thêm kiosk. Kiểm tra trạng thái shop và kỳ thuê.',
            'Contact, location or bank profile is incomplete' =>
              'Hồ sơ shop thiếu thông tin liên hệ hoặc ngân hàng. Cập nhật hồ sơ trước khi gửi lại.',
            final message => message,
          },
        );
      }
      if (e is ApiError && (e.ambiguous || e.status == 409)) {
        accepted = false;
        if (mounted) await refresh();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() => action(() async {
    if (!form.currentState!.validate() ||
        point == null ||
        !ready ||
        !accepted ||
        totalSlots < 1 ||
        totalSlots > 50) {
      return;
    }
    final current = await readCurrent();
    if (_inProgress(current)) {
      if (mounted) setState(() => application = current);
      return;
    }
    final latest = objectOf(await api.get('/api/kiosk-packages'));
    if (latest['configured'] != true ||
        latest['version'] != pricing?['version'] ||
        latest['annualSlotPrice'] != pricing?['annualSlotPrice']) {
      if (mounted) {
        setState(() {
          pricing = latest;
          accepted = false;
          error = 'Bảng giá đã thay đổi. Kiểm tra tổng phí và xác nhận lại.';
        });
      }
      return;
    }
    final created = objectOf(
      await api.post(
        customer
            ? '/api/member/kiosk-applications'
            : '/api/me/kiosk-applications',
        {
          if (customer)
            for (final entry in customerFields.entries)
              entry.key: entry.value.text.trim(),
          'installationAddress': address.text.trim(),
          'latitude': point!.latitude,
          'longitude': point!.longitude,
          'walkInSlots': walk,
          'preorderSlots': preorder,
          'pricingVersion': pricing!['version'],
        },
      ),
    );
    if (mounted) {
      setState(() {
        application = created;
        accepted = false;
        if (customer) {
          for (final controller in customerFields.values) {
            controller.clear();
          }
        }
      });
    }
  });

  Future<void> pay(Json app) => action(() async {
    final current = await readCurrent();
    if (current?['id'] != app['id'] ||
        current?['status'] != 'AWAITING_PAYMENT') {
      if (mounted) setState(() => application = current);
      throw const ApiError(
        409,
        'Hồ sơ không còn chờ thanh toán. Vui lòng xem trạng thái mới.',
      );
    }
    final payment = objectOf(
      await api.post(
        '/api/member/kiosk-applications/${app['id']}/payment-link',
      ),
    );
    final uri = Uri.tryParse('${payment['checkoutUrl']}');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'pay.payos.vn' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      throw const ApiError(400, 'Liên kết thanh toán PayOS không hợp lệ.');
    }
    await openSafeLink(uri.toString());
  });

  Future<void> reconcile(Json app) => action(() async {
    final updated = objectOf(
      await api.post('/api/member/kiosk-applications/${app['id']}/reconcile'),
    );
    if (mounted) {
      setState(() {
        application = updated;
        notice = 'Đã cập nhật kết quả từ PayOS.';
      });
    }
  });

  Future<void> cancel(Json app) async {
    final reason = await askForm(context, 'Hủy hồ sơ thuê kiosk', [
      const InputSpec('reason', 'Lý do hủy', minLength: 5, lines: 3),
    ], submitLabel: 'Tiếp tục');
    if (reason == null || !mounted) return;
    if (reason['reason']!.length > 500) {
      message(context, 'Lý do tối đa 500 ký tự.');
      return;
    }
    final confirmed = await confirm(
      context,
      'Xác nhận hủy hồ sơ?',
      app['status'] == 'AWAITING_PAYMENT'
          ? 'Hủy hồ sơ thuê kiosk chưa thanh toán.'
          : 'Hồ sơ đã thanh toán sẽ được xử lý hoàn phí theo quy định.',
    );
    if (!confirmed || !mounted) return;
    await action(() async {
      final updated = objectOf(
        await api.post('/api/member/kiosk-applications/${app['id']}/cancel', {
          'reason': reason['reason'],
        }),
      );
      if (mounted) setState(() => application = updated);
    });
  }

  Widget card(List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  Widget title(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: forest,
    ),
  );
  Widget fact(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF617568)),
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, height: 1.45)),
      ],
    ),
  );

  Widget status(Json app) => Text(
    applicationLabels[app['status']] ?? '${app['status']}',
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: ['CANCELLED', 'REJECTED'].contains(app['status'])
          ? const Color(0xFFB42318)
          : ['ACTIVE', 'REFUNDED'].contains(app['status'])
          ? forest
          : const Color(0xFF925B0A),
    ),
  );

  Widget appView(Json app) => card([
    StatusHeading(title: title('Hồ sơ thuê kiosk'), status: status(app)),
    if (customer && app['status'] == 'ACTIVE' && widget.onActivateShop != null)
      FilledButton(
        onPressed: busy ? null : widget.onActivateShop,
        child: const Text('Đăng nhập lại để vào shop'),
      ),
    const SizedBox(height: 12),
    Text(
      money(app['annualFee']),
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: forest,
      ),
    ),
    fact(
      'Số ô',
      '${app['walkInSlots'] ?? 0} bán sẵn · ${app['preorderSlots'] ?? 0} đặt trước',
    ),
    fact('Địa điểm lắp đặt', valueOf(app, 'installationAddress')),
    if (app['scheduledDate'] != null)
      fact(
        'Lịch lắp đặt',
        '${rentalDate(app['scheduledDate'])} · ${valueOf(app, 'timeWindow', '')}',
      ),
    if (app['assignedTechnicianName'] != null)
      fact('Kỹ thuật viên', valueOf(app, 'assignedTechnicianName')),
    if (app['reviewNote'] != null)
      fact('Phản hồi quản lý', valueOf(app, 'reviewNote')),
    if (app['reworkReason'] != null)
      fact('Yêu cầu kiểm tra lại', valueOf(app, 'reworkReason')),
    if (app['technicianReport'] != null)
      fact('Báo cáo lắp đặt', valueOf(app, 'technicianReport')),
    if (app['handoverAt'] != null)
      fact('Đã bàn giao', dateText(app['handoverAt'])),
    if (app['status'] == 'REFUND_PENDING' || app['status'] == 'REFUNDED')
      fact(
        'Tài khoản nhận hoàn',
        '${valueOf(app, 'bankName')} · ${valueOf(app, 'bankHolder')} · ••••${valueOf(app, 'bankAccountSuffix', '')}',
      ),
    if (app['status'] == 'AWAITING_PAYMENT') ...[
      const SizedBox(height: 16),
      FilledButton(
        onPressed: busy ? null : () => pay(app),
        child: const Text('Thanh toán phí thuê'),
      ),
    ],
    if (['AWAITING_PAYMENT', 'CANCELLED', 'REJECTED'].contains(app['status']) &&
        app['paymentId'] != null) ...[
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: busy ? null : () => reconcile(app),
        child: Text(
          app['status'] == 'AWAITING_PAYMENT'
              ? 'Kiểm tra thanh toán'
              : 'Kiểm tra thanh toán muộn',
        ),
      ),
    ],
    if (app['canVoluntaryCancel'] == true) ...[
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: busy ? null : () => cancel(app),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFB42318),
        ),
        child: const Text('Hủy hồ sơ'),
      ),
    ],
  ]);

  Widget counter(String label, int count, ValueChanged<int> update) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Giảm $label',
          onPressed: busy || count == 0 || totalSlots == 1
              ? null
              : () => update(count - 1),
          icon: const Icon(Icons.remove, size: 18),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '$count',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: forest,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Tăng $label',
          onPressed: busy || totalSlots >= 50 ? null : () => update(count + 1),
          icon: const Icon(Icons.add, size: 18),
        ),
      ],
    ),
  );

  void _onAddressChanged(String value) {
    _searchDebounce?.cancel();
    final reqId = ++_searchId;
    _detailId++;
    final trimmed = value.trim();
    setState(() {
      point = null;
      accepted = false;
      _pinnedFromSuggestion = false;
      _resolvingAddress = false;
      _addressSearchError = null;
      _predictions = [];
      _searchEmpty = false;
      _searchingAddress = false;
      _showSuggestions = false;
    });
    if (_places == null || trimmed.length < 3) return;
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted || reqId != _searchId) return;
      setState(() {
        _searchingAddress = true;
        _showSuggestions = true;
      });
      try {
        final result = await _places!.suggestions(trimmed);
        if (!mounted || reqId != _searchId) return;
        setState(() {
          _predictions = result;
          _searchEmpty = result.isEmpty;
        });
      } catch (e) {
        if (!mounted || reqId != _searchId) return;
        setState(() => _addressSearchError = '$e');
      } finally {
        if (mounted && reqId == _searchId) {
          setState(() => _searchingAddress = false);
        }
      }
    });
  }

  void _clearAddress() {
    address.clear();
    _onAddressChanged('');
  }

  Future<void> _chooseSuggestion(Json prediction) async {
    if (_places == null) return;
    _searchDebounce?.cancel();
    _searchId++;
    final reqId = ++_detailId;
    final parsed = parseGoongSuggestion(prediction);
    if (parsed.placeId.isEmpty) return;
    setState(() {
      _showSuggestions = false;
      _predictions = [];
      _searchEmpty = false;
      _searchingAddress = false;
      _resolvingAddress = true;
      _addressSearchError = null;
    });
    try {
      final place = await _places!.detail(parsed.placeId);
      if (!mounted || reqId != _detailId) return;
      final resolved = place.address.isNotEmpty
          ? place.address
          : parsed.description;
      if (resolved.isNotEmpty) {
        address.value = TextEditingValue(
          text: resolved,
          selection: TextSelection.collapsed(offset: resolved.length),
        );
      }
      setState(() {
        point = (latitude: place.latitude, longitude: place.longitude);
        _pinnedFromSuggestion = true;
        accepted = false;
      });
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (!mounted || reqId != _detailId) return;
      setState(() => _addressSearchError = '$e');
    } finally {
      if (mounted && reqId == _detailId) {
        setState(() => _resolvingAddress = false);
      }
    }
  }

  Future<void> _openMapPicker() async {
    _searchDebounce?.cancel();
    _searchId++;
    _detailId++;
    setState(() {
      _showSuggestions = false;
      _searchingAddress = false;
      _resolvingAddress = false;
    });
    FocusScope.of(context).unfocus();
    final selected = widget.locationPicker != null
        ? await widget.locationPicker!(context, point, address.text)
        : await Navigator.push<KioskLocation>(
            context,
            MaterialPageRoute(
              builder: (_) => KioskLocationPicker(
                initial: point,
                initialAddress: address.text,
                placesClient: widget.placesClient,
              ),
            ),
          );
    if (mounted && selected != null) {
      setState(() {
        point = selected.point;
        _pinnedFromSuggestion = false;
        if (selected.address != null && selected.address!.isNotEmpty) {
          address.text = selected.address!;
        }
        accepted = false;
      });
    }
  }

  Widget _locationCard() => card([
    title('Vị trí lắp đặt'),
    const SizedBox(height: 14),
    TextFormField(
      controller: address,
      enabled: !busy,
      maxLength: 200,
      maxLines: 2,
      decoration: InputDecoration(
        label: const Text.rich(
          TextSpan(
            text: 'Địa chỉ lắp đặt',
            children: [
              TextSpan(
                text: ' *',
                style: TextStyle(color: Color(0xFFB42318)),
              ),
            ],
          ),
        ),
        hintText: 'Số nhà, đường, phường/xã, tỉnh/thành',
        counterText: '',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _searchingAddress || _resolvingAddress
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : address.text.isNotEmpty && !busy
            ? IconButton(
                tooltip: 'Xóa địa chỉ',
                onPressed: _clearAddress,
                icon: const Icon(Icons.close_rounded, size: 18),
              )
            : null,
      ),
      onChanged: _onAddressChanged,
      validator: (v) =>
          (v ?? '').trim().isEmpty ? 'Nhập địa chỉ lắp đặt.' : null,
    ),
    if (_showSuggestions)
      GoongSuggestionPanel(
        predictions: _predictions,
        loading: _searchingAddress,
        empty: _searchEmpty,
        error: _addressSearchError,
        onSelect: _chooseSuggestion,
        onManualMap: _openMapPicker,
      ),
    const SizedBox(height: 8),
    const Text(
      'Nhập ít nhất 3 ký tự để chọn địa chỉ gợi ý Goong và ghim tọa độ tự động, hoặc chọn trực tiếp trên bản đồ.',
      style: TextStyle(fontSize: 12, color: Color(0xFF617568), height: 1.45),
    ),
    if (_resolvingAddress) ...[
      const SizedBox(height: 6),
      const Text(
        'Đang xác định vị trí…',
        style: TextStyle(fontSize: 12, color: Color(0xFF617568)),
      ),
    ] else if (!_showSuggestions && _addressSearchError != null) ...[
      const SizedBox(height: 6),
      Text(
        _addressSearchError!,
        style: const TextStyle(fontSize: 12, color: Color(0xFFB42318)),
      ),
    ] else if (point != null && _pinnedFromSuggestion) ...[
      const SizedBox(height: 6),
      const Row(
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: forest),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Đã ghim vị trí tự động từ địa chỉ gợi ý',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: forest,
              ),
            ),
          ),
        ],
      ),
    ],
    const SizedBox(height: 10),
    OutlinedButton.icon(
      onPressed: busy ? null : _openMapPicker,
      icon: Icon(
        point == null ? Icons.location_on_outlined : Icons.check_circle_outline,
        size: 18,
      ),
      label: Text(
        point == null ? 'Chọn vị trí trên bản đồ' : 'Đã ghim vị trí · Chọn lại',
      ),
    ),
  ]);

  Widget _customerCard() => card([
    title('Thông tin shop'),
    for (final entry in const {
      'shopName': 'Tên shop',
      'phone': 'Số điện thoại',
      'contactEmail': 'Email liên hệ',
      'bankName': 'Ngân hàng nhận hoàn phí',
      'bankHolder': 'Chủ tài khoản',
      'bankAccountNumber': 'Số tài khoản',
    }.entries)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextFormField(
          controller: customerFields[entry.key],
          enabled: !busy,
          readOnly: entry.key == 'bankName',
          onTap: entry.key != 'bankName'
              ? null
              : () async {
                  final value = await pickVietnamBank(context);
                  if (mounted && value != null) {
                    customerFields['bankName']!.text = value;
                  }
                },
          keyboardType: ['phone', 'bankAccountNumber'].contains(entry.key)
              ? TextInputType.phone
              : entry.key == 'contactEmail'
              ? TextInputType.emailAddress
              : TextInputType.text,
          decoration: InputDecoration(labelText: entry.value),
          validator: (value) {
            final text = (value ?? '').trim();
            if (text.isEmpty) return 'Nhập ${entry.value.toLowerCase()}.';
            if (entry.key == 'shopName' &&
                (text.length < 2 || text.length > 120)) {
              return 'Tên shop từ 2 đến 120 ký tự.';
            }
            if (entry.key == 'contactEmail' &&
                !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
              return 'Email chưa hợp lệ.';
            }
            if (entry.key == 'phone' &&
                !RegExp(r'^\+?[0-9]{9,15}$').hasMatch(text)) {
              return 'Số điện thoại chưa hợp lệ.';
            }
            if (entry.key == 'bankAccountNumber' &&
                !RegExp(r'^[0-9]{6,30}$').hasMatch(text)) {
              return 'Số tài khoản từ 6 đến 30 chữ số.';
            }
            return null;
          },
        ),
      ),
  ]);

  Widget applicationForm() => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (setupError != null) ...[
          Text('$setupError', style: const TextStyle(color: Color(0xFFB42318))),
          OutlinedButton(
            onPressed: busy ? null : refresh,
            child: const Text('Tải lại hồ sơ shop'),
          ),
        ],
        if (customer)
          _customerCard()
        else
          card([
            title(valueOf(shop ?? {}, 'shopName', widget.session.name)),
            if (bank?['status'] == 'READY')
              fact(
                'Ngân hàng nhận hoàn phí',
                '${valueOf(bank!, 'bankName')} · ${valueOf(bank!, 'holder')} · ••••${valueOf(bank!, 'accountSuffix', '')}',
              )
            else ...[
              const SizedBox(height: 10),
              const Text(
                'Cập nhật ngân hàng nhận hoàn phí trước khi thuê.',
                style: TextStyle(color: Color(0xFFB42318)),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () async {
                        await openPage(
                          context,
                          'Ngân hàng shop',
                          PaymentChannelPage(api, widget.session),
                        );
                        if (mounted) await refresh();
                      },
                child: const Text('Cập nhật ngân hàng shop'),
              ),
            ],
          ]),
        card([
          title('Chọn số ô'),
          const SizedBox(height: 4),
          counter(
            'Ô bán sẵn',
            walk,
            (v) => setState(() {
              walk = v;
              accepted = false;
            }),
          ),
          counter(
            'Ô đặt trước',
            preorder,
            (v) => setState(() {
              preorder = v;
              accepted = false;
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'Tổng $totalSlots ô · ${money(unitPrice)}/ô/năm',
            style: const TextStyle(fontSize: 12, color: Color(0xFF617568)),
          ),
          if (pricing?['configured'] != true)
            const Text(
              'Bảng giá chưa được cấu hình.',
              style: TextStyle(color: Color(0xFFB42318)),
            ),
        ]),
        _locationCard(),
        card([
          const Text(
            'Phí thuê 12 tháng',
            style: TextStyle(fontSize: 12, color: Color(0xFF617568)),
          ),
          const SizedBox(height: 6),
          Text(
            money(unitPrice * totalSlots),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: forest,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Kỳ thuê bắt đầu từ ngày bàn giao.',
            style: TextStyle(fontSize: 12, color: Color(0xFF617568)),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: accepted,
            onChanged: busy || !ready
                ? null
                : (v) => setState(() => accepted = v == true),
            title: const Text(
              'Tôi đã kiểm tra số ô và tổng phí.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          FilledButton(
            onPressed: busy || !ready || !accepted || point == null
                ? null
                : submit,
            child: Text(busy ? 'Đang gửi…' : 'Gửi hồ sơ thuê kiosk'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Thanh toán sau khi gửi hồ sơ.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF617568)),
          ),
        ]),
        if (application != null)
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text(
              'Hồ sơ gần nhất',
              style: TextStyle(fontSize: 14, color: forest),
            ),
            children: [appView(application!)],
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: busy ? () async {} : refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (loadError != null) ...[
            Text(
              '$loadError',
              style: const TextStyle(color: Color(0xFFB42318)),
            ),
            OutlinedButton(onPressed: refresh, child: const Text('Tải lại')),
          ] else if (_inProgress(application) ||
              (customer && application?['status'] == 'ACTIVE'))
            appView(application!)
          else
            applicationForm(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                error!,
                style: const TextStyle(color: Color(0xFFB42318)),
              ),
            ),
          if (notice != null)
            Text(notice!, style: const TextStyle(color: forest)),
        ],
      ),
    );
  }
}

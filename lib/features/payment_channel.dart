import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/team_widgets.dart';
import '../ui/vietnam_bank_picker.dart';

class PaymentChannelPage extends StatefulWidget {
  const PaymentChannelPage(
    this.api,
    this.session, {
    this.startWithTransactions = false,
    super.key,
  });
  final ApiClient api;
  final Session session;
  final bool startWithTransactions;

  @override
  State<PaymentChannelPage> createState() => _PaymentChannelPageState();
}

class _SectionState<T> {
  int epoch = 0;
  bool loading = false;
  bool loaded = false;
  String? error;
  T? data;
}

class _BadgeStyle {
  const _BadgeStyle(this.label, this.bg, this.fg);
  final String label;
  final Color bg;
  final Color fg;
}

class _PaymentChannelPageState extends State<PaymentChannelPage>
    with WidgetsBindingObserver {
  int _segment = 0;
  int _page = 1;
  String _statusFilter = '';
  bool _busy = false;
  bool _transactionsLoaded = false;
  String? _reconcilingId;
  int _paymentsEpoch = 0;

  final _channel = _SectionState<Json?>();
  final _bank = _SectionState<Json>();
  final _report = _SectionState<Json>();
  final _payments = _SectionState<Json>();

  String? get _sellerId => widget.session.sellerId;
  String get _base => '/api/sellers/$_sellerId';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _segment = widget.startWithTransactions ? 1 : 0;
    if (_sellerId != null) {
      unawaited(_refreshActive());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        !_busy &&
        _sellerId != null &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      unawaited(_refreshActive());
    }
  }

  Future<void> _refreshActive() =>
      _segment == 0 ? _loadOverview() : _loadTransactions();

  Future<void> _loadOverview() => Future.wait([_loadChannel(), _loadBank()]);

  Future<void> _loadTransactions() {
    _transactionsLoaded = true;
    return Future.wait([_loadReport(), _loadPayments()]);
  }

  Future<void> _loadChannel() async {
    if (_sellerId == null) return;
    final epoch = ++_channel.epoch;
    setState(() {
      _channel.loading = true;
      _channel.error = null;
    });
    try {
      Json? item;
      try {
        item = objectOf(await widget.api.get('$_base/payment-channel'));
      } on ApiError catch (e) {
        if (e.status != 404) rethrow;
      }
      if (!mounted || epoch != _channel.epoch) return;
      setState(() {
        _channel.data = item;
        _channel.loaded = true;
      });
    } catch (e) {
      if (!mounted || epoch != _channel.epoch) return;
      setState(() => _channel.error = '$e');
    } finally {
      if (mounted && epoch == _channel.epoch) {
        setState(() => _channel.loading = false);
      }
    }
  }

  Future<void> _loadBank() async {
    if (_sellerId == null) return;
    final epoch = ++_bank.epoch;
    setState(() {
      _bank.loading = true;
      _bank.error = null;
    });
    try {
      final result = objectOf(await widget.api.get('$_base/bank'));
      if (!mounted || epoch != _bank.epoch) return;
      setState(() {
        _bank.data = result;
        _bank.loaded = true;
      });
    } catch (e) {
      if (!mounted || epoch != _bank.epoch) return;
      setState(() => _bank.error = '$e');
    } finally {
      if (mounted && epoch == _bank.epoch) {
        setState(() => _bank.loading = false);
      }
    }
  }

  Future<void> _loadReport() async {
    if (_sellerId == null) return;
    final epoch = ++_report.epoch;
    setState(() {
      _report.loading = true;
      _report.error = null;
    });
    try {
      final result = objectOf(await widget.api.get('$_base/reports/sales'));
      if (!mounted || epoch != _report.epoch) return;
      setState(() {
        _report.data = result;
        _report.loaded = true;
      });
    } catch (e) {
      if (!mounted || epoch != _report.epoch) return;
      setState(() => _report.error = '$e');
    } finally {
      if (mounted && epoch == _report.epoch) {
        setState(() => _report.loading = false);
      }
    }
  }

  Future<void> _loadPayments() async {
    if (_sellerId == null) return;
    final epoch = ++_paymentsEpoch;
    setState(() {
      _payments.loading = true;
      _payments.error = null;
    });
    final filterQuery = _statusFilter.isEmpty
        ? ''
        : '&status=${Uri.encodeQueryComponent(_statusFilter)}';
    try {
      final result = objectOf(
        await widget.api.get(
          '$_base/payments?page=$_page&pageSize=10$filterQuery',
        ),
      );
      if (!mounted || epoch != _paymentsEpoch) return;
      setState(() {
        _payments.data = result;
        _payments.loaded = true;
      });
    } catch (e) {
      if (!mounted || epoch != _paymentsEpoch) return;
      setState(() => _payments.error = '$e');
    } finally {
      if (mounted && epoch == _paymentsEpoch) {
        setState(() => _payments.loading = false);
      }
    }
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) message(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyChannel() => _runBusy(() async {
    final result = objectOf(
      await widget.api.post('$_base/payment-channel/verify'),
    );
    if (!mounted) return;
    message(context, valueOf(result, 'message', 'Đã kiểm tra xác thực kênh.'));
    await _loadChannel();
  });

  Future<void> _changeChannelStatus(String nextStatus) => _runBusy(() async {
    final pausing = nextStatus == 'PAUSED';
    final ok = await confirm(
      context,
      pausing ? 'Tạm dừng kênh thanh toán?' : 'Mở lại kênh thanh toán?',
      pausing
          ? 'Tạm dừng nhận thanh toán mới qua kênh PayOS này.'
          : 'Bật lại nhận thanh toán qua kênh PayOS đã xác minh.',
    );
    if (!ok || !mounted) return;
    await widget.api.request(
      'PATCH',
      '$_base/payment-channel/status',
      body: {'status': nextStatus},
    );
    if (!mounted) return;
    message(
      context,
      pausing ? 'Đã tạm dừng kênh thanh toán.' : 'Đã mở lại kênh thanh toán.',
    );
    await _loadChannel();
  });

  Future<void> _openBankSheet(Json bankData) async {
    final sellerId = _sellerId;
    if (sellerId == null || _busy) return;
    final status = '${bankData['status'] ?? ''}';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _BankFormSheet(
        api: widget.api,
        sellerId: sellerId,
        initialBankName: bankData['bankName']?.toString() ?? '',
        initialHolder: bankData['holder']?.toString() ?? '',
        isUpdate: status == 'READY' || status == 'NEEDS_UPDATE',
      ),
    );
    if (saved == true && mounted) {
      await _loadBank();
      if (!mounted) return;
      final refreshedStatus = _bank.data?['status']?.toString();
      message(
        context,
        refreshedStatus == 'READY'
            ? 'Đã lưu tài khoản ngân hàng nhận hoàn phí.'
            : 'Đã gửi thông tin ngân hàng. Hãy kéo xuống để kiểm tra trạng thái mới nhất.',
      );
    }
  }

  Future<void> _reconcilePayment(String paymentId) async {
    if (_busy || _reconcilingId != null) return;
    setState(() => _reconcilingId = paymentId);
    try {
      final result = objectOf(
        await widget.api.post('$_base/payments/$paymentId/reconcile'),
      );
      if (!mounted) return;
      message(
        context,
        result['transitioned'] == true
            ? 'Giao dịch đã cập nhật thành Đã thanh toán.'
            : 'Đã tra cứu PayOS: trạng thái ${valueOf(result, 'providerStatus', 'chưa đổi')}.',
      );
      await Future.wait([_loadPayments(), _loadReport()]);
    } catch (e) {
      if (mounted) message(context, '$e');
    } finally {
      if (mounted) setState(() => _reconcilingId = null);
    }
  }

  bool get _anyLoading =>
      _busy ||
      _channel.loading ||
      _bank.loading ||
      _report.loading ||
      _payments.loading;

  @override
  Widget build(BuildContext context) {
    if (_sellerId == null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          InfoBox('Tài khoản chưa liên kết với shop.', warning: true),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshActive,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_anyLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(),
            ),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(value: 0, label: Text('Kênh & tài khoản')),
              ButtonSegment<int>(value: 1, label: Text('Giao dịch')),
            ],
            selected: {_segment},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: const Color(0xFFE3EEDC),
              selectedForegroundColor: forest,
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFD4E0D4)),
            ),
            onSelectionChanged: (selection) {
              final next = selection.first;
              if (next == _segment) return;
              setState(() => _segment = next);
              if (next == 0 &&
                  (!_channel.loaded || !_bank.loaded) &&
                  !_channel.loading &&
                  !_bank.loading) {
                unawaited(_loadOverview());
              }
              if (next == 1 &&
                  !_transactionsLoaded &&
                  !_report.loading &&
                  !_payments.loading) {
                unawaited(_loadTransactions());
              }
            },
          ),
          const SizedBox(height: 16),
          if (_segment == 0) ...[
            _buildPayOsCard(),
            _buildBankCard(),
          ] else ...[
            _buildReportCard(),
            _buildPaymentsCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildPayOsCard() {
    final ch = _channel.data;
    final state = ch?['state']?.toString() ?? '';
    return _PanelCard(
      title: 'Kênh nhận tiền PayOS',
      subtitle: 'Nhận tiền bán hoa từ khách mua tại tủ và đặt trước.',
      badge: _channel.loaded && _channel.error == null
          ? _StatusPill(_channelBadge(ch))
          : null,
      loading: _channel.loading && !_channel.loaded,
      error: _channel.error,
      onRetry: _loadChannel,
      child: ch == null
          ? const InfoBox(
              'Chưa có kênh PayOS của shop. Quản trị viên gắn cấu hình kênh payOS trước khi shop xác thực và nhận thanh toán.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamFact(
                  'Chủ tài khoản',
                  valueOf(ch, 'expectedBankName', 'Chưa cập nhật'),
                ),
                TeamFact(
                  'Số tài khoản',
                  valueOf(ch, 'expectedBankAccountMasked', 'Chưa cập nhật'),
                ),
                if (ch['verifiedAt'] != null)
                  TeamFact('Xác thực lúc', dateText(ch['verifiedAt'])),
                if (state != 'ACTIVE') ...[
                  const SizedBox(height: 4),
                  const InfoBox(
                    'Shop chưa thể nhận thanh toán đơn hoa mới. Quản trị viên gắn cấu hình kênh payOS và shop cần xác thực để kích hoạt.',
                    warning: true,
                  ),
                ],
                const SizedBox(height: 8),
                if (state == 'PENDING_VERIFICATION')
                  FilledButton.icon(
                    onPressed: _busy ? null : _verifyChannel,
                    icon: const Icon(Icons.verified_user_outlined, size: 19),
                    label: const Text('Kiểm tra xác thực PayOS'),
                  )
                else if (state == 'ACTIVE')
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB42318),
                    ),
                    onPressed: _busy
                        ? null
                        : () => _changeChannelStatus('PAUSED'),
                    icon: const Icon(Icons.pause_circle_outline, size: 19),
                    label: const Text('Tạm dừng nhận thanh toán'),
                  )
                else if (state == 'PAUSED' && ch['verifiedAt'] != null)
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _changeChannelStatus('ACTIVE'),
                    icon: const Icon(Icons.play_circle_outline, size: 19),
                    label: const Text('Mở lại kênh thanh toán'),
                  )
                else if (state == 'PAUSED')
                  const Text(
                    'Kênh chưa được xác thực trước khi tạm dừng nên chưa thể mở lại.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF617568),
                      height: 1.45,
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildBankCard() {
    final data = _bank.data ?? const <String, dynamic>{};
    final status = data['status']?.toString() ?? '';
    final ready = status == 'READY';
    final needsUpdate = status == 'NEEDS_UPDATE';

    return _PanelCard(
      title: 'Ngân hàng nhận hoàn phí',
      subtitle:
          'Nhận hoàn phí thuê kiosk từ hệ thống (độc lập với kênh PayOS).',
      badge: _bank.loaded && _bank.error == null && _bank.data != null
          ? _StatusPill(_bankBadge(status))
          : null,
      loading: _bank.loading && !_bank.loaded,
      error: _bank.error,
      onRetry: _loadBank,
      child: ready
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamFact(
                  'Tên ngân hàng',
                  valueOf(data, 'bankName', 'Chưa cập nhật'),
                ),
                TeamFact(
                  'Chủ tài khoản',
                  valueOf(data, 'holder', 'Chưa cập nhật'),
                ),
                TeamFact(
                  'Số tài khoản',
                  '•••• •••• •••• ${valueOf(data, 'accountSuffix', '••••')}',
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _openBankSheet(data),
                  icon: const Icon(Icons.edit_outlined, size: 19),
                  label: const Text('Thay đổi tài khoản'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InfoBox(
                  needsUpdate
                      ? 'Không đọc được số tài khoản đã lưu. Vui lòng nhập lại để cập nhật.'
                      : 'Shop chưa khai báo tài khoản ngân hàng nhận hoàn phí thuê kiosk.',
                  warning: true,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _openBankSheet(data),
                  icon: const Icon(Icons.account_balance_outlined, size: 19),
                  label: Text(
                    needsUpdate ? 'Cập nhật tài khoản' : 'Khai báo tài khoản',
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildReportCard() {
    final data = _report.data ?? const <String, dynamic>{};
    return _PanelCard(
      title: 'Doanh thu bán hoa',
      subtitle: 'Tổng hợp các giao dịch thanh toán qua PayOS.',
      loading: _report.loading && !_report.loaded,
      error: _report.error,
      onRetry: _loadReport,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  'Đã thanh toán',
                  money(data['grossPaid'] ?? 0),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  'Đã hoàn',
                  money(data['totalRefunded'] ?? 0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  'Sau hoàn tiền',
                  money(data['netReceipts'] ?? 0),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile('Đơn đã trả', '${data['paidOrders'] ?? 0}'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsCard() {
    final data = _payments.data;
    final rawList = data?['payments'];
    final rows = rawList is List ? rawList.map(objectOf).toList() : <Json>[];
    final totalCount = (data?['totalCount'] as num?)?.toInt() ?? rows.length;

    return _PanelCard(
      title: 'Giao dịch bán hoa',
      subtitle: 'Danh sách giao dịch và đối soát PayOS.',
      badge: PopupMenuButton<String>(
        tooltip: 'Lọc trạng thái giao dịch',
        initialValue: _statusFilter,
        onSelected: (value) {
          setState(() {
            _statusFilter = value;
            _page = 1;
          });
          unawaited(_loadPayments());
        },
        icon: Icon(
          _statusFilter.isEmpty
              ? Icons.filter_list_rounded
              : Icons.filter_alt_rounded,
          color: forest,
        ),
        itemBuilder: (_) => [
          for (final entry in _paymentFilterOptions.entries)
            CheckedPopupMenuItem<String>(
              value: entry.key,
              checked: _statusFilter == entry.key,
              child: Text(entry.value),
            ),
        ],
      ),
      loading: _payments.loading && !_payments.loaded,
      error: _payments.error,
      onRetry: _loadPayments,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Chưa có giao dịch bán hoa phù hợp.',
                  style: TextStyle(color: Color(0xFF617568)),
                ),
              ),
            )
          else
            for (final payment in rows) _buildPaymentItem(payment),
          if (_page > 1 || totalCount > 10)
            TeamPaging(
              page: _page,
              more: _page * 10 < totalCount,
              busy: _payments.loading,
              onPage: (next) {
                setState(() => _page = next);
                unawaited(_loadPayments());
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPaymentItem(Json payment) {
    final id = '${payment['id'] ?? ''}';
    final status = '${payment['status'] ?? ''}';
    final orderCode = payment['orderCode'];
    final title = orderCode != null
        ? 'Đơn #$orderCode'
        : 'GD #${id.substring(0, math.min(8, id.length))}';
    final receiverMasked = payment['receiverAccountMasked']?.toString() ?? '';
    final isReconciling = _reconcilingId == id;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBF9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5ECE2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: _StatusPill(_paymentBadge(status))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                money(payment['amount'] ?? 0),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: forest,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dateText(payment['paidAt'] ?? payment['createdAt']),
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF617568),
                  ),
                ),
              ),
            ],
          ),
          if (receiverMasked.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'TK nhận: $receiverMasked',
              style: const TextStyle(fontSize: 12, color: Color(0xFF617568)),
            ),
          ],
          if (status == 'PENDING') ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy || _reconcilingId != null
                  ? null
                  : () => _reconcilePayment(id),
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: Text(isReconciling ? 'Đang đối soát…' : 'Đối soát PayOS'),
            ),
          ],
        ],
      ),
    );
  }
}

const _paymentFilterOptions = {
  '': 'Tất cả',
  'SUCCEEDED': 'Đã thanh toán',
  'PENDING': 'Chờ thanh toán',
  'FAILED': 'Thanh toán thất bại',
  'EXPIRED': 'Hết hạn',
  'CANCELLED': 'Đã hủy',
  'REFUNDED': 'Đã hoàn tiền',
};

_BadgeStyle _channelBadge(Json? ch) {
  if (ch == null) {
    return const _BadgeStyle(
      'Chưa cấu hình',
      Color(0xFFEEF2EE),
      Color(0xFF526458),
    );
  }
  final state = '${ch['state'] ?? ''}';
  return switch (state) {
    'ACTIVE' => const _BadgeStyle('Đã kích hoạt', Color(0xFFE9F5EC), forest),
    'PENDING_VERIFICATION' => const _BadgeStyle(
      'Chờ xác thực',
      Color(0xFFFFF4DE),
      Color(0xFF9A6700),
    ),
    'PAUSED' => const _BadgeStyle(
      'Tạm dừng',
      Color(0xFFFEECEB),
      Color(0xFFB42318),
    ),
    _ => _BadgeStyle(
      statusText(state),
      const Color(0xFFEEF2EE),
      const Color(0xFF526458),
    ),
  };
}

_BadgeStyle _bankBadge(String status) => switch (status) {
  'READY' => const _BadgeStyle('Đã sẵn sàng', Color(0xFFE9F5EC), forest),
  'MISSING' => const _BadgeStyle(
    'Chưa khai báo',
    Color(0xFFFFF4DE),
    Color(0xFF9A6700),
  ),
  'NEEDS_UPDATE' => const _BadgeStyle(
    'Cần cập nhật',
    Color(0xFFFFF4DE),
    Color(0xFF9A6700),
  ),
  _ => _BadgeStyle(
    statusText(status),
    const Color(0xFFEEF2EE),
    const Color(0xFF526458),
  ),
};

_BadgeStyle _paymentBadge(String status) => switch (status) {
  'PAID' ||
  'SUCCEEDED' => const _BadgeStyle('Đã thanh toán', Color(0xFFE9F5EC), forest),
  'PENDING' => const _BadgeStyle(
    'Chờ thanh toán',
    Color(0xFFFFF4DE),
    Color(0xFF9A6700),
  ),
  'CANCELLED' || 'CANCELED' => const _BadgeStyle(
    'Đã hủy',
    Color(0xFFEEF2EE),
    Color(0xFF526458),
  ),
  'FAILED' => const _BadgeStyle(
    'Thanh toán thất bại',
    Color(0xFFFEECEB),
    Color(0xFFB42318),
  ),
  'EXPIRED' => const _BadgeStyle(
    'Hết hạn',
    Color(0xFFEEF2EE),
    Color(0xFF526458),
  ),
  'REFUNDED' => const _BadgeStyle(
    'Đã hoàn tiền',
    Color(0xFFEFF4FF),
    Color(0xFF175CD3),
  ),
  _ => _BadgeStyle(
    statusText(status),
    const Color(0xFFEEF2EE),
    const Color(0xFF526458),
  ),
};

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.title,
    this.subtitle,
    this.badge,
    this.loading = false,
    this.error,
    this.onRetry,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? badge;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: forest,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF617568),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (badge != null) ...[const SizedBox(width: 8), badge!],
            ],
          ),
          const SizedBox(height: 14),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  error!,
                  style: const TextStyle(
                    color: Color(0xFFB42318),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Tải lại'),
                    ),
                  ),
                ],
              ],
            )
          else
            child,
        ],
      ),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.style);
  final _BadgeStyle style;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: style.bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      style.label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: style.fg,
      ),
    ),
  );
}

class _MetricTile extends StatelessWidget {
  const _MetricTile(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF6F9F5),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE0E8DC)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF617568)),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: forest,
          ),
        ),
      ],
    ),
  );
}

class _BankFormSheet extends StatefulWidget {
  const _BankFormSheet({
    required this.api,
    required this.sellerId,
    required this.initialBankName,
    required this.initialHolder,
    required this.isUpdate,
  });

  final ApiClient api;
  final String sellerId;
  final String initialBankName;
  final String initialHolder;
  final bool isUpdate;

  @override
  State<_BankFormSheet> createState() => _BankFormSheetState();
}

class _BankFormSheetState extends State<_BankFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _bankCtrl = TextEditingController(
    text: widget.initialBankName,
  );
  late final TextEditingController _holderCtrl = TextEditingController(
    text: widget.initialHolder,
  );
  final TextEditingController _accountCtrl = TextEditingController();
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _bankCtrl.dispose();
    _holderCtrl.dispose();
    _accountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final bank = _bankCtrl.text.trim();
    final holder = _holderCtrl.text.trim().toUpperCase();
    final account = _accountCtrl.text.trim();
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await widget.api.post(
        '/api/sellers/${widget.sellerId}/flows/set_seller_bank',
        {'p_bank': bank, 'p_holder': holder, 'p_account_enc': account},
      );
      _accountCtrl.clear();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitError = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.isUpdate
                        ? 'Cập nhật ngân hàng nhận hoàn phí'
                        : 'Khai báo ngân hàng nhận hoàn phí',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: forest,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng',
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Dùng khi hệ thống hoàn phí thuê kiosk cho shop.',
              style: TextStyle(fontSize: 13, color: Color(0xFF617568)),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bankCtrl,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Tên ngân hàng *',
                hintText: 'Chọn ngân hàng',
                suffixIcon: Icon(Icons.arrow_drop_down),
              ),
              onTap: _submitting
                  ? null
                  : () async {
                      final picked = await pickVietnamBank(context);
                      if (mounted && picked != null) {
                        _bankCtrl.text = picked;
                      }
                    },
              validator: (v) {
                final text = (v ?? '').trim();
                if (text.length < 2) {
                  return 'Vui lòng chọn tên ngân hàng (từ 2 ký tự trở lên).';
                }
                if (text.length > 120) {
                  return 'Tên ngân hàng không được quá 120 ký tự.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _holderCtrl,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.characters,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Tên chủ tài khoản *',
                hintText: 'Ví dụ: NGUYEN VAN A',
                counterText: '',
              ),
              validator: (v) {
                final text = (v ?? '').trim();
                if (text.length < 2) {
                  return 'Vui lòng nhập tên chủ tài khoản (từ 2 ký tự trở lên).';
                }
                if (text.length > 120) {
                  return 'Tên chủ tài khoản không được quá 120 ký tự.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _accountCtrl,
              enabled: !_submitting,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 34,
              decoration: const InputDecoration(
                labelText: 'Số tài khoản ngân hàng *',
                hintText: '4–34 chữ số hoặc chữ cái, không khoảng trắng',
                counterText: '',
              ),
              validator: (v) {
                final text = (v ?? '').trim();
                if (text.isEmpty) {
                  return 'Vui lòng nhập số tài khoản ngân hàng.';
                }
                if (!RegExp(r'^[A-Za-z0-9]{4,34}$').hasMatch(text)) {
                  return 'Số tài khoản gồm 4–34 chữ cái hoặc chữ số, không khoảng trắng.';
                }
                return null;
              },
            ),
            if (_submitError != null) ...[
              const SizedBox(height: 12),
              Text(
                _submitError!,
                style: const TextStyle(color: Color(0xFFB42318), fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Đang lưu…' : 'Lưu tài khoản'),
            ),
          ],
        ),
      ),
    ),
  );
}

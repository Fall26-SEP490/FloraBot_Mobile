export 'repair_approvals.dart' show RepairApprovalsPage;
export 'seller_staff.dart' show StaffManagementPage;
import '../ui/product_detail.dart';
import 'dart:async';
import '../core/slot_labels.dart';
import '../ui/inventory_widgets.dart';
import '../ui/catalog_widgets.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';
import 'repair_approvals.dart' show repairApprovalActive;

export 'inventory_lists.dart' show KiosksPage, SlotsPage;

int integerInput(String? value, {bool positive = true}) {
  final number = int.tryParse(value ?? '');
  if (number == null || (positive ? number <= 0 : number < 0)) {
    throw const ApiError(400, 'Nhập số nguyên hợp lệ.');
  }
  return number;
}

double dimensionInput(String? value) {
  final number = double.tryParse(value ?? '');
  if (number == null || !number.isFinite || number <= 0) {
    throw const ApiError(400, 'Kích thước phải lớn hơn 0.');
  }
  return number;
}

Future<T?> openPage<T>(BuildContext context, String title, Widget child) =>
    Navigator.push<T>(
      context,
      MaterialPageRoute<T>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: child,
        ),
      ),
    );

class SlotDetail extends StatefulWidget {
  const SlotDetail(
    this.api,
    this.session,
    this.kiosk,
    this.slot, {
    this.pickEvidence,
    super.key,
  });
  final ApiClient api;
  final Session session;
  final Json kiosk, slot;
  final Future<XFile?> Function(BuildContext)? pickEvidence;
  @override
  State<SlotDetail> createState() => _SlotDetailState();
}

class _SlotDetailState extends State<SlotDetail> {
  final resourceKey = GlobalKey<ResourceViewState>();
  Timer? poll;
  Timer? repairTimer;
  bool activeSession = false;
  bool selfService = true;
  bool deviceFaultReported = false;
  bool repairApproveBlocked = false;
  bool _repairRefreshing = false;
  bool _repairPollingNeeded = false;
  int _repairEpoch = 0;
  List<Json> _repairRows = [];
  Object? _repairError;
  @override
  void initState() {
    super.initState();
    poll = Timer.periodic(const Duration(seconds: 3), (_) {
      final state = resourceKey.currentState;
      if (mounted &&
          activeSession &&
          state != null &&
          !state.busy &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        unawaited(state.reload(background: true));
      }
    });
    repairTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final state = resourceKey.currentState;
      if (!mounted ||
          state == null ||
          state.busy ||
          _repairRefreshing ||
          !_repairPollingNeeded ||
          widget.session.role != AppRole.seller ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
          !(ModalRoute.of(context)?.isCurrent ?? false)) {
        return;
      }
      _repairRefreshing = true;
      unawaited(
        _refreshRepairs().whenComplete(() => _repairRefreshing = false),
      );
    });
  }

  @override
  void dispose() {
    poll?.cancel();
    repairTimer?.cancel();
    super.dispose();
  }

  String? pendingSessionId;
  Future<void> _refreshRepairs({bool notify = true}) async {
    final epoch = ++_repairEpoch;
    List<Json> rows = [];
    Object? error;
    try {
      rows = itemsOf(await widget.api.get('/api/me/technical-repairs'));
    } catch (e) {
      error = e;
    }
    if (!mounted || epoch != _repairEpoch) return;
    void update() {
      _repairRows = rows;
      _repairError = error;
    }

    if (notify) {
      setState(update);
    } else {
      update();
    }
  }

  String get kioskId => '${widget.kiosk['id']}';
  String get slotId => '${widget.slot['id']}';
  String get base =>
      '/api/me/kiosks/$kioskId/slots/$slotId/maintenance-sessions';
  Future<Json> load() async {
    final slots = itemsOf(
      await widget.api.get('/api/me/kiosks/$kioskId/slots'),
    );
    final slot = slots.firstWhere(
      (s) => s['id'] == slotId,
      orElse: () => throw const ApiError(404, 'Ô không còn trong kiosk này.'),
    );
    Json? current;
    if (slot['sensorEnabled'] == true && slot['zone'] == 'WALK_IN') {
      try {
        final active = await widget.api.get('$base/active');
        current = active == null ? null : objectOf(active);
      } on ApiError catch (e) {
        if (e.status != 404) rethrow;
      }
    }
    activeSession =
        current != null &&
        ![
          'Completed',
          'Recovered',
          'SessionExpired',
        ].contains(current['stage']);
    if (!activeSession) pendingSessionId = null;
    final products = itemsOf(await widget.api.get('/api/me/products'));
    final kiosks = itemsOf(
      await widget.api.get('/api/sellers/${widget.session.sellerId}/kiosks'),
    );
    final kiosk =
        kiosks.where((row) => '${row['id']}' == kioskId).firstOrNull ??
        widget.kiosk;
    _repairPollingNeeded =
        widget.session.role == AppRole.seller &&
        (slot['status'] == 'FAULT' || deviceFaultReported);
    if (_repairPollingNeeded) await _refreshRepairs(notify: false);
    return {
      'slot': slot,
      'current': current,
      'products': products,
      'kiosk': kiosk,
      'repairs': _repairRows,
      'repairsError': _repairError,
    };
  }

  Future<void> issue(
    ResourceViewState state,
    Json slot,
    Json? current,
    List<Json> products,
    String operation, {
    String? action,
    Map<String, String>? formValues,
  }) => state.run(() async {
    final kiosks = itemsOf(
      await widget.api.get('/api/sellers/${widget.session.sellerId}/kiosks'),
    );
    final kiosk = kiosks.where((row) => '${row['id']}' == kioskId).firstOrNull;
    if (kiosk?['status'] != 'ONLINE') {
      throw const ApiError(409, 'Kiosk chưa trực tuyến. Chờ kết nối để mở ô.');
    }
    if (operation == 'START' && slotOrderBlocked(slot)) {
      throw const ApiError(
        409,
        'Ô đang liên quan đến đơn hàng. Chưa thể nạp, thu hồi hoặc thay hoa.',
      );
    }
    if (!mounted) return;
    String reason = 'Thao tác hoa tại kiosk từ ứng dụng di động';
    String? productId;
    if (operation == 'START') {
      final needsProduct = action == 'LOAD' || action == 'REPLACE';
      final form =
          formValues ??
          await askForm(
            context,
            action == 'LOAD'
                ? 'Nạp hoa'
                : action == 'REMOVE'
                ? 'Thu hồi hoa'
                : 'Thay hoa',
            [
              if (needsProduct)
                InputSpec(
                  'productId',
                  'Mẫu hoa',
                  choices: {
                    for (final p in products.where(
                      (p) =>
                          p['status'] == 'ACTIVE' &&
                          (p['quantity'] as num? ?? 0) > 0,
                    ))
                      '${p['id']}': '${p['name']} (còn ${p['quantity']})',
                  },
                ),
              const InputSpec(
                'reason',
                'Lý do / ghi chú',
                minLength: 5,
                lines: 3,
              ),
            ],
            submitLabel: 'Mở ô',
          );
      if (form == null) return;
      reason = form['reason']!;
      productId = form['productId'];
    } else {
      final form = await askForm(context, 'Mở ô để tiếp tục', [
        const InputSpec('reason', 'Lý do', minLength: 5, lines: 3),
      ]);
      if (form == null) return;
      reason = form['reason']!;
    }
    pendingSessionId ??= const Uuid().v4();
    await widget.api.post('/api/me/maintenance-open', {
      'kioskId': kioskId,
      'slotId': slotId,
      'operation': operation,
      'sessionId': current?['id'] ?? pendingSessionId,
      'action': action ?? current?['action'],
      'expectedBouquetId': slot['bouquetId'],
      'productId': productId ?? current?['newProductId'],
      'reason': reason,
      if (operation == 'RETRY') 'requestId': const Uuid().v4(),
    });
    if (mounted) message(context, 'Đã gửi yêu cầu mở ô. Chờ tủ phản hồi.');
  });
  @override
  Widget build(BuildContext context) => ResourceView(
    key: resourceKey,
    title: 'Ô ${widget.slot['slotCode']}',
    load: load,
    builder: (context, data, state) {
      final payload = objectOf(data), slot = objectOf(payload['slot']);
      final current = payload['current'] as Json?;
      final kiosk = objectOf(payload['kiosk']);
      final online = kiosk['status'] == 'ONLINE';
      final held = slotOrderBlocked(slot);
      final products = (payload['products'] as List).map(objectOf).toList();
      final actions = (current?['availableActions'] as List? ?? [])
          .cast<String>();
      final now = DateTime.now();
      final matchingRepairs = _repairRows
          .where((r) => r['slotId'] == slotId && r['kioskId'] == kioskId)
          .toList();
      final repairsError = _repairError;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  valueOf(kiosk, 'name', 'Kiosk'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF617267),
                  ),
                ),
              ),
              InventoryStatus(valueOf(kiosk, 'status')),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDDE6DF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        slotZoneLabel(slot['zone']),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF617267),
                        ),
                      ),
                    ),
                    InventoryStatus(slotStateLabel(slot)),
                  ],
                ),
                if (slot['productId'] != null &&
                    (slot['bouquetId'] != null || slot['qrCode'] != null)) ...[
                  const SizedBox(height: 14),
                  SlotBouquetPhoto(
                    widget.api,
                    '${slot['productId']}',
                    products: products,
                    price: slot['priceSnapshot'],
                  ),
                ],
                const SizedBox(height: 12),
                if (slot['bouquetId'] != null || slot['qrCode'] != null)
                  InventoryField(
                    'Hạn bán',
                    slot['sellableUntil'] == null ||
                            '${slot['sellableUntil']}'.startsWith('9999')
                        ? 'Không giới hạn'
                        : dateText(slot['sellableUntil']),
                  ),
                if (slot['orderCode'] != null)
                  InventoryField('Đơn hàng', '${slot['orderCode']}'),
                InventoryField(
                  'Cảm biến',
                  slot['sensorEnabled'] != true
                      ? 'Không sử dụng'
                      : slot['sensorReady'] == true
                      ? 'Đã sẵn sàng'
                      : 'Chưa sẵn sàng',
                ),
                if (slot['qrCode'] != null)
                  ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Mã bó hoa',
                      style: TextStyle(fontSize: 12, color: Color(0xFF617267)),
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SelectableText(
                            '${slot['qrCode']}',
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: forest,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (slot['zone'] == 'WALK_IN') ...[
            Row(
              children: [
                Expanded(
                  child: _SlotModeTab(
                    label: 'Tự thực hiện',
                    icon: Icons.pan_tool_outlined,
                    selected: selfService,
                    onTap: state.busy
                        ? null
                        : () => setState(() => selfService = true),
                  ),
                ),
                Expanded(
                  child: _SlotModeTab(
                    label: 'Giao nhân viên',
                    icon: Icons.person_outline,
                    selected: !selfService,
                    onTap: state.busy
                        ? null
                        : () => setState(() => selfService = false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (held)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Ô đang được giữ hoặc chờ khách nhận hoa. Chưa thể thao tác.',
                  style: TextStyle(color: Color(0xFF925B0A), height: 1.6),
                ),
              ),
          ] else
            const Text(
              'Nạp hoa đặt trước trong chi tiết đơn đã thanh toán.',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Color(0xFF617267),
              ),
            ),
          if (selfService &&
              online &&
              !held &&
              !activeSession &&
              slot['zone'] == 'WALK_IN' &&
              (slot['sensorEnabled'] != true || slot['sensorReady'] != true))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Cảm biến chưa sẵn sàng để mở ô. Cần kiểm tra trước khi nạp hoặc thay hoa.',
                style: TextStyle(color: Color(0xFFB42318), height: 1.6),
              ),
            ),
          if (current != null && selfService) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                current['stage'] == 'Completed' ||
                        current['stage'] == 'Recovered'
                    ? 'Hệ thống đã xác nhận kết quả và cập nhật ô.'
                    : current['stage'] == 'SessionExpired'
                    ? 'Phiên đã hết hạn. Liên hệ đội vận hành để kiểm tra trạng thái thực tế.'
                    : current['action'] == 'REPLACE' &&
                          current['substate'] == 'RemovalClosedEmptyConfirmed'
                    ? 'Đã lấy hoa cũ và xác nhận ô trống. Chọn Mở cửa nạp hoa mới để đặt bó mới vào ô.'
                    : current['action'] == 'LOAD' ||
                          current['stage'] == 'AwaitLoading'
                    ? 'Chờ cửa mở thực tế, đặt bó hoa đã chọn vào ô rồi đóng cửa. Hệ thống tự xác nhận cảm biến.'
                    : 'Chờ cửa mở thực tế, lấy hoa cũ ra rồi đóng cửa. Hệ thống tự xác nhận ô trống.',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: forest,
                ),
              ),
            ),

            RecordCard(
              title:
                  const {
                    'LOAD': 'Nạp hoa',
                    'REMOVE': 'Thu hồi hoa',
                    'REPLACE': 'Thay hoa',
                  }[current['action']] ??
                  'Thao tác tại tủ',
              subtitle: 'Hết hạn: ${dateText(current['expiresAt'])}',
              status: current['stage'],
            ),
            if (current['inspectionReason'] != null)
              Text(
                'Cần xử lý: ${current['inspectionReason']}',
                style: const TextStyle(color: Color(0xFFB42318), height: 1.6),
              ),
            OutlinedButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      await widget.api.post('$base/${current['id']}/check');
                    }),
              child: const Text('Kiểm tra tiến độ'),
            ),
            if (actions.contains('open-next'))
              FilledButton(
                onPressed: state.busy || !online
                    ? null
                    : () => issue(state, slot, current, products, 'OPEN_NEXT'),
                child: const Text('Mở ô nạp hoa mới'),
              ),
            if (actions.contains('open-for-check'))
              OutlinedButton(
                onPressed: state.busy || !online
                    ? null
                    : () => issue(
                        state,
                        slot,
                        current,
                        products,
                        'OPEN_FOR_CHECK',
                      ),
                child: const Text('Mở ô kiểm tra'),
              ),
            if (slot['manualRetryEnabled'] == true &&
                current['currentCmdId'] != null &&
                (current['retryAfterSeconds'] as num? ?? 0) <= 0)
              OutlinedButton(
                onPressed: state.busy || !online
                    ? null
                    : () => issue(state, slot, current, products, 'RETRY'),
                child: const Text('Thử mở lại ô'),
              ),
            if (actions.contains('report-issue'))
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () => state.run(() async {
                        final f =
                            await askForm(context, 'Báo lỗi phiên thao tác', [
                              const InputSpec(
                                'reason',
                                'Mô tả sự cố',
                                minLength: 5,
                                lines: 4,
                              ),
                            ]);
                        if (f != null) {
                          await widget.api.post(
                            '$base/${current['id']}/report-issue',
                            {'reason': f['reason']},
                          );
                        }
                      }),
                child: const Text('Ghi nhận lỗi phiên'),
              ),
            if (current['stage'] == 'NeedsInspection')
              const Text(
                'Phiên cần kiểm tra. Liên hệ đội vận hành để xử lý.',
                style: TextStyle(color: Color(0xFFB42318), height: 1.6),
              ),
          ],
          if (selfService &&
              !held &&
              slot['sensorEnabled'] != true &&
              slot['bouquetId'] != null &&
              ['STOCKED', 'PENDING_REMOVAL'].contains(slot['status']))
            RemoveSlotFlower(
              api: widget.api,
              kioskId: kioskId,
              slot: slot,
              onRemoved: state.reload,
            ),
          if (selfService &&
              (current == null ||
                  ['Completed', 'Recovered'].contains(current['stage'])) &&
              slot['zone'] == 'WALK_IN' &&
              slot['sensorEnabled'] == true &&
              [
                'RENTED_EMPTY',
                'STOCKED',
                'PENDING_REMOVAL',
              ].contains(slot['status']))
            _SlotOperationForm(
              key: ValueKey(
                '${slot['id']}:${slot['bouquetId']}:${slot['status']}',
              ),
              empty: slot['status'] == 'RENTED_EMPTY',
              products: products,
              busy: state.busy,
              canOpen: online && !held && slot['sensorReady'] == true,
              onStart: (action, values) => issue(
                state,
                slot,
                null,
                products,
                'START',
                action: action,
                formValues: values,
              ),
            ),
          if (!selfService &&
              !held &&
              !activeSession &&
              [
                'RENTED_EMPTY',
                'STOCKED',
                'PENDING_REMOVAL',
              ].contains(slot['status']) &&
              slot['zone'] == 'WALK_IN')
            _SlotAssignmentForm(
              api: widget.api,
              sellerId: '${widget.session.sellerId}',
              slot: slot,
              products: products,
              busy: state.busy,
              onAssign: (values) => assign(state, slot, values),
            ),
          if (widget.session.sellerId != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDDE6DF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.report_problem_outlined,
                        size: 19,
                        color: Color(0xFFB42318),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Báo sự cố thiết bị ô tủ',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: forest,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Nếu cửa ô kẹt, cảm biến lỗi hoặc thiết bị có sự cố, gửi báo cáo kèm ảnh để đội vận hành kiểm tra và điều phối kỹ thuật viên.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: Color(0xFF617267),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (slot['status'] == 'FAULT' || deviceFaultReported) ...[
                    if (matchingRepairs.isNotEmpty)
                      for (final repair in matchingRepairs) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6FAF6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFD5E4D8)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Yêu cầu mở ô sửa chữa',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: forest,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: repairApprovalActive(repair, now)
                                          ? const Color(0xFFEAF3EC)
                                          : const Color(0xFFFFFAEB),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: repairApprovalActive(repair, now)
                                            ? const Color(0xFFC7DFCE)
                                            : const Color(0xFFFDE68A),
                                      ),
                                    ),
                                    child: Text(
                                      repairApprovalActive(repair, now)
                                          ? 'Đã duyệt'
                                          : 'Chờ duyệt',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: repairApprovalActive(repair, now)
                                            ? forest
                                            : const Color(0xFF9A6700),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                valueOf(repair, 'reason'),
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  height: 1.5,
                                  color: Color(0xFF1F3428),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (repairApprovalActive(repair, now))
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEAF3EC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFC7DFCE),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.verified_user_outlined,
                                        size: 18,
                                        color: forest,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Đã duyệt quyền mở ô đến ${dateText(repair['expiresAt'])}. Kỹ thuật viên có thể lấy OTP mở ô.',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            height: 1.5,
                                            color: forest,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else ...[
                                const Text(
                                  'Kỹ thuật viên đã nhận việc sửa ô này. Duyệt để kỹ thuật viên được lấy OTP mở đúng ô.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.45,
                                    color: Color(0xFF617267),
                                  ),
                                ),
                                if (repairApproveBlocked) ...[
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Chưa xác nhận được kết quả. Tải lại trước khi duyệt tiếp.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFB42318),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: state.busy
                                        ? null
                                        : () async {
                                            try {
                                              await widget.api.get(
                                                '/api/me/technical-repairs',
                                              );
                                              await state.reload();
                                              if (mounted) {
                                                setState(
                                                  () => repairApproveBlocked =
                                                      false,
                                                );
                                              }
                                            } catch (error) {
                                              if (context.mounted) {
                                                message(context, '$error');
                                              }
                                            }
                                          },
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Tải lại yêu cầu'),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                  ),
                                  onPressed: state.busy || repairApproveBlocked
                                      ? null
                                      : () => approveTechnicalRepair(
                                          state,
                                          kiosk,
                                          slot,
                                          repair,
                                        ),
                                  icon: const Icon(
                                    Icons.verified_user_outlined,
                                    size: 19,
                                  ),
                                  label: const Text('Duyệt quyền mở ô'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ]
                    else if (repairsError != null) ...[
                      Text(
                        '$repairsError',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFB42318),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: state.busy ? null : state.reload,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Tải lại yêu cầu'),
                      ),
                    ] else
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFAEB),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.build_circle_outlined,
                              size: 18,
                              color: Color(0xFF925B0A),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Ô đã có báo cáo sự cố. Đội vận hành sẽ kiểm tra và xử lý.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.5,
                                      color: Color(0xFF925B0A),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.session.role == AppRole.seller
                                        ? 'Khi kỹ thuật viên nhận việc và gửi yêu cầu, nút duyệt quyền mở ô sẽ hiển thị ngay tại đây.'
                                        : 'Chủ shop sẽ duyệt quyền mở ô khi kỹ thuật viên nhận việc.',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      height: 1.45,
                                      color: Color(0xFF925B0A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ] else
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: const Color(0xFFB42318),
                        side: const BorderSide(color: Color(0xFFFECDCA)),
                        backgroundColor: const Color(0xFFFEF3F2),
                      ),
                      onPressed: state.busy
                          ? null
                          : () => reportDeviceFault(state, slot),
                      icon: const Icon(Icons.report_problem_outlined, size: 19),
                      label: Text('Báo sự cố ô ${valueOf(slot, 'slotCode')}'),
                    ),
                ],
              ),
            ),
          ],
        ],
      );
    },
  );

  Future<void> reportDeviceFault(
    ResourceViewState state,
    Json slot,
  ) => state.run(() async {
    final sellerId = widget.session.sellerId;
    if (sellerId == null || sellerId.isEmpty) {
      throw const ApiError(403, 'Tài khoản chưa gắn với cửa hàng.');
    }
    if (slot['status'] == 'FAULT' || deviceFaultReported) {
      throw const ApiError(
        409,
        'Ô đã có báo cáo sự cố. Đội vận hành sẽ kiểm tra và xử lý.',
      );
    }
    final slotCode = valueOf(slot, 'slotCode');
    final form = await askForm(
      context,
      'Báo sự cố ô $slotCode',
      [
        const InputSpec(
          'description',
          'Tình trạng cần kiểm tra',
          minLength: 5,
          lines: 4,
        ),
      ],
      submitLabel: 'Tiếp tục chụp / chọn ảnh',
      description:
          'Ghi lại tình trạng bạn quan sát được. Nếu cửa đang mở, chờ cửa đóng và không cố tác động vào khóa.',
    );
    if (form == null || !mounted) return;
    final picker = widget.pickEvidence ?? chooseEvidence;
    final file = await picker(context);
    if (file == null || !mounted) return;
    final evidence = await widget.api.upload(
      '/api/sellers/$sellerId/slots/$slotId/evidence/report_device_fault',
      file,
    );
    final reference = evidence['reference']?.toString() ?? '';
    if (!reference.startsWith('evidence:v1:')) {
      throw const ApiError(
        0,
        'Chưa nhận được mã ảnh minh chứng hợp lệ. Vui lòng thử lại.',
      );
    }
    if (!mounted ||
        !await confirm(
          context,
          'Gửi báo cáo sự cố ô $slotCode?',
          '${form['description']!}\n\nGửi báo cáo có thể dừng bán tại ô, hủy lượt thanh toán chưa hoàn tất hoặc tạo yêu cầu hoàn tiền cho đơn đang giao.',
        )) {
      return;
    }
    await widget.api.post('/api/sellers/$sellerId/flows/report_device_fault', {
      'p_kiosk': kioskId,
      'p_slot': slotId,
      'p_desc': form['description']!,
      'p_photo': reference,
    });
    if (mounted) {
      setState(() => deviceFaultReported = true);
      message(
        context,
        'Đã gửi báo cáo sự cố. Đội vận hành sẽ kiểm tra và điều phối kỹ thuật viên.',
      );
    }
  });

  Future<void> approveTechnicalRepair(
    ResourceViewState state,
    Json kiosk,
    Json slot,
    Json repair,
  ) => state.run(() async {
    if (!await confirm(
      context,
      'Duyệt quyền mở ô?',
      '${valueOf(kiosk, 'name', 'Kiosk')} · Ô ${valueOf(slot, 'slotCode')}. Kỹ thuật viên sẽ được phép lấy OTP để sửa ô này.',
    )) {
      return;
    }
    try {
      await widget.api.post(
        '/api/me/technical-repairs/${repair['id']}/approve',
      );
      if (mounted) {
        setState(() => repairApproveBlocked = false);
        message(context, 'Đã duyệt quyền mở ô sửa chữa.');
      }
    } on ApiError catch (error) {
      if (mounted &&
          (error.ambiguous || error.status == 0 || error.status >= 500)) {
        setState(() => repairApproveBlocked = true);
      }
      rethrow;
    }
  });

  Future<void> assign(
    ResourceViewState state,
    Json slot,
    Map<String, String> form,
  ) => state.run(() async {
    if (form['action'] != 'REMOVE' && (form['productId'] ?? '').isEmpty) {
      throw const ApiError(400, 'Chọn mẫu hoa khi nạp hoặc thay hoa.');
    }
    await widget.api.post('/api/me/inventory-tasks', {
      'id': const Uuid().v4(),
      'assigneeId': form['assigneeId'],
      'kioskId': kioskId,
      'slotId': slotId,
      'action': form['action'],
      'expectedBouquetId': slot['bouquetId'],
      'productId': form['action'] == 'REMOVE' ? null : form['productId'],
      'instructions': form['instructions'],
    });
    if (mounted) message(context, 'Đã giao việc cho nhân viên.');
  });
}

class _SlotAssignmentForm extends StatefulWidget {
  const _SlotAssignmentForm({
    required this.api,
    required this.sellerId,
    required this.slot,
    required this.products,
    required this.busy,
    required this.onAssign,
  });
  final ApiClient api;
  final String sellerId;
  final Json slot;
  final List<Json> products;
  final bool busy;
  final Future<void> Function(Map<String, String>) onAssign;
  @override
  State<_SlotAssignmentForm> createState() => _SlotAssignmentFormState();
}

class _SlotAssignmentFormState extends State<_SlotAssignmentForm> {
  late Future<dynamic> staff;
  Future<dynamic> load() =>
      widget.api.get('/api/sellers/${widget.sellerId}/staff');
  @override
  void initState() {
    super.initState();
    staff = load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: staff,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      if (snapshot.hasError) {
        return Column(
          children: [
            const Text(
              'Chưa tải được nhân viên.',
              style: TextStyle(color: Color(0xFFB42318)),
            ),
            TextButton(
              onPressed: () => setState(() => staff = load()),
              child: const Text('Thử lại'),
            ),
          ],
        );
      }
      final people = itemsOf(snapshot.data);
      if (people.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'Chưa có nhân viên đang hoạt động.',
            style: TextStyle(fontSize: 13, color: Color(0xFF617267)),
          ),
        );
      }
      return _SlotOperationForm(
        empty: widget.slot['status'] == 'RENTED_EMPTY',
        products: widget.products,
        busy: widget.busy,
        canOpen: true,
        staff: people,
        onStart: (action, values) => widget.onAssign({
          ...values,
          'action': action,
          'instructions': values['reason']!,
        }),
      );
    },
  );
}

class _SlotModeTab extends StatelessWidget {
  const _SlotModeTab({
    required this.label,
    required this.icon,
    required this.selected,
    this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? forest : const Color(0xFF617267),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected ? forest : const Color(0xFF617267),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 2,
              color: selected ? forest : const Color(0xFFDDE6DF),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SlotOperationForm extends StatefulWidget {
  const _SlotOperationForm({
    required this.empty,
    required this.products,
    required this.busy,
    required this.canOpen,
    required this.onStart,
    this.staff,
    super.key,
  });
  final bool empty, busy, canOpen;
  final List<Json> products;
  final List<Json>? staff;
  final Future<void> Function(String, Map<String, String>) onStart;
  @override
  State<_SlotOperationForm> createState() => _SlotOperationFormState();
}

class _SlotOperationFormState extends State<_SlotOperationForm> {
  final form = GlobalKey<FormState>();
  final reason = TextEditingController();
  String action = 'REMOVE';
  String? productId;
  String? assigneeId;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedAction = widget.empty ? 'LOAD' : action;
    final assignment = widget.staff != null;
    final needsProduct = selectedAction != 'REMOVE';
    final products = widget.products
        .where(
          (p) => p['status'] == 'ACTIVE' && (p['quantity'] as num? ?? 0) > 0,
        )
        .toList();
    if (!products.any((p) => p['id'] == productId)) productId = null;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              assignment
                  ? 'Giao việc cho nhân viên'
                  : widget.empty
                  ? 'Nạp hoa vào ô'
                  : 'Thu hồi hoặc thay hoa',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: forest,
              ),
            ),
            const SizedBox(height: 16),
            if (assignment) ...[
              DropdownButtonFormField<String>(
                style: Theme.of(context).textTheme.bodyLarge,
                initialValue: assigneeId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Nhân viên',
                  hintText: 'Chọn nhân viên',
                ),
                items: [
                  for (final person in widget.staff!)
                    DropdownMenuItem(
                      value: '${person['id']}',
                      child: Text(
                        valueOf(person, 'name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: widget.busy
                    ? null
                    : (value) => setState(() => assigneeId = value),
                validator: (value) =>
                    value == null ? 'Chọn nhân viên phụ trách.' : null,
              ),
              const SizedBox(height: 16),
            ],
            if (!widget.empty) ...[
              DropdownButtonFormField<String>(
                style: Theme.of(context).textTheme.bodyLarge,
                initialValue: action,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Thao tác'),
                items: const [
                  DropdownMenuItem(value: 'REMOVE', child: Text('Thu hồi hoa')),
                  DropdownMenuItem(
                    value: 'REPLACE',
                    child: Text('Thay hoa mới'),
                  ),
                ],
                onChanged: widget.busy
                    ? null
                    : (value) => setState(() => action = value ?? 'REMOVE'),
              ),
              const SizedBox(height: 16),
            ],
            if (needsProduct) ...[
              DropdownButtonFormField<String>(
                style: Theme.of(context).textTheme.bodyLarge,
                key: ValueKey(
                  '${products.map((p) => p['id']).join(',')}:$productId',
                ),
                initialValue: productId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Mẫu hoa',
                  hintText: 'Chọn mẫu hoa',
                ),
                items: [
                  for (final p in products)
                    DropdownMenuItem(
                      value: '${p['id']}',
                      child: Text(
                        '${p['name']} · Còn ${p['quantity']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: widget.busy
                    ? null
                    : (value) => setState(() => productId = value),
                validator: (value) =>
                    value == null ? 'Chọn mẫu hoa để nạp hoặc thay.' : null,
              ),
              if (products.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Chưa có mẫu hoa còn hàng.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFB42318)),
                  ),
                ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: reason,
              enabled: !widget.busy,
              minLines: 2,
              maxLines: 3,
              maxLength: assignment ? 2000 : 500,
              decoration: InputDecoration(
                labelText: assignment
                    ? 'Hướng dẫn công việc'
                    : 'Lý do thao tác',
                hintText: assignment
                    ? 'Nội dung công việc, từ 10 ký tự'
                    : 'Nhập lý do, từ 5 ký tự',
                floatingLabelBehavior: FloatingLabelBehavior.always,
                alignLabelWithHint: true,
                counterText: '',
              ),
              validator: (value) =>
                  (value ?? '').trim().length < (assignment ? 10 : 5)
                  ? assignment
                        ? 'Nhập hướng dẫn từ 10 ký tự.'
                        : 'Nhập lý do từ 5 ký tự.'
                  : null,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed:
                  widget.busy ||
                      !widget.canOpen ||
                      (needsProduct && products.isEmpty)
                  ? null
                  : () {
                      if (form.currentState?.validate() != true) return;
                      widget.onStart(selectedAction, {
                        'reason': reason.text.trim(),
                        'productId': ?productId,
                        'assigneeId': ?assigneeId,
                      });
                    },
              child: Text(
                widget.busy
                    ? 'Đang gửi yêu cầu…'
                    : assignment
                    ? 'Giao việc'
                    : switch (selectedAction) {
                        'LOAD' => 'Mở ô nạp hoa',
                        'REPLACE' => 'Bắt đầu thay hoa',
                        _ => 'Bắt đầu thu hồi hoa',
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductsPage extends StatefulWidget {
  const ProductsPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  ApiClient get api => widget.api;
  Session get session => widget.session;
  String query = '', filter = 'ALL';
  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => api.get('/api/me/products'),
    builder: (context, data, state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CatalogToolbar(
          accessory: false,
          query: query,
          status: filter,
          onQuery: (value) => setState(() => query = value),
          onStatus: (value) => setState(() => filter = value),
          onCreate: state.busy ? null : () => edit(context, state),
        ),
        if (itemsOf(data).where(matches).isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('Không có mẫu hoa phù hợp.')),
          ),
        for (final row in itemsOf(data).where(matches))
          CatalogListItem(
            item: row,
            onTap: () async {
              await openPage(
                context,
                'Mẫu hoa',
                ResourceView(
                  load: () => api.get('/api/me/products'),
                  builder: (context, data, detailState) {
                    final item = itemsOf(
                      data,
                    ).where((p) => p['id'] == row['id']).firstOrNull;
                    if (item == null) {
                      return const InfoBox('Mẫu hoa không còn khả dụng.');
                    }
                    return ProductDetailView(
                      api: api,
                      item: item,
                      busy: detailState.busy,
                      onEdit: () => edit(context, detailState, item),
                      onPhoto: () => detailState.run(() async {
                        final file = await chooseEvidence(context);
                        if (file == null) return;
                        await api.upload(
                          '/api/me/products/${item['id']}/photos',
                          file,
                        );
                        if (context.mounted) {
                          message(context, 'Đã thêm ảnh mẫu hoa.');
                        }
                      }),
                      onStatus: () => detailState.run(() async {
                        final next = item['status'] == 'ACTIVE'
                            ? 'INACTIVE'
                            : 'ACTIVE';
                        if (await confirm(
                          context,
                          next == 'ACTIVE'
                              ? 'Bật bán mẫu hoa?'
                              : 'Ngừng bán mẫu hoa?',
                          'Thay đổi trạng thái mẫu ${item['name']}.',
                        )) {
                          await api.post('/api/me/flows/set_product_status', {
                            'productId': item['id'],
                            'status': next,
                          });
                        }
                      }),
                    );
                  },
                ),
              );
              await state.reload();
            },
          ),
      ],
    ),
  );
  bool matches(Json item) =>
      (filter == 'ALL' || item['status'] == filter) &&
      '${item['name']} ${item['description'] ?? ''}'.toLowerCase().contains(
        query.trim().toLowerCase(),
      );
  Future<void> edit(
    BuildContext context,
    ResourceViewState state, [
    Json? row,
  ]) => state.run(() async {
    if (!context.mounted) return;
    final body = await showCatalogEditor(context, item: row);
    if (body == null || !context.mounted) return;
    if (row == null) {
      await api.post('/api/me/products', body);
    } else {
      await api.put(
        '/api/sellers/${session.sellerId}/products/${row['id']}',
        body,
      );
    }
    if (context.mounted) message(context, 'Đã lưu mẫu hoa.');
  });
}

class SlotBouquetPhoto extends StatefulWidget {
  const SlotBouquetPhoto(
    this.api,
    this.productId, {
    required this.products,
    this.price,
    super.key,
  });
  final ApiClient api;
  final String productId;
  final List<Json> products;
  final dynamic price;
  @override
  State<SlotBouquetPhoto> createState() => _SlotBouquetPhotoState();
}

class _SlotBouquetPhotoState extends State<SlotBouquetPhoto> {
  late Future<dynamic> photos;
  Future<dynamic> load() =>
      widget.api.get('/api/me/products/${widget.productId}/photos');
  @override
  void initState() {
    super.initState();
    photos = load();
  }

  @override
  void didUpdateWidget(SlotBouquetPhoto old) {
    super.didUpdateWidget(old);
    if (old.productId != widget.productId || old.api != widget.api) {
      photos = load();
    }
  }

  void viewPhoto(String url) => showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 600,
        height: MediaQuery.sizeOf(context).height * .75,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Center(child: Text('Không tải được ảnh.')),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: 'Đóng ảnh',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final product = widget.products
        .where((p) => p['id'] == widget.productId)
        .firstOrNull;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          height: 96,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ColoredBox(
              color: const Color(0xFFF2F5F0),
              child: FutureBuilder<dynamic>(
                future: photos,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: IconButton(
                        tooltip: 'Tải lại ảnh',
                        onPressed: () => setState(() => photos = load()),
                        icon: const Icon(Icons.refresh, color: forest),
                      ),
                    );
                  }
                  final images = itemsOf(snapshot.data);
                  final cover =
                      images.where((p) => p['isCover'] == true).firstOrNull ??
                      images.firstOrNull;
                  final uri = Uri.tryParse('${cover?['url']}');
                  if (uri == null ||
                      uri.scheme != 'https' ||
                      uri.host.isEmpty ||
                      uri.userInfo.isNotEmpty) {
                    return const Icon(
                      Icons.local_florist_outlined,
                      color: forest,
                    );
                  }
                  return Semantics(
                    button: true,
                    label: 'Xem ảnh lớn',
                    child: InkWell(
                      onTap: () => viewPhoto(uri.toString()),
                      child: Image.network(
                        uri.toString(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image_outlined,
                          color: forest,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product == null ? 'Bó hoa trong ô' : valueOf(product, 'name'),
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: forest,
                ),
              ),
              if (widget.price != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    money(widget.price),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: forest,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class RemoveSlotFlower extends StatefulWidget {
  const RemoveSlotFlower({
    required this.api,
    required this.kioskId,
    required this.slot,
    required this.onRemoved,
    super.key,
  });
  final ApiClient api;
  final String kioskId;
  final Json slot;
  final Future<void> Function() onRemoved;
  @override
  State<RemoveSlotFlower> createState() => _RemoveSlotFlowerState();
}

class _RemoveSlotFlowerState extends State<RemoveSlotFlower> {
  final reason = TextEditingController();
  bool confirmed = false;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> remove() async {
    if (busy || !confirmed || reason.text.trim().length < 5) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.request(
        'DELETE',
        '/api/me/kiosks/${widget.kioskId}/slots/${widget.slot['id']}/bouquet',
        body: {
          'bouquetId': widget.slot['bouquetId'],
          'reason': reason.text.trim(),
          'confirmedRemoved': confirmed,
        },
      );
      if (mounted) {
        message(
          context,
          'Đã ghi nhận thu hồi hoa. Ô đã được làm trống và giữ nguyên hình thức bán.',
        );
      }
      await widget.onRemoved();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiError && e.status == 404
              ? 'API thu hồi chưa được triển khai trên máy chủ này.'
              : '$e',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final held =
        widget.slot['bouquetStatus'] == 'HELD' ||
        widget.slot['orderStatus'] == 'AWAITING_PAYMENT';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Thu hồi hoa khỏi ô ${widget.slot['slotCode']}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const InfoBox(
          'Chỉ xác nhận sau khi đã lấy bó hoa thực tế khỏi ô. Hệ thống ghi lịch sử thu hồi, giữ nguyên vùng bán và thông tin đơn hàng, hoàn tiền liên quan.',
        ),
        if (held)
          const InfoBox(
            'Không thể thu hồi lúc này vì bó hoa đang được giữ cho một đơn hàng.',
          )
        else ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: confirmed,
            onChanged: busy
                ? null
                : (value) => setState(() => confirmed = value ?? false),
            title: const Text('Tôi đã lấy hoa thực tế khỏi ô này.'),
          ),
          TextField(
            controller: reason,
            maxLength: 500,
            maxLines: 3,
            enabled: !busy,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Lý do thu hồi',
              hintText: 'Nhập lý do, tối thiểu 5 ký tự',
            ),
          ),
          if (error != null) InfoBox(error!, warning: true),
          OutlinedButton(
            onPressed: !busy && confirmed && reason.text.trim().length >= 5
                ? remove
                : null,
            child: Text(busy ? 'Đang ghi nhận…' : 'Xác nhận đã lấy hoa khỏi ô'),
          ),
        ],
      ],
    );
  }
}

class KioskLocationPage extends StatelessWidget {
  const KioskLocationPage(this.api, this.session, this.kiosk, {super.key});
  final ApiClient api;
  final Session session;
  final Json kiosk;
  String get base => '/api/sellers/${session.sellerId}/kiosks/${kiosk['id']}';
  @override
  Widget build(BuildContext context) => ResourceView(
    load: () async {
      final rows = itemsOf(
        await api.get('/api/sellers/${session.sellerId}/kiosks'),
      );
      final fresh = rows.where((row) => row['id'] == kiosk['id']).firstOrNull;
      if (fresh == null) throw const ApiError(404, 'Không tìm thấy kiosk.');
      return {
        'kiosk': fresh,
        'requests': await api.get('$base/location-requests'),
      };
    },
    builder: (context, data, state) {
      final kiosk = objectOf(objectOf(data)['kiosk']);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageTitle(valueOf(kiosk, 'name'), valueOf(kiosk, 'address')),
          Text(
            'Vĩ độ: ${kiosk['latitude'] ?? 'Chưa có'} · Kinh độ: ${kiosk['longitude'] ?? 'Chưa có'}',
          ),
          OutlinedButton(
            onPressed: () => navigateAddress(valueOf(kiosk, 'address')),
            child: const Text('Xem bản đồ'),
          ),
          if (kiosk['canEditLocation'] != true)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFF925B0A),
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Vị trí do hệ thống quản lý. Shop chỉ có quyền xem.',
                      style: TextStyle(color: Color(0xFF925B0A), height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          if (kiosk['canEditLocation'] == true)
            FilledButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final form =
                          await askForm(context, 'Đề nghị cập nhật vị trí', [
                            InputSpec(
                              'address',
                              'Địa chỉ',
                              initial: valueOf(kiosk, 'address', ''),
                              minLength: 5,
                            ),
                            InputSpec(
                              'latitude',
                              'Vĩ độ',
                              initial: '${kiosk['latitude'] ?? ''}',
                            ),
                            InputSpec(
                              'longitude',
                              'Kinh độ',
                              initial: '${kiosk['longitude'] ?? ''}',
                            ),
                            const InputSpec(
                              'reason',
                              'Lý do thay đổi',
                              minLength: 10,
                              lines: 3,
                            ),
                          ]);
                      if (form == null) return;
                      final lat = double.tryParse(form['latitude']!),
                          lon = double.tryParse(form['longitude']!);
                      if (lat == null ||
                          lon == null ||
                          !lat.isFinite ||
                          !lon.isFinite ||
                          lat < -90 ||
                          lat > 90 ||
                          lon < -180 ||
                          lon > 180) {
                        throw const ApiError(400, 'Tọa độ không hợp lệ.');
                      }
                      await api.put('$base/location', {
                        'address': form['address'],
                        'latitude': lat,
                        'longitude': lon,
                        'reason': form['reason'],
                      });
                      if (context.mounted) {
                        message(
                          context,
                          'Đã gửi cập nhật vị trí. Theo dõi trạng thái xét duyệt bên dưới.',
                        );
                      }
                    }),
              child: const Text('Cập nhật vị trí kiosk'),
            ),
          for (final request in itemsOf(objectOf(data)['requests']))
            RecordCard(
              title: valueOf(request, 'address'),
              subtitle: valueOf(request, 'reason', ''),
              status: request['status'],
            ),
        ],
      );
    },
  );
}

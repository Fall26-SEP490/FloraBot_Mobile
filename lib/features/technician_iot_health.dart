import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';

const _cycleText = {
  'NONE': 'Chưa ghi nhận thao tác từ khi thiết bị khởi động',
  'RELAY_PULSED': 'Đã kích relay, đang chờ tín hiệu mở cửa',
  'OPEN_DETECTED': 'Đã nhận tín hiệu mở, đang chờ cửa đóng',
  'CLOSE_DETECTED': 'Đã nhận tín hiệu mở và đóng',
  'OPEN_TIMEOUT': 'Đã kích relay, hết thời gian chờ tín hiệu mở',
  'CLOSE_TIMEOUT': 'Đã nhận tín hiệu mở, hết thời gian chờ tín hiệu đóng',
  'INSPECTION_REQUIRED': 'Cần kiểm tra cửa tại tủ',
};

class TechnicianIoTHealth extends StatefulWidget {
  const TechnicianIoTHealth({
    required this.api,
    required String taskId,
    super.key,
  }) : path = '/api/staff/tasks/$taskId/iot-health',
       wholeKiosk = false;

  const TechnicianIoTHealth.forKiosk({
    required this.api,
    required String kioskId,
    super.key,
  }) : path = '/api/staff/kiosk-health/$kioskId',
       wholeKiosk = true;

  final ApiClient api;
  final String path;
  final bool wholeKiosk;

  @override
  State<TechnicianIoTHealth> createState() => _TechnicianIoTHealthState();
}

class _TechnicianIoTHealthState extends State<TechnicianIoTHealth> {
  Json? _health;
  Timer? _poll;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.wholeKiosk) _onExpansionChanged(true);
  }

  Future<void> _read() async {
    if (_loading) return;
    setState(() {
      _loading = true;
    });
    try {
      final health = objectOf(await widget.api.get(widget.path));
      if (!mounted) return;
      setState(() {
        _health = health;
        _failed = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _health = null;
        _failed = true;
        _loading = false;
      });
    }
  }

  void _onExpansionChanged(bool expanded) {
    _poll?.cancel();
    if (expanded) {
      unawaited(_read());
      _poll = Timer.periodic(const Duration(seconds: 5), (_) {
        if (ModalRoute.of(context)?.isCurrent == true) unawaited(_read());
      });
    } else {
      _health = null;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  String _signal(bool fresh, Object? value, String on, String off) =>
      fresh && value is bool ? (value ? on : off) : 'Chưa xác định';

  @override
  Widget build(BuildContext context) {
    final health = _health;
    final checkedAt = DateTime.tryParse('${health?['observedAt']}');
    final fresh =
        health?['isFresh'] == true &&
        checkedAt != null &&
        DateTime.now().difference(checkedAt) <= const Duration(seconds: 45);
    final slots = health?['slots'];
    final rows = slots is List ? slots.whereType<Map>() : const <Map>[];
    final content = <Widget>[
      if (_loading && health == null && !_failed)
        const Text('Đang đọc tín hiệu từ tủ…'),
      if (_failed) const Text('Chưa tải được dữ liệu IoT. Hãy thử đọc lại.'),
      if (health != null) ...[
        if (widget.wholeKiosk) ...[
          StatusHeading(
            title: const Text(
              'Tình trạng kiosk',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            status: StatusChip(health['kioskStatus']),
          ),
          Text('Heartbeat gần nhất ${dateText(health['lastHeartbeatAt'])}'),
        ],
        Text(
          checkedAt == null
              ? 'Chưa nhận được bản đo từ tủ'
              : 'Lần đo gần nhất ${dateText(health['observedAt'])}',
        ),
        if (!fresh)
          const Text('Đang chờ dữ liệu mới. Trạng thái từng ô chưa xác định.'),
        if (rows.isEmpty) const Text('Chưa có ô tủ để kiểm tra.'),
        for (final slot in rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Ô ${slot['slotCode']}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LM393 · ${_signal(fresh, slot['flowerDetected'], 'Phát hiện vật', 'Không phát hiện vật')}',
                ),
                Text(
                  'MC-38 · ${_signal(fresh, slot['doorClosed'], 'Báo cửa đóng', 'Báo cửa mở')}',
                ),
                Text(
                  fresh
                      ? (_cycleText[slot['lastCycle']] ??
                            'Chưa có dữ liệu thao tác cửa')
                      : 'Thao tác cửa gần nhất chưa xác định',
                ),
                if (fresh && slot['lastCycleAt'] != null)
                  Text(dateText(slot['lastCycleAt'])),
              ],
            ),
          ),
        const Text(
          'Nếu tín hiệu không khớp thực tế, hãy kiểm tra dây cảm biến, nam châm, nguồn khóa và cơ cấu chốt tại ô. Tủ hiện chưa đo dòng qua khóa điện.',
        ),
      ],
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _loading ? null : _read,
        icon: const Icon(Icons.refresh),
        label: const Text('Đọc lại tín hiệu'),
      ),
    ];
    if (widget.wholeKiosk) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: content,
      );
    }
    return ExpansionTile(
      title: const Text('Sức khỏe thiết bị IoT'),
      tilePadding: EdgeInsets.zero,
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      onExpansionChanged: _onExpansionChanged,
      children: content,
    );
  }
}

class TechnicianKioskHealthPage extends StatelessWidget {
  const TechnicianKioskHealthPage({required this.api, super.key});
  final ApiClient api;

  @override
  Widget build(BuildContext context) => ApiListPage(
    api: api,
    path: '/api/staff/kiosk-health',
    title: 'Sức khỏe kiosk',
    subtitle: 'Chọn kiosk được giao để kiểm tra kết nối và các ô tủ.',
    item: (context, row, _) => RecordCard(
      title: valueOf(row, 'code'),
      subtitle: valueOf(row, 'name'),
      status: row['status'],
      onTap: () {
        final id = valueOf(row, 'id');
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: Text(valueOf(row, 'code'))),
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    PageTitle(valueOf(row, 'name'), 'Tình trạng thiết bị'),
                    TechnicianIoTHealth.forKiosk(api: api, kioskId: id),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';

const _cycleText = {
  'NONE': 'Chưa có thao tác cửa',
  'RELAY_PULSED': 'Đã gửi lệnh, chờ cửa mở',
  'OPEN_DETECTED': 'Cửa đã mở, chờ đóng',
  'CLOSE_DETECTED': 'Đã ghi nhận mở và đóng cửa',
  'OPEN_TIMEOUT': 'Quá thời gian chờ mở cửa',
  'CLOSE_TIMEOUT': 'Quá thời gian chờ đóng cửa',
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
        const LinearProgressIndicator(minHeight: 2),
      if (_failed)
        const InfoBox('Chưa tải được tín hiệu. Thử lại nhé.', warning: true),
      if (health != null) ...[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDCE6E0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StatusHeading(
                title: const Text(
                  'Kết nối',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                status: widget.wholeKiosk
                    ? StatusChip(health['kioskStatus'])
                    : null,
              ),
              const SizedBox(height: 12),
              const Text(
                'Tín hiệu gần nhất',
                style: TextStyle(fontSize: 12, color: Color(0xFF617568)),
              ),
              const SizedBox(height: 3),
              Text(
                checkedAt == null
                    ? 'Chưa có dữ liệu'
                    : dateText(health['observedAt']),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (!fresh)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: Color(0xFF94620B),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Chưa có tín hiệu mới từ tủ.',
                    style: TextStyle(color: Color(0xFF94620B), fontSize: 13),
                  ),
                ),
              ],
            ),
          )
        else
          const SizedBox(height: 16),
        if (rows.isEmpty)
          const InfoBox('Chưa có ô tủ để kiểm tra.')
        else
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFDCE6E0)),
            ),
            child: Column(
              children: [
                Container(
                  color: const Color(0xFFEDF4EF),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text(
                          'Ô tủ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Cảm biến vật',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Cửa tủ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final slot in rows)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 18,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0xFFEDF1EE))),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 52,
                          child: Text(
                            'Ô ${slot['slotCode']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: forest,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _SensorReading(
                            text: _signal(
                              fresh,
                              slot['flowerDetected'],
                              'Phát hiện vật',
                              'Không phát hiện vật',
                            ),
                            known: fresh && slot['flowerDetected'] is bool,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SensorReading(
                            text: _signal(
                              fresh,
                              slot['doorClosed'],
                              'Cửa đóng',
                              'Cửa mở',
                            ),
                            known: fresh && slot['doorClosed'] is bool,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          title: const Text(
            'Chi tiết tín hiệu',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          children: [
            if (widget.wholeKiosk)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: const Text('Kết nối gần nhất'),
                subtitle: Text(dateText(health['lastHeartbeatAt'])),
              ),
            for (final slot in rows)
              if (fresh)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text('Ô ${slot['slotCode']}'),
                  subtitle: Text(
                    [
                      _cycleText[slot['lastCycle']] ??
                          'Chưa có dữ liệu thao tác cửa',
                      if (slot['lastCycleAt'] != null)
                        dateText(slot['lastCycleAt']),
                    ].join(' · '),
                  ),
                ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 4, 4, 16),
              child: Text(
                'Tín hiệu không khớp thực tế: kiểm tra dây cảm biến, nam châm, nguồn khóa và chốt cửa. Tủ chưa đo dòng qua khóa điện.',
                style: TextStyle(fontSize: 13, color: Color(0xFF617568)),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _loading ? null : _read,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(_loading ? 'Đang kiểm tra…' : 'Đọc lại tín hiệu'),
        ),
      ),
    ];
    if (widget.wholeKiosk) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: content,
      );
    }
    return ExpansionTile(
      title: const Text('Tín hiệu thiết bị'),
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
    title: 'Tín hiệu thiết bị',
    subtitle: '',
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
                    PageTitle(valueOf(row, 'name'), ''),
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

class _SensorReading extends StatelessWidget {
  const _SensorReading({required this.text, required this.known});
  final String text;
  final bool known;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      height: 1.4,
      color: known ? forest : const Color(0xFF718078),
      fontWeight: known ? FontWeight.w600 : FontWeight.w400,
    ),
  );
}

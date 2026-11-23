import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/inventory_widgets.dart';

class KioskOverviewPage extends StatelessWidget {
  const KioskOverviewPage(this.api, this.session, this.kiosk, {super.key});
  final ApiClient api;
  final Session session;
  final Json kiosk;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      centerTitle: true,
      title: Text(
        valueOf(kiosk, 'name', 'Kiosk'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
    ),
    body: ResourceView(
      load: () async {
        final rows = itemsOf(
          await api.get('/api/sellers/${session.sellerId}/kiosks'),
        );
        return rows.where((row) => row['id'] == kiosk['id']).firstOrNull ??
            (throw const ApiError(404, 'Không tìm thấy kiosk.'));
      },
      builder: (context, data, state) {
        final current = objectOf(data);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                      const Expanded(
                        child: Text(
                          'Thông tin kiosk',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: forest,
                          ),
                        ),
                      ),
                      InventoryStatus(valueOf(current, 'status')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    valueOf(current, 'address', 'Chưa có địa chỉ'),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: forest,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _FlowerPresencePanel(api, '${current['id']}'),
          ],
        );
      },
    ),
  );
}

class _FlowerPresencePanel extends StatefulWidget {
  const _FlowerPresencePanel(this.api, this.kioskId);
  final ApiClient api;
  final String kioskId;
  @override
  State<_FlowerPresencePanel> createState() => _FlowerPresencePanelState();
}

class _FlowerPresencePanelState extends State<_FlowerPresencePanel>
    with WidgetsBindingObserver {
  Timer? timer;
  Json? data;
  Object? error;
  bool reading = false;
  int tick = 0;
  bool get visible =>
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      (ModalRoute.of(context)?.isCurrent ?? true);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(read());
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !visible) return;
      setState(() {});
      if (++tick % 5 == 0) unawaited(read());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && visible) {
      unawaited(read());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> read() async {
    if (reading) return;
    setState(() => reading = true);
    try {
      final result = objectOf(
        await widget.api.get('/api/kiosks/${widget.kioskId}/flower-presence'),
      );
      if (!mounted) return;
      setState(() {
        data = result;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e);
    } finally {
      if (mounted) setState(() => reading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final observed = DateTime.tryParse('${data?['observedAt']}');
    final age = observed == null ? null : DateTime.now().difference(observed);
    final fresh =
        error == null &&
        data?['isFresh'] == true &&
        age != null &&
        age.inMilliseconds >= -5000 &&
        age.inMilliseconds <= 45000;
    final slots = data == null ? <Json>[] : itemsOf(data!['slots']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Cảm biến ô tủ',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: forest,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          observed == null
              ? 'Tự cập nhật mỗi 5 giây'
              : 'Lần đo: ${dateText(observed.toIso8601String())}',
          style: const TextStyle(
            fontSize: 12,
            height: 1.5,
            color: Color(0xFF617267),
          ),
        ),
        const SizedBox(height: 12),
        if (data == null && reading)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (error != null)
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Chưa đọc được cảm biến.',
                  style: TextStyle(fontSize: 13, color: Color(0xFFB42318)),
                ),
              ),
              TextButton(
                onPressed: reading ? null : read,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        if (data != null && slots.isEmpty)
          const Text(
            'Chưa có dữ liệu cảm biến cho các ô tủ.',
            style: TextStyle(fontSize: 13, color: Color(0xFF617267)),
          ),
        for (final slot in slots)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDDE6DF)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Ô ${slot['slotCode']}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: forest,
                    ),
                  ),
                ),
                Text(
                  !fresh || slot['hasFlowers'] == null
                      ? 'Chưa xác định'
                      : slot['hasFlowers'] == true
                      ? 'Có hoa'
                      : 'Không có hoa',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: !fresh || slot['hasFlowers'] == null
                        ? const Color(0xFF617267)
                        : slot['hasFlowers'] == true
                        ? forest
                        : const Color(0xFF925B0A),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        const Text(
          'Tín hiệu cảm biến không xác nhận khách đã lấy hoa. “Không có hoa” cũng có thể do cảm biến chưa kết nối.',
          style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFFB42318)),
        ),
      ],
    );
  }
}

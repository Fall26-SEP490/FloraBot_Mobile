import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';

Future<void> openTaskPage(BuildContext context, Widget page) =>
    Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));

class ApiPhoto extends StatefulWidget {
  const ApiPhoto(this.api, this.path, {super.key});
  final ApiClient api;
  final String path;
  @override
  State<ApiPhoto> createState() => _ApiPhotoState();
}

class _ApiPhotoState extends State<ApiPhoto> {
  late Future<Uint8List> bytes = widget.api.imageBytes(widget.path);
  @override
  void didUpdateWidget(ApiPhoto old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.api != widget.api) {
      bytes = widget.api.imageBytes(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    key: ValueKey(widget.path),
    future: bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return TextButton.icon(
          onPressed: () => setState(() {
            bytes = widget.api.imageBytes(widget.path);
          }),
          icon: const Icon(Icons.refresh),
          label: const Text('Tải lại ảnh'),
        );
      }
      if (!snapshot.hasData) {
        return const SizedBox(
          height: 110,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            child: Stack(
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * .75,
                  child: InteractiveViewer(
                    child: Center(
                      child: Image.memory(snapshot.data!, fit: BoxFit.contain),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    tooltip: 'Đóng ảnh',
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            snapshot.data!,
            height: 180,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      );
    },
  );
}

class EvidenceGallery extends StatefulWidget {
  const EvidenceGallery(this.api, this.base, {super.key});
  final ApiClient api;
  final String base;
  @override
  State<EvidenceGallery> createState() => _EvidenceGalleryState();
}

class _EvidenceGalleryState extends State<EvidenceGallery> {
  int page = 1;
  @override
  Widget build(BuildContext context) => ResourceView(
    title: 'Ảnh minh chứng',
    resourceKey: page,
    load: () => widget.api.get('${widget.base}?page=$page'),
    builder: (context, data, state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (itemsOf(data).isEmpty) const InfoBox('Chưa có ảnh minh chứng.'),
        for (final item in itemsOf(data))
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                ApiPhoto(widget.api, '${widget.base}/${item['id']}'),
                Text(
                  dateText(item['createdAt']),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        if (data is Map && (page > 1 || data['hasMore'] == true))
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: page > 1 ? () => setState(() => page--) : null,
                child: const Text('Trang trước'),
              ),
              Text('Trang $page'),
              TextButton(
                onPressed: data['hasMore'] == true
                    ? () => setState(() => page++)
                    : null,
                child: const Text('Trang sau'),
              ),
            ],
          ),
      ],
    ),
  );
}

class TaskHistoryPage extends StatefulWidget {
  const TaskHistoryPage(this.api, this.base, {super.key});
  final ApiClient api;
  final String base;
  @override
  State<TaskHistoryPage> createState() => _TaskHistoryPageState();
}

class _TaskHistoryPageState extends State<TaskHistoryPage> {
  int page = 1;
  @override
  Widget build(BuildContext context) => ResourceView(
    title: 'Lịch sử công việc',
    resourceKey: page,
    load: () => widget.api.get('${widget.base}?page=$page'),
    builder: (context, data, state) {
      final detail = objectOf(data);
      final history = itemsOf(detail['history'] ?? []);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (history.isEmpty) const InfoBox('Chưa có lịch sử.'),
          for (final row in history)
            RecordCard(
              title: valueOf(row, 'actorName'),
              subtitle:
                  '${statusText(row['fromStatus'])} → ${statusText(row['toStatus'])}\n${valueOf(row, 'report', '')}\n${dateText(row['createdAt'])}',
            ),
          if (page > 1 || detail['hasMore'] == true)
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: page > 1 ? () => setState(() => page--) : null,
                  child: const Text('Trang trước'),
                ),
                Text('Trang $page'),
                TextButton(
                  onPressed: detail['hasMore'] == true
                      ? () => setState(() => page++)
                      : null,
                  child: const Text('Trang sau'),
                ),
              ],
            ),
        ],
      );
    },
  );
}

class RepairReadinessPanel extends StatefulWidget {
  const RepairReadinessPanel(this.api, this.taskId, {super.key});
  final ApiClient api;
  final String taskId;
  @override
  State<RepairReadinessPanel> createState() => _RepairReadinessPanelState();
}

class _RepairReadinessPanelState extends State<RepairReadinessPanel>
    with WidgetsBindingObserver {
  Json? readiness;
  String? error;
  bool loading = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(read());
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          ModalRoute.of(context)?.isCurrent == true) {
        unawaited(read());
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true) {
      unawaited(read());
    }
  }

  Future<void> read() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final value = objectOf(
        await widget.api.get(
          '/api/staff/tasks/${widget.taskId}/repair-readiness',
        ),
      );
      if (mounted) {
        setState(() {
          readiness = value;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          readiness = null;
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Điều kiện gửi báo cáo',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red))
          else if (readiness == null)
            const Text('Đang kiểm tra…')
          else
            InfoBox(
              valueOf(
                readiness!,
                'detail',
                readiness!['code'] == null
                    ? 'Đủ điều kiện gửi báo cáo.'
                    : 'Chưa đủ điều kiện gửi báo cáo.',
              ),
              warning: readiness!['code'] != null,
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: loading ? null : read,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Kiểm tra lại'),
            ),
          ),
        ],
      ),
    ),
  );
}

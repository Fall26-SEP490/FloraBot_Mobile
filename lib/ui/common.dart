import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api.dart';
import '../core/models.dart';

const forest = Color(0xFF174C3C);
const paper = Color(0xFFFAF8F1);
String money(dynamic amount) =>
    '${NumberFormat.decimalPattern('vi').format(num.tryParse('$amount') ?? 0)} đ';
String dateText(dynamic value) {
  final date = DateTime.tryParse('$value');
  return date == null
      ? 'Chưa xác định'
      : DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());
}

void message(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
}

Future<void> openSafeLink(String value) async {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const ApiError(400, 'Liên kết không hợp lệ.');
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw const ApiError(0, 'Không mở được liên kết.');
  }
}

Future<void> navigateAddress(String address) => openSafeLink(
  'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
);

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final dynamic status;
  @override
  Widget build(BuildContext context) => Chip(
    label: Text(
      statusText(status),
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
    backgroundColor: const Color(0xFFE9F1E8),
    side: BorderSide.none,
    padding: const EdgeInsets.symmetric(horizontal: 3),
  );
}

class InfoBox extends StatelessWidget {
  const InfoBox(this.text, {this.warning = false, super.key});
  final String text;
  final bool warning;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFFFF2D7) : const Color(0xFFEAF1E7),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(text, style: const TextStyle(height: 1.5)),
  );
}

class RecordCard extends StatelessWidget {
  const RecordCard({
    required this.title,
    this.subtitle,
    this.status,
    this.onTap,
    this.trailing,
    super.key,
  });
  final String title;
  final String? subtitle;
  final dynamic status;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
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
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 7),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: Color(0xFF617568),
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (status != null) StatusChip(status),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
}

class PageTitle extends StatelessWidget {
  const PageTitle(this.title, this.subtitle, {super.key});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: forest,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF617568), height: 1.5),
        ),
      ],
    ),
  );
}

class ResourceView extends StatefulWidget {
  const ResourceView({
    required this.load,
    required this.builder,
    this.resourceKey,
    this.title,
    super.key,
  });
  final Future<dynamic> Function() load;
  final Widget Function(BuildContext, dynamic, ResourceViewState) builder;
  final Object? resourceKey;
  final String? title;
  @override
  State<ResourceView> createState() => ResourceViewState();
}

class ResourceViewState extends State<ResourceView> {
  late Future<dynamic> future;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    future = widget.load();
  }

  @override
  void didUpdateWidget(ResourceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resourceKey != widget.resourceKey) future = widget.load();
  }

  Future<void> reload() async {
    if (!mounted) return;
    setState(() => future = widget.load());
    try {
      await future;
    } catch (_) {
      /* Render the error, with explicit retry. */
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (mounted) await reload();
    } catch (e) {
      if (mounted) {
        message(context, '$e');
        if (e is ApiError && (e.ambiguous || e.status == 409)) await reload();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<dynamic>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.cloud_off_rounded, size: 52, color: forest),
              const SizedBox(height: 20),
              Text('${snapshot.error}', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Tải lại'),
              ),
            ],
          );
        }
        return RefreshIndicator(
          onRefresh: reload,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (busy) const LinearProgressIndicator(),
                widget.builder(context, snapshot.data, this),
                const SizedBox(height: 16),
                Text(
                  'Dữ liệu từ máy chủ • Kéo xuống để cập nhật',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
    return widget.title == null
        ? body
        : Scaffold(
            appBar: AppBar(title: Text(widget.title!)),
            body: body,
          );
  }
}

class ApiListPage extends StatefulWidget {
  const ApiListPage({
    required this.api,
    required this.path,
    required this.title,
    required this.subtitle,
    required this.item,
    this.actions = const [],
    super.key,
  });
  final ApiClient api;
  final String path, title, subtitle;
  final Widget Function(BuildContext, Json, ResourceViewState) item;
  final List<Widget> actions;
  @override
  State<ApiListPage> createState() => _ApiListPageState();
}

class _ApiListPageState extends State<ApiListPage> {
  int page = 1;
  @override
  void didUpdateWidget(ApiListPage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) page = 1;
  }

  @override
  Widget build(BuildContext context) => ResourceView(
    resourceKey: '${widget.path}:$page',
    load: () => widget.api.get(
      '${widget.path}${widget.path.contains('?') ? '&' : '?'}page=$page',
    ),
    builder: (context, data, state) {
      final items = itemsOf(data);
      final hasMore = data is Map && data['hasMore'] == true;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageTitle(widget.title, widget.subtitle),
          ...widget.actions,
          if (items.isEmpty)
            const InfoBox('Chưa có dữ liệu trong danh sách này.'),
          ...items.map(
            (row) => widget.item(context, {...row, '_mobilePage': page}, state),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: page > 1 && !state.busy
                    ? () => setState(() => page--)
                    : null,
                child: const Text('Trang trước'),
              ),
              Text('$page'),
              TextButton(
                onPressed: hasMore && !state.busy
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

class InputSpec {
  const InputSpec(
    this.key,
    this.label, {
    this.initial = '',
    this.required = true,
    this.lines = 1,
    this.secret = false,
    this.numeric = false,
    this.choices,
    this.minLength = 1,
  });
  final String key, label, initial;
  final bool required, secret, numeric;
  final int lines, minLength;
  final Map<String, String>? choices;
}

Future<Map<String, String>?> askForm(
  BuildContext context,
  String title,
  List<InputSpec> fields, {
  String submitLabel = 'Xác nhận',
  String? description,
}) => showModalBottomSheet<Map<String, String>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _InputSheet(title, fields, submitLabel, description),
);

class _InputSheet extends StatefulWidget {
  const _InputSheet(
    this.title,
    this.fields,
    this.submitLabel,
    this.description,
  );
  final String title, submitLabel;
  final String? description;
  final List<InputSpec> fields;
  @override
  State<_InputSheet> createState() => _InputSheetState();
}

class _InputSheetState extends State<_InputSheet> {
  final key = GlobalKey<FormState>();
  late final controllers = {
    for (final f in widget.fields)
      f.key: TextEditingController(text: f.initial),
  };
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      24,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Form(
        key: key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            if (widget.description != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(widget.description!),
              ),
            for (final f in widget.fields)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: f.choices != null
                    ? DropdownButtonFormField<String>(
                        initialValue: f.choices!.containsKey(f.initial)
                            ? f.initial
                            : null,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: f.label),
                        items: f.choices!.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => controllers[f.key]!.text = v ?? '',
                        validator: (v) => f.required && (v == null || v.isEmpty)
                            ? 'Vui lòng chọn ${f.label.toLowerCase()}.'
                            : null,
                      )
                    : TextFormField(
                        controller: controllers[f.key],
                        obscureText: f.secret,
                        autocorrect: !f.secret,
                        enableSuggestions: !f.secret,
                        maxLines: f.secret ? 1 : f.lines,
                        keyboardType: f.numeric
                            ? const TextInputType.numberWithOptions(
                                decimal: true,
                              )
                            : TextInputType.text,
                        decoration: InputDecoration(labelText: f.label),
                        validator: (v) {
                          final text = f.secret ? (v ?? '') : (v ?? '').trim();
                          if (f.required && text.length < f.minLength) {
                            return 'Nhập ít nhất ${f.minLength} ký tự.';
                          }
                          if (text.isNotEmpty &&
                              f.numeric &&
                              num.tryParse(text) == null) {
                            return 'Vui lòng nhập số hợp lệ.';
                          }
                          return null;
                        },
                      ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                if (key.currentState!.validate()) {
                  Navigator.pop(context, {
                    for (final f in widget.fields)
                      f.key: f.secret
                          ? controllers[f.key]!.text
                          : controllers[f.key]!.text.trim(),
                  });
                }
              },
              child: Text(widget.submitLabel),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String detail) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    ) ??
    false;

Future<XFile?> chooseEvidence(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Chụp ảnh'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Chọn từ thư viện'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  return ImagePicker().pickImage(
    source: source,
    imageQuality: 82,
    maxWidth: 2000,
  );
}

Future<void> showAccessCode(BuildContext context, Json access) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OtpDialog(access),
    );

class _OtpDialog extends StatefulWidget {
  const _OtpDialog(this.access);
  final Json access;
  @override
  State<_OtpDialog> createState() => _OtpDialogState();
}

class _OtpDialogState extends State<_OtpDialog> with WidgetsBindingObserver {
  late String code = widget.access['code']?.toString() ?? '';
  late final DateTime? expires = DateTime.tryParse(
    '${widget.access['expiresAt']}',
  );
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          if (expires != null && !expires!.isAfter(DateTime.now())) code = '';
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() => code = '');
    }
  }

  @override
  void dispose() {
    code = '';
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Xác nhận tại kiosk'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          code.isEmpty ? 'Mã đã được ẩn hoặc gửi qua email.' : code,
          style: TextStyle(
            fontSize: code.isEmpty ? 16 : 36,
            fontWeight: FontWeight.w800,
            letterSpacing: code.isEmpty ? 0 : 7,
          ),
        ),
        const SizedBox(height: 16),
        Text('Hạn sử dụng: ${dateText(widget.access['expiresAt'])}'),
        const SizedBox(height: 12),
        const Text(
          'Nhập mã tại đúng kiosk. Mã không đồng nghĩa cửa đã mở. Không chia sẻ mã cho người khác.',
        ),
        if (widget.access['message'] != null)
          Text('${widget.access['message']}'),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Đã hiểu'),
      ),
    ],
  );
}

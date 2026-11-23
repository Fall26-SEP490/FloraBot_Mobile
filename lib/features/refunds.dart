import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';
import 'inventory.dart' show openPage;

String refundStatus(Json item) {
  if (item['status'] == 'PENDING') {
    if (item['submissionStatus'] == 'PENDING_REVIEW' ||
        (item['submission'] is Map &&
            item['submission']['status'] == 'PENDING_REVIEW')) {
      return 'Chờ đối chiếu';
    }
    return item['isApproved'] == true ? 'Chờ chuyển tiền' : 'Chờ duyệt';
  }
  return switch (item['status']) {
    'TRANSFERRED' => 'Đã chuyển tiền',
    'COMPLETED' || 'SUCCEEDED' => 'Hoàn tất',
    'REJECTED' => 'Từ chối',
    'CANCELLED' => 'Đã hủy',
    _ => statusText(item['status']),
  };
}

class _RefundStatus extends StatelessWidget {
  const _RefundStatus(this.item);
  final Json item;
  @override
  Widget build(BuildContext context) {
    final color = switch (item['status']) {
      'CANCELLED' || 'REJECTED' => const Color(0xFFB42318),
      'PENDING' => const Color(0xFF925B0A),
      _ => forest,
    };
    return Text(
      refundStatus(item),
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    );
  }
}

class SellerRefundsPage extends StatelessWidget {
  const SellerRefundsPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;

  @override
  Widget build(BuildContext context) => ApiListPage(
    api: api,
    path: '/api/sellers/${session.sellerId}/refunds',
    title: 'Hoàn tiền trực tiếp',
    subtitle: 'Shop chuyển khoản cho khách và gửi chứng từ đối chiếu.',
    showHeading: false,
    item: (context, item, state) => Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await openPage(
            context,
            'Chi tiết khoản hoàn',
            SellerRefundDetail(api, session, '${item['id']}'),
          );
          if (context.mounted) await state.reload();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusHeading(
                title: const Text(
                  'Đơn hàng',
                  style: TextStyle(fontSize: 12, color: Color(0xFF617568)),
                ),
                status: _RefundStatus(item),
              ),
              const SizedBox(height: 6),
              Text(
                valueOf(item, 'orderCode'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                money(item['amount']),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: forest,
                ),
              ),
              if (item['createdAt'] != null) ...[
                const SizedBox(height: 8),
                Text(
                  dateText(item['createdAt']),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF617568),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class SellerRefundDetail extends StatefulWidget {
  const SellerRefundDetail(this.api, this.session, this.id, {super.key});
  final ApiClient api;
  final Session session;
  final String id;
  @override
  State<SellerRefundDetail> createState() => _SellerRefundDetailState();
}

class _SellerRefundDetailState extends State<SellerRefundDetail>
    with WidgetsBindingObserver {
  final resource = GlobalKey<ResourceViewState>();
  final formKey = GlobalKey<FormState>();
  final reason = TextEditingController();
  final reference = TextEditingController();
  final note = TextEditingController();
  Json? bank;
  Timer? bankTimer;
  DateTime? transferredAt;
  XFile? evidence;
  bool accessing = false, submitting = false;
  int bankEpoch = 0;
  String? error;
  String? notice;
  String get base =>
      '/api/sellers/${widget.session.sellerId}/refunds/${widget.id}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void hideBank() {
    bankEpoch++;
    bankTimer?.cancel();
    if (mounted) setState(() => bank = null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) hideBank();
  }

  @override
  void dispose() {
    bankTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    reason.dispose();
    reference.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> revealBank() async {
    final text = reason.text.trim();
    if (text.length < 5 || text.length > 500) {
      setState(() => error = 'Nhập lý do từ 5 đến 500 ký tự.');
      return;
    }
    final epoch = ++bankEpoch;
    setState(() {
      accessing = true;
      error = null;
    });
    try {
      final result = objectOf(
        await widget.api.post('$base/bank-details', {'reason': text}),
      );
      if (!mounted || epoch != bankEpoch) return;
      setState(() => bank = result);
      bankTimer?.cancel();
      bankTimer = Timer(const Duration(seconds: 60), hideBank);
    } catch (e) {
      if (mounted && epoch == bankEpoch) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => accessing = false);
    }
  }

  Future<void> pickDate() async {
    final now = DateTime.now();
    final first = now.subtract(const Duration(days: 30));
    final date = await showDatePicker(
      context: context,
      initialDate: transferredAt ?? now,
      firstDate: DateUtils.dateOnly(first),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(transferredAt ?? now),
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (selected.isAfter(DateTime.now()) ||
        selected.isBefore(DateTime.now().subtract(const Duration(days: 30)))) {
      setState(
        () => error =
            'Chọn thời gian chuyển trong 30 ngày gần nhất, không ở tương lai.',
      );
      return;
    }
    setState(() {
      transferredAt = selected;
      error = null;
    });
  }

  Future<void> submit(Json item) async {
    if (submitting || !formKey.currentState!.validate()) return;
    final receiver = bank;
    final date = transferredAt;
    final photo = evidence;
    if (receiver == null || date == null || photo == null) {
      setState(
        () => error = receiver == null
            ? 'Mở lại tài khoản nhận hoàn để xác nhận.'
            : date == null
            ? 'Chọn thời gian đã chuyển tiền.'
            : 'Chọn ảnh chứng từ chuyển khoản.',
      );
      return;
    }
    final now = DateTime.now();
    if (date.isAfter(now) ||
        date.isBefore(now.subtract(const Duration(days: 30)))) {
      setState(
        () => error = 'Thời gian chuyển phải nằm trong 30 ngày gần nhất.',
      );
      return;
    }
    setState(() {
      submitting = true;
      error = null;
      notice = null;
    });
    try {
      final confirmed = await confirm(
        context,
        'Xác nhận đã chuyển tiền?',
        '${money(item['amount'])}\n${receiver['bankName']} · ${receiver['holder']}\n${receiver['account']}\nChỉ gửi sau khi đã chuyển khoản đúng thông tin.',
      );
      if (!confirmed || !mounted) return;
      // Sensitive receiver data must still be visible when confirming.
      if (bank == null || bank != receiver) {
        if (mounted) {
          setState(
            () => error = 'Tài khoản đã tự ẩn. Vui lòng mở lại trước khi gửi.',
          );
        }
        return;
      }
      final upload = await widget.api.upload('$base/evidence/upload', photo);
      await widget.api.post('$base/submit-transfer', {
        'amount': item['amount'],
        'currency': 'VND',
        'bankName': receiver['bankName'],
        'bankHolder': receiver['holder'],
        'accountNumber': receiver['account'],
        'providerReference': reference.text.trim(),
        'transferredAt': date.toUtc().toIso8601String(),
        'evidenceTicket': upload['reference'],
        'note': note.text.trim(),
      });
      if (!mounted) return;
      hideBank();
      reference.clear();
      note.clear();
      reason.clear();
      setState(() {
        evidence = null;
        transferredAt = null;
        notice = 'Đã gửi chứng từ. Chờ Admin đối chiếu.';
      });
      await resource.currentState?.reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '$e');
      if (e is ApiError && (e.ambiguous || e.status == 409)) {
        hideBank();
        await resource.currentState?.reload();
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Widget section(List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  Widget heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 16,
        color: forest,
      ),
    ),
  );

  Widget fact(String label, String value, {bool selectable = false}) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF617568)),
        ),
        const SizedBox(height: 4),
        if (selectable)
          SelectableText(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: forest,
            ),
          )
        else
          Text(value, style: const TextStyle(fontSize: 14, height: 1.45)),
      ],
    ),
  );

  Widget fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text.rich(
      TextSpan(
        text: text,
        children: const [
          TextSpan(
            text: ' *',
            style: TextStyle(color: Color(0xFFB42318)),
          ),
        ],
      ),
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
    ),
  );

  @override
  Widget build(BuildContext context) => ResourceView(
    key: resource,
    load: () => widget.api.get(base),
    builder: (context, data, state) {
      final item = objectOf(data);
      final submission = objectOf(item['submission'] ?? <String, dynamic>{});
      final canSend = item['canSubmitTransfer'] == true;
      final canReveal =
          item['canAccessBank'] == true &&
          (submission.isEmpty || submission['status'] == 'REJECTED');
      final pending = item['status'] == 'PENDING';
      final hint = !pending
          ? null
          : item['isApproved'] != true
          ? 'Chờ Admin duyệt khoản hoàn.'
          : submission['status'] == 'PENDING_REVIEW'
          ? 'Đã gửi chứng từ. Chờ Admin đối chiếu.'
          : item['canAccessBank'] != true
          ? 'Khách chưa bổ sung tài khoản nhận hoàn trên biên nhận.'
          : canSend
          ? 'Chuyển khoản cho khách, sau đó gửi chứng từ.'
          : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          section([
            StatusHeading(
              title: const Text(
                'Đơn hàng',
                style: TextStyle(fontSize: 12, color: Color(0xFF617568)),
              ),
              status: _RefundStatus(item),
            ),
            const SizedBox(height: 6),
            SelectableText(
              valueOf(item, 'orderCode'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Text(
              'Số tiền hoàn',
              style: TextStyle(fontSize: 12, color: Color(0xFF617568)),
            ),
            const SizedBox(height: 4),
            Text(
              money(item['amount']),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: forest,
              ),
            ),
            if (item['createdAt'] != null) ...[
              const SizedBox(height: 6),
              Text(
                'Tạo lúc ${dateText(item['createdAt'])}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF617568)),
              ),
            ],
            if (valueOf(item, 'reason', '').isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Lý do hoàn',
                style: TextStyle(fontSize: 12, color: Color(0xFF617568)),
              ),
              const SizedBox(height: 4),
              Text(
                valueOf(item, 'reason', '').replaceFirst(
                  RegExp(r'^AUTO_REFUND:\s*', caseSensitive: false),
                  'Hoàn tự động: ',
                ),
              ),
            ],
            if (hint != null) ...[
              const SizedBox(height: 14),
              Text(
                hint,
                style: const TextStyle(color: Color(0xFF925B0A), height: 1.4),
              ),
            ],
          ]),
          if (submission.isNotEmpty)
            section([
              StatusHeading(
                title: Text(
                  submission['attemptCount'] == null
                      ? 'Chứng từ đã gửi'
                      : 'Chứng từ lần ${submission['attemptCount']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: forest,
                  ),
                ),
                status: Text(
                  switch (submission['status']) {
                    'PENDING_REVIEW' => 'Chờ đối chiếu',
                    'REJECTED' => 'Bị từ chối',
                    'CONFIRMED' => 'Đã đối chiếu',
                    _ => statusText(submission['status']),
                  },
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: switch (submission['status']) {
                      'REJECTED' => const Color(0xFFB42318),
                      'PENDING_REVIEW' => const Color(0xFF925B0A),
                      _ => forest,
                    },
                  ),
                ),
              ),
              fact(
                'Mã giao dịch',
                valueOf(submission, 'providerReference'),
                selectable: true,
              ),
              if (submission['transferredAt'] != null)
                fact('Thời gian chuyển', dateText(submission['transferredAt'])),
              if (valueOf(submission, 'note', '').isNotEmpty)
                fact('Ghi chú', valueOf(submission, 'note')),
              if (valueOf(submission, 'reviewReason', '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Lý do từ chối: ${submission['reviewReason']}',
                  style: const TextStyle(color: Color(0xFFB42318)),
                ),
              ],
            ]),
          if (canReveal)
            section([
              heading('Tài khoản nhận hoàn của khách'),
              if (bank == null) ...[
                fieldLabel('Lý do truy cập'),
                TextField(
                  controller: reason,
                  enabled: !accessing && !submitting,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    hintText: 'Đối chiếu tài khoản để hoàn tiền',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: accessing || submitting ? null : revealBank,
                  icon: accessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Xem tài khoản nhận hoàn'),
                ),
              ] else ...[
                const Text(
                  'Ngân hàng',
                  style: TextStyle(fontSize: 12, color: Color(0xFF617568)),
                ),
                SelectableText(
                  valueOf(bank!, 'bankName'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Chủ tài khoản',
                  style: TextStyle(fontSize: 12, color: Color(0xFF617568)),
                ),
                SelectableText(
                  valueOf(bank!, 'holder'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Số tài khoản',
                  style: TextStyle(fontSize: 12, color: Color(0xFF617568)),
                ),
                SelectableText(
                  valueOf(bank!, 'account'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: forest,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Tự ẩn sau 60 giây hoặc khi rời ứng dụng.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF617568)),
                ),
              ],
            ]),
          if (canSend)
            section([
              heading(
                submission['status'] == 'REJECTED'
                    ? 'Gửi lại chứng từ'
                    : 'Xác nhận đã chuyển tiền',
              ),
              Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    fieldLabel('Mã giao dịch ngân hàng'),
                    TextFormField(
                      controller: reference,
                      enabled: !submitting,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        hintText: 'Nhập mã trên chứng từ',
                        counterText: '',
                      ),
                      validator: (v) => (v ?? '').trim().length < 3
                          ? 'Nhập mã giao dịch từ 3 đến 100 ký tự.'
                          : null,
                    ),
                    fieldLabel('Thời gian chuyển'),
                    OutlinedButton.icon(
                      onPressed: submitting ? null : pickDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Text(
                        transferredAt == null
                            ? 'Chọn ngày và giờ'
                            : dateText(transferredAt!.toIso8601String()),
                      ),
                    ),
                    fieldLabel('Ảnh chứng từ'),
                    OutlinedButton.icon(
                      onPressed: submitting
                          ? null
                          : () async {
                              try {
                                final photo = await chooseEvidence(context);
                                if (mounted && photo != null) {
                                  setState(() => evidence = photo);
                                }
                              } catch (e) {
                                if (mounted) setState(() => error = '$e');
                              }
                            },
                      icon: Icon(
                        evidence == null
                            ? Icons.add_photo_alternate_outlined
                            : Icons.check_circle_outline,
                        size: 18,
                      ),
                      label: Text(
                        evidence == null
                            ? 'Chọn ảnh chứng từ'
                            : 'Đã chọn ảnh · Chọn lại',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: note,
                      enabled: !submitting,
                      maxLines: 2,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Ghi chú',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: submitting || bank == null
                          ? null
                          : () => submit(item),
                      child: Text(
                        submitting
                            ? 'Đang gửi chứng từ…'
                            : 'Gửi chứng từ chuyển khoản',
                      ),
                    ),
                    if (bank == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Xem tài khoản nhận hoàn trước khi gửi.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF617568),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ]),
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
      );
    },
  );
}

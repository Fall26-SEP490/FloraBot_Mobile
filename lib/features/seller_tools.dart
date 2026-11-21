import 'inventory.dart' show integerInput, openPage;
import 'chat.dart' show PrivateImage;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';

class AccessoriesPage extends StatelessWidget {
  const AccessoriesPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  String get base => '/api/sellers/${session.sellerId}/accessories';
  Future<void> edit(BuildContext context, Json? item) async {
    final form =
        await askForm(context, item == null ? 'Tạo phụ kiện' : 'Sửa phụ kiện', [
          InputSpec(
            'name',
            'Tên phụ kiện',
            initial: item?['name'] ?? '',
            minLength: 2,
          ),
          InputSpec(
            'price',
            'Giá (đồng)',
            initial: '${item?['price'] ?? ''}',
            numeric: true,
          ),
        ]);
    if (form == null) return;
    final body = {'name': form['name'], 'price': integerInput(form['price'])};
    if (item == null) {
      await api.post(base, body);
    } else {
      await api.put('$base/${item['id']}', body);
    }
  }

  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => api.get('$base?scope=SHOP'),
    builder: (context, data, state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageTitle(
          'Phụ kiện',
          'Kho phụ kiện dùng chung cho đơn đặt trước.',
        ),
        FilledButton(
          onPressed: state.busy
              ? null
              : () => state.run(() => edit(context, null)),
          child: const Text('Tạo phụ kiện'),
        ),
        for (final item in itemsOf(data))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item['name']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${money(item['price'])} · Tồn: ${item['stockQuantity']}',
                  ),
                  StatusChip(item['status']),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: state.busy
                            ? null
                            : () => state.run(() => edit(context, item)),
                        child: const Text('Sửa'),
                      ),
                      TextButton(
                        onPressed: state.busy
                            ? null
                            : () => state.run(() async {
                                final form =
                                    await askForm(context, 'Nhập kho', [
                                      const InputSpec(
                                        'quantity',
                                        'Số lượng thêm',
                                        numeric: true,
                                      ),
                                    ]);
                                if (form != null) {
                                  await api.post(
                                    '/api/sellers/${session.sellerId}/flows/restock_accessory',
                                    {
                                      'p_accessory': item['id'],
                                      'p_qty': integerInput(form['quantity']),
                                    },
                                  );
                                }
                              }),
                        child: const Text('Nhập kho'),
                      ),
                      TextButton(
                        onPressed: state.busy
                            ? null
                            : () => state.run(() async {
                                final next = item['status'] == 'ACTIVE'
                                    ? 'INACTIVE'
                                    : 'ACTIVE';
                                if (await confirm(
                                  context,
                                  'Đổi trạng thái phụ kiện?',
                                  next == 'ACTIVE'
                                      ? 'Bật bán phụ kiện này.'
                                      : 'Dừng bán phụ kiện này.',
                                )) {
                                  await api.request(
                                    'PATCH',
                                    '$base/${item['id']}/status',
                                    body: {'status': next},
                                  );
                                }
                              }),
                        child: Text(
                          item['status'] == 'ACTIVE' ? 'Dừng bán' : 'Bật bán',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class PaymentChannelPage extends StatelessWidget {
  const PaymentChannelPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  String get base => '/api/sellers/${session.sellerId}/payment-channel';
  @override
  Widget build(BuildContext context) => ResourceView(
    load: () async {
      try {
        return await api.get(base);
      } on ApiError catch (e) {
        if (e.status == 404) return <String, dynamic>{};
        rethrow;
      }
    },
    builder: (context, data, state) {
      final item = objectOf(data);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageTitle(
            'Kênh thanh toán',
            'Cấu hình và xác minh kênh nhận tiền của shop.',
          ),
          StatusChip(item['state']),
          Text(
            '${item['expectedBankName'] ?? ''} · ${item['expectedBankAccountMasked'] ?? ''}',
          ),
          Text('Xác minh: ${dateText(item['verifiedAt'])}'),
          const InfoBox(
            'Quản trị viên gắn cấu hình kênh payOS. Shop có thể xác minh, tạm dừng hoặc bật lại kênh đã được cấu hình.',
          ),
          OutlinedButton(
            onPressed: state.busy
                ? null
                : () => state.run(() async {
                    final result = objectOf(await api.post('$base/verify'));
                    if (context.mounted) {
                      message(context, valueOf(result, 'message'));
                    }
                  }),
            child: const Text('Xác minh kênh'),
          ),
          if (item.isNotEmpty)
            OutlinedButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final next = item['state'] == 'ACTIVE'
                          ? 'PAUSED'
                          : 'ACTIVE';
                      if (await confirm(
                        context,
                        'Đổi trạng thái kênh?',
                        next == 'PAUSED'
                            ? 'Tạm dừng nhận thanh toán mới qua kênh này.'
                            : 'Bật lại kênh thanh toán đã xác minh.',
                      )) {
                        await api.request(
                          'PATCH',
                          '$base/status',
                          body: {'status': next},
                        );
                      }
                    }),
              child: Text(
                item['state'] == 'ACTIVE' ? 'Tạm dừng kênh' : 'Bật lại kênh',
              ),
            ),
        ],
      );
    },
  );
}

class TerminationsPage extends StatelessWidget {
  const TerminationsPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  Widget build(BuildContext context) => ApiListPage(
    api: api,
    path: '/api/sellers/${session.sellerId}/kiosks',
    title: 'Chấm dứt thuê kiosk',
    subtitle: 'Chọn kiosk để xem hoặc gửi yêu cầu.',
    item: (context, item, state) => RecordCard(
      title: valueOf(item, 'name'),
      subtitle: valueOf(item, 'code'),
      onTap: () => openPage(
        context,
        'Chấm dứt thuê',
        TerminationDetail(api, session, item),
      ),
    ),
  );
}

class TerminationDetail extends StatelessWidget {
  const TerminationDetail(this.api, this.session, this.kiosk, {super.key});
  final ApiClient api;
  final Session session;
  final Json kiosk;
  String get base =>
      '/api/sellers/${session.sellerId}/kiosks/${kiosk['id']}/termination-requests';
  Future<dynamic> load() async {
    try {
      return await api.get('$base/current');
    } on ApiError catch (e) {
      if (e.status == 404) return <String, dynamic>{};
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => ResourceView(
    load: load,
    builder: (context, data, state) {
      final item = objectOf(data);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageTitle(
            valueOf(kiosk, 'name'),
            'Yêu cầu được quản lý vận hành xét duyệt.',
          ),
          if (item.isNotEmpty) ...[
            StatusChip(item['status']),
            Text(valueOf(item, 'reason')),
            Text(valueOf(item, 'reviewReason', '')),
            Text('Tiến độ: ${item['lifecycleStatus'] ?? ''}'),
          ],
          if (item.isEmpty ||
              ['CANCELLED', 'REJECTED', 'COMPLETED'].contains(item['status']))
            FilledButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final form = await askForm(context, 'Yêu cầu chấm dứt', [
                        const InputSpec(
                          'reason',
                          'Lý do',
                          minLength: 10,
                          lines: 4,
                        ),
                      ]);
                      if (form == null || !context.mounted) return;
                      if (await confirm(
                        context,
                        'Gửi yêu cầu chấm dứt thuê?',
                        'Yêu cầu áp dụng cho ${kiosk['name']}. Quản lý sẽ xét duyệt trước khi bàn giao.',
                      )) {
                        await api.post(base, {'reason': form['reason']});
                      }
                    }),
              child: const Text('Gửi yêu cầu'),
            ),
          if (item['status'] == 'REQUESTED')
            OutlinedButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final form = await askForm(context, 'Rút yêu cầu', [
                        const InputSpec(
                          'reason',
                          'Lý do rút',
                          minLength: 10,
                          lines: 3,
                        ),
                      ]);
                      if (form != null) {
                        await api.post('$base/${item['id']}/withdraw', {
                          'version': item['version'],
                          'reason': form['reason'],
                        });
                      }
                    }),
              child: const Text('Rút yêu cầu'),
            ),
        ],
      );
    },
  );
}

class ComplaintsPage extends StatelessWidget {
  const ComplaintsPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  Widget build(BuildContext context) => ApiListPage(
    api: api,
    path: '/api/me/complaints',
    title: 'Phản ánh chất lượng',
    subtitle: 'Tiếp nhận và xử lý phản ánh của khách.',
    item: (context, item, state) => RecordCard(
      title: valueOf(item, 'orderCode'),
      subtitle: valueOf(item, 'reason'),
      status: item['status'],
      onTap: () => openPage(
        context,
        'Phản ánh',
        ComplaintDetail(api, session, '${item['id']}'),
      ),
    ),
  );
}

class ComplaintDetail extends StatelessWidget {
  const ComplaintDetail(this.api, this.session, this.id, {super.key});
  final ApiClient api;
  final Session session;
  final String id;
  String get base => '/api/me/complaints/$id';
  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => api.get(base),
    builder: (context, data, state) {
      final item = objectOf(data),
          task = objectOf(item['task'] ?? <String, dynamic>{});
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageTitle('Đơn ${item['orderCode']}', valueOf(item, 'reason')),
          StatusChip(item['status']),
          if (item['resolution'] != null) InfoBox('${item['resolution']}'),
          for (final photo in itemsOf(item['evidence']))
            PrivateImage(api, '${photo['url']}'),
          if (item['status'] == 'REPORTED')
            FilledButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      await api.post('$base/accept', {
                        'version': item['version'],
                      });
                    }),
              child: const Text('Tiếp nhận'),
            ),
          OutlinedButton(
            onPressed: state.busy
                ? null
                : () => state.run(() async {
                    final staff = itemsOf(
                      await api.get('/api/sellers/${session.sellerId}/staff'),
                    );
                    if (!context.mounted) return;
                    final form = await askForm(context, 'Giao việc kiểm tra', [
                      InputSpec(
                        'assigneeId',
                        'Nhân viên',
                        choices: {
                          for (final s in staff)
                            '${s['staffId']}': valueOf(s, 'name'),
                        },
                      ),
                      InputSpec(
                        'orderItemId',
                        'Mặt hàng',
                        choices: {
                          for (final s in itemsOf(item['items']))
                            '${s['orderItemId']}': valueOf(s, 'name'),
                        },
                      ),
                      const InputSpec(
                        'instructions',
                        'Hướng dẫn',
                        minLength: 10,
                        lines: 3,
                      ),
                    ]);
                    if (form != null) {
                      await api.post('$base/assignment', {
                        'version': item['version'],
                        'taskId': const Uuid().v4(),
                        ...form,
                      });
                    }
                  }),
            child: const Text('Giao nhân viên kiểm tra'),
          ),
          if (task.isNotEmpty) ...[
            InfoBox('Công việc: ${task['status']}\n${task['report'] ?? ''}'),
            OutlinedButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final products = itemsOf(
                        await api.get('/api/me/products'),
                      );
                      final slots = itemsOf(
                        await api.get(
                          '/api/me/kiosks/${item['kioskId']}/slots',
                        ),
                      );
                      if (!context.mounted) return;
                      final form = await askForm(
                        context,
                        'Phương án thay hoa',
                        [
                          InputSpec(
                            'productId',
                            'Mẫu hoa',
                            choices: {
                              for (final p in products)
                                '${p['id']}': valueOf(p, 'name'),
                            },
                          ),
                          InputSpec(
                            'slotId',
                            'Ô tủ',
                            choices: {
                              for (final s in slots)
                                '${s['id']}': valueOf(s, 'slotCode'),
                            },
                          ),
                        ],
                      );
                      if (form != null) {
                        await api.post('$base/replacement-plan', {
                          'version': item['version'],
                          'taskVersion': task['version'],
                          ...form,
                        });
                      }
                    }),
              child: const Text('Lập phương án thay hoa'),
            ),
            FilledButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final form = await askForm(
                        context,
                        'Duyệt kết quả xử lý',
                        [
                          const InputSpec(
                            'outcome',
                            'Kết quả',
                            choices: {
                              'RETURN': 'Yêu cầu làm lại',
                              'EXPLANATION': 'Giải thích',
                              'REPLACEMENT': 'Duyệt thay hoa',
                              'REFUND_REVIEW': 'Chuyển xét hoàn tiền',
                            },
                          ),
                          const InputSpec(
                            'resolution',
                            'Nội dung xử lý',
                            minLength: 10,
                            lines: 4,
                          ),
                        ],
                      );
                      if (form != null) {
                        await api.post('$base/review', {
                          'version': item['version'],
                          'taskVersion': task['version'],
                          ...form,
                        });
                      }
                    }),
              child: const Text('Duyệt báo cáo'),
            ),
          ],
          if (item['replacement'] != null)
            OutlinedButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final form = await askForm(
                        context,
                        'Hủy phương án thay hoa',
                        [
                          const InputSpec(
                            'reason',
                            'Lý do',
                            minLength: 10,
                            lines: 3,
                          ),
                        ],
                      );
                      if (form != null) {
                        await api.post('$base/replacement/cancel', {
                          'version': item['version'],
                          'reason': form['reason'],
                        });
                      }
                    }),
              child: const Text('Hủy phương án thay hoa'),
            ),
        ],
      );
    },
  );
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
    subtitle: 'Gửi chứng từ cho khoản đã được duyệt.',
    item: (context, item, state) => RecordCard(
      title: valueOf(item, 'orderCode'),
      subtitle: money(item['amount']),
      status: item['status'],
      onTap: () => openPage(
        context,
        'Khoản hoàn',
        SellerRefundDetail(api, session, '${item['id']}'),
      ),
    ),
  );
}

class SellerRefundDetail extends StatelessWidget {
  const SellerRefundDetail(this.api, this.session, this.id, {super.key});
  final ApiClient api;
  final Session session;
  final String id;
  String get base => '/api/sellers/${session.sellerId}/refunds/$id';
  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => api.get(base),
    builder: (context, data, state) {
      final item = objectOf(data),
          submission = objectOf(item['submission'] ?? <String, dynamic>{});
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageTitle('Đơn ${item['orderCode']}', money(item['amount'])),
          StatusChip(item['status']),
          Text(valueOf(item, 'reason', '')),
          if (submission.isNotEmpty)
            InfoBox(
              'Chứng từ: ${submission['status']}\n${submission['reviewReason'] ?? ''}',
            ),
          if (item['canAccessBank'] == true)
            OutlinedButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final form =
                          await askForm(context, 'Xem tài khoản nhận hoàn', [
                            const InputSpec(
                              'reason',
                              'Lý do truy cập',
                              minLength: 10,
                              lines: 3,
                            ),
                          ]);
                      if (form == null) return;
                      final bank = objectOf(
                        await api.post('$base/bank-details', {
                          'reason': form['reason'],
                        }),
                      );
                      if (!context.mounted) return;
                      await showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Tài khoản nhận hoàn'),
                          content: Text(
                            '${bank['bankName']}\n${bank['holder']}\n${bank['account']}',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Đóng'),
                            ),
                          ],
                        ),
                      );
                    }),
              child: const Text('Xem tài khoản nhận hoàn'),
            ),
          if (item['canSubmitTransfer'] == true)
            FilledButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final form = await askForm(
                        context,
                        'Gửi chứng từ đã chuyển tiền',
                        [
                          const InputSpec(
                            'reason',
                            'Lý do truy cập tài khoản',
                            minLength: 10,
                          ),
                          const InputSpec(
                            'providerReference',
                            'Mã giao dịch ngân hàng',
                            minLength: 3,
                          ),
                          const InputSpec(
                            'note',
                            'Ghi chú',
                            required: false,
                            lines: 3,
                          ),
                        ],
                      );
                      if (form == null || !context.mounted) return;
                      final bank = objectOf(
                        await api.post('$base/bank-details', {
                          'reason': form['reason'],
                        }),
                      );
                      if (!context.mounted) return;
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date == null || !context.mounted) return;
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (time == null || !context.mounted) return;
                      final transferredAt = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                      if (transferredAt.isAfter(DateTime.now())) {
                        throw const ApiError(
                          400,
                          'Thời gian chuyển không được ở tương lai.',
                        );
                      }
                      final photo = await chooseEvidence(context);
                      if (photo == null || !context.mounted) return;
                      if (!await confirm(
                        context,
                        'Gửi xác nhận đã chuyển tiền?',
                        '${money(item['amount'])}\n${bank['bankName']} · ${bank['holder']}\n${bank['account']}\nChỉ xác nhận sau khi bạn đã chuyển khoản đúng thông tin.',
                      )) {
                        return;
                      }
                      final upload = await api.upload(
                        '$base/evidence/upload',
                        photo,
                      );
                      await api.post('$base/submit-transfer', {
                        'amount': item['amount'],
                        'currency': 'VND',
                        'bankName': bank['bankName'],
                        'bankHolder': bank['holder'],
                        'accountNumber': bank['account'],
                        'providerReference': form['providerReference'],
                        'transferredAt': transferredAt
                            .toUtc()
                            .toIso8601String(),
                        'evidenceTicket': upload['reference'],
                        'note': form['note'],
                      });
                    }),
              child: const Text('Gửi chứng từ chuyển khoản'),
            ),
        ],
      );
    },
  );
}

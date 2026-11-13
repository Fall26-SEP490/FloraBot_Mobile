import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/auth.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../ui/common.dart';
import 'auth_screens.dart';
import 'inventory.dart';
import 'tasks.dart';

class AccountPage extends StatelessWidget {
  const AccountPage(this.auth, this.session, {super.key});
  final AuthController auth;
  final Session session;
  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => auth.api.get('/api/account/profile'),
    builder: (context, data, state) {
      final row = objectOf(data), api = auth.api;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageTitle(valueOf(row, 'fullName'), session.role.label),
          RecordCard(
            title: 'Email đăng nhập',
            subtitle: valueOf(row, 'loginEmail'),
          ),
          RecordCard(
            title: 'Liên hệ',
            subtitle: '${valueOf(row, 'phone')}\n${valueOf(row, 'address')}',
          ),
          if (row['contactEmail'] != null)
            InfoBox(
              'Email liên hệ: ${row['contactEmail']}\nOTP nhận hoa vẫn gửi đến EMAIL ĐĂNG NHẬP.',
            ),
          OutlinedButton.icon(
            onPressed: state.busy
                ? null
                : () => state.run(() async {
                    final form = await askForm(context, 'Thông tin cá nhân', [
                      InputSpec(
                        'fullName',
                        'Họ tên',
                        initial: valueOf(row, 'fullName', ''),
                        minLength: 2,
                      ),
                      InputSpec(
                        'phone',
                        'Số điện thoại',
                        initial: valueOf(row, 'phone', ''),
                        required: false,
                      ),
                      InputSpec(
                        'address',
                        'Địa chỉ',
                        initial: valueOf(row, 'address', ''),
                        required: false,
                        lines: 3,
                      ),
                    ]);
                    if (form == null) return;
                    await api.put('/api/account/profile', form);
                    await auth.revalidate();
                    if (context.mounted) message(context, 'Đã lưu hồ sơ.');
                  }),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Sửa hồ sơ cá nhân'),
          ),
          OutlinedButton(
            onPressed: state.busy
                ? null
                : () => state.run(() async {
                    final email = await askForm(context, 'Email liên hệ', [
                      const InputSpec('email', 'Email mới'),
                    ]);
                    if (email == null) return;
                    if (!validEmail(email['email']!)) {
                      throw const ApiError(400, 'Email chưa hợp lệ.');
                    }
                    final sent = objectOf(
                      await api.post('/api/account/contact-email', email),
                    );
                    if (!context.mounted) return;
                    final code = await askForm(
                      context,
                      'Xác minh email liên hệ',
                      [
                        const InputSpec(
                          'code',
                          'Mã gửi qua email',
                          minLength: 6,
                        ),
                      ],
                    );
                    if (code != null) {
                      await api.post('/api/account/contact-email/verify', {
                        'challengeId': sent['challengeId'],
                        'code': code['code'],
                      });
                    }
                  }),
            child: const Text('Xác minh email liên hệ'),
          ),
          OutlinedButton.icon(
            onPressed: state.busy
                ? null
                : () => state.run(() async {
                    final form = await askForm(
                      context,
                      'Đổi mật khẩu',
                      [
                        const InputSpec(
                          'currentPassword',
                          'Mật khẩu hiện tại',
                          secret: true,
                        ),
                        const InputSpec(
                          'newPassword',
                          'Mật khẩu mới',
                          secret: true,
                          minLength: 12,
                        ),
                        const InputSpec(
                          'repeat',
                          'Nhập lại mật khẩu mới',
                          secret: true,
                          minLength: 12,
                        ),
                      ],
                      description:
                          'Đổi mật khẩu sẽ yêu cầu đăng nhập lại trên các phiên cũ.',
                    );
                    if (form == null) return;
                    if (!validPassword(form['newPassword']!) ||
                        form['newPassword'] != form['repeat']) {
                      throw const ApiError(
                        400,
                        'Mật khẩu mới cần ít nhất 12 ký tự, tối đa 72 byte UTF-8 và khớp ô xác nhận.',
                      );
                    }
                    await api.post('/api/mobile/auth/password', {
                      'currentPassword': form['currentPassword'],
                      'newPassword': form['newPassword'],
                    });
                    await auth.logout();
                  }),
            icon: const Icon(Icons.password_outlined),
            label: const Text('Đổi mật khẩu'),
          ),
          if (session.role == AppRole.seller) ...[
            const Divider(height: 32),
            const Text(
              'Vận hành shop',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            ListTile(
              leading: const Icon(Icons.local_florist_outlined),
              title: const Text('Mẫu hoa và tồn tại shop'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  openPage(context, 'Mẫu hoa', ProductsPage(api, session)),
            ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Nhân viên shop'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openPage(
                context,
                'Nhân viên',
                StaffManagementPage(api, session),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.assignment_outlined),
              title: const Text('Việc của nhân viên'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  openPage(context, 'Công việc', TasksPage(api, session)),
            ),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('Duyệt quyền sửa ô'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  openPage(context, 'Quyền sửa ô', RepairApprovalsPage(api)),
            ),
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Thông tin shop'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  openPage(context, 'Hồ sơ shop', ShopProfilePage(api)),
            ),
            ListTile(
              leading: const Icon(Icons.insights),
              title: const Text('Doanh số và dự báo'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  openPage(context, 'Doanh số', InsightsPage(api, session)),
            ),
            ListTile(
              leading: const Icon(Icons.event_repeat),
              title: const Text('Kỳ thuê và gia hạn kiosk'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openPage(
                context,
                'Thuê kiosk',
                SubscriptionsPage(api, session),
              ),
            ),
          ],
          const Divider(height: 32),
          OutlinedButton.icon(
            onPressed: state.busy
                ? null
                : () async {
                    try {
                      if (await confirm(
                        context,
                        'Đăng xuất?',
                        'Mã thao tác và dữ liệu trong phiên sẽ được xóa khỏi app.',
                      )) {
                        await auth.logout();
                      }
                    } catch (e) {
                      if (context.mounted) message(context, '$e');
                    }
                  },
            icon: const Icon(Icons.logout),
            label: const Text('Đăng xuất'),
          ),
          if (session.role == AppRole.customer)
            TextButton(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      if (!await confirm(
                        context,
                        'Đóng tài khoản?',
                        'Thông tin định danh sẽ được xử lý theo chính sách. Lịch sử giao dịch cần thiết vẫn được giữ. Thao tác này chấm dứt quyền đăng nhập.',
                      )) {
                        return;
                      }
                      if (!context.mounted) return;
                      final form =
                          await askForm(context, 'Xác nhận đóng tài khoản', [
                            const InputSpec(
                              'password',
                              'Mật khẩu hiện tại',
                              secret: true,
                            ),
                          ]);
                      if (form != null) {
                        await api.post('/api/account/close', form);
                        await auth.logout();
                      }
                    }),
              child: const Text('Yêu cầu đóng tài khoản'),
            ),
          const InfoBox(
            'Phiên đăng nhập và quyền được máy chủ kiểm tra lại. App không lưu mật khẩu, OTP mở ô hoặc API key của kiosk.',
          ),
        ],
      );
    },
  );
}

class ShopProfilePage extends StatelessWidget {
  const ShopProfilePage(this.api, {super.key});
  final ApiClient api;
  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => api.get('/api/me/shop'),
    builder: (context, data, state) {
      final row = objectOf(data);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageTitle(valueOf(row, 'shopName'), 'Thông tin chung của shop'),
          StatusChip(row['status']),
          InfoBox(
            '${valueOf(row, 'phone')}\n${valueOf(row, 'contactEmail')}\n${valueOf(row, 'address')}',
          ),
          FilledButton(
            onPressed: state.busy
                ? null
                : () => state.run(() async {
                    final form = await askForm(context, 'Sửa thông tin shop', [
                      InputSpec(
                        'shopName',
                        'Tên shop',
                        initial: valueOf(row, 'shopName', ''),
                        minLength: 2,
                      ),
                      InputSpec(
                        'phone',
                        'Điện thoại',
                        initial: valueOf(row, 'phone', ''),
                      ),
                      InputSpec(
                        'contactEmail',
                        'Email liên hệ',
                        initial: valueOf(row, 'contactEmail', ''),
                        required: false,
                      ),
                    ]);
                    if (form != null) await api.put('/api/me/shop', form);
                  }),
            child: const Text('Sửa hồ sơ shop'),
          ),
        ],
      );
    },
  );
}

class InsightsPage extends StatefulWidget {
  const InsightsPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  late int year = DateTime.now().year, month = DateTime.now().month;
  Json? forecast;
  @override
  Widget build(BuildContext context) => ResourceView(
    resourceKey: '$year-$month',
    load: () => widget.api.get(
      '/api/sellers/${widget.session.sellerId}/ai/seasonal-sales?year=$year&month=$month',
    ),
    builder: (context, data, state) {
      final row = objectOf(data);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageTitle(
            'Doanh số $month/$year',
            'Dữ liệu theo sản phẩm, không tự coi dự báo là đơn hàng thực tế.',
          ),
          Row(
            children: [
              Expanded(
                child: RecordCard(
                  title: '${row['totalInvoices'] ?? 0}',
                  subtitle: 'Hóa đơn sản phẩm',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RecordCard(
                  title: '${row['totalUnits'] ?? 0}',
                  subtitle: 'Số lượng bán',
                ),
              ),
            ],
          ),
          OutlinedButton(
            onPressed: state.busy
                ? null
                : () async {
                    final form = await askForm(context, 'Chọn kỳ thống kê', [
                      InputSpec('year', 'Năm', initial: '$year', numeric: true),
                      InputSpec(
                        'month',
                        'Tháng (1-12)',
                        initial: '$month',
                        numeric: true,
                      ),
                    ]);
                    if (form == null || !mounted) return;
                    try {
                      final nextYear = integerInput(form['year']),
                          nextMonth = integerInput(form['month']);
                      if (nextMonth > 12 ||
                          nextYear < 2000 ||
                          nextYear > 2100) {
                        throw const ApiError(400, 'Kỳ thống kê chưa hợp lệ.');
                      }
                      setState(() {
                        year = nextYear;
                        month = nextMonth;
                      });
                    } catch (e) {
                      if (context.mounted) message(context, '$e');
                    }
                  },
            child: const Text('Đổi kỳ thống kê'),
          ),
          for (final item in (row['products'] as List? ?? []).map(objectOf))
            RecordCard(
              title: valueOf(item, 'name'),
              subtitle:
                  '${item['totalInvoices']} hóa đơn • ${item['totalUnits']} bó',
            ),
          const Divider(height: 32),
          FilledButton.icon(
            onPressed: state.busy
                ? null
                : () => state.run(() async {
                    final now = DateTime.now(),
                        target = DateTime(
                          DateTime.now().year,
                          DateTime.now().month + 1,
                        );
                    final form =
                        await askForm(context, 'Dự báo nhu cầu theo tháng', [
                          InputSpec(
                            'year',
                            'Năm dự báo',
                            initial: '${target.year}',
                            numeric: true,
                          ),
                          InputSpec(
                            'month',
                            'Tháng dự báo',
                            initial: '${target.month}',
                            numeric: true,
                          ),
                          InputSpec(
                            'historyFrom',
                            'Lịch sử từ ngày (YYYY-MM-DD)',
                            initial: DateFormat(
                              'yyyy-MM-dd',
                            ).format(now.subtract(const Duration(days: 365))),
                          ),
                          InputSpec(
                            'historyTo',
                            'Lịch sử đến ngày (YYYY-MM-DD)',
                            initial: DateFormat(
                              'yyyy-MM-dd',
                            ).format(now.subtract(const Duration(days: 1))),
                          ),
                        ]);
                    if (form == null) return;
                    final result = objectOf(
                      await widget.api.post(
                        '/api/sellers/${widget.session.sellerId}/ai/seasonal-forecast',
                        {
                          'year': integerInput(form['year']),
                          'month': integerInput(form['month']),
                          'historyFrom': form['historyFrom'],
                          'historyTo': form['historyTo'],
                        },
                      ),
                    );
                    if (mounted) setState(() => forecast = result);
                  }),
            icon: const Icon(Icons.auto_graph),
            label: const Text('Lập dự báo'),
          ),
          if (forecast != null) ...[
            for (final warning in forecast!['warnings'] as List? ?? [])
              InfoBox('$warning', warning: true),
            for (final item in (forecast!['products'] as List? ?? []).map(
              objectOf,
            ))
              RecordCard(
                title: valueOf(item, 'name'),
                subtitle:
                    'Dự báo: ${item['forecastUnits'] ?? 'Chưa đủ dữ liệu'} bó\n${valueOf(item, 'explanation', '')}',
                status: item['modelStatus'],
              ),
          ],
        ],
      );
    },
  );
}

class SubscriptionsPage extends StatelessWidget {
  const SubscriptionsPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => api.get('/api/sellers/${session.sellerId}/subscriptions'),
    builder: (context, data, state) {
      final row = objectOf(data);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageTitle(
            'Kỳ thuê kiosk',
            'Mỗi kiosk có kỳ thuê và thanh toán riêng.',
          ),
          FilledButton.icon(
            onPressed: state.busy
                ? null
                : () => state.run(() async {
                    final kiosks = itemsOf(
                      await api.get('/api/sellers/${session.sellerId}/kiosks'),
                    );
                    if (!context.mounted) return;
                    final form = await askForm(context, 'Yêu cầu gia hạn', [
                      InputSpec(
                        'kioskId',
                        'Kiosk',
                        choices: {
                          for (final k in kiosks)
                            '${k['id']}': '${k['code']} - ${k['name']}',
                        },
                      ),
                    ]);
                    if (form == null) return;
                    final renewal = objectOf(
                      await api.post(
                        '/api/me/kiosks/${form['kioskId']}/renewals',
                      ),
                    );
                    if (!context.mounted) return;
                    if (await confirm(
                      context,
                      'Thanh toán gia hạn?',
                      'Phí: ${money(renewal['amount'])}\nTừ ${dateText(renewal['periodFrom'])} đến ${dateText(renewal['periodTo'])}',
                    )) {
                      final payment = objectOf(
                        await api.post('${renewal['paymentLinkPath']}'),
                      );
                      await openSafeLink('${payment['checkoutUrl']}');
                    }
                  }),
            icon: const Icon(Icons.event_repeat),
            label: const Text('Yêu cầu gia hạn kiosk'),
          ),
          for (final period in (row['subscriptions'] as List? ?? []).map(
            objectOf,
          ))
            RecordCard(
              title: valueOf(period, 'packageName'),
              subtitle:
                  '${money(period['price'])}\n${valueOf(period, 'periodFrom')} → ${valueOf(period, 'periodTo')}',
              status: period['status'],
            ),
          OutlinedButton(
            onPressed: () async {
              try {
                await openSafeLink('${AppConfig.portalUrl}/seller');
              } catch (e) {
                if (context.mounted) message(context, '$e');
              }
            },
            child: const Text('Mở cổng Web để xử lý hồ sơ thuê khác'),
          ),
        ],
      );
    },
  );
}

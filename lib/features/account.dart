export 'subscriptions.dart' show SubscriptionsPage;
export 'insights.dart' show InsightsPage;

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/auth.dart';

import '../core/models.dart';
import '../ui/common.dart';
import 'auth_screens.dart';
import 'kiosk_application.dart';

class AccountPage extends StatelessWidget {
  const AccountPage(this.auth, this.session, {super.key});
  final AuthController auth;
  final Session session;
  @override
  Widget build(BuildContext context) => ResourceView(
    load: () async {
      final data = await Future.wait<dynamic>([
        auth.api.get('/api/account/profile'),
        if (session.role == AppRole.seller)
          auth.api.get('/api/me/shop').catchError((Object error) => error),
      ]);
      return data;
    },
    builder: (context, data, state) {
      final results = data as List<dynamic>;
      final row = objectOf(results.first), api = auth.api;
      final VoidCallback? editProfile = state.busy
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
            });
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: 48),
              const Expanded(
                child: Text(
                  'Hồ sơ của tôi',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: forest,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Sửa hồ sơ cá nhân',
                onPressed: editProfile,
                icon: const Icon(Icons.edit_outlined, size: 21),
                color: forest,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ProfileIdentity(row: row, role: session.role.label),
          const SizedBox(height: 20),
          _ProfileSection(
            padding: EdgeInsets.zero,
            children: [
              _ProfileAction(
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
                icon: const Icon(Icons.mark_email_read_outlined),
                label: const Text('Email liên hệ'),
                subtitle: valueOf(row, 'contactEmail', 'Chưa thiết lập'),
              ),
              _ProfileAction(
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
            ],
          ),
          const SizedBox(height: 16),
          if (session.role == AppRole.seller) ...[
            _ProfileSection(
              children: [
                if (results[1] is Map) ...[
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Thông tin shop',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: forest,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Sửa thông tin shop',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: state.busy
                            ? null
                            : () => state.run(() async {
                                final shop = objectOf(results[1]);
                                final form = await askForm(
                                  context,
                                  'Sửa thông tin shop',
                                  [
                                    InputSpec(
                                      'shopName',
                                      'Tên shop',
                                      initial: valueOf(shop, 'shopName', ''),
                                      minLength: 2,
                                    ),
                                    InputSpec(
                                      'phone',
                                      'Số điện thoại',
                                      initial: valueOf(shop, 'phone', ''),
                                    ),
                                    InputSpec(
                                      'contactEmail',
                                      'Email liên hệ',
                                      initial: valueOf(
                                        shop,
                                        'contactEmail',
                                        '',
                                      ),
                                      required: false,
                                    ),
                                  ],
                                );
                                if (form == null) return;
                                await api.put('/api/me/shop', form);
                                if (context.mounted) {
                                  message(context, 'Đã lưu thông tin shop.');
                                }
                              }),
                      ),
                    ],
                  ),
                  for (final field in const [
                    ('Tên shop', 'shopName'),
                    ('Số điện thoại', 'phone'),
                    ('Email liên hệ', 'contactEmail'),
                    ('Địa chỉ đăng ký', 'address'),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            field.$1,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF617568),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            valueOf(
                                  objectOf(results[1]),
                                  field.$2,
                                  '',
                                ).trim().isEmpty
                                ? 'Chưa cập nhật'
                                : valueOf(objectOf(results[1]), field.$2),
                            style: const TextStyle(fontSize: 14, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                ] else ...[
                  const Text(
                    'Chưa tải được thông tin shop.',
                    style: TextStyle(color: Color(0xFFB42318)),
                  ),
                  TextButton(
                    onPressed: state.busy ? null : state.reload,
                    child: const Text('Thử lại'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
          ],
          _ProfileSection(
            padding: EdgeInsets.zero,
            children: [
              _ProfileAction(
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
                destructive: true,
                icon: const Icon(Icons.logout),
                label: const Text('Đăng xuất'),
              ),
            ],
          ),
          if (session.role == AppRole.customer)
            OutlinedButton.icon(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Thuê kiosk')),
                    body: KioskApplicationPage(
                      api,
                      session,
                      onActivateShop: auth.logout,
                    ),
                  ),
                ),
              ),
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Thuê kiosk / Mở shop'),
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
        ],
      );
    },
  );
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.children,
    this.padding = const EdgeInsets.all(16),
  });
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

class _ProfileIdentity extends StatelessWidget {
  const _ProfileIdentity({required this.row, required this.role});
  final Json row;
  final String role;

  Widget contact(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 17, color: const Color(0xFF617568)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Color(0xFF617568),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final name = valueOf(row, 'fullName', 'Tài khoản').trim();
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return _ProfileSection(
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFFEAF1E7),
              child: Text(
                initial,
                style: const TextStyle(
                  color: forest,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: forest,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    role,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF617568),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        contact(
          Icons.mail_outline_rounded,
          valueOf(row, 'loginEmail', 'Chưa cập nhật email'),
        ),
        if (valueOf(row, 'phone', '').trim().isNotEmpty)
          contact(Icons.phone_outlined, valueOf(row, 'phone')),
        if (valueOf(row, 'address', '').trim().isNotEmpty)
          contact(Icons.location_on_outlined, valueOf(row, 'address')),
      ],
    );
  }
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.subtitle,
    this.destructive = false,
  });
  final VoidCallback? onPressed;
  final Widget icon, label;
  final String? subtitle;
  final bool destructive;

  @override
  Widget build(BuildContext context) => ListTile(
    enabled: onPressed != null,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: destructive ? const Color(0xFFFFF4F3) : const Color(0xFFEAF1E7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconTheme(data: const IconThemeData(size: 19), child: icon),
    ),
    title: label,
    titleTextStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Color(0xFF617568),
            ),
          ),
    iconColor: destructive ? const Color(0xFFB42318) : forest,
    textColor: destructive ? const Color(0xFFB42318) : forest,
    onTap: onPressed,
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
          PageTitle(
            valueOf(row, 'shopName'),
            'Thông tin chung của shop',
            status: StatusChip(row['status']),
          ),
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

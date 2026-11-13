import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/auth.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/brand.dart';

bool validPassword(String text) =>
    text.length >= 12 &&
    utf8.encode(text).length <= 72 &&
    !text.runes.any((c) => c < 32 || c == 127);
bool validEmail(String text) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text) && text.length <= 254;

class LoginScreen extends StatefulWidget {
  const LoginScreen(this.auth, {super.key});
  final AuthController auth;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController(), password = TextEditingController();
  AppRole role = AppRole.customer;
  bool busy = false, obscure = true;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.clear();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (busy || !formKey.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.auth.login(email.text, password.text, role);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiError && e.status == 404
              ? 'Máy chủ chưa có API đăng nhập Mobile. Cần triển khai bản Backend đi kèm ứng dụng.'
              : '$e',
        );
      }
    } finally {
      if (mounted) {
        password.clear();
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FloralBackdrop(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
              child: AutofillGroup(
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const BrandWordmark(),
                      const SizedBox(height: 18),
                      const LoginArtwork(),
                      const SizedBox(height: 22),
                      const Text(
                        'Chào mừng trở lại.',
                        style: TextStyle(
                          fontSize: 28,
                          height: 1.15,
                          color: forest,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.8,
                        ),
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'Dùng email và mật khẩu để tiếp tục ngày mới.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF617568),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 22),
                      DropdownButtonFormField<AppRole>(
                        initialValue: role,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Vai trò của bạn',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        items: AppRole.values
                            .map(
                              (r) => DropdownMenuItem(
                                value: r,
                                child: Text(r.label),
                              ),
                            )
                            .toList(),
                        onChanged: busy
                            ? null
                            : (v) => setState(() {
                                role = v!;
                                error = null;
                              }),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.alternate_email),
                        ),
                        validator: (v) => validEmail((v ?? '').trim())
                            ? null
                            : 'Nhập email hợp lệ.',
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: password,
                        obscureText: obscure,
                        autofillHints: const [AutofillHints.password],
                        enableSuggestions: false,
                        autocorrect: false,
                        onFieldSubmitted: (_) => login(),
                        decoration: InputDecoration(
                          labelText: 'Mật khẩu',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (v) =>
                            (v ?? '').isEmpty || utf8.encode(v!).length > 72
                            ? 'Nhập mật khẩu hợp lệ.'
                            : null,
                      ),
                      if (error != null || widget.auth.error != null)
                        InfoBox(error ?? widget.auth.error!, warning: true),
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: busy ? null : login,
                        child: busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Đăng nhập'),
                                  SizedBox(width: 10),
                                  Icon(Icons.arrow_forward_rounded, size: 18),
                                ],
                              ),
                      ),
                      TextButton(
                        onPressed: busy ? null : forgot,
                        child: const Text('Quên mật khẩu?'),
                      ),
                      if (role == AppRole.customer)
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        RegistrationScreen(widget.auth.api),
                                  ),
                                ),
                          child: const Text('Tạo tài khoản khách đặt trước'),
                        ),
                      if (role == AppRole.customer || role == AppRole.seller)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => resetPassword(context, widget.auth.api),
                          child: const Text(
                            'Tôi đã có liên kết đặt lại mật khẩu',
                          ),
                        ),
                      const SizedBox(height: 16),
                      const Text(
                        'Đăng nhập bằng email và mật khẩu được cấp. Tài khoản kỹ thuật viên và nhân viên do người quản lý tạo.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF617568),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Future<void> forgot() async {
    if (role == AppRole.technician || role == AppRole.staff) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hỗ trợ tài khoản'),
          content: Text(
            role == AppRole.technician
                ? 'Liên hệ Manager quản lý tài khoản kỹ thuật viên để được hỗ trợ khôi phục quyền truy cập.'
                : 'Liên hệ chủ shop quản lý tài khoản nhân viên để được hỗ trợ khôi phục quyền truy cập.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đã hiểu'),
            ),
          ],
        ),
      );
      return;
    }
    final values = await askForm(context, 'Khôi phục mật khẩu', [
      InputSpec('email', 'Email đăng nhập', initial: email.text),
    ], submitLabel: 'Gửi liên kết');
    if (values == null) return;
    try {
      final result = objectOf(
        await widget.auth.api.request(
          'POST',
          '/api/auth/forgot-password',
          authenticated: false,
          body: values,
        ),
      );
      if (mounted) message(context, valueOf(result, 'message'));
    } catch (e) {
      if (mounted) message(context, '$e');
    }
  }
}

Future<void> resetPassword(BuildContext context, ApiClient api) async {
  final form = await askForm(context, 'Đặt mật khẩu mới', [
    const InputSpec('link', 'Liên kết đặt lại nhận qua email', secret: true),
    const InputSpec('password', 'Mật khẩu mới', secret: true, minLength: 12),
  ]);
  if (form == null) return;
  try {
    final link = Uri.tryParse(form['link']!),
        portal = Uri.parse(AppConfig.portalUrl);
    if (link == null ||
        link.scheme != 'https' ||
        link.host != portal.host ||
        link.path != '/dat-lai-mat-khau') {
      throw const ApiError(
        400,
        'Sử dụng liên kết đặt lại mật khẩu từ email FloraBot.',
      );
    }
    final token = Uri.splitQueryString(link.fragment)['token'];
    if (token == null || !validPassword(form['password']!)) {
      throw const ApiError(
        400,
        'Liên kết hoặc mật khẩu chưa hợp lệ. Mật khẩu cần ít nhất 12 ký tự và tối đa 72 byte UTF-8.',
      );
    }
    await api.request(
      'POST',
      '/api/auth/reset-password',
      authenticated: false,
      body: {'token': token, 'newPassword': form['password']},
    );
    if (context.mounted) {
      message(context, 'Đã đổi mật khẩu. Đăng nhập bằng mật khẩu mới.');
    }
  } catch (e) {
    if (context.mounted) message(context, '$e');
  }
}

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen(this.api, {super.key});
  final ApiClient api;
  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController(),
      code = TextEditingController();
  String? challenge, error;
  int cooldown = 0;
  bool busy = false;
  Timer? timer;
  @override
  void dispose() {
    timer?.cancel();
    for (final c in [name, email, password, code]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit({bool resend = false}) async {
    if (busy || (!resend && !formKey.currentState!.validate())) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (challenge == null || resend) {
        final result = objectOf(
          await widget.api.request(
            'POST',
            '/api/auth/register',
            authenticated: false,
            body: {
              'fullName': name.text.trim(),
              'email': email.text.trim(),
              'password': password.text,
            },
          ),
        );
        if (!mounted) return;
        setState(() {
          challenge = result['challengeId'] as String;
          cooldown = (result['resendAfterSeconds'] as num).toInt();
        });
        timer?.cancel();
        timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted && cooldown > 0) setState(() => cooldown--);
        });
      } else {
        await widget.api.request(
          'POST',
          '/api/auth/register/verify',
          authenticated: false,
          body: {'challengeId': challenge, 'code': code.text.trim()},
        );
        if (mounted) {
          message(context, 'Tài khoản đã xác thực. Vui lòng đăng nhập.');
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tài khoản khách đặt trước')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageTitle(
              'Chào mừng bạn',
              'Xác minh email để theo dõi đơn và nhận OTP lấy hoa.',
            ),
            TextFormField(
              controller: name,
              readOnly: challenge != null,
              decoration: const InputDecoration(labelText: 'Họ tên'),
              validator: (v) =>
                  (v ?? '').trim().length < 2 ? 'Nhập họ tên.' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: email,
              readOnly: challenge != null,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email đăng nhập'),
              validator: (v) =>
                  validEmail((v ?? '').trim()) ? null : 'Email chưa hợp lệ.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: password,
              obscureText: true,
              readOnly: challenge != null,
              decoration: const InputDecoration(
                labelText: 'Mật khẩu (ít nhất 12 ký tự)',
              ),
              validator: (v) => validPassword(v ?? '')
                  ? null
                  : 'Tối thiểu 12 ký tự, tối đa 72 byte UTF-8.',
            ),
            if (challenge != null) ...[
              const InfoBox(
                'Kiểm tra email và nhập mã xác thực. Đây không phải mã nhận hoa.',
              ),
              TextFormField(
                controller: code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Mã xác thực email',
                ),
                validator: (v) => RegExp(r'^\d{6}$').hasMatch((v ?? '').trim())
                    ? null
                    : 'Nhập đủ 6 số.',
              ),
              TextButton(
                onPressed: cooldown == 0 && !busy
                    ? () => submit(resend: true)
                    : null,
                child: Text(
                  cooldown > 0 ? 'Gửi lại sau ${cooldown}s' : 'Gửi lại mã',
                ),
              ),
            ],
            if (error != null) InfoBox(error!, warning: true),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy ? null : submit,
              child: Text(
                busy
                    ? 'Đang xử lý...'
                    : challenge == null
                    ? 'Gửi mã xác thực'
                    : 'Xác thực tài khoản',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

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
      await widget.auth.login(email.text, password.text);
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
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: AutofillGroup(
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const BrandWordmark(),
                      const SizedBox(height: 16),
                      const LoginArtwork(),
                      const SizedBox(height: 24),
                      const Text(
                        'Đăng nhập',
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
                        'Nhập email và mật khẩu của bạn.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF617568),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 18),
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
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: busy
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => _PasswordRecoveryScreen(
                                      widget.auth.api,
                                      initialEmail: email.text.trim(),
                                    ),
                                  ),
                                ),
                          child: const Text('Quên mật khẩu?'),
                        ),
                      ),
                      if (error != null || widget.auth.error != null)
                        InfoBox(error ?? widget.auth.error!, warning: true),
                      const SizedBox(height: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 52),
                        ),
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
                            : const Text('Đăng nhập'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF94A99E)),
                        ),
                        onPressed: busy
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      RegistrationScreen(widget.auth.api),
                                ),
                              ),
                        child: const Text('Tạo tài khoản'),
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
}

class _PasswordRecoveryScreen extends StatefulWidget {
  const _PasswordRecoveryScreen(this.api, {required this.initialEmail});

  final ApiClient api;
  final String initialEmail;

  @override
  State<_PasswordRecoveryScreen> createState() =>
      _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<_PasswordRecoveryScreen> {
  final formKey = GlobalKey<FormState>();
  late final email = TextEditingController(text: widget.initialEmail);
  bool busy = false;
  String? notice, error;

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> sendLink() async {
    if (busy || !formKey.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final result = objectOf(
        await widget.api.request(
          'POST',
          '/api/auth/forgot-password',
          authenticated: false,
          body: {'email': email.text.trim()},
        ),
      );
      if (mounted) setState(() => notice = valueOf(result, 'message'));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3EEDC),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.lock_reset_rounded, color: forest),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Quên mật khẩu?',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: forest,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Nhập email đăng nhập để nhận liên kết đặt lại mật khẩu.',
                    style: TextStyle(color: Color(0xFF53685D), height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: email,
                    enabled: !busy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email đăng nhập',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                    validator: (value) => validEmail((value ?? '').trim())
                        ? null
                        : 'Nhập email hợp lệ.',
                    onFieldSubmitted: (_) => sendLink(),
                  ),
                  if (notice != null || error != null) ...[
                    const SizedBox(height: 12),
                    InfoBox(error ?? notice!, warning: error != null),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                    onPressed: busy ? null : sendLink,
                    child: Text(busy ? 'Đang gửi…' : 'Gửi liên kết'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => resetPassword(context, widget.api),
                    child: const Text('Đã nhận liên kết? Đặt lại mật khẩu'),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFFD4E0D4)),
                  const SizedBox(height: 8),
                  Text(
                    'Tài khoản được cấp',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: forest,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Nhân viên liên hệ chủ shop. Kỹ thuật viên liên hệ Quản lý vận hành.',
                    style: TextStyle(color: Color(0xFF53685D), height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
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
      confirmPassword = TextEditingController(),
      code = TextEditingController();
  String? challenge, error;
  int cooldown = 0;
  bool busy = false;
  Timer? timer;
  @override
  void dispose() {
    timer?.cancel();
    for (final c in [name, email, password, confirmPassword, code]) {
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
    appBar: AppBar(title: const Text('Tạo tài khoản')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageTitle(
              'Thông tin đăng ký',
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
              autofillHints: const [AutofillHints.newPassword],
              readOnly: challenge != null,
              decoration: const InputDecoration(
                labelText: 'Mật khẩu (ít nhất 12 ký tự)',
              ),
              validator: (v) => validPassword(v ?? '')
                  ? null
                  : 'Tối thiểu 12 ký tự, tối đa 72 byte UTF-8.',
            ),
            if (challenge == null) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: confirmPassword,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: 'Xác nhận mật khẩu',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Nhập lại mật khẩu.';
                  }
                  return value == password.text ? null : 'Mật khẩu không khớp.';
                },
              ),
            ] else ...[
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

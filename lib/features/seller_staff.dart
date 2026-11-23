import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/team_widgets.dart';
import 'auth_screens.dart' show validEmail;
import 'chat.dart';
import 'inventory.dart' show openPage;

class StaffManagementPage extends StatefulWidget {
  const StaffManagementPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  State<StaffManagementPage> createState() => _StaffManagementPageState();
}

class _StaffManagementPageState extends State<StaffManagementPage> {
  String query = '', filter = '';
  int page = 1;
  String get base => '/api/sellers/${widget.session.sellerId}/staff';

  @override
  Widget build(BuildContext context) => ResourceView(
    load: () => widget.api.get('$base/accounts'),
    builder: (context, data, state) {
      final rows = itemsOf(data)
          .where(
            (r) =>
                (filter.isEmpty || r['status'] == filter) &&
                '${r['fullName']} ${r['email']} ${r['phone'] ?? ''}'
                    .toLowerCase()
                    .contains(query.trim().toLowerCase()),
          )
          .toList();
      final maxPage = (rows.length / 10).ceil().clamp(1, 100000);
      final current = page.clamp(1, maxPage);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamToolbar(
            hint: 'Tên, email hoặc số điện thoại',
            filter: filter,
            labels: staffAccountLabels,
            onQuery: (value) => setState(() {
              query = value;
              page = 1;
            }),
            onFilter: (value) => setState(() {
              filter = value;
              page = 1;
            }),
            createLabel: 'Thêm nhân viên',
            onCreate: state.busy
                ? null
                : () => state.run(() async {
                    final form = await showStaffEditor(context);
                    if (form != null) await widget.api.post(base, form);
                  }),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: Text('Không có nhân viên phù hợp.')),
            ),
          for (final row in rows.skip((current - 1) * 10).take(10))
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () async {
                  await openPage(
                    context,
                    'Chi tiết nhân viên',
                    SellerStaffDetail(widget.api, widget.session, row),
                  );
                  await state.reload();
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusHeading(
                        title: Text(
                          valueOf(row, 'fullName'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: forest,
                          ),
                        ),
                        status: TeamStatus(valueOf(row, 'status')),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        valueOf(row, 'email'),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF617568),
                        ),
                      ),
                      if (valueOf(row, 'phone', '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            valueOf(row, 'phone'),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF617568),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (maxPage > 1)
            TeamPaging(
              page: current,
              more: current < maxPage,
              busy: state.busy,
              onPage: (value) => setState(() => page = value),
            ),
        ],
      );
    },
  );
}

class SellerStaffDetail extends StatelessWidget {
  const SellerStaffDetail(this.api, this.session, this.seed, {super.key});
  final ApiClient api;
  final Session session;
  final Json seed;

  @override
  Widget build(BuildContext context) {
    final base = '/api/sellers/${session.sellerId}/staff/${seed['id']}';
    return ResourceView(
      load: () => api.get(base),
      builder: (context, data, state) {
        final row = objectOf(data);
        Future<void> change(String status) => state.run(() async {
          final title = const {
            'ACTIVE': 'Mở lại tài khoản?',
            'LOCKED': 'Tạm khóa nhân viên?',
            'DISABLED': 'Vô hiệu hóa nhân viên?',
          }[status]!;
          if (!await confirm(context, title, valueOf(row, 'fullName'))) return;
          await api.request('PATCH', '$base/status', body: {'status': status});
        });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TeamSection(
              children: [
                StatusHeading(
                  title: Text(
                    valueOf(row, 'fullName'),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: forest,
                    ),
                  ),
                  status: TeamStatus(valueOf(row, 'status')),
                ),
                const SizedBox(height: 20),
                TeamFact('Email đăng nhập', valueOf(row, 'email')),
                TeamFact(
                  'Số điện thoại',
                  valueOf(row, 'phone', 'Chưa cập nhật'),
                ),
                TeamFact('Địa chỉ', valueOf(row, 'address', 'Chưa cập nhật')),
                if (seed['createdAt'] != null)
                  TeamFact('Ngày tạo', dateText(seed['createdAt'])),
              ],
            ),
            FilledButton.icon(
              onPressed: state.busy
                  ? null
                  : () => state.run(() async {
                      final form = await showStaffEditor(context, item: row);
                      if (form != null) await api.put(base, form);
                    }),
              icon: const Icon(Icons.edit_outlined, size: 19),
              label: const Text('Chỉnh sửa hồ sơ'),
            ),
            const SizedBox(height: 10),
            if (row['status'] == 'ACTIVE') ...[
              OutlinedButton.icon(
                onPressed: state.busy
                    ? null
                    : () => state.run(() async {
                        final chat = objectOf(
                          await api.post('$base/chat/open'),
                        );
                        if (!context.mounted) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ChatThread(
                              api,
                              '${chat['id']}',
                              true,
                              valueOf(
                                chat,
                                'otherPartyName',
                                valueOf(row, 'fullName'),
                              ),
                            ),
                          ),
                        );
                      }),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 19),
                label: const Text('Nhắn tin'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: state.busy ? null : () => change('LOCKED'),
                child: const Text('Tạm khóa tài khoản'),
              ),
            ] else
              OutlinedButton(
                onPressed: state.busy ? null : () => change('ACTIVE'),
                child: const Text('Mở lại tài khoản'),
              ),
            if (row['status'] != 'DISABLED') ...[
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB42318),
                ),
                onPressed: state.busy ? null : () => change('DISABLED'),
                child: const Text('Vô hiệu hóa tài khoản'),
              ),
            ],
          ],
        );
      },
    );
  }
}

Future<Json?> showStaffEditor(BuildContext context, {Json? item}) =>
    Navigator.push<Json>(
      context,
      MaterialPageRoute(builder: (_) => _StaffEditor(item)),
    );

class _StaffEditor extends StatefulWidget {
  const _StaffEditor(this.item);
  final Json? item;
  @override
  State<_StaffEditor> createState() => _StaffEditorState();
}

class _StaffEditorState extends State<_StaffEditor> {
  final form = GlobalKey<FormState>();
  bool hidePassword = true;
  late final inputs = {
    for (final key in [
      'fullName',
      if (widget.item == null) 'email',
      'phone',
      if (widget.item == null) 'password' else 'address',
    ])
      key: TextEditingController(text: '${widget.item?[key] ?? ''}'),
  };
  @override
  void dispose() {
    for (final input in inputs.values) {
      input.clear();
      input.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.item == null ? 'Thêm nhân viên' : 'Sửa hồ sơ nhân viên',
      ),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TeamSection(
                children: [
                  for (final key in inputs.keys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              text: const {
                                'fullName': 'Họ và tên',
                                'email': 'Email đăng nhập',
                                'password': 'Mật khẩu ban đầu',
                                'phone': 'Số điện thoại',
                                'address': 'Địa chỉ',
                              }[key],
                              children: [
                                if (!['phone', 'address'].contains(key))
                                  const TextSpan(
                                    text: ' *',
                                    style: TextStyle(color: Color(0xFFB42318)),
                                  ),
                              ],
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: forest,
                            ),
                          ),
                          const SizedBox(height: 7),
                          TextFormField(
                            controller: inputs[key],
                            obscureText: key == 'password' && hidePassword,
                            autocorrect: key != 'password',
                            enableSuggestions: key != 'password',
                            maxLines: key == 'address' ? 3 : 1,
                            keyboardType: key == 'email'
                                ? TextInputType.emailAddress
                                : key == 'phone'
                                ? TextInputType.phone
                                : TextInputType.text,
                            decoration: InputDecoration(
                              suffixIcon: key != 'password'
                                  ? null
                                  : IconButton(
                                      tooltip: hidePassword
                                          ? 'Hiện mật khẩu'
                                          : 'Ẩn mật khẩu',
                                      onPressed: () => setState(
                                        () => hidePassword = !hidePassword,
                                      ),
                                      icon: Icon(
                                        hidePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        size: 20,
                                      ),
                                    ),
                            ),
                            validator: (raw) {
                              final value = key == 'password'
                                  ? raw ?? ''
                                  : (raw ?? '').trim();
                              if (key == 'fullName' &&
                                  (value.length < 2 || value.length > 120)) {
                                return 'Họ tên từ 2 đến 120 ký tự.';
                              }
                              if (key == 'email' &&
                                  (value.length > 254 || !validEmail(value))) {
                                return 'Nhập email hợp lệ.';
                              }
                              if (key == 'password' &&
                                  (value.length < 6 ||
                                      utf8.encode(value).length > 72)) {
                                return 'Mật khẩu từ 6 ký tự; giảm độ dài nếu có nhiều dấu.';
                              }
                              if (key == 'phone' &&
                                  value.isNotEmpty &&
                                  !RegExp(
                                    r'^(0[35789][0-9]{8}|\+84[35789][0-9]{8})$',
                                  ).hasMatch(value)) {
                                return 'Nhập số điện thoại Việt Nam hợp lệ.';
                              }
                              if (key == 'address' && value.length > 300) {
                                return 'Địa chỉ tối đa 300 ký tự.';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              FilledButton(
                onPressed: () {
                  if (!form.currentState!.validate()) return;
                  Navigator.pop(context, <String, dynamic>{
                    for (final input in inputs.entries)
                      input.key: input.key == 'password'
                          ? input.value.text
                          : input.value.text.trim(),
                  });
                },
                child: Text(
                  widget.item == null ? 'Tạo tài khoản' : 'Lưu thay đổi',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

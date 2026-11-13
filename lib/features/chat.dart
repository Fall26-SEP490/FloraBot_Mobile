import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';

Future<void> openCustomerChat(
  BuildContext context,
  ApiClient api,
  String sellerId, {
  String? productId,
}) async {
  final row = objectOf(
    await api.post('/api/member/chats/open', {
      'sellerId': sellerId,
      'productId': ?productId,
    }),
  );
  if (context.mounted) {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChatThread(
          api,
          '${row['id']}',
          false,
          valueOf(row, 'otherPartyName', 'Trao đổi với shop'),
        ),
      ),
    );
  }
}

class ChatsPage extends StatefulWidget {
  const ChatsPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;
  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  bool staffChats = false;
  @override
  Widget build(BuildContext context) {
    final role = widget.session.role;
    final staff =
        role == AppRole.staff || (role == AppRole.seller && staffChats);
    final path = staff
        ? '/api/seller-staff/chats'
        : role == AppRole.seller
        ? '/api/sellers/${widget.session.sellerId}/chats'
        : '/api/member/chats';
    return ApiListPage(
      api: widget.api,
      path: path,
      title: 'Tin nhắn',
      subtitle:
          'Trao đổi đúng shop và đúng công việc. Kéo xuống để cập nhật tin mới.',
      actions: [
        if (role == AppRole.seller)
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Khách hàng')),
              ButtonSegment(value: true, label: Text('Nhân viên')),
            ],
            selected: {staffChats},
            onSelectionChanged: (v) => setState(() => staffChats = v.single),
          ),
        if (staff)
          OutlinedButton.icon(
            onPressed: () async {
              try {
                Json result;
                if (role == AppRole.staff) {
                  result = objectOf(
                    await widget.api.post('/api/staff/chats/open'),
                  );
                } else {
                  final rows = itemsOf(
                    await widget.api.get(
                      '/api/sellers/${widget.session.sellerId}/staff',
                    ),
                  );
                  if (!context.mounted) return;
                  final choice = await askForm(
                    context,
                    'Trao đổi với nhân viên',
                    [
                      InputSpec(
                        'staffId',
                        'Nhân viên',
                        choices: {
                          for (final r in rows)
                            '${r['id']}': valueOf(r, 'name'),
                        },
                      ),
                    ],
                  );
                  if (choice == null) return;
                  result = objectOf(
                    await widget.api.post(
                      '/api/sellers/${widget.session.sellerId}/staff/${choice['staffId']}/chat/open',
                    ),
                  );
                }
                if (context.mounted) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ChatThread(
                        widget.api,
                        '${result['id']}',
                        true,
                        valueOf(result, 'otherPartyName'),
                      ),
                    ),
                  );
                }
                if (mounted) setState(() {});
              } catch (e) {
                if (context.mounted) message(context, '$e');
              }
            },
            icon: const Icon(Icons.edit_square),
            label: Text(
              role == AppRole.staff ? 'Nhắn chủ shop' : 'Nhắn nhân viên',
            ),
          ),
      ],
      item: (context, row, state) => RecordCard(
        title: valueOf(row, 'otherPartyName'),
        subtitle:
            '${row['lastMessageHasImage'] == true ? '[Ảnh] ' : ''}${row['lastMessage'] ?? 'Bắt đầu trao đổi'}',
        trailing: (row['unreadCount'] as num? ?? 0) > 0
            ? Badge(label: Text('${row['unreadCount']}'))
            : const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ChatThread(
                widget.api,
                '${row['id']}',
                staff,
                valueOf(row, 'otherPartyName'),
              ),
            ),
          );
          await state.reload();
        },
      ),
    );
  }
}

class ChatThread extends StatefulWidget {
  const ChatThread(this.api, this.id, this.staff, this.title, {super.key});
  final ApiClient api;
  final String id, title;
  final bool staff;
  @override
  State<ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<ChatThread> {
  final text = TextEditingController();
  int page = 1;
  String get base => widget.staff
      ? '/api/seller-staff/chats/${widget.id}'
      : '/api/chats/${widget.id}';
  @override
  void dispose() {
    text.clear();
    text.dispose();
    super.dispose();
  }

  Future<dynamic> load() async {
    final data = await widget.api.get('$base/messages?page=$page');
    // Reading markers are best effort and never gate displaying a fetched thread.
    try {
      await widget.api.post('$base/read');
    } on ApiError {
      /* Keep messages readable when mark-read fails. */
    }
    return data;
  }

  @override
  Widget build(BuildContext context) => ResourceView(
    title: widget.title,
    resourceKey: page,
    load: load,
    builder: (context, data, state) {
      final rows = itemsOf(data)
        ..sort((a, b) => '${a['createdAt']}'.compareTo('${b['createdAt']}'));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rows.isEmpty)
            const InfoBox('Chưa có tin nhắn. Bắt đầu trao đổi bên dưới.'),
          for (final row in rows)
            Align(
              alignment: row['isMine'] == true
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 330),
                margin: const EdgeInsets.symmetric(vertical: 5),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: row['isMine'] == true
                      ? const Color(0xFFE4F0DF)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valueOf(row, 'senderName'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: forest,
                      ),
                    ),
                    if (row['content'] != null)
                      Text(
                        '${row['content']}',
                        style: const TextStyle(fontSize: 16, height: 1.45),
                      ),
                    if (row['imageUrl'] is String)
                      PrivateImage(widget.api, row['imageUrl'] as String),
                    const SizedBox(height: 5),
                    Text(
                      dateText(row['createdAt']),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF617568),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: page > 1 ? () => setState(() => page = 1) : null,
                child: const Text('Tin mới nhất'),
              ),
              TextButton(
                onPressed: data is Map && data['hasMore'] == true
                    ? () => setState(() => page++)
                    : null,
                child: const Text('Tin cũ hơn'),
              ),
            ],
          ),
          const Divider(),
          TextField(
            controller: text,
            minLines: 1,
            maxLines: 4,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'Nội dung tin nhắn',
              hintText: 'Trao đổi trong ứng dụng',
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Gửi ảnh',
                onPressed: state.busy
                    ? null
                    : () => state.run(() async {
                        final file = await chooseEvidence(context);
                        if (file == null) return;
                        final uploaded = await widget.api.upload(
                          '$base/images',
                          file,
                        );
                        await widget.api.post('$base/messages', {
                          'content': null,
                          'imageReference': uploaded['reference'],
                        });
                        if (mounted) setState(() => page = 1);
                      }),
                icon: const Icon(Icons.add_photo_alternate_outlined),
              ),
              Expanded(
                child: FilledButton.icon(
                  onPressed: state.busy
                      ? null
                      : () => state.run(() async {
                          final content = text.text.trim();
                          if (content.isEmpty) return;
                          await widget.api.post('$base/messages', {
                            'content': content,
                          });
                          text.clear();
                          if (mounted) setState(() => page = 1);
                        }),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Gửi tin nhắn'),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

class PrivateImage extends StatefulWidget {
  const PrivateImage(this.api, this.path, {super.key});
  final ApiClient api;
  final String path;
  @override
  State<PrivateImage> createState() => _PrivateImageState();
}

class _PrivateImageState extends State<PrivateImage> {
  late final Future<Uint8List> bytes = widget.api.imageBytes(widget.path);
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: bytes,
    builder: (context, snap) {
      if (snap.hasError) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Không tải được ảnh. Tải lại cuộc trò chuyện.'),
        );
      }
      if (!snap.hasData) {
        return const SizedBox(
          height: 90,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Image.memory(snap.data!, width: 280, fit: BoxFit.contain),
      );
    },
  );
}

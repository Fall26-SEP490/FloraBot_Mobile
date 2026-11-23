import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/chat_live.dart';
import '../core/models.dart';
import '../ui/common.dart';
import 'ai_chat.dart';

String _shortChatTime(dynamic value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return '';
  final now = DateTime.now();
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return DateFormat('HH:mm').format(date);
  }
  return DateFormat('dd/MM HH:mm').format(date);
}

String _avatarLetter(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.substring(0, 1).toUpperCase();
}

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
  ChatLive? live;
  bool staffChats = false;
  bool loading = true;
  bool opening = false;
  int page = 1;
  bool hasMore = false;
  Object? loadError;
  List<Json> items = [];
  int _generation = 0;

  bool get isStaffDirectory =>
      widget.session.role == AppRole.seller && staffChats;

  bool get isStaffScope =>
      widget.session.role == AppRole.staff ||
      (widget.session.role == AppRole.seller && staffChats);

  String get listPath => isStaffScope
      ? '/api/seller-staff/chats'
      : widget.session.role == AppRole.seller
      ? '/api/sellers/${widget.session.sellerId}/chats'
      : '/api/member/chats';

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
    live = ChatLive(widget.api, () {
      if (mounted) unawaited(_fetch(silent: true));
    });
    live!.start();
  }

  @override
  void dispose() {
    live?.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool silent = false}) async {
    final epoch = ++_generation;
    if (!silent && mounted) {
      setState(() {
        loading = true;
        loadError = null;
      });
    }
    try {
      final directory = isStaffDirectory;
      final data = await widget.api.get(
        directory
            ? '/api/sellers/${widget.session.sellerId}/staff'
            : '$listPath?page=$page',
      );
      if (!mounted || epoch != _generation) return;
      setState(() {
        items = itemsOf(data);
        hasMore = !directory && data is Map && data['hasMore'] == true;
        loadError = null;
        loading = false;
      });
    } catch (e) {
      if (!mounted || epoch != _generation) return;
      setState(() {
        if (!silent || items.isEmpty) loadError = e;
        loading = false;
      });
    }
  }

  Future<void> _openStaffConversation({String? staffId}) async {
    if (opening) return;
    setState(() => opening = true);
    try {
      Json result;
      if (widget.session.role == AppRole.staff) {
        result = objectOf(await widget.api.post('/api/staff/chats/open'));
      } else {
        if (staffId == null) return;
        result = objectOf(
          await widget.api.post(
            '/api/sellers/${widget.session.sellerId}/staff/$staffId/chat/open',
          ),
        );
      }
      if (!mounted) return;
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
      if (mounted) unawaited(_fetch(silent: true));
    } catch (e) {
      if (mounted) message(context, '$e');
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.session.role;
    final staff = isStaffScope;
    return RefreshIndicator(
      onRefresh: () => _fetch(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          Material(
            color: forest,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AiChatPage(widget.api, widget.session),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Trợ lý AI FloraBot',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            role == AppRole.customer
                                ? 'Gợi ý chọn hoa theo dịp, ngân sách & tìm kiosk'
                                : 'Tư vấn mô tả hoa, gắn tag & chuẩn bị mẫu dịp lễ',
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: Color(0xFFD6E6BB),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (role == AppRole.seller) ...[
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.people_outline_rounded, size: 18),
                    label: Text('Khách hàng'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.badge_outlined, size: 18),
                    label: Text('Nhân viên'),
                  ),
                ],
                selected: {staffChats},
                onSelectionChanged: (v) {
                  setState(() {
                    staffChats = v.single;
                    page = 1;
                    items = [];
                  });
                  unawaited(_fetch());
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (role == AppRole.staff) ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                backgroundColor: Colors.white,
              ),
              onPressed: opening ? null : () => _openStaffConversation(),
              icon: const Icon(Icons.edit_square, size: 18),
              label: const Text('Nhắn chủ shop'),
            ),
            const SizedBox(height: 12),
          ],
          if (loading && items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (loadError != null && items.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDDE6DF)),
              ),
              child: Column(
                children: [
                  Text(
                    '$loadError',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFB42318)),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => _fetch(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tải lại'),
                  ),
                ],
              ),
            )
          else if (items.isEmpty && isStaffDirectory)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Text('Chưa có nhân viên đang hoạt động.')),
            )
          else if (items.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFDDE6DF)),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 32,
                    color: Color(0xFF617267),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Chưa có cuộc trò chuyện nào.',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: forest,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tin nhắn mới sẽ tự động cập nhật khi có kết nối.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF617267)),
                  ),
                ],
              ),
            )
          else if (isStaffDirectory) ...[
            for (final row in items)
              _ChatListTile(
                name: valueOf(row, 'name', 'Nhân viên'),
                preview: 'Nhân viên shop',
                timeText: '',
                unread: 0,
                onTap: () => _openStaffConversation(staffId: '${row['id']}'),
              ),
          ] else ...[
            for (final row in items)
              _ChatListTile(
                name: valueOf(row, 'otherPartyName', 'Hội thoại'),
                preview:
                    '${row['lastMessageHasImage'] == true ? '[Ảnh] ' : ''}${row['lastMessage'] ?? 'Bắt đầu trao đổi'}',
                timeText: _shortChatTime(
                  row['lastMessageAt'] ?? row['updatedAt'],
                ),
                unread: (row['unreadCount'] as num?)?.toInt() ?? 0,
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
                  if (mounted) unawaited(_fetch(silent: true));
                },
              ),
          ],
          if (page > 1 || hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: page > 1 && !loading
                        ? () {
                            setState(() => page--);
                            unawaited(_fetch());
                          }
                        : null,
                    child: const Text('Trang trước'),
                  ),
                  Text(
                    'Trang $page',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF617267),
                    ),
                  ),
                  TextButton(
                    onPressed: hasMore && !loading
                        ? () {
                            setState(() => page++);
                            unawaited(_fetch());
                          }
                        : null,
                    child: const Text('Trang sau'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ChatListTile extends StatelessWidget {
  const _ChatListTile({
    required this.name,
    required this.preview,
    required this.timeText,
    required this.unread,
    required this.onTap,
  });
  final String name, preview, timeText;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: unread > 0 ? const Color(0xFFBCD5C2) : const Color(0xFFDDE6DF),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFEAF3EC),
                foregroundColor: forest,
                child: Text(
                  _avatarLetter(name),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: forest,
                            ),
                          ),
                        ),
                        if (timeText.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            timeText,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF617267),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: unread > 0
                                  ? const Color(0xFF1F3428)
                                  : const Color(0xFF617267),
                              fontWeight: unread > 0
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (unread > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: forest,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$unread',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ChatThread extends StatefulWidget {
  const ChatThread(this.api, this.id, this.staff, this.title, {super.key});
  final ApiClient api;
  final String id, title;
  final bool staff;
  @override
  State<ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<ChatThread> with WidgetsBindingObserver {
  final text = TextEditingController();
  final scroll = ScrollController();
  ChatLive? live;
  List<Json> rows = [];
  bool loading = true;
  bool sending = false;
  bool hasMore = false;
  Object? loadError;
  int page = 1;
  int _generation = 0;

  String get base => widget.staff
      ? '/api/seller-staff/chats/${widget.id}'
      : '/api/chats/${widget.id}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    live = ChatLive(widget.api, () {
      if (mounted && page == 1) unawaited(_load(silent: true));
    });
    live!.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && page == 1) {
      unawaited(_load(silent: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    live?.dispose();
    text.clear();
    text.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final epoch = ++_generation;
    if (!silent && mounted) {
      setState(() {
        loading = true;
        loadError = null;
      });
    }
    try {
      final data = await widget.api.get('$base/messages?page=$page');
      // Reading markers are best effort and never gate displaying a fetched thread.
      try {
        await widget.api.post('$base/read');
      } on ApiError {
        /* Keep messages readable when mark-read fails. */
      }
      if (!mounted || epoch != _generation) return;
      final fetched = itemsOf(data)
        ..sort((a, b) => '${a['createdAt']}'.compareTo('${b['createdAt']}'));
      setState(() {
        rows = fetched;
        hasMore = data is Map && data['hasMore'] == true;
        loadError = null;
        loading = false;
      });
    } catch (e) {
      if (!mounted || epoch != _generation) return;
      setState(() {
        if (!silent || rows.isEmpty) loadError = e;
        loading = false;
      });
    }
  }

  Future<void> _sendText() async {
    final draft = text.text;
    final content = draft.trim();
    if (content.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      await widget.api.post('$base/messages', {'content': content});
      if (!mounted) return;
      if (text.text == draft) text.clear();
      setState(() => page = 1);
      await _load(silent: true);
      if (scroll.hasClients) {
        scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) message(context, '$e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _sendImage() async {
    if (sending) return;
    final file = await chooseEvidence(context);
    if (file == null || !mounted) return;
    setState(() => sending = true);
    try {
      final uploaded = await widget.api.upload('$base/images', file);
      await widget.api.post('$base/messages', {
        'content': null,
        'imageReference': uploaded['reference'],
      });
      if (!mounted) return;
      setState(() => page = 1);
      await _load(silent: true);
      if (scroll.hasClients) {
        scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) message(context, '$e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reversed = rows.reversed.toList();
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: const Color(0xFFEAF3EC),
              foregroundColor: forest,
              child: Text(
                _avatarLetter(widget.title),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: forest,
                    ),
                  ),
                  Text(
                    widget.staff ? 'Trao đổi nội bộ' : 'Hội thoại đơn hàng',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF617267),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (loading && rows.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: loading && rows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : loadError != null && rows.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$loadError',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFFB42318)),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => _load(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Tải lại'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _load(),
                    child: rows.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(24),
                            children: const [
                              SizedBox(height: 60),
                              InfoBox(
                                'Chưa có tin nhắn. Hãy nhập nội dung bên dưới để bắt đầu trao đổi.',
                              ),
                            ],
                          )
                        : ListView.builder(
                            controller: scroll,
                            reverse: true,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            itemCount: reversed.length + (hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (hasMore && index == reversed.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Center(
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 36),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 6,
                                        ),
                                      ),
                                      onPressed: loading
                                          ? null
                                          : () {
                                              setState(() => page++);
                                              unawaited(_load());
                                            },
                                      icon: const Icon(
                                        Icons.history_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Tin cũ hơn'),
                                    ),
                                  ),
                                );
                              }
                              final row = reversed[index];
                              final mine = row['isMine'] == true;
                              final older = index + 1 < reversed.length
                                  ? reversed[index + 1]
                                  : null;
                              final showSender =
                                  !mine &&
                                  (older == null ||
                                      older['isMine'] == true ||
                                      older['senderName'] != row['senderName']);
                              return Align(
                                alignment: mine
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  constraints: const BoxConstraints(
                                    maxWidth: 300,
                                  ),
                                  margin: EdgeInsets.only(
                                    top: showSender ? 8 : 3,
                                    bottom: 3,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: mine ? forest : Colors.white,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(18),
                                      topRight: const Radius.circular(18),
                                      bottomLeft: Radius.circular(
                                        mine ? 18 : 4,
                                      ),
                                      bottomRight: Radius.circular(
                                        mine ? 4 : 18,
                                      ),
                                    ),
                                    border: mine
                                        ? null
                                        : Border.all(
                                            color: const Color(0xFFDDE6DF),
                                          ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (showSender) ...[
                                        Text(
                                          valueOf(row, 'senderName'),
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: forest,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                      ],
                                      if (row['content'] != null)
                                        Text(
                                          '${row['content']}',
                                          style: TextStyle(
                                            fontSize: 15,
                                            height: 1.45,
                                            color: mine
                                                ? Colors.white
                                                : const Color(0xFF1F3428),
                                          ),
                                        ),
                                      if (row['imageUrl'] is String)
                                        PrivateImage(
                                          widget.api,
                                          row['imageUrl'] as String,
                                        ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _shortChatTime(row['createdAt']),
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: mine
                                              ? const Color(0xFFD6E6BB)
                                              : const Color(0xFF74867A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
          if (page > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ActionChip(
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFDDE6DF)),
                avatar: const Icon(
                  Icons.arrow_downward_rounded,
                  size: 16,
                  color: forest,
                ),
                label: const Text(
                  'Tin mới nhất',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: forest,
                  ),
                ),
                onPressed: loading
                    ? null
                    : () {
                        setState(() => page = 1);
                        unawaited(_load());
                      },
              ),
            ),
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFDDE6DF))),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        tooltip: 'Gửi ảnh',
                        onPressed: sending ? null : _sendImage,
                        icon: const Icon(
                          Icons.add_photo_alternate_outlined,
                          color: forest,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: text,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 2000,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendText(),
                        decoration: InputDecoration(
                          hintText: 'Nhập tin nhắn...',
                          counterText: '',
                          filled: true,
                          fillColor: const Color(0xFFF4F7F3),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: Color(0xFFDCE6DD),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: Color(0xFFDCE6DD),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: forest,
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: const CircleBorder(),
                        ),
                        onPressed: sending ? null : _sendText,
                        child: sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Tooltip(
                                message: 'Gửi tin nhắn',
                                child: Icon(Icons.send_rounded, size: 20),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
          padding: EdgeInsets.all(8),
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
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(snap.data!, width: 240, fit: BoxFit.contain),
        ),
      );
    },
  );
}

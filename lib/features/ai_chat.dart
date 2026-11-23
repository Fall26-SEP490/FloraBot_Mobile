import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../ui/common.dart';

class _AiQuickPrompt {
  const _AiQuickPrompt({
    required this.label,
    required this.question,
    this.mode,
    this.budget,
  });
  final String label, question;
  final String? mode;
  final int? budget;
}

class _AiExchange {
  _AiExchange({
    required this.question,
    this.mode,
    this.budget,
    this.pending = false,
  });
  final String question;
  final String? mode;
  final int? budget;
  String? answer;
  List<Json> suggestions = const [];
  String? error;
  bool pending;
}

class AiChatPage extends StatefulWidget {
  const AiChatPage(this.api, this.session, {super.key});
  final ApiClient api;
  final Session session;

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final exchanges = <_AiExchange>[];
  bool sending = false;

  bool get isSellerAudience =>
      widget.session.role == AppRole.seller ||
      widget.session.role == AppRole.staff;

  List<_AiQuickPrompt> get quickPrompts => isSellerAudience
      ? const [
          _AiQuickPrompt(
            label: 'Viết mô tả & gắn tag',
            question: 'Tôi nên viết mô tả và gắn tag cho bó hoa như thế nào?',
          ),
          _AiQuickPrompt(
            label: 'Chuẩn bị mẫu hoa dịp lễ',
            question: 'Tôi nên chuẩn bị mẫu hoa gì cho dịp sắp tới?',
          ),
          _AiQuickPrompt(
            label: 'Bán tại tủ & đặt trước',
            question:
                'Tôi nên phân biệt mẫu bán tại tủ và mẫu đặt trước như thế nào?',
          ),
        ]
      : const [
          _AiQuickPrompt(
            label: 'Hoa sinh nhật dưới 400k',
            question: 'Gợi ý hoa sinh nhật đặt trước dưới 400.000đ.',
            mode: 'PREORDER',
            budget: 400000,
          ),
          _AiQuickPrompt(
            label: 'Shop bán nhiều đơn nhất',
            question: 'Shop nào bán được nhiều đơn đặt trước nhất?',
            mode: 'PREORDER',
          ),
          _AiQuickPrompt(
            label: 'Gợi ý hoa tặng người thương',
            question: 'Gợi ý bó hoa hồng tặng người thương đặt trước.',
            mode: 'PREORDER',
          ),
        ];

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> sendQuestion(
    String rawQuestion, {
    String? mode,
    int? budget,
    _AiExchange? retryTarget,
  }) async {
    final text = rawQuestion.trim();
    if (text.isEmpty || sending) return;
    if (text.length > 500) {
      message(context, 'Câu hỏi tối đa 500 ký tự.');
      return;
    }

    final exchange =
        retryTarget ??
        _AiExchange(
          question: text,
          mode: mode ?? (isSellerAudience ? null : 'PREORDER'),
          budget: budget,
          pending: true,
        );

    setState(() {
      sending = true;
      exchange.pending = true;
      exchange.error = null;
      if (retryTarget == null) {
        exchanges.add(exchange);
        if (input.text.trim() == text) input.clear();
      }
    });

    if (scroll.hasClients) {
      scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }

    try {
      final payload = <String, dynamic>{
        'question': exchange.question,
        if (!isSellerAudience) 'mode': exchange.mode ?? 'PREORDER',
        if (!isSellerAudience && exchange.budget != null)
          'budget': exchange.budget,
      };
      final response = objectOf(
        await widget.api.post('/api/shop/flower-chat', payload),
      );
      if (!mounted) return;
      setState(() {
        exchange.pending = false;
        exchange.answer = valueOf(
          response,
          'message',
          'FloraBot chưa có câu trả lời phù hợp lúc này.',
        );
        exchange.suggestions = itemsOf(response['suggestions'] ?? []);
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        exchange.pending = false;
        exchange.error = e.status == 429
            ? 'Bạn gửi câu hỏi hơi nhanh. Chờ một phút rồi thử lại nhé.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        exchange.pending = false;
        exchange.error =
            'Chưa kết nối được với trợ lý AI FloraBot. Bạn thử gửi lại nhé.';
      });
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reversed = exchanges.reversed.toList();
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: forest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 19,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Trợ lý AI FloraBot',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: forest,
                    ),
                  ),
                  Text(
                    isSellerAudience
                        ? 'Hỗ trợ vận hành & gợi ý mẫu hoa'
                        : 'Tư vấn chọn hoa & tìm kiosk',
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
          Expanded(
            child: exchanges.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFDDE6DF)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEAF3EC),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.local_florist_rounded,
                                    color: forest,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Xin chào! Mình là FloraBot AI',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: forest,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              isSellerAudience
                                  ? 'Mình có thể gợi ý cách viết mô tả thu hút, gắn tag sản phẩm chuẩn, và chuẩn bị mẫu hoa phù hợp cho dịp lễ sắp tới.'
                                  : 'Hãy mô tả dịp tặng, người nhận hoặc ngân sách để mình gợi ý bó hoa phù hợp đang mở đặt trước trên FloraBot.',
                              style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.55,
                                color: Color(0xFF425A4C),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Gợi ý câu hỏi nhanh',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF617267),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final prompt in quickPrompts)
                            ActionChip(
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFFD4E0D4)),
                              avatar: const Icon(
                                Icons.auto_awesome_outlined,
                                size: 16,
                                color: forest,
                              ),
                              label: Text(
                                prompt.label,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: forest,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: sending
                                  ? null
                                  : () => sendQuestion(
                                      prompt.question,
                                      mode: prompt.mode,
                                      budget: prompt.budget,
                                    ),
                            ),
                        ],
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: scroll,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    itemCount: reversed.length,
                    itemBuilder: (context, index) {
                      final item = reversed[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 300),
                              margin: const EdgeInsets.only(top: 6, bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: const BoxDecoration(
                                color: forest,
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(18),
                                  topRight: Radius.circular(18),
                                  bottomLeft: Radius.circular(18),
                                  bottomRight: Radius.circular(4),
                                ),
                              ),
                              child: Text(
                                item.question,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  height: 1.45,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 320),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(18),
                                  topRight: Radius.circular(18),
                                  bottomRight: Radius.circular(18),
                                  bottomLeft: Radius.circular(4),
                                ),
                                border: Border.all(
                                  color: const Color(0xFFDDE6DF),
                                ),
                              ),
                              child: item.pending
                                  ? const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          'FloraBot đang trả lời…',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            color: Color(0xFF617267),
                                          ),
                                        ),
                                      ],
                                    )
                                  : item.error != null
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.error!,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            height: 1.45,
                                            color: Color(0xFFB42318),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            minimumSize: const Size(0, 36),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                          ),
                                          onPressed: sending
                                              ? null
                                              : () => sendQuestion(
                                                  item.question,
                                                  mode: item.mode,
                                                  budget: item.budget,
                                                  retryTarget: item,
                                                ),
                                          icon: const Icon(
                                            Icons.refresh_rounded,
                                            size: 16,
                                          ),
                                          label: const Text('Thử lại'),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.auto_awesome_rounded,
                                              size: 14,
                                              color: forest,
                                            ),
                                            SizedBox(width: 5),
                                            Text(
                                              'FloraBot AI',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: forest,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          item.answer ?? '',
                                          style: const TextStyle(
                                            fontSize: 14.5,
                                            height: 1.5,
                                            color: Color(0xFF1F3428),
                                          ),
                                        ),
                                        for (final s in item.suggestions)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              top: 10,
                                            ),
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF6FAF6),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: const Color(0xFFD9E6DC),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        valueOf(s, 'name'),
                                                        style: const TextStyle(
                                                          fontSize: 13.5,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: forest,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      money(s['price']),
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: forest,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (s['shopName'] != null ||
                                                    s['kioskName'] != null) ...[
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    [
                                                      if (s['shopName'] != null)
                                                        '${s['shopName']}',
                                                      if (s['kioskName'] !=
                                                          null)
                                                        '${s['kioskName']}',
                                                    ].join(' · '),
                                                    style: const TextStyle(
                                                      fontSize: 11.5,
                                                      color: Color(0xFF617267),
                                                    ),
                                                  ),
                                                ],
                                                if (s['reason'] != null) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '${s['reason']}',
                                                    style: const TextStyle(
                                                      fontSize: 12.5,
                                                      height: 1.4,
                                                      color: Color(0xFF334B3E),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      );
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
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: input,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 500,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => sendQuestion(input.text),
                        decoration: InputDecoration(
                          hintText: 'Hỏi FloraBot AI...',
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
                        onPressed: sending
                            ? null
                            : () => sendQuestion(input.text),
                        child: sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 20),
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

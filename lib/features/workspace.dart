import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/auth.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/brand.dart';
import 'account.dart';
import 'auth_screens.dart';
import 'chat.dart';
import 'inventory.dart';
import 'orders.dart';
import 'tasks.dart';
import 'technician_iot_health.dart';
import 'seller_overview.dart';
import 'seller_tools.dart';

class GuestWorkspace extends StatefulWidget {
  const GuestWorkspace(
    this.auth, {
    this.onPendingOrder,
    this.onPendingChat,
    this.onClearPending,
    super.key,
  });
  final AuthController auth;
  final void Function(PendingFlowerOrder)? onPendingOrder;
  final void Function(Json)? onPendingChat;
  final VoidCallback? onClearPending;

  @override
  State<GuestWorkspace> createState() => _GuestWorkspaceState();
}

class _GuestWorkspaceState extends State<GuestWorkspace> {
  int selected = 0;

  Future<void> _promptOrder(
    BuildContext context,
    Json row,
    List<Json> rows,
  ) async {
    widget.onPendingOrder?.call((item: row, rows: rows));
    await showGuestAuthPrompt(
      context,
      auth: widget.auth,
      title: 'Đăng nhập để đặt hoa',
      subtitle: '${valueOf(row, 'name')} · ${valueOf(row, 'shopName')}',
      onCancelled: widget.onClearPending,
    );
  }

  Future<void> _promptChat(BuildContext context, Json row) async {
    widget.onPendingChat?.call(row);
    await showGuestAuthPrompt(
      context,
      auth: widget.auth,
      title: 'Đăng nhập để nhắn shop',
      subtitle: valueOf(row, 'shopName'),
      onCancelled: widget.onClearPending,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: selected == 0
        ? AppBar(
            centerTitle: false,
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_florist_rounded),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'FloraBot',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  widget.onClearPending?.call();
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => LoginScreen(widget.auth, showBack: true),
                    ),
                  );
                },
                child: const Text(
                  'Đăng nhập',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
            ],
          )
        : null,
    body: SafeArea(
      child: KeyedSubtree(
        key: ValueKey('guest:$selected'),
        child: selected == 0
            ? CatalogPage(
                widget.auth.api,
                null,
                onGuestOrder: _promptOrder,
                onGuestChat: _promptChat,
              )
            : LoginScreen(widget.auth),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      animationDuration: const Duration(milliseconds: 250),
      selectedIndex: selected,
      onDestinationSelected: (index) {
        if (index == 1) widget.onClearPending?.call();
        setState(() => selected = index);
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.grid_view_rounded),
          label: 'Tổng quan',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Tài khoản',
        ),
      ],
    ),
  );
}

class Workspace extends StatefulWidget {
  const Workspace(
    this.auth,
    this.session, {
    this.pendingOrder,
    this.pendingChat,
    this.onPendingConsumed,
    super.key,
  });
  final AuthController auth;
  final Session session;
  final PendingFlowerOrder? pendingOrder;
  final Json? pendingChat;
  final VoidCallback? onPendingConsumed;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  int selected = 0;

  Future<void> _openChats(BuildContext context, ApiClient api, Session user) =>
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: const Text(
                'Tin nhắn',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            body: SafeArea(child: ChatsPage(api, user)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final api = widget.auth.api, user = widget.session;
    final hasChat = user.role != AppRole.technician;
    final labels = switch (user.role) {
      AppRole.technician => [
        'Tổng quan',
        'Công việc',
        'Lắp đặt',
        'Sức khỏe',
        'Tài khoản',
      ],
      AppRole.staff => ['Tổng quan', 'Công việc', 'Tài khoản'],
      AppRole.seller => ['Tổng quan', 'Tủ hoa', 'Đơn hàng', 'Tài khoản'],
      AppRole.customer => ['Tổng quan', 'Đơn đặt', 'Tài khoản'],
    };
    final icons = switch (user.role) {
      AppRole.technician => [
        Icons.grid_view_rounded,
        Icons.assignment_outlined,
        Icons.build_outlined,
        Icons.monitor_heart_outlined,
        Icons.person_outline,
      ],
      AppRole.staff => [
        Icons.grid_view_rounded,
        Icons.assignment_outlined,
        Icons.person_outline,
      ],
      AppRole.seller => [
        Icons.grid_view_rounded,
        Icons.kitchen_outlined,
        Icons.shopping_bag_outlined,
        Icons.person_outline,
      ],
      AppRole.customer => [
        Icons.grid_view_rounded,
        Icons.shopping_bag_outlined,
        Icons.person_outline,
      ],
    };
    final active = selected.clamp(0, labels.length - 1);
    Widget body;
    if (active == 0) {
      body = user.role == AppRole.seller
          ? SellerOverviewPage(api, user, (index) {
              if (index == 3) {
                _openChats(context, api, user);
              } else {
                setState(() => selected = index);
              }
            })
          : user.role == AppRole.customer
          ? CatalogPage(
              api,
              user,
              onOpenOrders: () => setState(() => selected = 1),
              pendingOrder: widget.pendingOrder,
              pendingChat: widget.pendingChat,
              onPendingConsumed: widget.onPendingConsumed,
            )
          : OverviewPage(api, user, (index) {
              if (user.role == AppRole.staff && index == 2) {
                _openChats(context, api, user);
              } else {
                setState(() => selected = index);
              }
            });
    } else if (active == labels.length - 1) {
      body = AccountPage(widget.auth, user);
    } else {
      body = switch (user.role) {
        AppRole.technician => switch (active) {
          1 => TasksPage(api, user),
          2 => InstallationsPage(api),
          _ => TechnicianKioskHealthPage(api: api),
        },
        AppRole.staff => TasksPage(api, user),
        AppRole.seller =>
          active == 1 ? KiosksPage(api, user) : OrdersPage(api, user),
        AppRole.customer => OrdersPage(api, user),
      };
    }
    return Scaffold(
      drawer: user.role == AppRole.seller && active == 0
          ? _SellerOperationsDrawer(
              api: api,
              user: user,
              onOpen: (title, page) {
                Navigator.pop(context);
                openPage(context, title, page);
              },
            )
          : null,
      appBar: active == 0
          ? AppBar(
              centerTitle: true,
              title: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_florist_rounded),
                  SizedBox(width: 8),
                  Text(
                    'FloraBot',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            )
          : null,
      body: SafeArea(
        child: KeyedSubtree(key: ValueKey('${user.role}:$active'), child: body),
      ),
      floatingActionButton: hasChat
          ? FloatingActionButton(
              tooltip: 'Tin nhắn',
              backgroundColor: forest,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              onPressed: () => _openChats(context, api, user),
              child: const Icon(Icons.chat_bubble_outline_rounded),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        animationDuration: const Duration(milliseconds: 250),
        selectedIndex: active,
        onDestinationSelected: (index) => setState(() => selected = index),
        destinations: [
          for (var i = 0; i < labels.length; i++)
            NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
        ],
      ),
    );
  }
}

class _SellerOperationsDrawer extends StatelessWidget {
  const _SellerOperationsDrawer({
    required this.api,
    required this.user,
    required this.onOpen,
  });
  final ApiClient api;
  final Session user;
  final void Function(String, Widget) onOpen;

  @override
  Widget build(BuildContext context) {
    final entries = <(IconData, String, Widget Function())>[
      (
        Icons.local_florist_outlined,
        'Mẫu hoa và phụ kiện',
        () => _SellerSectionTabs(
          labels: const ['Mẫu hoa', 'Phụ kiện'],
          pages: [
            () => ProductsPage(api, user),
            () => AccessoriesPage(api, user),
          ],
        ),
      ),
      (
        Icons.support_agent_outlined,
        'Phản ánh chất lượng',
        () => ComplaintsPage(api, user),
      ),
      (
        Icons.people_outline,
        'Nhân viên shop',
        () => _SellerSectionTabs(
          labels: const ['Nhân viên', 'Giao việc'],
          pages: [
            () => StaffManagementPage(api, user),
            () => TasksPage(api, user),
          ],
        ),
      ),
      (
        Icons.account_balance_outlined,
        'Kênh thanh toán',
        () => PaymentChannelPage(api, user),
      ),
      (
        Icons.payments_outlined,
        'Hoàn tiền trực tiếp',
        () => SellerRefundsPage(api, user),
      ),
      (
        Icons.insights_outlined,
        'Doanh số và dự báo',
        () => InsightsPage(api, user),
      ),
      (
        Icons.event_repeat_outlined,
        'Kỳ thuê kiosk',
        () => _SellerSectionTabs(
          labels: const ['Kỳ thuê & gia hạn', 'Chấm dứt thuê'],
          pages: [
            () => SubscriptionsPage(api, user),
            () => TerminationsPage(api, user),
          ],
        ),
      ),
    ];
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Vận hành shop',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: forest,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng menu',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 22),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
                children: [
                  for (final entry in entries)
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(entry.$1, size: 21, color: forest),
                      title: Text(
                        entry.$2,
                        style: const TextStyle(fontSize: 14),
                      ),
                      onTap: () => onOpen(entry.$2, entry.$3()),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerSectionTabs extends StatefulWidget {
  const _SellerSectionTabs({required this.labels, required this.pages});
  final List<String> labels;
  final List<Widget Function()> pages;

  @override
  State<_SellerSectionTabs> createState() => _SellerSectionTabsState();
}

class _SellerSectionTabsState extends State<_SellerSectionTabs> {
  int selected = 0;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: widget.labels.length,
    child: Column(
      children: [
        TabBar(
          labelColor: forest,
          unselectedLabelColor: const Color(0xFF617568),
          indicatorColor: forest,
          dividerColor: Colors.transparent,
          onTap: (index) => setState(() => selected = index),
          tabs: [for (final label in widget.labels) Tab(text: label)],
        ),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey(selected),
            child: widget.pages[selected](),
          ),
        ),
      ],
    ),
  );
}

class OverviewPage extends StatelessWidget {
  const OverviewPage(this.api, this.session, this.navigate, {super.key});
  final ApiClient api;
  final Session session;
  final void Function(int) navigate;
  @override
  Widget build(BuildContext context) {
    final path = switch (session.role) {
      AppRole.technician || AppRole.staff => '/api/staff/tasks?page=1',
      AppRole.seller => '/api/sellers/${session.sellerId}/preorders?page=1',
      AppRole.customer => '/api/member/preorders?page=1',
    };
    return ResourceView(
      load: () => api.get(path),
      builder: (context, data, state) {
        final items = itemsOf(data);
        final waiting = items
            .where(
              (r) => [
                'ASSIGNED',
                'SUBMITTED',
                'REQUESTED',
                'QUOTED',
                'AWAITING_PAYMENT',
              ].contains(r['status'] ?? r['orderStatus'] ?? r['state']),
            )
            .length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WorkspaceWelcome(session),
            if (session.sellerStatus != null &&
                session.sellerStatus != 'ACTIVE')
              InfoBox(
                'Shop: ${statusText(session.sellerStatus)}. Một số thao tác có thể bị giới hạn theo hợp đồng.',
                warning: true,
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: RecordCard(
                    title: '$waiting',
                    subtitle: 'Cần chú ý trên trang này',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RecordCard(
                    title: '${items.length}',
                    subtitle: 'Mục trên trang hiện tại',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Bắt đầu từ đây',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            RecordCard(
              title: switch (session.role) {
                AppRole.technician || AppRole.staff => 'Công việc được giao',
                AppRole.seller => 'Kiểm tra hoa tại tủ',
                AppRole.customer => 'Khám phá mẫu hoa',
              },
              subtitle: session.role.description,
              onTap: () => navigate(1),
            ),
            RecordCard(
              title: session.role == AppRole.technician
                  ? 'Lịch lắp đặt kiosk'
                  : session.role == AppRole.staff
                  ? 'Trao đổi với chủ shop'
                  : 'Theo dõi đơn đặt trước',
              subtitle: 'Xem trạng thái mới nhất từ hệ thống.',
              onTap: () => navigate(2),
            ),
            if (session.role == AppRole.customer)
              const InfoBox(
                'Mã nhận hoa 8 số được gửi qua email sau khi shop đã nạp đơn. Bạn nhập mã tại đúng kiosk trong khung giờ nhận.',
              ),
            if (session.role == AppRole.technician ||
                session.role == AppRole.staff)
              const InfoBox(
                'Chỉ lấy OTP trong đúng công việc đang thực hiện. Không tự xác nhận cửa mở hoặc hàng đã nạp khi chưa có phản hồi hợp lệ.',
              ),
            const FlowerJourney(),
            const SizedBox(height: 16),
            const Text(
              'Gần đây',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            if (items.isEmpty)
              const InfoBox('Chưa có công việc hoặc đơn đặt trong danh sách.'),
            for (final item in items.take(3))
              RecordCard(
                title: valueOf(
                  item,
                  'productName',
                  valueOf(item, 'kioskName', 'Theo dõi tiến độ'),
                ),
                subtitle: valueOf(
                  item,
                  'instructions',
                  valueOf(item, 'orderCode', ''),
                ),
                status: item['status'] ?? item['orderStatus'] ?? item['state'],
              ),
          ],
        );
      },
    );
  }
}

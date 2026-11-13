import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/auth.dart';
import '../core/models.dart';
import '../ui/common.dart';
import '../ui/brand.dart';
import 'account.dart';
import 'chat.dart';
import 'inventory.dart';
import 'orders.dart';
import 'tasks.dart';

class Workspace extends StatefulWidget {
  const Workspace(this.auth, this.session, {super.key});
  final AuthController auth;
  final Session session;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  int selected = 0;
  @override
  Widget build(BuildContext context) {
    final api = widget.auth.api, user = widget.session;
    final labels = switch (user.role) {
      AppRole.technician => ['Tổng quan', 'Công việc', 'Lắp đặt', 'Tài khoản'],
      AppRole.staff => ['Tổng quan', 'Công việc', 'Tin nhắn', 'Tài khoản'],
      AppRole.seller => [
        'Tổng quan',
        'Tủ hoa',
        'Đơn hàng',
        'Tin nhắn',
        'Tài khoản',
      ],
      AppRole.customer => [
        'Tổng quan',
        'Khám phá',
        'Đơn đặt',
        'Tin nhắn',
        'Tài khoản',
      ],
    };
    final icons = switch (user.role) {
      AppRole.technician => [
        Icons.grid_view_rounded,
        Icons.assignment_outlined,
        Icons.build_outlined,
        Icons.person_outline,
      ],
      AppRole.staff => [
        Icons.grid_view_rounded,
        Icons.assignment_outlined,
        Icons.chat_bubble_outline,
        Icons.person_outline,
      ],
      AppRole.seller => [
        Icons.grid_view_rounded,
        Icons.kitchen_outlined,
        Icons.shopping_bag_outlined,
        Icons.chat_bubble_outline,
        Icons.person_outline,
      ],
      AppRole.customer => [
        Icons.grid_view_rounded,
        Icons.local_florist_outlined,
        Icons.shopping_bag_outlined,
        Icons.chat_bubble_outline,
        Icons.person_outline,
      ],
    };
    Widget body;
    if (selected == 0) {
      body = OverviewPage(
        api,
        user,
        (index) => setState(() => selected = index),
      );
    } else if (selected == labels.length - 1) {
      body = AccountPage(widget.auth, user);
    } else {
      body = switch (user.role) {
        AppRole.technician =>
          selected == 1 ? TasksPage(api, user) : InstallationsPage(api),
        AppRole.staff =>
          selected == 1 ? TasksPage(api, user) : ChatsPage(api, user),
        AppRole.seller =>
          selected == 1
              ? KiosksPage(api, user)
              : selected == 2
              ? OrdersPage(api, user)
              : ChatsPage(api, user),
        AppRole.customer =>
          selected == 1
              ? CatalogPage(api, user)
              : selected == 2
              ? OrdersPage(api, user)
              : ChatsPage(api, user),
      };
    }
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.local_florist_rounded),
            SizedBox(width: 8),
            Text('FloraBot', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                user.role.label,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: KeyedSubtree(
          key: ValueKey('${user.role}:$selected'),
          child: body,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (index) => setState(() => selected = index),
        destinations: [
          for (var i = 0; i < labels.length; i++)
            NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
        ],
      ),
    );
  }
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

import 'package:flutter/material.dart';
import '../core/models.dart';
import 'common.dart';

abstract final class BrandImages {
  static const hero = 'assets/images/florabot-hero.webp';
  static const pattern = 'assets/images/florabot-pattern.webp';
  static const process = 'assets/images/florabot-process.png';
  static const stock = 'assets/images/florabot-step-stock.webp';
}

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key});
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Icon(Icons.local_florist_rounded, color: forest, size: 30),
      SizedBox(width: 7),
      Text(
        'FloraBot',
        style: TextStyle(
          color: forest,
          fontSize: 27,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
      ),
    ],
  );
}

class FloralBackdrop extends StatelessWidget {
  const FloralBackdrop({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: ExcludeSemantics(
          child: Opacity(
            opacity: .045,
            child: Image.asset(
              BrandImages.pattern,
              fit: BoxFit.cover,
              repeat: ImageRepeat.repeat,
            ),
          ),
        ),
      ),
      child,
    ],
  );
}

class LoginArtwork extends StatelessWidget {
  const LoginArtwork({super.key});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: SizedBox(
      height: 190,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            BrandImages.hero,
            fit: BoxFit.cover,
            semanticLabel: 'Tủ hoa FloraBot giữa vườn tulip và cúc họa mi',
          ),
          Positioned(
            left: 14,
            bottom: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: forest,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.spa_outlined, color: Color(0xFFD6E6BB), size: 15),
                  SizedBox(width: 6),
                  Text(
                    'MỘT CHÚT HOA, MỘT NGÀY VUI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class WorkspaceWelcome extends StatelessWidget {
  const WorkspaceWelcome(this.session, {super.key});
  final Session session;
  @override
  Widget build(BuildContext context) {
    final stock =
        session.role == AppRole.staff || session.role == AppRole.seller;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: forest,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Image.asset(
                stock ? BrandImages.stock : BrandImages.hero,
                height: 178,
                width: double.infinity,
                fit: BoxFit.cover,
                alignment: stock ? const Alignment(0, -.25) : Alignment.center,
                semanticLabel: stock
                    ? 'Chăm chút từng bó hoa trước khi nạp vào kiosk'
                    : 'Kiosk hoa FloraBot',
              ),
              Positioned(
                top: 14,
                left: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8EA),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    session.role.label,
                    style: const TextStyle(
                      color: forest,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 19, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Xin chào, ${session.name}',
                  style: const TextStyle(
                    color: Color(0xFFD6E6BB),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  switch (session.role) {
                    AppRole.technician => 'Sẵn sàng cho\nca làm hôm nay?',
                    AppRole.staff =>
                      'Chăm chút từng bó hoa.\nSẵn sàng mỗi điểm nhận.',
                    AppRole.seller => 'Shop của bạn,\ntrong tầm tay.',
                    AppRole.customer => 'Gửi một chút hoa.\nTrao cả niềm vui.',
                  },
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.2,
                    letterSpacing: -.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FlowerJourney extends StatelessWidget {
  const FlowerJourney({super.key});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8EA),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE8E2D2)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(17, 17, 17, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HÀNH TRÌNH MỘT BÓ HOA',
                style: TextStyle(
                  color: forest,
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Từ bàn tay chăm chút,\nđến niềm vui người nhận.',
                style: TextStyle(
                  color: forest,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        Image.asset(
          BrandImages.process,
          fit: BoxFit.fitWidth,
          semanticLabel:
              'Shop chuẩn bị hoa, nạp vào kiosk và quản lý trên ứng dụng',
        ),
        const Padding(
          padding: EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '01  Chuẩn bị',
                  style: TextStyle(color: forest, fontSize: 11),
                ),
              ),
              Expanded(
                child: Text(
                  '02  Nạp hoa',
                  style: TextStyle(color: forest, fontSize: 11),
                ),
              ),
              Expanded(
                child: Text(
                  '03  Theo dõi',
                  style: TextStyle(color: forest, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../ui/common.dart';

Uri? floraBotQrLink(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    return null;
  }
  const allowed = {
    'florabot.site',
    'www.florabot.site',
    'florabot-fe.vercel.app',
    'florabot-kiosk.vercel.app',
  };
  return allowed.contains(uri.host.toLowerCase()) ? uri : null;
}

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});
  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage>
    with WidgetsBindingObserver {
  final controller = MobileScannerController(
    autoStart: false,
    formats: [BarcodeFormat.qrCode],
  );
  bool handling = false;
  bool active = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.start();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active && !handling) {
      controller.start();
    } else {
      controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  Future<void> detected(BarcodeCapture capture) async {
    if (handling || !active) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null) return;
    handling = true;
    await controller.stop();
    if (!mounted) return;
    final uri = floraBotQrLink(value);
    if (uri == null) {
      message(context, 'Mã này không phải liên kết FloraBot được hỗ trợ.');
    } else {
      try {
        if (await confirm(
          context,
          'Mở liên kết FloraBot?',
          'Chuyển đến ${uri.host} trong trình duyệt.',
        )) {
          await openSafeLink(uri.toString());
        }
      } catch (e) {
        if (mounted) message(context, '$e');
      }
    }
    handling = false;
    if (mounted && active) await controller.start();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Đưa mã QR liên kết FloraBot vào khung hình.'),
      ),
      Expanded(
        child: MobileScanner(
          controller: controller,
          onDetect: detected,
          errorBuilder: (context, error) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Chưa mở được camera. Kiểm tra quyền camera của ứng dụng.',
                ),
                TextButton(
                  onPressed: () => controller.start(),
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

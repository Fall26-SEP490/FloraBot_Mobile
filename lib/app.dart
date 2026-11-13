import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/auth.dart';
import 'features/auth_screens.dart';
import 'features/workspace.dart';
import 'ui/common.dart';

class FloraBotApp extends StatefulWidget {
  const FloraBotApp({required this.auth, super.key});
  final AuthController auth;
  @override
  State<FloraBotApp> createState() => _FloraBotAppState();
}

class _FloraBotAppState extends State<FloraBotApp> with WidgetsBindingObserver {
  bool hidden = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.auth.loading) unawaited(widget.auth.restore());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() => hidden = state != AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed && widget.auth.session != null) {
      unawaited(widget.auth.revalidate());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.auth,
    builder: (context, _) {
      final session = widget.auth.session;
      return MaterialApp(
        key: ValueKey('${session?.id}:${session?.role.code}'),
        title: 'FloraBot',
        debugShowCheckedModeBanner: false,
        locale: const Locale('vi', 'VN'),
        supportedLocales: const [Locale('vi', 'VN'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: forest),
          scaffoldBackgroundColor: paper,
          appBarTheme: const AppBarTheme(
            backgroundColor: paper,
            foregroundColor: forest,
            elevation: 0,
            centerTitle: false,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFD4E0D4)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFFE0E8DC)),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: forest,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: forest,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          navigationBarTheme: const NavigationBarThemeData(
            backgroundColor: Colors.white,
            indicatorColor: Color(0xFFE3EEDC),
          ),
        ),
        builder: (context, child) => Stack(
          children: [
            ?child,
            if (hidden)
              const Positioned.fill(
                child: ColoredBox(
                  color: paper,
                  child: Center(
                    child: Icon(Icons.local_florist, color: forest, size: 72),
                  ),
                ),
              ),
          ],
        ),
        home: widget.auth.loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : widget.auth.waitingForConnection
            ? Scaffold(
                body: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off, size: 48, color: forest),
                          const SizedBox(height: 16),
                          Text(
                            widget.auth.error ??
                                'Đang chờ kết nối để khôi phục phiên.',
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: widget.auth.restore,
                            child: const Text('Thử kết nối lại'),
                          ),
                          TextButton(
                            onPressed: widget.auth.logout,
                            child: const Text('Đăng xuất trên thiết bị'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : session == null
            ? LoginScreen(widget.auth)
            : Workspace(
                widget.auth,
                session,
                key: ValueKey('${session.id}:${session.role}'),
              ),
      );
    },
  );
}

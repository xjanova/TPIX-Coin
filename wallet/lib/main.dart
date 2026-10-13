import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/locale_provider.dart';
import 'core/theme_provider.dart';
import 'providers/wallet_provider.dart';
import 'providers/update_provider.dart';
import 'services/bug_reporter.dart';
import 'services/walletconnect_service.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  // error ที่หลุดจาก async ใดๆ ถูกส่งเข้าระบบรายงานบั๊กกลาง — ไม่ต้องเดาว่าแอปพังตรงไหน
  await runZonedGuarded(
    _boot,
    (error, stack) => BugReporter.I.reportError(error, stack, context: 'zone', fatal: true),
  );
}

Future<void> _boot() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BugReporter.I.install(product: 'tpix-wallet');
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final localeProvider = LocaleProvider();
  final themeProvider = ThemeProvider();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProvider.value(value: localeProvider),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => WalletConnectService()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
      ],
      child: FutureBuilder(
        future: Future.wait([localeProvider.init(), themeProvider.init()]),
        // รอธีม/ภาษาที่บันทึกไว้ก่อนค่อยวาดแอป (อ่าน SharedPreferences ไม่กี่มิลลิวินาที)
        // ไม่งั้นเฟรมแรกจะเป็นธีมเริ่มต้นแล้วค่อยครอสเฟดไปธีมที่ผู้ใช้เลือก —
        // และธีม Obsidian จะสร้างตัวเล่นวิดีโอขึ้นมาแล้วทิ้งเปล่า ๆ
        builder: (_, snap) => snap.connectionState == ConnectionState.done
            ? const TPIXWalletApp()
            : const ColoredBox(color: Color(0xFF07080C)),
      ),
    ),
  );
}

class TPIXWalletApp extends StatelessWidget {
  const TPIXWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    final themeProv = context.watch<ThemeProvider>();
    final bundle = themeProv.current;

    // Theme-aware system UI (status bar + nav bar)
    final isDark = locale.isDark || !bundle.supportsLight;
    final lightData = bundle.buildLight();
    final darkData = bundle.buildDark();
    final activeData = isDark ? darkData : lightData;
    final navBarColor = activeData.scaffoldBackgroundColor == Colors.transparent
        ? (activeData.extension<dynamic>() != null
            ? darkData.colorScheme.surface
            : Colors.black)
        : activeData.scaffoldBackgroundColor;

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: navBarColor,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    ));

    return MaterialApp(
      title: 'TPIX Wallet',
      debugShowCheckedModeBanner: false,
      theme: lightData,
      darkTheme: darkData,
      themeMode: bundle.supportsLight ? locale.themeMode : ThemeMode.dark,
      // wrapApp injects theme overlay (sun grid / scanlines / nothing)
      // ผ่าน MaterialApp.builder → ทุกหน้าได้ overlay อัตโนมัติ
      // AnimatedSwitcher ทำ crossfade ระหว่างธีม (key=themeId → switch trigger)
      builder: (context, child) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: KeyedSubtree(
            key: ValueKey(bundle.id),
            child: bundle.wrapApp(context, child ?? const SizedBox()),
          ),
        );
      },
      home: const SplashScreen(),
    );
  }
}

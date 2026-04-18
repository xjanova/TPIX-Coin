import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/locale_provider.dart';
import 'core/theme_provider.dart';
import 'providers/wallet_provider.dart';
import 'providers/update_provider.dart';
import 'services/walletconnect_service.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        builder: (_, __) => const TPIXWalletApp(),
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

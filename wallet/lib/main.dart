import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/locale_provider.dart';
import 'core/theme.dart';
import 'providers/wallet_provider.dart';
import 'services/walletconnect_service.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final localeProvider = LocaleProvider();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProvider.value(value: localeProvider),
        ChangeNotifierProvider(create: (_) => WalletConnectService()),
      ],
      child: FutureBuilder(
        future: localeProvider.init(),
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

    // Update system UI overlay based on theme
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: locale.isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: locale.isDark ? AppTheme.bgDark : AppTheme.bgLight,
      systemNavigationBarIconBrightness: locale.isDark ? Brightness.light : Brightness.dark,
    ));

    return MaterialApp(
      title: 'TPIX Wallet',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: locale.themeMode,
      home: const SplashScreen(),
    );
  }
}

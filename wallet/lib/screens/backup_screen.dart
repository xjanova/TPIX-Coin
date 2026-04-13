import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import 'pin_screen.dart';

class BackupScreen extends StatefulWidget {
  final String mnemonic;
  const BackupScreen({super.key, required this.mnemonic});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  late String _mnemonic;
  Timer? _autoClearTimer;
  int _secondsLeft = 60;
  bool _cleared = false;

  @override
  void initState() {
    super.initState();
    _mnemonic = widget.mnemonic;
    // Prevent screenshots
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
    // Auto-clear mnemonic after 60 seconds
    _autoClearTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          _clearMnemonic();
        }
      });
    });
  }

  @override
  void dispose() {
    _autoClearTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _clearMnemonic() {
    _autoClearTimer?.cancel();
    setState(() {
      _mnemonic = '';
      _cleared = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final c = AppColors.of(context);
    final words = _mnemonic.isNotEmpty ? _mnemonic.split(' ') : <String>[];

    return Scaffold(
      body: Container(
        decoration: AppColors.of(context).screenBg,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_ios, color: c.text),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.t('backup.title'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
                        Text(l.t('backup.subtitle'), style: TextStyle(fontSize: 12, color: c.textMuted)),
                      ],
                    ),
                    const Spacer(),
                    // Countdown
                    if (!_cleared)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: (_secondsLeft <= 10 ? AppTheme.danger : AppTheme.warm).withValues(alpha: 0.15),
                        ),
                        child: Text(
                          '${_secondsLeft}s',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _secondsLeft <= 10 ? AppTheme.danger : AppTheme.warm,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 24),

                // Warning
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: AppTheme.warm.withValues(alpha: 0.1),
                    border: Border.all(color: AppTheme.warm.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppTheme.warm, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l.t('backup.warning'),
                          style: const TextStyle(fontSize: 13, color: AppTheme.warm, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Words grid or cleared message
                Expanded(
                  child: _cleared
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.timer_off, size: 48, color: c.textMuted.withValues(alpha: 0.4)),
                              const SizedBox(height: 16),
                              Text(l.t('backup.autoCleared'),
                                  style: TextStyle(fontSize: 16, color: c.textMuted)),
                            ],
                          ),
                        )
                      : GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 2.5,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: words.length,
                          itemBuilder: (_, i) => Container(
                            decoration: glassCard(borderRadius: 12),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('${i + 1}. ', style: TextStyle(fontSize: 12, color: c.textMuted)),
                                Text(words[i], style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                              ],
                            ),
                          ),
                        ),
                ),

                const SizedBox(height: 16),

                // Copy button
                if (!_cleared)
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _mnemonic));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.t('backup.copied')), backgroundColor: AppTheme.success),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 18, color: AppTheme.primary),
                      label: Text(l.t('backup.copy'), style: const TextStyle(color: AppTheme.primary)),
                    ),
                  ),

                const SizedBox(height: 16),

                // Continue button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      _clearMnemonic();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const PinScreen(isSetup: true)),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(l.t('backup.continue'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

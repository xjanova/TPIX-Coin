import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/themes/tokens.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../core/themes/theme_bundle.dart';
import '../core/themes/widgets/screen_background.dart';
import '../widgets/obsidian/obsidian.dart';
import '../widgets/obsidian/obsidian_screen_header.dart';
import 'pin_screen.dart';

class BackupScreen extends StatefulWidget {
  final String mnemonic;

  /// เปิดมาจากหน้าตั้งค่าเพื่อ "ดูวลีอย่างเดียว" — ปุ่มล่างคือ "เสร็จสิ้น" แล้วกลับหน้าเดิม
  /// (false = ขั้นตอนสร้างกระเป๋าใหม่ ต่อไปตั้ง PIN ตามเดิม)
  /// เดิมทุกทางพาไปตั้ง PIN ใหม่ + บันทึกกระเป๋าซ้ำ ทั้งที่ผู้ใช้แค่เข้ามาดูวลี
  final bool viewOnly;

  const BackupScreen({super.key, required this.mnemonic, this.viewOnly = false});

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

  /// ปุ่มล่าง: ล้างวลีออกจากหน่วยความจำก่อนเสมอ แล้วไปต่อตามที่มา
  void _onContinue() {
    _clearMnemonic();
    if (widget.viewOnly) {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const PinScreen(isSetup: true)),
    );
  }

  void _clearMnemonic() {
    _autoClearTimer?.cancel();
    setState(() {
      _mnemonic = '';
      _cleared = true;
    });
  }

  /// ธีม Obsidian — นับถอยหลัง/ล้างอัตโนมัติ/คัดลอก/ไปต่อ เหมือนเดิมทุกอย่าง
  Widget _buildObsidian(LocaleProvider l, List<String> words) {
    final st = ObsidianStyle.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final urgent = _secondsLeft <= 10;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: EdgeInsets.fromLTRB(24, math.max(52.0, top + 8), 24, math.max(24.0, MediaQuery.paddingOf(context).bottom + 12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ObsidianScreenHeader(
              title: l.t('backup.title'),
              backSemantics: MaterialLocalizations.of(context).backButtonTooltip,
              trailing: _cleared
                  ? null
                  : SizedBox(
                      width: 46,
                      height: 46,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (urgent ? ObsidianColors.danger : ObsidianColors.warning).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${_secondsLeft}s',
                            style: st.number(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: urgent ? ObsidianColors.dangerSoft : ObsidianColors.warning,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ObsidianColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: ObsidianColors.warning.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: ObsidianColors.warning, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(l.t('backup.warning'),
                        style: st.ui(fontSize: 13, height: 1.5, color: ObsidianColors.warning)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _cleared
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon3D(ObsidianIcons.lock, size: 64, dimmed: true),
                        const SizedBox(height: 14),
                        Text(l.t('backup.autoCleared'), style: st.ui(fontSize: 15, color: ObsidianColors.textSec)),
                      ],
                    )
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 2.4,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: words.length,
                      itemBuilder: (_, i) => ObsidianPanel(
                        surface: ObsidianSurface.field.copyWith(radius: 14),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('${i + 1}', style: st.number(fontSize: 11, color: ObsidianColors.textMuted)),
                            const SizedBox(width: 6),
                            // คำยาว (เช่น "irresistible") ต้องไม่ล้นช่อง
                            Flexible(
                              child: Text(
                                words[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: st.ui(fontSize: 15, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (!_cleared) ...[
              const SizedBox(height: 12),
              ObsidianButton.secondary(
                label: l.t('backup.copy'),
                trailingIcon: Icons.copy_rounded,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _mnemonic));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.t('backup.copied'))));
                },
              ),
            ],
            const SizedBox(height: 12),
            ObsidianButton(
              label: l.t(widget.viewOnly ? 'backup.done' : 'backup.continue'),
              onPressed: _onContinue,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final words = _mnemonic.isNotEmpty ? _mnemonic.split(' ') : <String>[];
    if (TpixThemeExtension.of(context).themeId == ThemeId.obsidian) return _buildObsidian(l, words);
    final c = AppColors.of(context);

    return Scaffold(
      body: TpixScreenBackground(
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
                    const SizedBox(width: TpixGap.sm),
                    Expanded(
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.t('backup.title'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
                        Text(l.t('backup.subtitle'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: c.textMuted)),
                      ],
                      ),
                    ),
                    const SizedBox(width: TpixGap.sm),
                    // Countdown
                    if (!_cleared)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(TpixRadius.xs),
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

                const SizedBox(height: TpixGap.xxl),

                // Warning
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(TpixRadius.md),
                    color: AppTheme.warm.withValues(alpha: 0.1),
                    border: Border.all(color: AppTheme.warm.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppTheme.warm, size: 28),
                      const SizedBox(width: TpixGap.md),
                      Expanded(
                        child: Text(
                          l.t('backup.warning'),
                          style: const TextStyle(fontSize: 13, color: AppTheme.warm, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: TpixGap.xxl),

                // Words grid or cleared message
                Expanded(
                  child: _cleared
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.timer_off, size: 48, color: c.textMuted.withValues(alpha: 0.4)),
                              const SizedBox(height: TpixGap.lg),
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
                            decoration: adaptiveGlassCard(context, borderRadius: 12),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('${i + 1}. ', style: TextStyle(fontSize: 12, color: c.textMuted)),
                                // คำกู้คืนบางคำยาว (เช่น "irresistible") ช่องกริดแคบ
                                // ไม่ครอบ Flexible = ล้นขอบช่องทุกใบ
                                Flexible(
                                  child: Text(words[i],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),

                const SizedBox(height: TpixGap.lg),

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

                const SizedBox(height: TpixGap.lg),

                // Continue button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _onContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.md)),
                    ),
                    child: Text(l.t(widget.viewOnly ? 'backup.done' : 'backup.continue'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
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

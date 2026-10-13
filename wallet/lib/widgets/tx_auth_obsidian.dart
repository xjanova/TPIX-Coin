// TPIX Wallet — ใส่ PIN ยืนยันธุรกรรม ธีม Obsidian (ตาม A-Pin.dc.html)
//
// เป็น part ของ tx_auth.dart: authorizeTransaction เปิดหน้านี้แทนกล่อง PIN เดิมเมื่อใช้ธีม Obsidian
//
// กติกาความปลอดภัยเหมือนกล่องเดิมทุกข้อ:
//   - ก่อนตรวจทุกครั้งถาม WalletService.isPinLocked() ก่อน — ล็อกอยู่ = ไม่ตรวจ บอกเวลารอ
//   - ตรวจผ่าน wallet.unlock(pin) ตัวเดิม (นับครั้งผิด + ล็อกชั่วคราวอยู่ในนั้น)
//   - คืน true เฉพาะ PIN ถูก/สแกนนิ้วผ่าน · ปิดหน้า/ย้อนกลับ = false
// ต่างจากกล่องเดิม: PIN ผิดแล้วไม่ปิดหน้า แต่สั่น + บอก "PIN ไม่ถูกต้อง" ให้ลองใหม่
// (กล่องเดิมปิดเงียบ ๆ ผู้ใช้ไม่รู้ว่าผิด) — ทุกครั้งที่ลองยังถูกนับใน WalletService เหมือนเดิม
//
// Developed by Xman Studio

part of 'tx_auth.dart';

class ObsidianPinVerifyPage extends StatefulWidget {
  /// ข้อความที่ระบบสแกนนิ้วแสดง (เหมือนที่ authorizeTransaction ใช้)
  final String reason;
  final TxAuthSummary? summary;

  /// เครื่องนี้เปิดใช้สแกนนิ้วไว้ → มีปุ่มสแกนนิ้วที่แป้นซ้ายล่าง
  final bool biometric;

  const ObsidianPinVerifyPage({super.key, required this.reason, this.summary, this.biometric = false});

  /// เลื่อนขึ้นจากล่าง + จางเข้า (pnIn) — ปิดด้วยปุ่มย้อนกลับ = ยกเลิก
  static Route<bool> route({required String reason, TxAuthSummary? summary, bool biometric = false}) =>
      PageRouteBuilder<bool>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, _, _) => ObsidianPinVerifyPage(reason: reason, summary: summary, biometric: biometric),
        transitionsBuilder: (_, anim, _, child) {
          final t = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: t,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(t),
              child: child,
            ),
          );
        },
      );

  @override
  State<ObsidianPinVerifyPage> createState() => _ObsidianPinVerifyPageState();
}

class _ObsidianPinVerifyPageState extends State<ObsidianPinVerifyPage> with SingleTickerProviderStateMixin {
  String _pin = '';

  /// กำลังตรวจ PIN (กันตรวจซ้อน + ล็อกแป้น)
  bool _checking = false;

  bool _scanning = false;

  /// ข้อความผิดพลาดใต้จุด (PIN ผิด / ถูกล็อก) — null = ไม่มี
  String? _error;

  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _onDigit(String d) {
    if (_checking || _scanning || _pin.length >= 6) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == 6) _verify();
  }

  void _onDelete() {
    if (_checking || _pin.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  Future<void> _verify() async {
    if (_checking) return;
    final l = context.read<LocaleProvider>();
    final wallet = context.read<WalletProvider>();
    setState(() => _checking = true);

    // ล็อกชั่วคราวอยู่ → ไม่ตรวจเลย (ไม่เปิดช่องเดา PIN ระหว่างล็อก)
    final service = WalletService();
    if (await service.isPinLocked()) {
      final remaining = await service.getPinLockRemaining();
      if (!mounted) return;
      _fail(l.t('pin.locked').replaceAll('{s}', '$remaining'));
      return;
    }
    if (!mounted) return;

    final ok = await wallet.unlock(_pin);
    if (!mounted) return;
    // ผู้ใช้กดปิดไประหว่างตรวจ → หน้านี้ไม่ใช่หน้าบนสุดแล้ว ห้าม pop (จะไปปิดหน้าส่งทิ้ง)
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    _fail(l.t('pin.wrong'));
  }

  void _fail(String message) {
    HapticFeedback.heavyImpact();
    SynthService.playError();
    setState(() {
      _checking = false;
      _pin = '';
      _error = message;
    });
    _shake.forward(from: 0);
  }

  Future<void> _biometric() async {
    if (_checking || _scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
    });
    final ok = await BiometricService().authenticate(widget.reason);
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final st = ObsidianStyle.of(context);
    final topInset = MediaQuery.paddingOf(context).top;

    final title = _scanning
        ? l.t('obs.pin.scanning')
        : _checking
        ? l.t('obs.pin.verifying')
        : l.t('obs.pin.title');
    final subtitle = _checking
        ? l.t('obs.pin.verifyingSub')
        : widget.biometric
        ? l.t('obs.pin.orBio')
        : l.t('obs.pin.sub');
    final hero = _scanning
        ? ObsidianIcons.fingerprint
        : _checking
        ? ObsidianIcons.shield
        : ObsidianIcons.lock;
    final mode = _error != null
        ? PinDotsMode.error
        : _checking
        ? PinDotsMode.busy
        : PinDotsMode.entering;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, box) {
          return Stack(
            children: [
              const ObsidianScrim.pin(),
              SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, math.max(52.0, topInset + 8), 24, 24),
                    child: Column(
                      children: [
                        ObsidianTopBar(
                          leading: ObsidianTopButton(
                            blur: 0,
                            onTap: () => obsidianPopIfCurrent(context, false),
                            semanticLabel: l.t('send.cancel'),
                            child: const ObsidianGlyphIcon(ObsidianGlyph.close, strokeWidth: 2.2),
                          ),
                          center: widget.summary == null ? const SizedBox.shrink() : _summaryPill(widget.summary!, st),
                        ),
                        const SizedBox(height: 16 + 18),
                        ObsidianFloatingHero(asset: hero),
                        const SizedBox(height: 16),
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: st.ui(fontSize: 19, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: st.ui(fontSize: 13, color: ObsidianColors.textSec),
                        ),
                        const SizedBox(height: 16),
                        AnimatedBuilder(
                          animation: _shake,
                          builder: (_, child) => Transform.translate(
                            offset: Offset(math.sin(_shake.value * math.pi * 4) * 10, 0),
                            child: child,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 6),
                            child: ObsidianPinDots(
                              count: _pin.length,
                              mode: mode,
                              semanticLabel: l.t('obs.pin.progress').replaceAll('{n}', '${_pin.length}'),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          child: _error == null
                              ? null
                              : Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      _error!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: st.ui(fontSize: 13, color: ObsidianColors.danger),
                                    ),
                                  ),
                                ),
                        ),
                        ObsidianKeypad(
                          onDigit: _onDigit,
                          onDelete: _onDelete,
                          onBiometric: widget.biometric ? _biometric : null,
                          biometricActive: _scanning,
                          enabled: !_checking,
                          biometricLabel: l.t('obs.pin.bio'),
                          deleteLabel: l.t('obs.pin.delete'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// ป้ายดำโปร่ง: โลโก้เหรียญ + "ส่ง 1,500 TPIX" + "ถึง … · 0x…"
  Widget _summaryPill(TxAuthSummary s, ObsidianStyle st) {
    return Container(
      padding: EdgeInsets.fromLTRB(s.leading == null ? 14 : 6, 6, 14, 6),
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.leading != null) ...[SizedBox.square(dimension: 30, child: s.leading), const SizedBox(width: 10)],
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: st.ui(fontSize: 13, fontWeight: FontWeight.w600, height: 1.25, color: ObsidianColors.text),
                ),
                if (s.subtitle != null)
                  Text(
                    s.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: st.ui(fontSize: 11, height: 1.25, color: ObsidianColors.textSec),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

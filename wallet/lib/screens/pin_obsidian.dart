// TPIX Wallet — หน้า PIN (ปลดล็อก / ตั้ง PIN) ธีม Obsidian (ตาม A-Pin.dc.html)
//
// เป็น part ของ pin_screen.dart โดยตั้งใจ: ใช้ตรรกะเดิมทั้งหมด (สแกนนิ้วอัตโนมัติ,
// ล็อกชั่วคราวเมื่อผิดเกิน, นับครั้งผิด, ตั้ง PIN + ยืนยัน, สั่นเมื่อผิด) — เปลี่ยนแค่หน้าตา
//
// Developed by Xman Studio

part of 'pin_screen.dart';

extension _ObsidianPin on _PinScreenState {
  Widget _buildObsidianPin(LocaleProvider l, String title, String subtitle) {
    final st = ObsidianStyle.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final scanning = _biometricInProgress;
    final mode = _isError
        ? PinDotsMode.error
        : _verifying
        ? PinDotsMode.busy
        : PinDotsMode.entering;
    final hero = scanning
        ? ObsidianIcons.fingerprint
        : _verifying
        ? ObsidianIcons.shield
        : ObsidianIcons.lock;

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
                    // ไม่มีปุ่มหัว (ปลดล็อกยกเลิกไม่ได้) — เว้นที่เท่าแถวหัวของ mock ให้ตำแหน่งตรงกัน
                    padding: EdgeInsets.fromLTRB(24, max(52.0, topInset + 8) + 46 + 16, 24, 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 18),
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
                        // สั่นซ้ายขวาเมื่อ PIN ผิด (ตัวควบคุมเดิม)
                        AnimatedBuilder(
                          animation: _shakeController,
                          builder: (_, child) => Transform.translate(
                            offset: Offset(sin(_shakeController.value * pi * 4) * 10, 0),
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
                          child: _isError
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    l.t('pin.wrong'),
                                    style: st.ui(fontSize: 13, color: ObsidianColors.danger),
                                  ),
                                )
                              : null,
                        ),
                        ObsidianKeypad(
                          onDigit: _onNumberTap,
                          onDelete: _onDelete,
                          onBiometric: _biometricAvailable ? _authenticateWithBiometric : null,
                          biometricActive: scanning,
                          enabled: !_verifying,
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
}

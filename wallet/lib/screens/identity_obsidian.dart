// TPIX Wallet — หน้าการปกป้องตัวตนธีม Obsidian
//
// เป็น part ของ identity_screen.dart: ใช้ตัวโหลดสถานะ/แผ่นตั้งค่า (คำถาม พิกัด Recovery PIN
// ทดสอบกู้คืน) ของเดิมทั้งหมด — เปลี่ยนแค่หน้าหลักให้เข้าชุดกับ Obsidian
//   - หัวหน้ามีปุ่มกระจกย้อนกลับ · การ์ดระดับ (โล่ 3D + มาตรวัด 3 ขีด)
//   - 3 ขั้นเป็นแผงกระจก ไอคอน 3D สว่างเมื่อทำแล้ว (จางเมื่อยังไม่ทำ)
//   - ปุ่มทดสอบกู้คืนโผล่เมื่อปกป้องแล้ว ≥ 2 อย่าง (เงื่อนไขเดิม)
//
// Developed by Xman Studio

part of 'identity_screen.dart';

extension _ObsidianIdentity on _IdentityScreenState {
  Widget _buildObsidian(LocaleProvider l) {
    final top = MediaQuery.paddingOf(context).top;
    final level = (_status['level'] as int? ?? 0).clamp(0, 3);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: ObsidianScreenDim.node),
          ListView(
            padding: EdgeInsets.fromLTRB(24, math.max(52.0, top + 8), 24, 40),
            children: [
              ObsidianPageHeader(
                title: l.t('identity.title'),
                backSemantics: MaterialLocalizations.of(context).backButtonTooltip,
              ),
              const SizedBox(height: 20),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: ObsidianColors.cyan),
                    ),
                  ),
                )
              else ...[
                _obsHero(l, level),
                const SizedBox(height: 16),
                _obsStep(
                  step: 1,
                  icon: ObsidianIcons.info,
                  title: l.t('identity.questions'),
                  desc: l.t('identity.questionsDesc'),
                  done: _status['hasQuestions'] as bool? ?? false,
                  onTap: () => _showSecurityQuestionsDialog(l),
                ),
                const SizedBox(height: 12),
                _obsStep(
                  step: 2,
                  icon: ObsidianIcons.language,
                  title: l.t('identity.location'),
                  desc: l.t('identity.locationDesc'),
                  done: _status['hasLocations'] as bool? ?? false,
                  onTap: () => _showLocationDialog(l),
                  extra: _locationLabels.isEmpty ? null : _obsLocationChips(),
                ),
                const SizedBox(height: 12),
                _obsStep(
                  step: 3,
                  icon: ObsidianIcons.lock,
                  title: l.t('identity.recoveryPin'),
                  desc: l.t('identity.recoveryPinDesc'),
                  done: _status['hasRecoveryPin'] as bool? ?? false,
                  onTap: () => _showRecoveryPinDialog(l),
                ),
                if (level >= 2) ...[
                  const SizedBox(height: 20),
                  ObsidianButton.secondary(
                    label: l.t('identity.testRecovery'),
                    trailingIcon: Icons.verified_user_rounded,
                    onPressed: () {
                      SynthService.playTap();
                      _showRecoveryTestDialog(l);
                    },
                  ),
                ],
              ],
            ],
          ),
        ],
      ),
    );
  }

  static const _levelColors = [
    ObsidianColors.dangerSoft,
    ObsidianColors.warning,
    Color(0xFFC4B5FD),
    ObsidianColors.successSoft,
  ];

  Widget _obsHero(LocaleProvider l, int level) {
    final st = ObsidianStyle.of(context);
    final color = _levelColors[level];
    final labels = [l.t('identity.level0'), l.t('identity.level1'), l.t('identity.level2'), l.t('identity.level3')];
    return ObsidianPanel(
      surface: ObsidianSurface(
        radius: 26,
        gradient: LinearGradient(
          begin: const Alignment(-0.342, -0.94),
          end: const Alignment(0.342, 0.94),
          colors: [color.withValues(alpha: 0.16), const Color(0x05FFFFFF)],
          stops: const [0, 0.6],
        ),
        topHighlight: const Color(0x24FFFFFF),
        ring: color.withValues(alpha: 0.4),
        ringWidth: 1.2,
        shadows: [CssShadow(0, 18, 34, -18, color.withValues(alpha: 0.6))],
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Row(
        children: [
          Icon3D(
            ObsidianIcons.shield,
            size: 84,
            dimmed: level == 0,
            shadows: [
              const IconDropShadow(0, 12, 16, Color(0xCC000000)),
              IconDropShadow(0, 0, 18, color.withValues(alpha: 0.6)),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('identity.securityLevel'), style: st.ui(fontSize: 12, color: ObsidianColors.textSec)),
                const SizedBox(height: 2),
                Text(
                  labels[level],
                  style: st.ui(fontSize: 22, fontWeight: FontWeight.w600, color: color, height: 1.3),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: i < level ? color : const Color(0x1FFFFFFF),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text('$level / 3', style: st.number(fontSize: 13, color: ObsidianColors.textSec)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _obsStep({
    required int step,
    required String icon,
    required String title,
    required String desc,
    required bool done,
    required VoidCallback onTap,
    Widget? extra,
  }) {
    final st = ObsidianStyle.of(context);
    return ObsidianPanel(
      surface: ObsidianSurface.panel.copyWith(
        radius: 22,
        ring: done ? ObsidianColors.success.withValues(alpha: 0.35) : null,
      ),
      onTap: () {
        SynthService.playTap();
        onTap();
      },
      semanticLabel: title,
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon3D(icon, size: 44, dimmed: !done),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0x14FFFFFF),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'STEP $step',
                            style: st.number(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: ObsidianColors.textSec,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        if (done) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.check_circle_rounded, size: 16, color: ObsidianColors.successSoft),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: st.ui(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: done ? ObsidianColors.successPale : ObsidianColors.text,
                        height: 1.35,
                      ),
                    ),
                    Text(desc, style: st.ui(fontSize: 12, color: ObsidianColors.textMuted, height: 1.45)),
                  ],
                ),
              ),
              Icon(
                done ? Icons.tune_rounded : Icons.chevron_right_rounded,
                size: done ? 18 : 22,
                color: ObsidianColors.textMuted,
              ),
            ],
          ),
          if (extra != null) ...[const SizedBox(height: 12), extra],
        ],
      ),
    );
  }

  Widget _obsLocationChips() {
    final st = ObsidianStyle.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final (idx, loc) in _locationLabels.indexed)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
            decoration: BoxDecoration(
              color: const Color(0x1F8B5CF6),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x408B5CF6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pin_drop_rounded, size: 14, color: Color(0xFFC4B5FD)),
                const SizedBox(width: 6),
                Text(
                  loc['label'] ?? '',
                  style: st.ui(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFFC4B5FD)),
                ),
                const SizedBox(width: 2),
                // ลบต้องยืนยันก่อน (ตัวเดียวกับธีมอื่น)
                ObsidianPressable(
                  onTap: () => _confirmRemoveLocation(idx, loc['label'] ?? ''),
                  semanticLabel: 'Remove ${loc['label'] ?? ''}',
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 14, color: Color(0x99C4B5FD)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

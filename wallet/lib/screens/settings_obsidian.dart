// TPIX Wallet — หน้าตั้งค่าธีม Obsidian (ตาม A-Settings.dc.html)
//
// เป็น part ของ settings_screen.dart: ใช้ตัวจัดการเดิมทุกตัวร่วมกัน (PIN / สแกนนิ้ว /
// สำรองวลี / ล็อก / ลบข้อมูล / ตรวจอัปเดต) — ธีมอื่นยังใช้เลย์เอาต์เดิมทั้งหมด
//
// ทุกปุ่มของหน้าเดิมยังอยู่ครบ (ย้ายที่ตาม mock):
//   ทั่วไป        → ภาษา (แผ่นเลือก) · ธีม (แผ่นเลือก ทุกธีม) · สแกนนิ้ว (สวิตช์)
//   ความปลอดภัย   → สำรองวลี (ต้องใส่ PIN) · การปกป้องตัวตน · ประวัติการเซ็น · ล็อกทันที
//   การเชื่อมต่อ   → WalletConnect · เครือข่าย (แผ่นข้อมูล แตะเพื่อคัดลอก)
//   อื่น ๆ         → รายงานปัญหา · ตรวจอัปเดต · ลบข้อมูลทั้งหมด (มีกล่องยืนยัน)
//   การ์ดบัญชี     → คัดลอกที่อยู่ · QR ของฉัน · มาตรวัดการปกป้องตัวตน (แตะเปิดหน้าตัวตน)
//
// 🔴 ไม่มีป้าย "สำรองแล้ว" แบบ mock — แอปไม่ได้บันทึกว่าผู้ใช้สำรองวลีแล้วหรือยัง
//    ขึ้นป้ายนี้ = โกหกผู้ใช้ (อาจไม่ได้สำรองจริง) จึงบอกแค่ว่าต้องใช้ PIN
//
// Developed by Xman Studio

part of 'settings_screen.dart';

extension _ObsidianSettings on _SettingsScreenState {
  Widget _buildObsidian(LocaleProvider l) {
    final top = MediaQuery.paddingOf(context).top;
    final st = ObsidianStyle.of(context);
    final wallet = context.watch<WalletProvider>();
    final themeProv = context.watch<ThemeProvider>();
    final wc = context.watch<WalletConnectService>();
    final bundle = themeProv.current;
    final hasMnemonic = (wallet.mnemonic ?? '').isNotEmpty;

    Widget gap(double h) => SizedBox(height: h);

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      bottomNavigationBar: ObsidianTabBar(current: ObsidianTab.settings, onReselect: _obsScrollTop),
      body: Stack(
        children: [
          const Positioned.fill(child: ObsidianScreenDim.settings),
          ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(24, math.max(56.0, top + 12), 24, NotchedNavBar.heightFor(context) + 24),
            children: [
              Semantics(
                header: true,
                child: Text(
                  l.t('settings.title'),
                  style: st.ui(fontSize: 26, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                ),
              ),
              gap(12),
              _obsProfileCard(l, wallet),

              // ── ทั่วไป ──
              gap(12),
              ObsidianSectionLabel(l.t('obs.set.general')),
              gap(12),
              ObsidianListGroup(children: [
                ObsidianListRow(
                  icon: ObsidianIcons.language,
                  title: l.t('settings.language'),
                  value: l.isThai ? 'ไทย' : 'English',
                  onTap: () => _obsPickLanguage(l),
                ),
                ObsidianListRow(
                  icon: ObsidianIcons.theme,
                  title: l.t('settings.theme'),
                  value: l.isThai ? bundle.nameTh : bundle.nameEn,
                  onTap: () => _showThemePicker(l),
                ),
                // เครื่องไม่รองรับสแกนนิ้ว = ไม่มีแถวนี้ (เหมือนหน้าเดิม)
                if (_bioSupported == true)
                  ObsidianListRow(
                    icon: ObsidianIcons.fingerprint,
                    title: l.t('obs.set.biometric'),
                    trailing: ObsidianSwitch(
                      value: _bioEnabled,
                      busy: _isBioToggling,
                      semanticLabel: l.t('obs.set.biometric'),
                      onChanged: (_) => _toggleBiometric(l, _bioEnabled),
                    ),
                  ),
              ]),

              // ── ความปลอดภัย ──
              gap(12),
              ObsidianSectionLabel(l.t('obs.set.security')),
              gap(12),
              ObsidianListGroup(children: [
                ObsidianListRow(
                  icon: ObsidianIcons.backup,
                  title: l.t('obs.set.backup'),
                  trailing: ObsidianBadge(
                    hasMnemonic ? l.t('obs.set.needsPin') : l.t('obs.set.importedKey'),
                    color: hasMnemonic ? ObsidianColors.textSec : ObsidianColors.warning,
                  ),
                  onTap: () => _viewBackup(l),
                ),
                ObsidianListRow(
                  icon: ObsidianIcons.shield,
                  title: l.t('identity.title'),
                  value: _identityLevel == null ? null : '$_identityLevel / 3',
                  onTap: _obsOpenIdentity,
                ),
                ObsidianListRow(
                  icon: ObsidianIcons.signHistory,
                  title: l.t('obs.set.signHistory'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SignHistoryScreen()),
                  ),
                ),
                ObsidianListRow(
                  icon: ObsidianIcons.lock,
                  title: l.t('obs.set.lockNow'),
                  chevron: false,
                  onTap: () {
                    context.read<WalletProvider>().lock();
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const PinScreen()),
                      (_) => false,
                    );
                  },
                ),
              ]),

              // ── การเชื่อมต่อ ──
              gap(12),
              ObsidianSectionLabel(l.t('obs.set.connections')),
              gap(12),
              ObsidianListGroup(children: [
                ObsidianListRow(
                  icon: ObsidianIcons.link,
                  title: l.t('obs.set.wc'),
                  value: '${wc.sessions.length}',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DAppConnectScreen()),
                  ),
                ),
                ObsidianListRow(
                  icon: ObsidianIcons.network,
                  title: l.t('obs.set.network'),
                  value: 'Chain ID ${TpixChain.chainId}',
                  onTap: () => _obsShowNetwork(l),
                ),
              ]),

              // ── อื่น ๆ ──
              gap(12),
              ObsidianSectionLabel(l.t('obs.set.other')),
              gap(12),
              ObsidianListGroup(children: [
                ObsidianListRow(
                  icon: ObsidianIcons.bug,
                  title: l.t('obs.set.report'),
                  chevron: false,
                  onTap: () => showBugReportSheet(context, isThai: l.isThai),
                ),
                ObsidianListRow(
                  icon: ObsidianIcons.update,
                  title: l.t('obs.set.checkUpdate'),
                  value: _versionName.isEmpty ? null : 'v$_versionName',
                  chevron: false,
                  onTap: () => _manualCheckUpdate(l),
                ),
                ObsidianListRow(
                  icon: ObsidianIcons.trash,
                  title: l.t('obs.set.deleteAll'),
                  titleColor: ObsidianColors.dangerSoft,
                  chevron: false,
                  // กล่องยืนยันเดิม (ลบถาวร) — ห้ามลบทันทีจากการแตะครั้งเดียว
                  onTap: () => _confirmDeleteAll(l),
                ),
              ]),

              gap(28),
              _obsAbout(st),
            ],
          ),
        ],
      ),
    );
  }

  void _obsScrollTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    }
  }

  Future<void> _obsOpenIdentity() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const IdentityScreen()));
    if (!mounted) return;
    // ผู้ใช้อาจเพิ่งตั้ง/ลบการปกป้อง → อ่านระดับใหม่
    await _loadIdentityLevel();
  }

  // ════════════════════════════════════════════════════════════
  //  การ์ดบัญชี
  // ════════════════════════════════════════════════════════════

  static const _profileSurface = ObsidianSurface(
    radius: 22,
    // CSS linear-gradient(160deg, violet .18, white .03 60%)
    gradient: LinearGradient(
      begin: Alignment(-0.342, -0.94),
      end: Alignment(0.342, 0.94),
      colors: [Color(0x2E8B5CF6), Color(0x08FFFFFF)],
      stops: [0, 0.6],
    ),
    topHighlight: Color(0x24FFFFFF),
    ring: Color(0x4D8B5CF6),
    shadows: [CssShadow(0, 18, 34, -18, Color(0xF2000000))],
  );

  Widget _obsProfileCard(LocaleProvider l, WalletProvider wallet) {
    final st = ObsidianStyle.of(context);
    final address = wallet.address;
    final short = address == null || address.length < 12
        ? (address ?? '—')
        : '${address.substring(0, 6)}…${address.substring(address.length - 4)}';
    final level = _identityLevel;
    return ObsidianPanel(
      surface: _profileSurface,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [ObsidianColors.cyan, ObsidianColors.violet, ObsidianColors.orange],
                stops: [0, 0.55, 1],
              ),
              boxShadow: [
                // CSS 0 10px 24px -8px rgba(139,92,246,.8)
                BoxShadow(color: Color(0xCC8B5CF6), offset: Offset(0, 10), blurRadius: 20, spreadRadius: -8),
              ],
            ),
            child: const TpixCoinLogo(size: 52),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  wallet.activeWallet?.name ?? 'TPIX Wallet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: st.ui(fontSize: 16, fontWeight: FontWeight.w600, color: ObsidianColors.text, height: 1.5),
                ),
                const SizedBox(height: 4),
                ObsidianPressable(
                  onTap: address == null ? null : () => _obsCopy(address, l.t('home.copied')),
                  semanticLabel: l.t('obs.copyAddress'),
                  pressedScale: 0.98,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(short, style: st.mono(fontSize: 12, color: ObsidianColors.chrome, height: 1.5)),
                      const SizedBox(width: 6),
                      const Icon3D(ObsidianIcons.copy, size: 18),
                    ],
                  ),
                ),
                if (level != null) ...[
                  const SizedBox(height: 4),
                  ObsidianPressable(
                    onTap: _obsOpenIdentity,
                    semanticLabel: l.t('obs.set.securityMeter').replaceAll('{n}', '$level'),
                    pressedScale: 0.98,
                    child: _obsSecurityMeter(l, level, st),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          ObsidianPressable(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceiveScreen())),
            semanticLabel: l.t('obs.set.myQr'),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon3D(ObsidianIcons.qr, size: 36),
            ),
          ),
        ],
      ),
    );
  }

  /// มาตรวัด 3 ขีด = การปกป้องตัวตน 3 อย่าง (คำถาม / พิกัด / Recovery PIN)
  Widget _obsSecurityMeter(LocaleProvider l, int level, ObsidianStyle st) {
    final (fill, text) = switch (level) {
      >= 2 => (ObsidianColors.success, ObsidianColors.successPale),
      1 => (ObsidianColors.warning, ObsidianColors.warning),
      _ => (ObsidianColors.orange, ObsidianColors.orange),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Container(
            width: 18,
            height: 5,
            decoration: BoxDecoration(
              color: i < level ? fill : const Color(0x26FFFFFF),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            l.t('obs.set.securityMeter').replaceAll('{n}', '$level'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: st.ui(fontSize: 11.5, color: text, height: 1.5),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════
  //  แผ่นเลือก / ข้อมูล
  // ════════════════════════════════════════════════════════════

  void _obsCopy(String value, String message) {
    Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  void _obsPickLanguage(LocaleProvider l) {
    ObsidianSheetFrame.show<void>(
      context,
      builder: (sheetCtx) {
        Widget option(String code, String label) {
          final selected = l.locale == code;
          return ObsidianListRow(
            leading: Text(code.toUpperCase(),
                style: ObsidianStyle.of(sheetCtx).number(fontSize: 15, color: ObsidianColors.textSec)),
            title: label,
            chevron: false,
            trailing: selected ? const Icon(Icons.check_rounded, size: 20, color: ObsidianColors.cyan) : null,
            onTap: () {
              Navigator.pop(sheetCtx);
              if (!selected) l.setLocale(code);
            },
          );
        }

        return ObsidianSheetFrame(
          title: l.t('obs.set.chooseLanguage'),
          children: [
            ObsidianListGroup(dividerIndent: 14, children: [
              option('th', 'ไทย'),
              option('en', 'English'),
            ]),
          ],
        );
      },
    );
  }

  void _obsShowNetwork(LocaleProvider l) {
    ObsidianSheetFrame.show<void>(
      context,
      builder: (sheetCtx) {
        Widget row(String label, String value, {bool mono = false}) => ObsidianDetailRow(
              label: label,
              value: value,
              mono: mono,
              trailingIcon: Icons.copy_rounded,
              onTap: () => _obsCopy(value, l.t('home.copied')),
            );
        return ObsidianSheetFrame(
          title: l.t('obs.networkInfo'),
          children: [
            ObsidianPanel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  row('RPC', TpixChain.rpcUrl, mono: true),
                  row('Chain ID', TpixChain.chainId.toString()),
                  row(l.t('settings.symbol'), TpixChain.symbol),
                  row(l.t('home.consensus'), 'IBFT 2.0'),
                ],
              ),
            ),
            ObsidianNote(text: l.t('obs.set.tapToCopy'), color: ObsidianColors.textMuted),
          ],
        );
      },
    );
  }

  Widget _obsAbout(ObsidianStyle st) {
    return Column(
      children: [
        Image.asset('assets/images/logowallet.png', width: 40, height: 40, cacheWidth: 120, cacheHeight: 120),
        const SizedBox(height: 8),
        Text('TPIX Wallet', style: st.ui(fontSize: 14, fontWeight: FontWeight.w600, color: ObsidianColors.textSoft)),
        if (_appVersion.isNotEmpty)
          Text('v$_appVersion', style: st.ui(fontSize: 12, color: ObsidianColors.textMuted)),
        const SizedBox(height: 2),
        ObsidianPressable(
          onTap: () => launchUrl(Uri.parse('https://tpix.online'), mode: LaunchMode.externalApplication),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text('tpix.online', style: st.ui(fontSize: 12, color: ObsidianColors.cyan)),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// แผ่นเลือกธีม (ธีม Obsidian) — โชว์ทุกธีมในทะเบียน เลือกแล้วเปลี่ยนทั้งแอปทันที
// ──────────────────────────────────────────────────────────────────────────

class _ObsThemePickerSheet extends StatelessWidget {
  final LocaleProvider locale;
  final ThemeProvider themeProv;

  const _ObsThemePickerSheet({required this.locale, required this.themeProv});

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final th = locale.isThai;
    return ObsidianSheetFrame(
      title: locale.t('obs.set.chooseTheme'),
      children: [
        Text(locale.t('obs.set.themeHint'), style: st.ui(fontSize: 12.5, color: ObsidianColors.textMuted, height: 1.5)),
        const SizedBox(height: 12),
        ObsidianListGroup(
          dividerIndent: 70,
          children: [
            for (final bundle in ThemeProvider.registry)
              ObsidianListRow(
                leading: _ThemeSwatch(bundle: bundle),
                title: th ? bundle.nameTh : bundle.nameEn,
                subtitle: th ? bundle.taglineTh : bundle.taglineEn,
                chevron: false,
                trailing: bundle.id == themeProv.id
                    ? const Icon(Icons.check_circle_rounded, size: 22, color: ObsidianColors.cyan)
                    : const Icon(Icons.radio_button_unchecked_rounded, size: 22, color: ObsidianColors.textMuted),
                onTap: () async {
                  if (bundle.id != themeProv.id) await themeProv.setTheme(bundle.id);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
          ],
        ),
        // Obsidian มีแต่โหมดมืด — ธีมที่สลับสว่าง/มืดได้ เลือกโหมดในหน้าตั้งค่าของธีมนั้น
        if (themeProv.current.supportsLight)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Expanded(
                  child: ObsidianButton.secondary(
                    label: locale.t('settings.themeLight'),
                    height: 44,
                    onPressed: locale.isDark ? locale.toggleTheme : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ObsidianButton.secondary(
                    label: locale.t('settings.themeDark'),
                    height: 44,
                    onPressed: locale.isDark ? null : locale.toggleTheme,
                  ),
                ),
              ],
            ),
          )
        else
          ObsidianNote(text: locale.t('obs.set.darkOnly'), color: ObsidianColors.textMuted),
      ],
    );
  }
}

/// ตัวอย่างสีของธีม (ไล่สีแบรนด์ของธีมนั้น + ไอคอนธีม)
class _ThemeSwatch extends StatelessWidget {
  final ThemeBundle bundle;

  const _ThemeSwatch({required this.bundle});

  /// ไล่สีของแต่ละธีม — สร้าง ThemeData ทั้งชุดแค่ครั้งแรกต่อธีม ไม่ใช่ทุกเฟรม
  static final _gradients = <ThemeId, Gradient>{};

  @override
  Widget build(BuildContext context) {
    final gradient = _gradients[bundle.id] ??= bundle.buildDark().extension<TpixThemeExtension>()!.brandGradient;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: gradient,
        boxShadow: const [BoxShadow(color: Color(0x99000000), offset: Offset(0, 6), blurRadius: 10, spreadRadius: -4)],
      ),
      child: Icon(bundle.icon, color: Colors.white, size: 22),
    );
  }
}

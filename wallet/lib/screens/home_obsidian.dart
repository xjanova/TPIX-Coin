// TPIX Wallet — หน้าแรกธีม Obsidian (ตาม Main.dc.html)
//
// เป็น part ของ home_screen.dart โดยตั้งใจ: ใช้ตัวจัดการเดิมของหน้าแรกร่วมกัน
// (สแกนจ่าย/รับ, แผ่นรายละเอียดเชน, ยืนยันลบโทเค็น, deep link, WalletConnect)
// ธีมอื่นยังใช้เลย์เอาต์เดิมใน home_screen.dart ทุกอย่าง ไม่แตะ
//
// ฟีเจอร์เดิมของหน้าแรกที่ย้ายที่ (ไม่มีอะไรหาย):
//   - รายการกระเป๋า / สลับกระเป๋า  → กดชื่อกระเป๋าที่หัว + เมนูล่าง "กระเป๋า"
//   - คัดลอกที่อยู่                 → แตะที่อยู่บนบัตร
//   - ป้ายเชน / ข้อมูลเชน         → ป้ายชื่อเชนบนบัตร (มีลูกศรลง) + แผง "ข้อมูลเครือข่าย"
//   - สลับ TH/EN · เวอร์ชันแอป     → หน้าตั้งค่า (มีอยู่แล้วทั้งคู่)
//   - ประวัติ / เชื่อมต่อ dApp       → เมนูล่าง "กิจกรรม" / ปุ่มลิงก์ที่หัว
//   - แลกเหรียญ (เดิมอยู่เมนูล่าง)  → แถวทางลัด
//   - แบนเนอร์อัปเดต              → แบนเนอร์ใต้หัว + กระดิ่งแจ้งเตือน
//   - การ์ด TPIX Trade · การ์ดตัวตน · ธุรกรรมล่าสุด · กราฟราคา · ข้อมูลเชน · ลิงก์ → ใต้รายการเหรียญ
//
// Developed by Xman Studio

part of 'home_screen.dart';

/// ตัวเลขแสดงผลแบบไม่ขึ้นกับภาษาเครื่อง (ไม่ใช่ toString ของ double)
final _amountFmt = NumberFormat('#,##0.00', 'en_US');
final _smallFmt = NumberFormat('#,##0.00####', 'en_US');
final _usdFmt = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);

String _obsAmount(double v) {
  if (v.isNaN || v.isInfinite) return '—';
  if (v >= 1e9) return NumberFormat.compact(locale: 'en_US').format(v);
  return v >= 1 ? _amountFmt.format(v) : _smallFmt.format(v);
}

String _obsShortAddress(String? a) =>
    a == null || a.length < 12 ? (a ?? '—') : '${a.substring(0, 6)}…${a.substring(a.length - 4)}';

extension _ObsidianHome on _HomeScreenState {
  // ════════════════════════════════════════════════════════════
  //  โครงหน้า
  // ════════════════════════════════════════════════════════════

  Widget _buildObsidianHome(LocaleProvider l) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      // เนื้อหาไหลลอดใต้แถบเมนูลอย
      extendBody: true,
      backgroundColor: Colors.transparent,
      bottomNavigationBar: _buildObsidianNav(l),
      body: Consumer<WalletProvider>(
        builder: (context, wallet, _) {
          final chains = ChainConfig.all;
          final found = chains.indexWhere((c) => c.chainId == wallet.activeChainId);
          final activeIndex = found < 0 ? 0 : found;
          final chain = chains[activeIndex];

          return RefreshIndicator(
            onRefresh: () => _obsRefreshAll(wallet),
            color: ObsidianColors.cyan,
            backgroundColor: ObsidianColors.card,
            edgeOffset: topInset,
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              physics: const AlwaysScrollableScrollPhysics(),
              // บน mock หัวเริ่มที่ 52 (รวมแถบสถานะ) — เครื่องที่แถบสถานะสูงกว่าใช้ค่านั้น + 8
              padding: EdgeInsets.fromLTRB(
                24,
                max(52.0, topInset + 8),
                24,
                NotchedNavBar.heightFor(context) + 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _obsHeader(wallet, l),
                  const SizedBox(height: 16),
                  _obsUpdateBanner(l),
                  ChainCardDeck(
                    cards: [for (final c in chains) _obsCardFor(c, wallet, l)],
                    activeIndex: activeIndex,
                    onSelect: (i) => _obsSwitchChain(wallet, i),
                    onChainPillTap: () => _showChainInfo(wallet),
                    onAddressTap: () => _obsCopyAddress(wallet, l),
                    chainPillSemantics: l.t('obs.chainPill'),
                    addressSemantics: l.t('obs.copyAddress'),
                  ),
                  const SizedBox(height: 16),
                  ChainChips(
                    chains: [for (final c in chains) ObsidianChainArt.of(c.chainId)],
                    activeIndex: activeIndex,
                    onSelect: (i) => _obsSwitchChain(wallet, i),
                    semanticLabel: l.t('obs.pickChain'),
                  ),
                  const SizedBox(height: 16),
                  _obsQuickActions(l),
                  const SizedBox(height: 16),
                  _obsAssets(wallet, chain, l),
                  if (wallet.txHistory.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _obsRecentTx(wallet, l),
                  ],
                  const SizedBox(height: 24),
                  PriceChartWidget(
                    currentPrice: wallet.tpixPrice,
                    isPriceStale: wallet.isPriceStale,
                    balanceTPIX: wallet.hasBalance ? wallet.balance : null,
                  ),
                  // การ์ด TPIX Trade (ซ่อนตัวเองถ้ายังไม่รู้ว่าติดตั้งไหม)
                  const SizedBox(height: 24),
                  const PeerAppCard(),
                  const SizedBox(height: 8),
                  _obsMore(wallet, l),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  หัวหน้า: สลับกระเป๋า + สถานะตัวตน · เชื่อมต่อ dApp · แจ้งเตือน
  // ════════════════════════════════════════════════════════════

  Widget _obsHeader(WalletProvider wallet, LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final update = context.watch<UpdateProvider>();
    final hasNotice = update.hasUpdate ||
        wallet.isBalanceStale ||
        wallet.txHistory.any((t) => t.status == 'pending');

    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              ObsidianPressable(
                onTap: () => WalletListSheet.show(context),
                semanticLabel: l.t('obs.switchWallet'),
                child: _obsAvatar(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ObsidianPressable(
                      onTap: () => WalletListSheet.show(context),
                      semanticLabel: l.t('obs.switchWallet'),
                      pressedScale: 0.98,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              wallet.activeWallet?.name ?? 'TPIX Wallet',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: st.ui.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                                color: ObsidianColors.text,
                                shadows: const [Shadow(color: Color(0x99000000), offset: Offset(0, 2), blurRadius: 7.8)],
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: ObsidianColors.chrome),
                        ],
                      ),
                    ),
                    _obsIdentityLine(l, st),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _obsHeaderTile(
          asset: ObsidianIcons.link,
          label: l.t('obs.connectDapp'),
          onTap: () => _obsOpen(const DAppConnectScreen()),
        ),
        const SizedBox(width: 12),
        _obsHeaderTile(
          asset: ObsidianIcons.bell,
          label: l.t('obs.notifications'),
          dot: hasNotice,
          onTap: () => _obsShowNotifications(wallet, l),
        ),
      ],
    );
  }

  /// อวาตาร์ 44px วงไล่สีแบรนด์ (cyan → violet → orange)
  Widget _obsAvatar() {
    return Container(
      width: 44,
      height: 44,
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
          // CSS: 0 8px 22px -6px rgba(139,92,246,.7)
          BoxShadow(color: Color(0xB38B5CF6), offset: Offset(0, 8), blurRadius: 18.2, spreadRadius: -6),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/logowallet.png',
          fit: BoxFit.cover,
          cacheWidth: 132,
          cacheHeight: 132,
        ),
      ),
    );
  }

  /// สถานะการปกป้องตัวตนจริง (คำถามกันลืม / พิกัด / Recovery PIN) → แตะเปิดหน้าตั้งค่าตัวตน
  Widget _obsIdentityLine(LocaleProvider l, ObsidianStyle st) {
    final level = _identityLevel;
    // ยังอ่านไม่เสร็จ — เว้นที่ไว้เท่าเดิม ไม่กะพริบข้อความผิด
    if (level == null) return const SizedBox(height: 18);
    final (text, color) = switch (level) {
      >= 3 => (l.t('obs.identityOn'), ObsidianColors.successPale),
      0 => (l.t('obs.identityOff'), ObsidianColors.orange),
      _ => (l.t('obs.identityPartial').replaceAll('{n}', '$level'), ObsidianColors.warning),
    };
    return ObsidianPressable(
      onTap: _openIdentity,
      semanticLabel: text,
      pressedScale: 0.98,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon3D(ObsidianIcons.shield, size: 18, dimmed: level == 0),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: st.ui.copyWith(fontSize: 12, height: 1.4, color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// ปุ่มกระจก 46x46 มน 16 ที่หัวหน้า (ไอคอน 3D 30px)
  Widget _obsHeaderTile({
    required String asset,
    required String label,
    required VoidCallback onTap,
    bool dot = false,
  }) {
    return ObsidianPanel(
      surface: ObsidianSurface.raised,
      blur: 14,
      width: 46,
      height: 46,
      onTap: onTap,
      semanticLabel: label,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const SizedBox.expand(),
          Center(child: Icon3D(asset, size: 30)),
          if (dot)
            Positioned(
              top: 9,
              right: 10,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: ObsidianColors.orange,
                  boxShadow: [
                    BoxShadow(color: Color(0xFF10131A), spreadRadius: 2),
                    BoxShadow(color: ObsidianColors.orange, blurRadius: 8),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// แบนเนอร์อัปเดต (เฉพาะเมื่อมีเวอร์ชันใหม่ที่ยังไม่ปิด)
  Widget _obsUpdateBanner(LocaleProvider l) {
    final update = context.watch<UpdateProvider>();
    if (!update.hasUpdate) return const SizedBox.shrink();
    final result = update.result!;
    final st = ObsidianStyle.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ObsidianPanel(
        surface: ObsidianSurface.raised.copyWith(radius: 18, ring: const Color(0x5922D3EE)),
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        onTap: () => UpdateService.showUpdateDialog(context, result, update.service),
        semanticLabel: l.t('update.available'),
        child: Row(
          children: [
            const Icon3D(ObsidianIcons.update, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.t('update.available'),
                    style: st.ui.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                  ),
                  Text(
                    'v${result.currentVersion} → v${result.latestVersion}',
                    style: st.mono.copyWith(fontSize: 12, color: ObsidianColors.cyan),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18, color: ObsidianColors.textSec),
              onPressed: update.dismiss,
              tooltip: l.t('common.later'),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  บัตรประจำเชน
  // ════════════════════════════════════════════════════════════

  /// ข้อมูลบนบัตร — ทุกตัวเลขมาจากยอดจริง ไม่รู้ = "—" (ห้ามเดา ห้ามโชว์ 0 หลอก)
  ChainCardData _obsCardFor(ChainConfig chain, WalletProvider wallet, LocaleProvider l) {
    final art = ObsidianChainArt.of(chain.chainId);
    String amount;
    String? sub;
    Color? subColor;

    if (chain.chainId == TpixChain.chainId) {
      amount = wallet.hasBalance ? _obsAmount(wallet.balance) : '—';
      final usd = wallet.portfolioValueUSD;
      if (wallet.isBalanceStale) {
        // ดึงยอดรอบล่าสุดไม่สำเร็จ — บอกตรง ๆ ว่าเป็นยอดเก่า / ยังไม่มียอด
        sub = l.t(wallet.hasBalance ? 'home.balanceStale' : 'home.balanceUnavailable');
        subColor = ObsidianColors.warning;
      } else if (usd != null) {
        sub = '≈ ${_usdFmt.format(usd)}';
        final ch = wallet.tpixChange24h;
        if (ch != null && ch > -100) {
          // มูลค่าที่เปลี่ยนวันนี้ = มูลค่าตอนนี้ − มูลค่าเมื่อ 24 ชม.ก่อน (ยอดเท่าเดิม)
          final delta = usd - usd / (1 + ch / 100);
          final up = ch >= 0;
          sub = '${up ? '▲ +' : '▼ −'}${_usdFmt.format(delta.abs())} '
              '(${ch.abs().toStringAsFixed(2)}%) ${l.t('obs.today')}';
          subColor = up ? ObsidianColors.successSoft : ObsidianColors.dangerSoft;
        }
      }
    } else {
      // ยอดเหรียญหลักของเชนอื่น — ยังไม่เคยโหลดได้ = "—"
      final known = wallet.chainBalances.containsKey(chain.chainId);
      amount = known ? _obsAmount(wallet.getChainBalance(chain.chainId)) : '—';
    }

    return ChainCardData(
      art: art,
      chainName: chain.name,
      balanceLabel: l.t('obs.balanceOnChain'),
      amount: amount,
      unit: chain.symbol,
      subline: sub,
      sublineColor: subColor,
      address: _obsShortAddress(wallet.address),
      gasText: chain.isGasless
          ? l.t('obs.gasFree')
          : l.t('obs.gasPaidIn').replaceAll('{symbol}', chain.symbol),
    );
  }

  /// สลับเชนจากสำรับ/ชิป — ทางเดียวกับแผ่นเลือกเชนเดิม (wallet.switchChain)
  void _obsSwitchChain(WalletProvider wallet, int index) {
    final chain = ChainConfig.all[index];
    if (chain.chainId == wallet.activeChainId) return; // กดซ้ำ = ไม่ทำอะไร
    SynthService.playTap();
    wallet.switchChain(chain.chainId);
  }

  void _obsCopyAddress(WalletProvider wallet, LocaleProvider l) {
    final a = wallet.address;
    if (a == null) return;
    Clipboard.setData(ClipboardData(text: a));
    SynthService.playTap();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(l.t('home.copied')),
        duration: const Duration(seconds: 1),
      ));
  }

  // ════════════════════════════════════════════════════════════
  //  ทางลัด 5 ปุ่ม (ไทล์ 3D)
  // ════════════════════════════════════════════════════════════

  Widget _obsQuickActions(LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final actions = <(String, String, Widget)>[
      (ObsidianIcons.send, l.t('home.send'), const SendScreen()),
      (ObsidianIcons.receive, l.t('home.receive'), const ReceiveScreen()),
      (ObsidianIcons.swap, l.t('home.swap'), const SwapScreen()),
      (ObsidianIcons.bridge, l.t('home.bridge'), const BridgeScreen()),
      (ObsidianIcons.node, l.t('home.node'), const MasterNodeScreen()),
    ];
    return LayoutBuilder(builder: (context, box) {
      // จอแคบ: ไทล์ย่อตามช่อง ไม่ล้น (mock: 60px ที่ช่องกว้าง ~64)
      final cell = (box.maxWidth - 6 * 4) / 5;
      final size = min(60.0, cell - 2);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: ObsidianPressable(
                onTap: () => _obsOpen(actions[i].$3),
                semanticLabel: actions[i].$2,
                pressedScale: 0.93,
                child: Column(
                  children: [
                    Icon3D(
                      actions[i].$1,
                      size: size,
                      shadows: [
                        IconDropShadow.tile,
                        if (i == 0) IconDropShadow.cyanGlow,
                      ],
                    ),
                    const SizedBox(height: 6),
                    ExcludeSemantics(
                      child: Text(
                        actions[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: st.ui.copyWith(
                          fontSize: 12.5,
                          fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w500,
                          color: i == 0 ? ObsidianColors.text : ObsidianColors.textSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    });
  }

  // ════════════════════════════════════════════════════════════
  //  สินทรัพย์บนเชนที่เลือก
  // ════════════════════════════════════════════════════════════

  Widget _obsAssets(WalletProvider wallet, ChainConfig chain, LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final tokens = wallet.activeTokens.where((t) => t.chainId == chain.chainId).toList();
    final missing = wallet.missingContractTokens.where((t) => t.chainId == chain.chainId).toList();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.t('obs.assetsOn').replaceAll('{chain}', chain.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: st.ui.copyWith(fontSize: 17, fontWeight: FontWeight.w600, color: ObsidianColors.text),
              ),
            ),
            ObsidianPressable(
              onTap: () async {
                await _obsOpen(const AddTokenScreen());
                // กลับมาแล้วโหลดรายการใหม่ (เพิ่ม/ลบในหน้านั้น)
                if (!mounted) return;
                wallet.loadTokens();
              },
              semanticLabel: l.t('obs.addToken'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon3D(ObsidianIcons.addToken, size: 24),
                    const SizedBox(width: 4),
                    Text(
                      l.t('obs.addToken'),
                      style: st.ui.copyWith(fontSize: 13, color: ObsidianColors.chrome),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // สลับเชน → รายการลอยขึ้นใหม่ (mock: tokA/tokB .5s หน่วง .2s)
        TweenAnimationBuilder<double>(
          key: ValueKey(chain.chainId),
          tween: Tween(begin: reduce ? 1 : 0, end: 1),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 700),
          curve: const Interval(0.2 / 0.7, 1, curve: Curves.easeOut),
          builder: (_, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child),
          ),
          child: ObsidianPanel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                _obsNativeRow(wallet, chain, l, st),
                for (final t in tokens) _obsTokenRow(wallet, chain, t, l, st),
                for (final t in missing) _obsMissingRow(wallet, t, l),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _obsNativeRow(WalletProvider wallet, ChainConfig chain, LocaleProvider l, ObsidianStyle st) {
    final isTpix = chain.chainId == TpixChain.chainId;
    final art = ObsidianChainArt.of(chain.chainId);

    String amount;
    String? usd;
    String sub;
    bool stale;
    if (isTpix) {
      amount = wallet.hasBalance ? _obsAmount(wallet.balance) : '—';
      final v = wallet.portfolioValueUSD;
      usd = v == null ? null : _usdFmt.format(v);
      final price = wallet.tpixPrice;
      final ch = wallet.tpixChange24h;
      sub = price == null
          ? l.t('obs.priceUnavailable')
          : '${l.t('obs.price')} \$${price.toStringAsFixed(4)}'
              '${ch == null ? '' : ' · ${ch >= 0 ? '+' : '−'}${ch.abs().toStringAsFixed(2)}%'}';
      stale = wallet.isBalanceStale;
    } else {
      final known = wallet.chainBalances.containsKey(chain.chainId);
      amount = known ? _obsAmount(wallet.getChainBalance(chain.chainId)) : '—';
      sub = chain.name;
      stale = false;
    }

    return _obsAssetRow(
      st: st,
      logo: ObsidianChainLogo(art: art, size: 40),
      symbol: chain.symbol,
      sub: sub,
      amount: amount,
      usd: usd,
      staleLabel: stale ? l.t('token.balanceStale') : null,
    );
  }

  Widget _obsTokenRow(WalletProvider wallet, ChainConfig chain, TokenInfo token, LocaleProvider l, ObsidianStyle st) {
    final raw = wallet.getTokenBalanceRaw(token.contractAddress);
    final bal = wallet.getTokenBalance(token.contractAddress);
    // โลโก้ในตัวแอปใช้ได้เฉพาะสัญญาตัวจริงที่รู้จัก — โทเค็นปลอมชื่อ "USDT" ต้องไม่ได้โลโก้ทางการ
    final official = chain.knownTokens.any((k) => k.address.toLowerCase() == token.contractAddress.toLowerCase());
    final bundled = official ? ObsidianLogos.forSymbol(token.symbol) : null;
    final logo = bundled != null
        ? ClipOval(child: Image.asset(bundled, width: 40, height: 40, cacheWidth: 96, excludeFromSemantics: true))
        : TokenAvatar(symbol: token.symbol, logoUrl: wallet.tokenLogo(token), size: 40, color: ObsidianColors.violet);

    return _obsAssetRow(
      st: st,
      logo: logo,
      symbol: token.symbol,
      trust: wallet.tokenTrust(token),
      sub: token.name,
      amount: raw == null ? '—' : _obsAmount(bal),
      staleLabel: wallet.isTokenBalanceStale(token.contractAddress) ? l.t('token.balanceStale') : null,
      // แตะ = ส่งเหรียญนี้ (เลือกไว้ให้) · กดค้าง = ลบ (มีกล่องยืนยันเสมอ)
      onTap: token.chainId == TpixChain.chainId
          ? () => _obsOpen(SendScreen(initialTokenAddress: token.contractAddress))
          : null,
      onLongPress: () => _confirmRemoveToken(token, wallet, l),
    );
  }

  /// โทเค็นที่สัญญาหายไปจากเชนแล้ว — ป้ายเตือน + ปุ่มลบ (ยืนยันก่อน)
  Widget _obsMissingRow(WalletProvider wallet, TokenInfo token, LocaleProvider l) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: _buildMissingTokenRow(token, wallet, l),
    );
  }

  Widget _obsAssetRow({
    required ObsidianStyle st,
    required Widget logo,
    required String symbol,
    required String sub,
    required String amount,
    String? usd,
    String? staleLabel,
    TokenTrust? trust,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              // CSS: 0 6px 14px -4px rgba(0,0,0,.8)
              boxShadow: [BoxShadow(color: Color(0xCC000000), offset: Offset(0, 6), blurRadius: 11.3, spreadRadius: -4)],
            ),
            child: SizedBox(width: 40, height: 40, child: logo),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        symbol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: st.ui.copyWith(fontSize: 15, fontWeight: FontWeight.w500, color: ObsidianColors.text),
                      ),
                    ),
                    if (trust != null && trust != TokenTrust.unverified) ...[
                      const SizedBox(width: 4),
                      TokenTrustIcon(trust: trust),
                    ],
                  ],
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: st.ui.copyWith(fontSize: 12, color: ObsidianColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: st.number.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: ObsidianColors.text),
              ),
              if (usd != null)
                Text(usd, style: st.ui.copyWith(fontSize: 12, color: ObsidianColors.textMuted)),
              if (staleLabel != null)
                Text(staleLabel, style: st.ui.copyWith(fontSize: 11, color: ObsidianColors.warning)),
            ],
          ),
        ],
      ),
    );
    if (onTap == null && onLongPress == null) return row;
    return ObsidianPressable(onTap: onTap, onLongPress: onLongPress, pressedScale: 0.985, child: row);
  }

  // ════════════════════════════════════════════════════════════
  //  ธุรกรรมล่าสุด
  // ════════════════════════════════════════════════════════════

  Widget _obsRecentTx(WalletProvider wallet, LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final recent = wallet.txHistory.take(3).toList();
    return ObsidianPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.t('home.recentTx'),
                  style: st.ui.copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                ),
              ),
              ObsidianPressable(
                onTap: () => _obsOpen(const TxHistoryScreen()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    l.t('home.viewAll'),
                    style: st.ui.copyWith(fontSize: 13, color: ObsidianColors.cyan),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final tx in recent) _obsTxRow(tx, st),
        ],
      ),
    );
  }

  Widget _obsTxRow(TxRecord tx, ObsidianStyle st) {
    final sent = tx.direction == 'sent';
    final color = tx.status == 'failed'
        ? ObsidianColors.textMuted
        : sent
            ? ObsidianColors.dangerSoft
            : ObsidianColors.successSoft;
    final logo = ObsidianLogos.forSymbol(tx.symbol);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Stack(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: tx.isTpix
                      ? const TpixCoinLogo(size: 32)
                      : logo != null
                          ? ClipOval(child: Image.asset(logo, width: 32, height: 32, cacheWidth: 96))
                          : TokenAvatar(symbol: tx.symbol, size: 32, color: color),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: sent ? ObsidianColors.danger : ObsidianColors.success,
                      border: Border.all(color: ObsidianColors.ground, width: 1.5),
                    ),
                    child: Icon(
                      sent ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      color: Colors.white,
                      size: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              sent ? tx.shortTo : tx.shortFrom,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: st.mono.copyWith(fontSize: 13, color: ObsidianColors.textSec),
            ),
          ),
          Text(
            '${sent ? '−' : '+'}${_obsAmount(tx.amount)} ${tx.symbol}',
            style: st.number.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  เพิ่มเติม: ตัวตน · ข้อมูลเครือข่าย · ลิงก์ · ตั้งค่า
  // ════════════════════════════════════════════════════════════

  Widget _obsMore(WalletProvider wallet, LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final level = _identityLevel;
    final identitySub = level == null
        ? l.t('identity.subtitle')
        : level >= 3
            ? l.t('obs.identityOn')
            : level == 0
                ? l.t('obs.identityOff')
                : l.t('obs.identityPartial').replaceAll('{n}', '$level');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ข้อมูลเด่นของ TPIX Chain (เดิมเป็นการ์ด 3 ใบ)
        ObsidianPanel(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Row(
            children: [
              _obsStat(l.t('home.blockTime'), l.t('home.blockTimeVal'), ObsidianColors.successSoft, st),
              _obsStat(l.t('home.gasFee'), l.t('home.gasFeeVal'), ObsidianColors.orange, st),
              _obsStat(l.t('home.consensus'), 'IBFT 2.0', ObsidianColors.violet, st),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            l.t('obs.more'),
            style: st.ui.copyWith(fontSize: 17, fontWeight: FontWeight.w600, color: ObsidianColors.text),
          ),
        ),
        ObsidianPanel(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _obsLinkRow(ObsidianIcons.shield, l.t('identity.title'), identitySub, st, onTap: _openIdentity),
              _obsLinkRow(ObsidianIcons.network, l.t('obs.networkInfo'), l.t('obs.networkInfoSub'), st,
                  onTap: () => _showChainInfo(wallet)),
              _obsLinkRow(ObsidianIcons.node, l.t('mn.title'), 'TPIX Chain', st,
                  onTap: () => _obsOpen(const MasterNodeScreen())),
              _obsLinkRow(ObsidianIcons.chart, 'TPIX TRADE', 'tpix.online', st, url: 'https://tpix.online'),
              _obsLinkRow(ObsidianIcons.link, 'Explorer', 'explorer.tpix.online', st, url: TpixChain.explorerUrl),
              _obsLinkRow(ObsidianIcons.info, 'Whitepaper', 'tpix.online/whitepaper', st,
                  url: 'https://tpix.online/whitepaper'),
              _obsLinkRow(ObsidianIcons.settings, l.t('settings.title'), null, st,
                  onTap: () => _obsOpen(const SettingsScreen())),
            ],
          ),
        ),
      ],
    );
  }

  Widget _obsStat(String label, String value, Color color, ObsidianStyle st) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: st.ui.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: st.ui.copyWith(fontSize: 11.5, color: ObsidianColors.textMuted),
          ),
        ],
      ),
    );
  }

  /// [url] = เปิดเบราว์เซอร์ภายนอก (ไอคอนออกนอกแอป) · [onTap] = หน้าในแอป (ลูกศรขวา)
  Widget _obsLinkRow(String asset, String title, String? sub, ObsidianStyle st, {VoidCallback? onTap, String? url}) {
    return ObsidianPressable(
      onTap: onTap ?? () => launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication),
      semanticLabel: title,
      pressedScale: 0.985,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon3D(asset, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: st.ui.copyWith(fontSize: 14.5, fontWeight: FontWeight.w500, color: ObsidianColors.text),
                  ),
                  if (sub != null)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: st.ui.copyWith(fontSize: 12, color: ObsidianColors.textMuted),
                    ),
                ],
              ),
            ),
            Icon(
              url != null ? Icons.open_in_new_rounded : Icons.chevron_right_rounded,
              size: url != null ? 16 : 20,
              color: ObsidianColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  แจ้งเตือน (จากข้อมูลจริงเท่านั้น: อัปเดต / ธุรกรรมรอยืนยัน / ยอดเก่า)
  // ════════════════════════════════════════════════════════════

  void _obsShowNotifications(WalletProvider wallet, LocaleProvider l) {
    final update = context.read<UpdateProvider>();
    final pending = wallet.txHistory.where((t) => t.status == 'pending').length;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final st = ObsidianStyle.of(sheetCtx);
        final items = <Widget>[
          if (update.hasUpdate)
            _obsNoticeRow(
              st,
              ObsidianIcons.update,
              l.t('update.available'),
              'v${update.result!.currentVersion} → v${update.result!.latestVersion}',
              () {
                Navigator.pop(sheetCtx);
                UpdateService.showUpdateDialog(context, update.result!, update.service);
              },
            ),
          if (pending > 0)
            _obsNoticeRow(
              st,
              ObsidianIcons.activity,
              l.t('obs.pendingTx').replaceAll('{n}', '$pending'),
              l.t('obs.pendingTxSub'),
              () {
                Navigator.pop(sheetCtx);
                _obsOpen(const TxHistoryScreen());
              },
            ),
          if (wallet.isBalanceStale)
            _obsNoticeRow(
              st,
              ObsidianIcons.network,
              l.t(wallet.hasBalance ? 'home.balanceStale' : 'home.balanceUnavailable'),
              l.t('obs.retryBalance'),
              () {
                Navigator.pop(sheetCtx);
                _obsRefreshAll(wallet);
              },
            ),
        ];
        return Container(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + MediaQuery.paddingOf(sheetCtx).bottom),
          decoration: const BoxDecoration(
            color: ObsidianColors.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(TpixRadius.sheet)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l.t('obs.notifications'),
                style: st.ui.copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: ObsidianColors.text),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      const Icon3D(ObsidianIcons.bell, size: 56, dimmed: true),
                      const SizedBox(height: 10),
                      Text(
                        l.t('obs.noNotifications'),
                        style: st.ui.copyWith(fontSize: 14, color: ObsidianColors.textSec),
                      ),
                    ],
                  ),
                )
              else
                ObsidianPanel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: items),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _obsNoticeRow(ObsidianStyle st, String asset, String title, String sub, VoidCallback onTap) {
    return ObsidianPressable(
      onTap: onTap,
      semanticLabel: title,
      pressedScale: 0.985,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon3D(asset, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: st.ui.copyWith(fontSize: 14.5, fontWeight: FontWeight.w500, color: ObsidianColors.text)),
                  Text(sub, style: st.ui.copyWith(fontSize: 12, color: ObsidianColors.textMuted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: ObsidianColors.textMuted),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  แถบเมนูล่าง: หน้าหลัก · กิจกรรม · [สแกน] · กระเป๋า · ตั้งค่า
  // ════════════════════════════════════════════════════════════

  Widget _buildObsidianNav(LocaleProvider l) {
    return NotchedNavBar(
      currentIndex: 0, // อยู่หน้าหลักเสมอ (หน้าอื่นเปิดซ้อนขึ้นมา)
      scanLabel: l.t('nav.scan'),
      scanSemantics: l.t('obs.scanSemantics'),
      onScanTap: _onScanTap, // แผ่นเลือก "สแกนจ่าย / รับเงิน" เดิม
      items: [
        NotchedNavItem(
          asset: ObsidianIcons.home,
          label: l.t('nav.home'),
          // อยู่หน้านี้แล้ว → เลื่อนกลับบนสุด (ไม่ push ซ้ำ)
          onTap: () {
            if (_scrollCtrl.hasClients) {
              _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
            }
          },
        ),
        NotchedNavItem(
          asset: ObsidianIcons.activity,
          label: l.t('nav.activity'),
          onTap: () => _obsOpen(const TxHistoryScreen()),
        ),
        NotchedNavItem(
          asset: ObsidianIcons.wallet,
          label: l.t('nav.wallet'),
          onTap: () => WalletListSheet.show(context),
        ),
        NotchedNavItem(
          asset: ObsidianIcons.settings,
          label: l.t('nav.settings'),
          onTap: () => _obsOpen(const SettingsScreen()),
        ),
      ],
    );
  }
}

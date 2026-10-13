// TPIX Wallet — หน้าแลกเหรียญธีม Obsidian (ตาม A-Swap.dc.html)
//
// เป็น part ของ swap_screen.dart โดยตั้งใจ: ใช้สถานะ/ตัวจัดการเดิมทั้งหมด
// (ใบเสนอราคา · ราคาขยับ · อนุมัติ · ส่ง · ค่าธรรมเนียม) — ไฟล์นี้เปลี่ยนแค่หน้าตา
// ธีมอื่นยังใช้เลย์เอาต์เดิมใน swap_screen.dart ทุกอย่าง
//
// สิ่งที่หน้านี้เพิ่ม (เฉพาะ Obsidian):
//   - ขอราคาใหม่ทุก 15 วิ พร้อมวงนับถอยหลัง — หยุดนับเมื่อกำลังขอราคา/อนุมัติ/แลก
//     หรือมีหน้าต่างอื่นทับ (กล่องยืนยันเปิดอยู่ ราคาที่ผู้ใช้เห็นต้องไม่เปลี่ยนใต้มือ)
//   - (แก้จำนวน/เหรียญ/เชน = ล้างราคาเดิมทันที + ทิ้งผลที่มาช้า — ทำใน swap_screen.dart ใช้ร่วมทุกธีม)
//   - ระหว่างอนุมัติ/แลก: สลับเชน/เหรียญ/ทิศ/จำนวนไม่ได้ (ธุรกรรมที่กำลังรอผลอ้างอิงเชนเดิม)
//   - แท็บ TPIX Chain (TPIX DEX): หน้าตาชุดเดียวกัน แต่ตัวเลข/สถานะ/ธุรกรรมมาจาก TpixSwapController
//     ทั้งหมด (กฎเดียวกับธีมอื่น) — ทะเบียนไม่พร้อม = ไม่มีฟอร์ม ไม่มีปุ่มส่ง
//
// Developed by Xman Studio

part of 'swap_screen.dart';

/// ชื่อ DEX ตาม router ใน ChainConfig (ใช้แสดงเส้นทางเท่านั้น)
const Map<int, String> _obsDexNames = {4289: 'TPIX DEX', 56: 'PancakeSwap', 137: 'QuickSwap', 1: 'Uniswap'};

extension _SwapObsidian on _SwapScreenState {
  // ════════════════════════════════════════════════════════════
  //  โครงหน้า
  // ════════════════════════════════════════════════════════════

  Widget _obsBuild(LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final pad = MediaQuery.paddingOf(context);
    // ระหว่างอนุมัติ/แลก (ทุกเครือข่าย) ห้ามแก้อินพุต — ธุรกรรมที่รอผลอ้างอิงชุดเดิม
    final busy = _networkLocked;
    // TPIX Chain ไม่มี router ใน ChainConfig (ที่อยู่ DEX มาจากทะเบียนบนเซิร์ฟเวอร์เท่านั้น)
    final swapChains = [ChainConfig.tpix, ...ChainConfig.all.where((c) => c.hasSwap)];
    final chainIndex = swapChains.indexWhere((c) => c.chainId == _chain.chainId);
    final tpix = _isTpix;
    // TPIX DEX ยังไม่พร้อม/ติดต่อไม่ได้ = ไม่มีฟอร์ม ไม่มีปุ่มส่ง (fail-closed) + บอกเหตุผล
    final tpixClosed = tpix && _tpix.phase != TpixSwapPhase.ready;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: ObsidianPageScrim()),
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, math.max(52.0, pad.top + 8), 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ObsidianPageHeader(
                        title: l.t('obs.swap.title'),
                        backLabel: l.t('obs.back'),
                        trailing: ObsidianHeaderTile(
                          asset: ObsidianIcons.settings,
                          label: l.t('obs.swap.settings'),
                          onTap: busy ? null : _showSlippageDialog,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ChainChips(
                        chains: [for (final c in swapChains) ObsidianChainArt.of(c.chainId)],
                        activeIndex: chainIndex < 0 ? 0 : chainIndex,
                        onSelect: (i) {
                          if (busy) return; // ธุรกรรมที่รอผลอยู่อ้างอิงเชนนี้ — ห้ามสลับกลางทาง
                          _onChainChanged(swapChains[i]);
                        },
                        height: 40,
                        radius: 14,
                        logoSize: 18,
                        semanticLabel: l.t('obs.swap.network'),
                      ),
                      const SizedBox(height: 14),
                      if (tpixClosed)
                        _obsTpixStatus(l, st)
                      else ...[
                        _obsCards(l, st, busy),
                        const SizedBox(height: 14),
                        _obsRateRow(l, st),
                        const SizedBox(height: 14),
                        if (tpix) _obsTpixDetails(l, st) else _obsDetails(l, st),
                      ],
                    ],
                  ),
                ),
              ),
              if (!tpixClosed)
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 8, 24, math.max(26.0, pad.bottom + 12)),
                  child: tpix ? _obsTpixCta(l, st) : _obsCta(l),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  การ์ดจ่าย / ลูกแก้วสลับ / การ์ดได้รับ
  // ════════════════════════════════════════════════════════════

  /// จำนวนที่กรอก (หน่วยของเหรียญ) — ว่าง/ศูนย์ = null
  BigInt? get _obsAmountIn {
    if (_isTpix) {
      // ตัวควบคุมแปลงด้วยทศนิยมของเหรียญจริงแล้ว (ผิดรูป/ทศนิยมเกิน = null)
      final v = _tpix.amountIn;
      return v != null && v > BigInt.zero ? v : null;
    }
    final text = _amountController.text.trim();
    if (text.isEmpty || _tokenIn == null) return null;
    final v = SwapService.parseAmount(text, _tokenIn!.decimals);
    return v > BigInt.zero ? v : null;
  }

  /// เหรียญฝั่งจ่าย/ได้รับของเครือข่ายที่เลือก — แท็บ TPIX Chain อ่านจาก TpixSwapController
  TokenDef? get _obsTokenIn => _isTpix ? _tpix.from : _tokenIn;
  TokenDef? get _obsTokenOut => _isTpix ? _tpix.to : _tokenOut;

  /// ยอดฝั่งจ่าย — null = อ่านไม่ได้ (แท็บ TPIX ไม่เดาเป็น 0)
  BigInt? get _obsBalanceIn => _isTpix ? _tpix.balanceIn : _balanceIn;

  /// จำนวนที่จะได้รับตามราคาล่าสุด — แท็บ TPIX: ตัวควบคุมล้าง quote ทุกครั้งที่อินพุตเปลี่ยน
  /// (ตัวเลขที่เห็นจึงเป็นของจำนวน/เหรียญปัจจุบันเสมอ)
  BigInt? get _obsQuoteOut => _isTpix ? _tpix.quote?.amountOut : _quoteAmount;

  Widget _obsCards(LocaleProvider l, ObsidianStyle st, bool busy) {
    final tpix = _isTpix;
    final tokenIn = _obsTokenIn;
    final tokenOut = _obsTokenOut;
    final amountIn = _obsAmountIn;
    final balance = _obsBalanceIn;
    final quoteOut = _obsQuoteOut;
    final inValue = amountIn == null || tokenIn == null ? null : SwapService.formatAmount(amountIn, tokenIn.decimals);
    final outValue = quoteOut == null || tokenOut == null
        ? null
        : SwapService.formatAmount(quoteOut, tokenOut.decimals);
    // แท็บ TPIX: ตัวเลขจาก BigInt ตรงตัวแบบปัดลง (ปัดขึ้นแล้วผู้ใช้กรอกตามจะเกินยอด)
    final String? outText = quoteOut == null || tokenOut == null
        ? null
        : tpix
        ? TpixDexMath.display(quoteOut, tokenOut.decimals)
        : obsidianAmountText(outValue!);
    final String? balanceText = tokenIn == null
        ? null
        : balance == null
        ? '—'
        : tpix
        ? TpixDexMath.display(balance, tokenIn.decimals, maxFraction: 4)
        : obsidianAmountText(SwapService.formatAmount(balance, tokenIn.decimals));
    final loadingBalance = tpix ? _tpix.loadingBalance : _loadingBalance;
    final quoting = tpix ? _tpix.quoting && quoteOut == null : _isQuoting;
    final canFill = !busy && tokenIn != null && balance != null && balance > BigInt.zero;
    final usd = obsidianSwapUsd(
      paySymbol: tokenIn?.symbol ?? '',
      payAmount: inValue,
      receiveSymbol: tokenOut?.symbol ?? '',
      receiveAmount: outValue,
    );
    final label = st.ui(fontSize: 12.5, color: ObsidianColors.textSec, height: 1.4);
    final big = st.number(
      fontSize: 38,
      fontWeight: FontWeight.w700,
      letterSpacing: -1,
      height: 1.15,
      color: ObsidianColors.text,
    );

    final pay = ObsidianPanel(
      surface: ObsidianCards.hero,
      blur: 16,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(l.t('obs.swap.pay'), style: label),
              const Spacer(),
              if (loadingBalance)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.6, color: ObsidianColors.textMuted),
                )
              else if (balanceText != null)
                Flexible(
                  child: Text(
                    l.t('obs.swap.balance').replaceAll('{amount}', balanceText),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: label,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 46,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('obs-swap-amount'),
                    controller: _amountController,
                    enabled: !busy,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                    style: big,
                    cursorColor: ObsidianColors.cyan,
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: big.copyWith(color: const Color(0x40FFFFFF)),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: tpix ? _obsTpixAmountEdited : _obsAmountEdited,
                  ),
                ),
                const SizedBox(width: 10),
                ObsidianTokenPill(
                  key: const ValueKey('obs-swap-token-in'),
                  logo: tokenIn == null ? null : ObsidianTokenLogo(token: tokenIn, chain: _chain, size: 32),
                  label: tokenIn?.symbol ?? l.t('obs.swap.selectToken'),
                  semanticLabel: l.t('obs.swap.selectPay'),
                  onTap: busy ? null : (tpix ? () => _selectTpixToken(isFrom: true) : _selectTokenIn),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  usd.pay == null ? '' : obsidianUsdText(usd.pay!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: st.ui(fontSize: 13, color: ObsidianColors.textSec),
                ),
              ),
              ObsidianChipButton(label: '25%', onTap: canFill ? () => _obsFillPercent(25) : null),
              const SizedBox(width: 6),
              ObsidianChipButton(label: '50%', onTap: canFill ? () => _obsFillPercent(50) : null),
              const SizedBox(width: 6),
              ObsidianChipButton(
                key: const ValueKey('obs-swap-max'),
                label: l.t('obs.swap.max'),
                onTap: busy || tokenIn == null ? null : _obsMax,
              ),
            ],
          ),
        ],
      ),
    );

    final receive = ObsidianPanel(
      surface: ObsidianCards.quiet,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.t('obs.swap.receive'), style: label),
          const SizedBox(height: 10),
          SizedBox(
            height: 46,
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: quoting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: ObsidianColors.violet),
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              outText ?? '0',
                              key: const ValueKey('obs-swap-amount-out'),
                              maxLines: 1,
                              style: big.copyWith(
                                color: outText == null ? const Color(0x40FFFFFF) : const Color(0xFFE9EAEE),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                ObsidianTokenPill(
                  key: const ValueKey('obs-swap-token-out'),
                  logo: tokenOut == null ? null : ObsidianTokenLogo(token: tokenOut, chain: _chain, size: 32),
                  label: tokenOut?.symbol ?? l.t('obs.swap.selectToken'),
                  semanticLabel: l.t('obs.swap.selectReceive'),
                  onTap: busy ? null : (tpix ? () => _selectTpixToken(isFrom: false) : _selectTokenOut),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            usd.receive == null ? '' : obsidianUsdText(usd.receive!),
            maxLines: 1,
            style: st.ui(fontSize: 13, color: ObsidianColors.textSec, height: 1.4),
          ),
        ],
      ),
    );

    // ลูกแก้วลอยทับรอยต่อของสองการ์ด — ตามตำแหน่งช่องว่างจริง (ไม่ขึ้นกับความสูงของการ์ด)
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            pay,
            CompositedTransformTarget(link: _obsOrbLink, child: const SizedBox(height: 8)),
            receive,
          ],
        ),
        Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _obsOrbLink,
            targetAnchor: Alignment.center,
            followerAnchor: Alignment.center,
            child: ObsidianSwapOrb(
              key: const ValueKey('obs-swap-flip'),
              flips: _obsFlips,
              semanticLabel: l.t('obs.swap.flip'),
              onTap: busy || tokenIn == null || tokenOut == null ? null : _obsFlip,
            ),
          ),
        ),
      ],
    );
  }

  /// ผู้ใช้แก้จำนวน — เริ่มนับรอบใหม่ (การล้างราคาเก่าทำใน _onAmountChanged)
  void _obsAmountEdited(String value) {
    _obsRefreshLeft.value = _SwapScreenState._obsRefreshSeconds;
    _onAmountChanged(value);
  }

  /// แท็บ TPIX: จำนวนไปที่ตัวควบคุม (ตัวควบคุมล้างราคาเก่า + ขอราคาใหม่เอง)
  void _obsTpixAmountEdited(String value) {
    _obsRefreshLeft.value = _SwapScreenState._obsRefreshSeconds;
    _tpix.setAmount(value);
  }

  void _obsApplyAmount(String text) {
    _amountController.text = text;
    _isTpix ? _obsTpixAmountEdited(text) : _obsAmountEdited(text);
  }

  /// 25% / 50% ของยอด — คิดด้วย BigInt ปัดลง (ไม่มีทางเกินยอดจริง)
  void _obsFillPercent(int percent) {
    final token = _obsTokenIn;
    final balance = _obsBalanceIn;
    if (token == null || balance == null) return;
    SynthService.playTap();
    _obsApplyAmount(obsidianFractionText(balance, percent, token.decimals));
  }

  /// เต็มยอด — เชนที่มีค่าแก๊สกันไว้ส่วนหนึ่ง · เชน TPIX ไม่มีค่าแก๊ส ใช้ได้ทั้งยอดแบบตรงตัว
  void _obsMax() {
    if (!_isTpix) return _obsApplyAmount(_maxAmountText());
    final text = _tpix.maxAmountText;
    if (text != null) _obsApplyAmount(text);
  }

  void _obsFlip() {
    if (_obsTokenIn == null || _obsTokenOut == null) return;
    _obsSet(() => _obsFlips++);
    _obsRefreshLeft.value = _SwapScreenState._obsRefreshSeconds;
    _isTpix ? _flipTpix() : _flipTokens();
  }

  /// หน้านี้อยู่บนสุด (ไม่มีกล่องยืนยัน/แผ่นเลือกเหรียญทับ)
  bool get _obsOnTop => ModalRoute.of(context)?.isCurrent ?? true;

  /// ทุก 1 วิ: นับถอยหลัง → ครบแล้วขอราคาใหม่ (เรียกจาก Timer ใน didChangeDependencies)
  void _obsRefreshTick() {
    if (!mounted) return;
    // แอปอยู่เบื้องหลัง = ไม่ต้องขอราคา (กลับมาแล้วนับต่อ)
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null && life != AppLifecycleState.resumed) return;
    // รอจังหวะพิมพ์ (debounce) / กำลังขอราคา = ยังไม่เริ่มนับ — 15 วิเริ่มนับจากตอนที่ราคามาถึง
    if (_isTpix) {
      // แท็บ TPIX: นับเฉพาะตอนมีราคาของอินพุตปัจจุบันแล้ว · ราคาเก่าระหว่างรอยังโชว์อยู่ (ไม่กะพริบ)
      final tpixPaused =
          _tpix.phase != TpixSwapPhase.ready || _tpix.quote == null || _tpix.quoting || _networkLocked || !_obsOnTop;
      if (tpixPaused) return;
      final left = _obsRefreshLeft.value - 1;
      if (left > 0) {
        _obsRefreshLeft.value = left;
        return;
      }
      _obsRefreshLeft.value = _SwapScreenState._obsRefreshSeconds;
      _tpix.refreshQuote();
      return;
    }
    final paused =
        _obsAmountIn == null ||
        _tokenOut == null ||
        (_quoteDebounce?.isActive ?? false) ||
        _isQuoting ||
        _obsRefreshing ||
        _isSwapping ||
        _isApproving ||
        !_obsOnTop;
    if (paused) return;
    final next = _obsRefreshLeft.value - 1;
    if (next > 0) {
      _obsRefreshLeft.value = next;
      return;
    }
    _obsRefreshLeft.value = _SwapScreenState._obsRefreshSeconds;
    _obsRefetchQuote();
  }

  /// ขอราคาใหม่ของจำนวนเดิม (รอบอัตโนมัติ)
  ///
  /// ★ ไม่ใช้ _isQuoting — ตัวเลขเดิมยังโชว์อยู่ระหว่างรอ (ไม่กะพริบเป็นวงหมุนทุก 15 วิ)
  /// ★ ผลที่กลับมาใช้ได้เฉพาะเมื่อทุกอย่างยังเหมือนตอนขอ และไม่มีกล่องยืนยันเปิดอยู่
  ///   (ยอดขั้นต่ำที่จะได้คำนวณจากราคาที่ผู้ใช้เห็นในกล่องยืนยันเท่านั้น)
  Future<void> _obsRefetchQuote() async {
    final tokenIn = _tokenIn;
    final tokenOut = _tokenOut;
    final chain = _chain;
    final text = _amountController.text.trim();
    final amountIn = _obsAmountIn;
    if (tokenIn == null || tokenOut == null || amountIn == null) return;
    // ไม่เพิ่มเลขรอบเอง (ไม่ไปทับรอบที่ผู้ใช้สั่ง) — แค่จำไว้ว่าออกตัวตอนรอบไหน
    final requestId = _quoteRequestId;
    _obsSet(() => _obsRefreshing = true);
    final quote = await SwapService.getQuote(
      chain: chain,
      tokenIn: tokenIn.isNative ? TokenDef.nativeAddress : tokenIn.address,
      tokenOut: tokenOut.isNative ? TokenDef.nativeAddress : tokenOut.address,
      amountIn: amountIn,
    );
    if (!mounted) return;
    final same =
        requestId == _quoteRequestId &&
        identical(tokenIn, _tokenIn) &&
        identical(tokenOut, _tokenOut) &&
        identical(chain, _chain) &&
        _amountController.text.trim() == text &&
        !_isQuoting &&
        !_isSwapping &&
        !_isApproving &&
        _obsOnTop;
    _obsSet(() {
      _obsRefreshing = false;
      // ไม่มีราคา (ไม่มีสภาพคล่อง/เน็ตสะดุด) = ปิดปุ่มแลกไว้ก่อน รอบหน้าลองใหม่เอง
      if (same) _quoteAmount = quote;
    });
  }

  // ════════════════════════════════════════════════════════════
  //  อัตรา + วงนับถอยหลัง · แผงรายละเอียด
  // ════════════════════════════════════════════════════════════

  Widget _obsRateRow(LocaleProvider l, ObsidianStyle st) {
    final amountIn = _obsAmountIn;
    final tokenIn = _obsTokenIn;
    final tokenOut = _obsTokenOut;
    final quoteOut = _obsQuoteOut;
    if (amountIn == null || tokenIn == null || tokenOut == null) return const SizedBox(height: 20);
    final refreshing = _isTpix ? _tpix.quoting : _isQuoting || _obsRefreshing;

    String rate = '';
    if (quoteOut != null) {
      // แสดงผลเท่านั้น (ไม่ใช้คิดยอดที่ส่ง)
      final inV = SwapService.formatAmount(amountIn, tokenIn.decimals);
      final outV = SwapService.formatAmount(quoteOut, tokenOut.decimals);
      if (inV > 0) rate = '1 ${tokenIn.symbol} = ${obsidianAmountText(outV / inV)} ${tokenOut.symbol}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 20,
        child: Row(
          children: [
            Expanded(
              child: Text(
                rate,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: st.ui(fontSize: 13, color: ObsidianColors.textSoft),
              ),
            ),
            ValueListenableBuilder<int>(
              valueListenable: _obsRefreshLeft,
              builder: (context, left, _) {
                const total = _SwapScreenState._obsRefreshSeconds;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: left / total),
                      // เริ่มรอบใหม่ = เต็มวงทันที · ระหว่างรอบ = หดนุ่ม ๆ ทีละวินาที
                      duration: left == total ? Duration.zero : const Duration(seconds: 1),
                      builder: (_, v, _) => ObsidianCountdownRing(remaining: v),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      refreshing ? l.t('obs.swap.refreshing') : l.t('obs.swap.refreshIn').replaceAll('{s}', '$left'),
                      style: st.ui(fontSize: 12, color: ObsidianColors.textMuted),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String get _obsSlippageText => '${_slippagePercent % 1 == 0 ? _slippagePercent.toInt() : _slippagePercent}%';

  Widget _obsDetails(LocaleProvider l, ObsidianStyle st) {
    final tokenIn = _tokenIn;
    final tokenOut = _tokenOut;
    final amountIn = _obsAmountIn;
    final quote = _quoteAmount;
    final hasQuote = quote != null && amountIn != null && tokenIn != null && tokenOut != null;

    final rows = <Widget>[
      if (hasQuote)
        ObsidianKv(
          l.t('obs.swap.minReceived'),
          '${obsidianAmountText(SwapService.formatAmount(SwapService.applySlippage(quote, _slippagePercent), tokenOut.decimals))} ${tokenOut.symbol}',
        ),
      ObsidianPressable(
        onTap: _networkLocked ? null : _showSlippageDialog,
        semanticLabel: l.t('obs.swap.settings'),
        pressedScale: 0.985,
        child: ObsidianKv(
          l.t('obs.swap.slippage'),
          _obsSlippageText,
          trailing: const Icon(Icons.tune_rounded, size: 14, color: ObsidianColors.textMuted),
        ),
      ),
      if (hasQuote && _swapFee.feePercent > 0)
        ObsidianKv(
          l.t('swap.platformFee'),
          '${obsidianAmountText(SwapService.formatAmount(_swapFee.calculateFee(amountIn), tokenIn.decimals))} ${tokenIn.symbol} (${_swapFee.feePercent}%)',
        ),
      if (hasQuote && _swapFee.feeWallet.isNotEmpty)
        ObsidianKv(l.t('swap.feeWallet'), FeeService.shortWallet(_swapFee.feeWallet), mono: true),
      if (tokenIn != null && tokenOut != null) _obsRouteRow(l, st, tokenIn, tokenOut),
      ObsidianKv(l.t('swap.network'), _chain.name),
    ];

    return ObsidianPanel(
      surface: ObsidianCards.details,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }

  /// [viaWtpix] = เส้นทางของ TPIX DEX ผ่าน WTPIX (เหรียญ ↔ เหรียญ ไม่มีพูลตรง)
  Widget _obsRouteRow(
    LocaleProvider l,
    ObsidianStyle st,
    TokenDef tokenIn,
    TokenDef tokenOut, {
    bool viaWtpix = false,
  }) {
    final text = st.ui(fontSize: 13, color: ObsidianColors.text, height: 1.35);
    final dex = _obsDexNames[_chain.chainId];
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 34),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(l.t('obs.swap.route'), style: st.ui(fontSize: 13, color: ObsidianColors.textSec)),
            const SizedBox(width: 12),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ObsidianTokenLogo(token: tokenIn, chain: _chain, size: 16),
                    const SizedBox(width: 4),
                    Text(viaWtpix ? '${tokenIn.symbol} → WTPIX → ' : '${tokenIn.symbol} → ', style: text),
                    ObsidianTokenLogo(token: tokenOut, chain: _chain, size: 16),
                    const SizedBox(width: 4),
                    Text(dex == null ? tokenOut.symbol : '${tokenOut.symbol} · $dex', style: text),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  ปุ่มหลัก (สถานะเดียวกับปุ่มเดิมทุกกรณี + ปิดระหว่างรอราคาใหม่)
  // ════════════════════════════════════════════════════════════

  Widget _obsCta(LocaleProvider l) {
    final tokenIn = _tokenIn;
    final tokenOut = _tokenOut;
    final amountIn = _obsAmountIn ?? BigInt.zero;
    final hasAmount = amountIn > BigInt.zero;
    final hasQuote = _quoteAmount != null && _quoteAmount! > BigInt.zero;
    final hasSufficientBalance = amountIn <= _balanceIn && hasAmount;
    // ยอด/allowance ของเหรียญที่เพิ่งเลือกยังโหลดไม่เสร็จ = ยังเชื่อค่าไม่ได้ (กันแลกเกินยอด/อนุมัติซ้ำเสียค่าแก๊ส)
    final canSwap = hasAmount && hasQuote && hasSufficientBalance && !_busy && !_isQuoting && !_loadingBalance;

    String label;
    VoidCallback? onPressed;
    var loading = false;
    if (tokenIn == null || tokenOut == null) {
      label = l.t('obs.swap.selectToken');
    } else if (!hasAmount) {
      label = l.t('swap.enterAmount');
    } else if (!hasSufficientBalance) {
      label = l.t('swap.insufficient');
    } else if (_needsApproval) {
      label = _isApproving ? l.t('swap.approving') : l.t('obs.swap.approveCta').replaceAll('{symbol}', tokenIn.symbol);
      onPressed = _busy || _loadingBalance ? null : _approve;
      loading = _isApproving;
    } else {
      label = _isSwapping
          ? l.t('swap.swapping')
          : l.t('obs.swap.cta').replaceAll('{from}', tokenIn.symbol).replaceAll('{to}', tokenOut.symbol);
      onPressed = canSwap ? _executeSwap : null;
      loading = _isSwapping;
    }
    return ObsidianButton(key: const ValueKey('obs-swap-cta'), label: label, onPressed: onPressed, loading: loading);
  }

  // ════════════════════════════════════════════════════════════
  //  แท็บ TPIX Chain (TPIX DEX) — ตัวเลข/สถานะ/ธุรกรรมทั้งหมดมาจาก TpixSwapController
  // ════════════════════════════════════════════════════════════

  /// TPIX DEX ยังใช้ไม่ได้ — กำลังโหลด / ทะเบียนไม่พร้อม / ติดต่อไม่ได้ (ไม่มีฟอร์ม ไม่มีปุ่มส่ง)
  Widget _obsTpixStatus(LocaleProvider l, ObsidianStyle st) {
    if (_tpix.phase == TpixSwapPhase.loading) {
      return Padding(
        key: const ValueKey('tpix-swap-loading'),
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: ObsidianColors.cyan),
            ),
            const SizedBox(height: 12),
            Text(l.t('swap.tpix.loading'), style: st.ui(fontSize: 13, color: ObsidianColors.textMuted)),
          ],
        ),
      );
    }

    final unreachable = _tpix.phase == TpixSwapPhase.unreachable;
    return ObsidianPanel(
      key: const ValueKey('tpix-swap-closed'),
      surface: ObsidianCards.details,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                unreachable ? Icons.cloud_off_rounded : Icons.lock_clock_rounded,
                size: 20,
                color: ObsidianColors.warning,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l.t(unreachable ? 'swap.tpix.unreachable' : 'swap.tpix.unavailable'),
                  style: st.ui(fontSize: 15, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l.t(unreachable ? 'swap.tpix.unreachableBody' : 'swap.tpix.unavailableBody'),
            style: st.ui(fontSize: 13, height: 1.5, color: ObsidianColors.textSec),
          ),
          const SizedBox(height: 16),
          ObsidianButton.secondary(
            key: const ValueKey('tpix-retry'),
            label: l.t('swap.tpix.retry'),
            onPressed: () => _tpix.load(force: true),
          ),
          const SizedBox(height: 10),
          ObsidianButton.secondary(
            key: const ValueKey('tpix-use-bsc'),
            label: l.t('swap.tpix.useBsc'),
            onPressed: () => _onChainChanged(ChainConfig.bsc),
          ),
        ],
      ),
    );
  }

  /// ขั้นต่ำที่จะได้รับ / ผลกระทบต่อราคา / ค่าธรรมเนียมในพูล / เส้นทาง ของแท็บ TPIX
  Widget _obsTpixDetails(LocaleProvider l, ObsidianStyle st) {
    final q = _tpix.quote;
    final err = _tpix.quoteError;
    final from = _tpix.from;
    final to = _tpix.to;
    String? minText;
    if (q != null) {
      try {
        minText = '${TpixDexMath.display(q.minOut(_slippagePercent), q.to.decimals)} ${q.to.symbol}';
      } on TpixDexException {
        minText = '—';
      }
    }
    final bps = q?.impactBps;
    final Color? impactColor = q == null
        ? null
        : bps == null || q.exceedsImpactLimit
        ? ObsidianColors.danger
        : (bps >= 300 ? ObsidianColors.warning : null);
    final maxIn = q != null && q.exceedsImpactLimit ? q.maxAmountInUnderLimit : null;
    final warn = st.ui(fontSize: 12.5, height: 1.45, color: ObsidianColors.danger);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ObsidianPanel(
          surface: ObsidianCards.details,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (minText != null) ObsidianKv(l.t('obs.swap.minReceived'), minText),
              if (q != null)
                ObsidianKv(
                  l.t('swap.tpix.priceImpact'),
                  _impactText(q, l),
                  key: const ValueKey('tpix-impact'),
                  valueColor: impactColor,
                ),
              ObsidianPressable(
                onTap: _networkLocked ? null : _showSlippageDialog,
                semanticLabel: l.t('obs.swap.settings'),
                pressedScale: 0.985,
                child: ObsidianKv(
                  l.t('obs.swap.slippage'),
                  _obsSlippageText,
                  trailing: const Icon(Icons.tune_rounded, size: 14, color: ObsidianColors.textMuted),
                ),
              ),
              ObsidianKv(l.t('swap.tpix.poolFee'), l.t('swap.tpix.poolFeeValue')),
              ObsidianKv(l.t('swap.tpix.gasFee'), l.t('swap.tpix.gasFeeValue')),
              if (from != null && to != null) _obsRouteRow(l, st, from, to, viaWtpix: q?.viaWtpix ?? false),
              ObsidianKv(l.t('swap.network'), ChainConfig.tpix.name),
            ],
          ),
        ),
        if (q == null && err != null && !_tpix.quoting) ...[
          const SizedBox(height: 10),
          Text(l.t(err.localeKey), key: const ValueKey('tpix-quote-error'), textAlign: TextAlign.center, style: warn),
        ],
        if (maxIn != null && maxIn > BigInt.zero) ...[
          const SizedBox(height: 10),
          Text(
            l
                .t('swap.tpix.maxHint')
                .replaceAll('{amount}', TpixDexMath.display(maxIn, q!.from.decimals, maxFraction: 4))
                .replaceAll('{symbol}', q.from.symbol),
            key: const ValueKey('tpix-max-hint'),
            textAlign: TextAlign.center,
            style: warn,
          ),
        ],
      ],
    );
  }

  /// ปุ่มหลักของแท็บ TPIX — สถานะตาม TpixSwapController.block ชุดเดียวกับธีมอื่น
  Widget _obsTpixCta(LocaleProvider l, ObsidianStyle st) {
    final block = _tpix.block;
    final from = _tpix.from;
    final to = _tpix.to;
    final busy = _tpix.busy || _tpixTapBusy;
    String label;
    VoidCallback? onPressed;
    var loading = false;
    switch (block) {
      case TpixSwapBlock.enterAmount:
        label = from == null || to == null ? l.t('obs.swap.selectToken') : l.t('swap.enterAmount');
      case TpixSwapBlock.invalidAmount:
        label = l.t('swap.tpix.invalidAmount');
      case TpixSwapBlock.tooManyDecimals:
        label = l.t('swap.tpix.tooManyDecimals');
      case TpixSwapBlock.loading:
        label = l.t('swap.tpix.loadingShort');
      case TpixSwapBlock.balanceUnknown:
        label = l.t('swap.tpix.balanceUnknown');
        onPressed = _tpix.refreshBalance;
      case TpixSwapBlock.insufficient:
        label = l.t('swap.insufficient');
      case TpixSwapBlock.quoting:
        label = l.t('swap.tpix.quoting');
      case TpixSwapBlock.quoteFailed:
        label = l.t('swap.tpix.retryQuote');
        onPressed = _tpix.refreshQuote;
      case TpixSwapBlock.impactUnknown:
        label = l.t('swap.tpix.impactUnknownButton');
      case TpixSwapBlock.impactTooHigh:
        label = l.t('swap.tpix.impactTooHighButton');
      case TpixSwapBlock.needsApproval:
        label = _tpix.approving
            ? l.t('swap.approving')
            : l.t('obs.swap.approveCta').replaceAll('{symbol}', from?.symbol ?? '');
        onPressed = busy ? null : _approveTpix;
        loading = _tpix.approving;
      case TpixSwapBlock.none:
        label = _tpix.swapping
            ? l.t('swap.swapping')
            : l.t('obs.swap.cta').replaceAll('{from}', from?.symbol ?? '').replaceAll('{to}', to?.symbol ?? '');
        onPressed = busy ? null : _executeTpixSwap;
        loading = _tpix.swapping;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ObsidianButton(key: const ValueKey('obs-swap-cta'), label: label, onPressed: onPressed, loading: loading),
        if (block == TpixSwapBlock.needsApproval) ...[
          const SizedBox(height: 8),
          Text(
            l.t('swap.tpix.approveNote'),
            textAlign: TextAlign.center,
            style: st.ui(fontSize: 11.5, color: ObsidianColors.textMuted),
          ),
        ],
      ],
    );
  }

  // ════════════════════════════════════════════════════════════
  //  กล่องยืนยัน / สำเร็จ / ตั้งค่าราคาขยับ
  // ════════════════════════════════════════════════════════════

  /// [quote]/[slippage] = ชุดที่ _executeSwap ถ่ายไว้และจะใช้คิด amountOutMin จริง
  Future<bool?> _obsConfirm(String amountStr, BigInt amountIn, BigInt quote, double slippage) {
    final l = context.read<LocaleProvider>();
    final tokenIn = _tokenIn!;
    final tokenOut = _tokenOut!;
    // ตัวเลขชุดเดียวกับกล่องยืนยันเดิมทุกตัว (6 ตำแหน่ง)
    final outFormatted = SwapService.formatAmount(quote, tokenOut.decimals);
    final minOut = SwapService.formatAmount(SwapService.applySlippage(quote, slippage), tokenOut.decimals);
    final slippageText = '${slippage % 1 == 0 ? slippage.toInt() : slippage}%';
    final feeFormatted = SwapService.formatAmount(_swapFee.calculateFee(amountIn), tokenIn.decimals);
    final chain = _chain;

    return showObsidianSheet<bool>(
      context,
      title: l.t('swap.confirmTitle'),
      builder: (ctx) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _obsConfirmSides(
              ctx,
              chain,
              (tokenIn, amountStr, l.t('obs.swap.pay')),
              (tokenOut, outFormatted.toStringAsFixed(6), l.t('obs.swap.receive')),
            ),
            const SizedBox(height: 8),
            ObsidianKv(l.t('swap.minReceived'), '${minOut.toStringAsFixed(6)} ${tokenOut.symbol}', strong: true),
            ObsidianKv(l.t('swap.slippage'), slippageText),
            if (_swapFee.feePercent > 0) ...[
              ObsidianKv(
                l.t('swap.platformFee'),
                '${feeFormatted.toStringAsFixed(6)} ${tokenIn.symbol} (${_swapFee.feePercent}%)',
              ),
              if (_swapFee.feeWallet.isNotEmpty)
                ObsidianKv(l.t('swap.feeWallet'), FeeService.shortWallet(_swapFee.feeWallet), mono: true),
            ],
            ObsidianKv(l.t('swap.network'), chain.name),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ObsidianButton.secondary(
                    label: l.t('send.cancel'),
                    onPressed: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ObsidianButton(
                    key: const ValueKey('obs-swap-confirm'),
                    label: l.t('swap.button'),
                    height: 52,
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// แผงจ่าย ↓ ได้รับ ในกล่องยืนยัน — (เหรียญ, จำนวนที่แสดง, หัวข้อ)
  Widget _obsConfirmSides(
    BuildContext ctx,
    ChainConfig chain,
    (TokenDef, String, String) pay,
    (TokenDef, String, String) receive,
  ) {
    final st = ObsidianStyle.of(ctx);
    Widget side((TokenDef, String, String) s) {
      final (t, amount, caption) = s;
      return Row(
        children: [
          ObsidianTokenLogo(token: t, chain: chain, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(caption, style: st.ui(fontSize: 12, color: ObsidianColors.textMuted)),
                Text(
                  '$amount ${t.symbol}',
                  style: st.number(fontSize: 20, fontWeight: FontWeight.w700, color: ObsidianColors.text),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ObsidianPanel(
      surface: ObsidianCards.details,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          side(pay),
          const Padding(
            padding: EdgeInsets.only(left: 8, top: 6, bottom: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Icon(Icons.arrow_downward_rounded, size: 18, color: ObsidianColors.textMuted),
            ),
          ),
          side(receive),
        ],
      ),
    );
  }

  /// กล่องยืนยันแท็บ TPIX — [minOut] คือตัวเดียวกับที่ _executeTpixSwap ส่งจริง (ผูกกับ [q] ที่เห็น)
  Future<bool?> _obsTpixConfirm(TpixDexQuote q, BigInt minOut) {
    final l = context.read<LocaleProvider>();
    const chain = ChainConfig.tpix;
    final bps = q.impactBps;
    return showObsidianSheet<bool>(
      context,
      title: l.t('swap.confirmTitle'),
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _obsConfirmSides(
            ctx,
            chain,
            (q.from, TpixDexMath.display(q.amountIn, q.from.decimals), l.t('obs.swap.pay')),
            (q.to, TpixDexMath.display(q.amountOut, q.to.decimals), l.t('obs.swap.receive')),
          ),
          const SizedBox(height: 8),
          ObsidianKv(
            l.t('swap.minReceived'),
            '${TpixDexMath.display(minOut, q.to.decimals)} ${q.to.symbol}',
            strong: true,
          ),
          ObsidianKv(
            l.t('swap.tpix.priceImpact'),
            _impactText(q, l),
            valueColor: bps != null && bps >= 300 ? ObsidianColors.warning : null,
          ),
          ObsidianKv(l.t('swap.slippage'), _slippageText),
          ObsidianKv(l.t('swap.tpix.poolFee'), l.t('swap.tpix.poolFeeValue')),
          ObsidianKv(l.t('swap.tpix.gasFee'), l.t('swap.tpix.gasFeeValue')),
          ObsidianKv(l.t('swap.tpix.route'), _routeText(q)),
          ObsidianKv(l.t('swap.network'), chain.name),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ObsidianButton.secondary(label: l.t('send.cancel'), onPressed: () => Navigator.pop(ctx, false)),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ObsidianButton(
                  key: const ValueKey('obs-swap-confirm'),
                  label: l.t('swap.button'),
                  height: 52,
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _obsSuccess(String txHash) {
    final l = context.read<LocaleProvider>();
    final shortTx = txHash.length > 16 ? '${txHash.substring(0, 10)}…${txHash.substring(txHash.length - 6)}' : txHash;
    showObsidianSheet<void>(
      context,
      builder: (ctx) {
        final st = ObsidianStyle.of(ctx);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: Alignment(-0.3, -0.4),
                    radius: 0.95,
                    colors: [ObsidianColors.successSoft, Color(0xFF059669)],
                  ),
                  boxShadow: [BoxShadow(color: Color(0x8034D399), blurRadius: 24, spreadRadius: -4)],
                ),
                child: const Icon(Icons.check_rounded, size: 36, color: Colors.white),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l.t('swap.success'),
              textAlign: TextAlign.center,
              style: st.ui(fontSize: 18, fontWeight: FontWeight.w600, color: ObsidianColors.successPale),
            ),
            const SizedBox(height: 6),
            Text(
              l.t('swap.successDesc'),
              textAlign: TextAlign.center,
              style: st.ui(fontSize: 13.5, color: ObsidianColors.textSec, height: 1.45),
            ),
            const SizedBox(height: 16),
            ObsidianPanel(
              surface: ObsidianCards.details,
              padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
              child: Row(
                children: [
                  Text(l.t('obs.swap.txHash'), style: st.ui(fontSize: 12.5, color: ObsidianColors.textMuted)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      shortTx,
                      textAlign: TextAlign.end,
                      style: st.mono(fontSize: 12.5, color: ObsidianColors.cyan),
                    ),
                  ),
                  IconButton(
                    tooltip: l.t('tx.hashCopied'),
                    icon: const Icon(Icons.copy_rounded, size: 16, color: ObsidianColors.textMuted),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: txHash));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(l.t('tx.hashCopied')), duration: const Duration(seconds: 1)),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            ObsidianButton(
              label: l.t('swap.done'),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _obsShowSlippage() async {
    final l = context.read<LocaleProvider>();
    final v = await showObsidianSheet<double>(
      context,
      title: l.t('obs.swap.slippage'),
      builder: (_) => _ObsSlippageSheet(current: _slippagePercent),
    );
    if (v == null || !mounted) return;
    _obsSet(() => _slippagePercent = v);
    SynthService.playTap();
  }
}

/// แผ่นตั้งค่าราคาขยับ — ค่าที่รับได้เท่ากับกล่องเดิม (มากกว่า 0 ถึง 50%)
class _ObsSlippageSheet extends StatefulWidget {
  final double current;

  const _ObsSlippageSheet({required this.current});

  static const presets = [0.5, 1.0, 3.0];

  @override
  State<_ObsSlippageSheet> createState() => _ObsSlippageSheetState();
}

class _ObsSlippageSheetState extends State<_ObsSlippageSheet> {
  late double? _preset = _ObsSlippageSheet.presets.contains(widget.current) ? widget.current : null;
  late final TextEditingController _custom = TextEditingController(text: _preset == null ? _plain(widget.current) : '');

  static String _plain(double v) => v % 1 == 0 ? '${v.toInt()}' : '$v';

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  /// ค่าที่จะตั้ง — null = ยังไม่ถูกต้อง
  double? get _value {
    if (_preset != null) return _preset;
    final v = double.tryParse(_custom.text.trim());
    return v != null && v > 0 && v <= 50 ? v : null;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final st = ObsidianStyle.of(context);
    final typed = _custom.text.trim();
    final invalid = _preset == null && typed.isNotEmpty && _value == null;
    final value = _value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ObsidianSegmented<double>(
          options: [for (final p in _ObsSlippageSheet.presets) ObsidianSegmentOption(p, '${_plain(p)}%')],
          value: _preset ?? -1,
          onChanged: (v) => setState(() {
            _preset = v;
            _custom.clear();
          }),
        ),
        const SizedBox(height: 12),
        ObsidianTextField(
          controller: _custom,
          hint: '${l.t('swap.custom')} (0.1 – 50)',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
          suffix: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('%', style: st.ui(fontSize: 15, color: ObsidianColors.textSec)),
          ),
          onChanged: (_) => setState(() => _preset = null),
          errorText: invalid ? l.t('obs.swap.slippageInvalid') : null,
          warningText: value != null && value > 5 ? l.t('obs.swap.slippageHigh') : null,
        ),
        const SizedBox(height: 10),
        Text(l.t('obs.swap.slippageHint'), style: st.ui(fontSize: 12, height: 1.5, color: ObsidianColors.textMuted)),
        const SizedBox(height: 18),
        ObsidianButton(
          key: const ValueKey('obs-slippage-set'),
          label: l.t('swap.set'),
          onPressed: value == null ? null : () => Navigator.pop(context, value),
        ),
      ],
    );
  }
}

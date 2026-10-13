// TPIX Wallet — หน้าส่งธีม Obsidian (ตาม A-Send.dc.html + หน้าสำเร็จจาก A-Pin.dc.html)
//
// เป็น part ของ send_screen.dart โดยตั้งใจ: ใช้ตรรกะเดิมทั้งหมดร่วมกัน
//   ตรวจที่อยู่ (checksum) · กันโอนเข้าสัญญามาสเตอร์โหนด · ตรวจทศนิยม/ยอด แบบ BigInt ·
//   ยืนยันตัวตน → แผ่นยืนยัน → กันสลับกระเป๋าระหว่างส่ง · รายการโปรด/บันทึกผู้รับ · กดซ้ำไม่ส่งซ้ำ
// เปลี่ยนแค่หน้าตา ธีมอื่นใช้เลย์เอาต์เดิมใน send_screen.dart ทุกอย่าง
//
// ที่ต่างจาก mock โดยตั้งใจ:
//   - ช่องจำนวนไม่ใส่จุลภาคหลักพันให้ — Units.parse อ่าน "1,500" เป็น 1.5 (จุลภาคตัวเดียว = ทศนิยม
//     สำหรับคีย์บอร์ดบางภาษา) ใส่ให้เองจะทำให้ส่งผิดจำนวน · แผ่นยืนยัน/หน้าสำเร็จคั่นหลักพันได้ (แสดงผลอย่างเดียว)
//   - ไม่มีปุ่ม "กรอกเป็น USD" — ยังไม่มีตรรกะแปลงจำนวนจาก USD (ห้ามเดาราคา/ปัดเศษเอง)
//
// Developed by Xman Studio

part of 'send_screen.dart';

final _obsUsd = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
final _obsBal = NumberFormat('#,##0.####', 'en_US');

String _obsShort(String a) => a.length < 12 ? a : '${a.substring(0, 6)}…${a.substring(a.length - 4)}';

extension _ObsidianSend on _SendScreenState {
  // ════════════════════════════════════════════════════════════
  //  ฟอร์ม
  // ════════════════════════════════════════════════════════════

  Widget _buildObsidianForm(LocaleProvider l) {
    final wallet = context.watch<WalletProvider>();
    final tokens = _sendableTokens(wallet);
    final token = _selectedTokenInfo(wallet);
    final symbol = _symbolOf(token);
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final st = ObsidianStyle.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const ObsidianScrim.send(),
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, math.max(52.0, topInset + 8), 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ObsidianTopBar(
                        leading: ObsidianTopButton(
                          onTap: () => obsidianPopIfCurrent(context),
                          semanticLabel: l.t('obs.sr.back'),
                          child: const ObsidianGlyphIcon(ObsidianGlyph.back, strokeWidth: 2.2),
                        ),
                        title: token == null ? l.t('obs.send.title') : l.t('send.titleToken').replaceAll('{symbol}', symbol),
                        trailing: ObsidianTopButton(
                          onTap: _isSending ? null : _pickFavorite,
                          semanticLabel: l.t('contacts.title'),
                          child: const Icon3D(ObsidianIcons.contacts, size: 30),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _obsAssetButton(wallet, tokens, token, l, st),
                      const SizedBox(height: 16),
                      _obsAmount(wallet, token, l, st),
                      const SizedBox(height: 16),
                      _obsAddress(l, st),
                      if (_favorites.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _obsFavorites(st),
                      ],
                      const SizedBox(height: 16),
                      _obsFeePanel(l, st),
                    ],
                  ),
                ),
              ),
              // ── ปุ่มหลักติดล่าง (ลอยเหนือคีย์บอร์ดเอง) ──
              Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + bottomInset),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ObsidianButton(
                      label: _isSending ? l.t('send.sending') : l.t('obs.send.review'),
                      trailingIcon: Icons.arrow_forward_rounded,
                      loading: _isSending,
                      onPressed: _send,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const ObsidianGlyphIcon(ObsidianGlyph.lock, size: 13, color: ObsidianColors.textMuted),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            l.t('obs.send.authHint'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: st.ui(fontSize: 12, color: ObsidianColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// โลโก้เหรียญ (TPIX / โทเค็นบน TPIX Chain)
  Widget _obsAssetLogo(WalletProvider wallet, TokenInfo? token, double size) {
    if (token == null) return TpixCoinLogo(size: size);
    final local = ObsidianLogos.forSymbol(token.symbol);
    if (local != null) {
      return ClipOval(
        child: Image.asset(
          local,
          width: size,
          height: size,
          cacheWidth: 96,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
        ),
      );
    }
    return TokenAvatar(symbol: token.symbol, logoUrl: wallet.tokenLogo(token), size: size, color: ObsidianColors.violet);
  }

  String _obsBalanceText(BigInt? raw, int decimals) =>
      raw == null ? '—' : _obsBal.format(Units.toDouble(raw, decimals));

  /// ปุ่มเลือกเหรียญ (มีโทเค็นบน TPIX Chain = กดเปิดรายการได้)
  Widget _obsAssetButton(
      WalletProvider wallet, List<TokenInfo> tokens, TokenInfo? token, LocaleProvider l, ObsidianStyle st) {
    final canPick = tokens.isNotEmpty && !_isSending;
    final raw = _rawBalanceOf(wallet, token);
    return ObsidianPanel(
      blur: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: canPick ? () => _obsPickAsset(wallet, tokens, l) : null,
      semanticLabel: canPick ? l.t('send.asset') : null,
      surface: const ObsidianSurface(
        radius: 20,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x14FFFFFF), Color(0x05FFFFFF)], // .08 → .02
        ),
        topHighlight: Color(0x24FFFFFF), // .14
        bottomShade: Color(0x80000000),
        shadows: [CssShadow(0, 16, 30, -18, Color(0xF2000000))],
      ),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [const CssShadow(0, 6, 16, -4, Color(0xB38B5CF6)).toBoxShadow()],
            ),
            child: _obsAssetLogo(wallet, token, 42),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _symbolOf(token),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: st.ui(fontSize: 15, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                ),
                Text('TPIX Chain', style: st.ui(fontSize: 12, color: ObsidianColors.textSec)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(l.t('obs.send.available'), style: st.ui(fontSize: 11, color: ObsidianColors.textSec)),
              Text(
                _obsBalanceText(raw, _decimalsOf(token)),
                style: st.number(fontSize: 14.5, fontWeight: FontWeight.w600, color: ObsidianColors.text),
              ),
            ],
          ),
          if (canPick) ...[
            const SizedBox(width: 12),
            const ObsidianGlyphIcon(ObsidianGlyph.chevronDown, size: 18, color: ObsidianColors.chrome),
          ],
        ],
      ),
    );
  }

  /// แผ่นเลือกเหรียญ — TPIX + โทเค็นบน TPIX Chain (ชุดเดียวกับชิปของหน้าเดิม)
  Future<void> _obsPickAsset(WalletProvider wallet, List<TokenInfo> tokens, LocaleProvider l) async {
    final current = _selectedToken;
    // '' = TPIX (null ใช้แทน "ปิดแผ่นเฉย ๆ")
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final st = ObsidianStyle.of(sheetCtx);
        Widget row(TokenInfo? t) {
          final key = t?.contractAddress.toLowerCase() ?? '';
          final selected = (current ?? '') == key;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ObsidianPanel(
              onTap: () => obsidianPopIfCurrent(sheetCtx, key),
              semanticLabel: _symbolOf(t),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              surface: ObsidianSurface.panel.copyWith(
                radius: 18,
                ring: selected ? ObsidianColors.violet : null,
                ringWidth: 1.5,
              ),
              child: Row(
                children: [
                  _obsAssetLogo(wallet, t, 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _symbolOf(t),
                      style: st.ui(fontSize: 15, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                    ),
                  ),
                  Text(
                    _obsBalanceText(_rawBalanceOf(wallet, t), _decimalsOf(t)),
                    style: st.number(fontSize: 14, fontWeight: FontWeight.w600, color: ObsidianColors.textSoft),
                  ),
                ],
              ),
            ),
          );
        }

        return Container(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.paddingOf(sheetCtx).bottom),
          decoration: const BoxDecoration(
            color: ObsidianColors.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(TpixRadius.sheet)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(l.t('send.asset'), style: st.ui(fontSize: 18, fontWeight: FontWeight.w600, color: ObsidianColors.text)),
                const SizedBox(height: 12),
                row(null),
                for (final t in tokens) row(t),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    _selectAsset(picked.isEmpty ? null : picked);
  }

  // ── จำนวน ──

  Widget _obsAmount(WalletProvider wallet, TokenInfo? token, LocaleProvider l, ObsidianStyle st) {
    final symbol = _symbolOf(token);
    final decimals = _decimalsOf(token);
    final raw = _rawBalanceOf(wallet, token);

    Widget pct(String label, int percent) => Expanded(
          child: ObsidianPanel(
            height: 38,
            surface: ObsidianSurface.dark,
            semanticLabel: label,
            // ตรวจยอดแบบ BigInt — 100% = ยอดเต็มทุกหลัก (ไม่ปัดขึ้นจนเกินยอด)
            onTap: raw == null || raw == BigInt.zero || _isSending
                ? null
                : () {
                    final v = percent == 100 ? raw : raw * BigInt.from(percent) ~/ BigInt.from(100);
                    _amountController.text = Units.format(v, decimals);
                    SynthService.playTap();
                  },
            child: Center(
              child: ExcludeSemantics(
                child: Text(label, style: st.ui(fontSize: 13, color: ObsidianColors.textSoft)),
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.t('send.amount'), style: st.ui(fontSize: 13, color: ObsidianColors.textSec)),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, box) {
          return ValueListenableBuilder<TextEditingValue>(
            valueListenable: _amountController,
            builder: (context, value, _) {
              // ช่องกว้างตามตัวเลขจริง ให้สัญลักษณ์เหรียญต่อท้ายตัวเลขแบบ mock
              // ตัวเลขยาวเกินที่ → ย่อฟอนต์ลง (ขั้นต่ำ 28) แทนการล้นจอ
              final symbolStyle = st.number(fontSize: 22, fontWeight: FontWeight.w600, color: ObsidianColors.textMuted);
              final symbolW = _obsTextWidth(symbol, symbolStyle);
              // เผื่อ 4px กันปัดเศษความกว้างตัวอักษรแล้วล้นขอบ
              final avail = math.max(80.0, box.maxWidth - symbolW - 10 - 4);
              final shown = value.text.isEmpty ? '0' : value.text;
              final base = st.number(fontSize: 54, fontWeight: FontWeight.w700, letterSpacing: -2, height: 1.05);
              final w54 = _obsTextWidth(shown, base) + 6;
              final size = (54 * math.min(1.0, avail / w54)).clamp(28.0, 54.0).toDouble();
              final style = st.number(
                fontSize: size,
                fontWeight: FontWeight.w700,
                letterSpacing: -2 * size / 54,
                height: 1.05,
                color: ObsidianColors.text,
                shadows: const [Shadow(color: Color(0x738B5CF6), blurRadius: 22, offset: Offset(0, 6))],
              );
              final fieldW = math.min(avail, _obsTextWidth(shown, style) + 8);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  SizedBox(
                    width: fieldW,
                    child: TextField(
                      controller: _amountController,
                      enabled: !_isSending,
                      // ทศนิยมต้องพิมพ์ได้ทุกเครื่อง (TextInputType.number บาง keyboard ไม่มีจุด)
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      style: style,
                      cursorColor: ObsidianColors.cyan,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        hintText: '0',
                        hintStyle: style.copyWith(color: ObsidianColors.textMuted.withValues(alpha: 0.5), shadows: const []),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(symbol, style: symbolStyle),
                ],
              );
            },
          );
        }),
        const SizedBox(height: 10),
        // มูลค่าโดยประมาณ — เฉพาะ TPIX ที่รู้ราคาจริง (โทเค็นอื่นไม่เดาราคา)
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _amountController,
          builder: (context, value, _) {
            final price = wallet.tpixPrice;
            String text = '';
            if (token == null && price != null) {
              final p = Units.parse(value.text, decimals);
              final v = p.isOk ? Units.toDouble(p.value!, decimals) : 0.0;
              text = '≈ ${_obsUsd.format(v * price)}';
            }
            return Text(text, style: st.ui(fontSize: 14, color: ObsidianColors.textSec));
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            pct('25%', 25),
            const SizedBox(width: 8),
            pct('50%', 50),
            const SizedBox(width: 8),
            pct('75%', 75),
            const SizedBox(width: 8),
            pct(l.t('obs.send.max'), 100),
          ],
        ),
      ],
    );
  }

  double _obsTextWidth(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  // ── ผู้รับ ──

  Future<void> _obsPaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    // วางได้ทั้งที่อยู่ล้วนและ URI จ่ายเงิน (ethereum:0x…) — ตัวแยกเดียวกับการสแกน
    _addressController.text = WalletService.parseAddressFromQR(text) ?? text;
    SynthService.playTap();
  }

  Widget _obsAddress(LocaleProvider l, ObsidianStyle st) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _addressController,
      builder: (context, value, _) {
        final text = value.text.trim();
        final valid = WalletService.isValidAddress(text);
        // แสดงว่า "ผิด" เฉพาะเมื่อพิมพ์ครบความยาวแล้ว หรือมีตัวที่ไม่ใช่ฐาน 16 (ไม่แดงระหว่างพิมพ์)
        final invalid = !valid &&
            text.isNotEmpty &&
            (text.length >= 42 || !RegExp(r'^(0|0x[0-9a-fA-F]*)$').hasMatch(text));

        final field = CustomPaint(
          painter: const ObsidianSurfacePainter(ObsidianSurface(
            radius: 18,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF08090D), Color(0xFF11131A)],
            ),
            innerShadows: [CssShadow(0, 3, 8, 0, Color(0xBF000000))],
          )),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _addressController,
                    enabled: !_isSending,
                    minLines: 2,
                    maxLines: 2,
                    keyboardType: TextInputType.visiblePassword, // ไม่ให้คีย์บอร์ดเดาคำ/ใส่เว้นวรรค
                    autocorrect: false,
                    enableSuggestions: false,
                    style: st.mono(fontSize: 14, height: 1.5, color: const Color(0xFFE9EAEE)),
                    cursorColor: ObsidianColors.cyan,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: '0x…',
                      hintStyle: st.mono(fontSize: 14, height: 1.5, color: ObsidianColors.textMuted),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ObsidianPanel(
                  width: 38,
                  height: 38,
                  onTap: _isSending ? null : _obsPaste,
                  semanticLabel: l.t('obs.send.paste'),
                  surface: const ObsidianSurface(
                    radius: 12,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [ObsidianColors.darkTop, ObsidianColors.darkBottom],
                    ),
                    topHighlight: Color(0x1FFFFFFF),
                    shadows: [CssShadow(0, 6, 12, -6, Color(0xE6000000))],
                  ),
                  child: const Center(
                    child: ObsidianGlyphIcon(ObsidianGlyph.paste, size: 17, color: Color(0xFFE9EAEE), strokeWidth: 1.8),
                  ),
                ),
                const SizedBox(width: 8),
                ObsidianPressable(
                  onTap: _isSending ? null : _scanQR,
                  semanticLabel: l.t('send.scanQR'),
                  child: const Icon3D(ObsidianIcons.scan, size: 38),
                ),
              ],
            ),
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.t('obs.send.to'), style: st.ui(fontSize: 13, color: ObsidianColors.textSec)),
            const SizedBox(height: 8),
            // ที่อยู่ถูกต้อง = ขอบไล่สีแบรนด์ + เรืองม่วง (เปลี่ยนนุ่ม ๆ)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(19),
                gradient: valid
                    ? const LinearGradient(
                        begin: Alignment(-0.87, -0.5), // 120deg
                        end: Alignment(0.87, 0.5),
                        colors: [Color(0xD922D3EE), Color(0x998B5CF6), Color(0xBFFB923C)],
                      )
                    : null,
                color: valid ? null : (invalid ? const Color(0x80F87171) : const Color(0x14FFFFFF)),
                boxShadow: valid ? [const CssShadow(0, 0, 24, -6, Color(0x8C8B5CF6)).toBoxShadow()] : const [],
              ),
              child: field,
            ),
            if (valid || invalid) ...[
              const SizedBox(height: 8),
              valid ? _obsValidLine(l, st) : _obsInvalidLine(l, st),
            ],
          ],
        );
      },
    );
  }

  /// "ที่อยู่ถูกต้อง · ตรงกับ “…” ในรายการโปรด" + ปุ่มบันทึก/แก้ชื่อ (ฟีเจอร์ดาวของหน้าเดิม)
  Widget _obsValidLine(LocaleProvider l, ObsidianStyle st) {
    final match = _matched;
    final text = match == null
        ? l.t('obs.send.valid')
        : l.t('obs.send.validMatch').replaceAll('{name}', match.name);
    return Row(
      children: [
        const Icon3D(ObsidianIcons.shield, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: st.ui(fontSize: 12.5, color: ObsidianColors.successPale),
          ),
        ),
        const SizedBox(width: 4),
        // ดาว = บันทึกที่อยู่นี้เป็นรายการโปรด (ทึบ = บันทึกแล้ว แตะเพื่อแก้ชื่อ) — ฟีเจอร์เดิมของช่องที่อยู่
        ObsidianPressable(
          onTap: _isSending ? null : _saveCurrentAddress,
          semanticLabel: l.t(match == null ? 'contacts.saveTitle' : 'contacts.editTitle'),
          child: SizedBox.square(
            dimension: 32,
            child: Icon(
              match == null ? Icons.star_border_rounded : Icons.star_rounded,
              size: 20,
              color: ObsidianColors.warning,
            ),
          ),
        ),
      ],
    );
  }

  Widget _obsInvalidLine(LocaleProvider l, ObsidianStyle st) => Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: ObsidianColors.danger),
          const SizedBox(width: 6),
          Expanded(
            child: Text(l.t('send.invalidAddress'), style: st.ui(fontSize: 12.5, color: ObsidianColors.dangerSoft)),
          ),
        ],
      );

  // ── รายการโปรด (ชิปทางลัด) ──

  Widget _obsFavorites(ObsidianStyle st) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: _favorites.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = _favorites[i];
          final selected = _matched?.id == c.id;
          final color = contactColor(c.address);
          return ObsidianPanel(
            onTap: _isSending
                ? null
                : () {
                    _addressController.text = c.address;
                    SynthService.playTap();
                  },
            semanticLabel: c.name,
            padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
            surface: selected
                ? const ObsidianSurface(
                    radius: 999,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x4D8B5CF6), Color(0x1F8B5CF6)], // .30 → .12
                    ),
                    topHighlight: Color(0x2EFFFFFF),
                    ring: Color(0x998B5CF6),
                    shadows: [CssShadow(0, 8, 18, -8, Color(0xB38B5CF6))],
                  )
                : const ObsidianSurface(
                    radius: 999,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [ObsidianColors.darkTop, ObsidianColors.darkBottom],
                    ),
                    topHighlight: Color(0x1FFFFFFF),
                    shadows: [CssShadow(0, 8, 16, -8, Color(0xE6000000))],
                  ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.3, -0.4),
                      radius: 0.9,
                      colors: [Color.lerp(color, Colors.white, 0.35)!, Color.lerp(color, Colors.black, 0.35)!],
                    ),
                  ),
                  child: Text(c.initial, style: st.ui(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: st.ui(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                      color: selected ? ObsidianColors.text : ObsidianColors.textSoft,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── สรุปค่าธรรมเนียม ──

  Widget _obsFeePanel(LocaleProvider l, ObsidianStyle st) {
    Widget row(String label, Widget value) => SizedBox(
          height: 36,
          child: Row(
            children: [
              Expanded(child: Text(label, style: st.ui(fontSize: 13.5, color: ObsidianColors.textSec))),
              value,
            ],
          ),
        );
    final valueStyle = st.ui(fontSize: 13.5, color: ObsidianColors.text);
    return ObsidianPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      surface: const ObsidianSurface(
        radius: 20,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x0FFFFFFF), Color(0x05FFFFFF)],
        ),
        topHighlight: Color(0x1AFFFFFF),
        bottomShade: Color(0x80000000),
        shadows: [CssShadow(0, 16, 30, -20, Color(0xE6000000))],
      ),
      child: Column(
        children: [
          row(
            l.t('send.network'),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: ObsidianColors.success,
                  boxShadow: [BoxShadow(color: ObsidianColors.success, blurRadius: 8)],
                ),
              ),
              const SizedBox(width: 6),
              Text('TPIX Chain', style: valueStyle),
            ]),
          ),
          row(
            l.t('obs.send.gas'),
            Text(
              l.t('obs.send.gasVal'),
              style: st.ui(fontSize: 13.5, fontWeight: FontWeight.w600, color: ObsidianColors.successSoft),
            ),
          ),
          row(l.t('obs.send.eta'), Text(l.t('obs.send.etaVal'), style: valueStyle)),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  ป้ายสรุปบนหน้า PIN
  // ════════════════════════════════════════════════════════════

  TxAuthSummary _authSummary(String address, String amountText, String symbol, TokenInfo? token, LocaleProvider l) {
    final match = _lookupFavorite(address);
    final who = match == null ? _obsShort(address) : '${match.name} · ${_obsShort(address)}';
    return TxAuthSummary(
      title: l.t('obs.send.summary').replaceAll('{amount}', groupDigits(amountText)).replaceAll('{symbol}', symbol),
      subtitle: l.t('obs.send.summaryTo').replaceAll('{name}', who),
      leading: _obsAssetLogo(context.read<WalletProvider>(), token, 30),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  แผ่นยืนยัน (ข้อมูลชุดเดิม: จาก / ผู้รับ / ที่อยู่ / จำนวน / เครือข่าย / ค่าแก๊ส)
  // ════════════════════════════════════════════════════════════

  Future<bool?> _obsConfirm({
    required String address,
    required String amountText,
    required String symbol,
    required String fromAddress,
    required String? fromName,
    required LocaleProvider l,
  }) {
    final wallet = context.read<WalletProvider>();
    final token = _selectedTokenInfo(wallet);
    final match = _lookupFavorite(address);
    final price = wallet.tpixPrice;
    final parsed = Units.parse(amountText, _decimalsOf(token));
    final usd = token == null && price != null && parsed.isOk
        ? _obsUsd.format(Units.toDouble(parsed.value!, _decimalsOf(token)) * price)
        : null;

    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final st = ObsidianStyle.of(sheetCtx);
        Widget row(String label, Widget value) => SizedBox(
              height: 34,
              child: Row(
                children: [
                  Text(label, style: st.ui(fontSize: 13, color: ObsidianColors.textSec)),
                  const SizedBox(width: 12),
                  Expanded(child: Align(alignment: Alignment.centerRight, child: value)),
                ],
              ),
            );
        final value = st.ui(fontSize: 13, color: ObsidianColors.text);

        return Container(
          padding: EdgeInsets.fromLTRB(22, 12, 22, 28 + MediaQuery.paddingOf(sheetCtx).bottom),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xF71C1F29), Color(0xFC0C0E13)],
            ),
            border: Border(top: BorderSide(color: Color(0x24FFFFFF))),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  l.t('send.confirmTitle'),
                  textAlign: TextAlign.center,
                  style: st.ui(fontSize: 15, fontWeight: FontWeight.w600, color: ObsidianColors.textSoft),
                ),
                const SizedBox(height: 14),
                // ผู้รับ — มีชื่อในรายการโปรดก็โชว์ชื่อ (ตรวจ "ส่งให้น้องเอ" ง่ายกว่าเลขย่อ)
                Row(
                  children: [
                    const SizedBox.square(
                      dimension: 48,
                      child: CustomPaint(
                        painter: ObsidianSurfacePainter(ObsidianSurface(
                          radius: 16,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [ObsidianColors.darkTop, ObsidianColors.darkBottom],
                          ),
                          topHighlight: Color(0x1FFFFFFF),
                        )),
                        child: Center(child: Icon3D(ObsidianIcons.wallet, size: 32)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.t('send.confirmTo'), style: st.ui(fontSize: 12, color: ObsidianColors.textSec)),
                          if (match != null)
                            Text(
                              match.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: st.ui(fontSize: 16, fontWeight: FontWeight.w600, color: ObsidianColors.successPale),
                            ),
                          // ที่อยู่เต็ม (ไม่ย่อ) — ให้ตรวจได้ทุกตัวอักษรก่อนส่งจริง
                          Text(
                            address,
                            style: st.mono(fontSize: 12, height: 1.4, color: ObsidianColors.textSec),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon3D(ObsidianIcons.shield, size: 30),
                  ],
                ),
                const SizedBox(height: 14),
                // จำนวนเต็มที่จะส่งจริง (ไม่ปัด)
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: groupDigits(amountText)),
                        const WidgetSpan(child: SizedBox(width: 8)),
                        TextSpan(
                          text: symbol,
                          style: st.number(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                            color: ObsidianColors.textMuted,
                          ),
                        ),
                      ]),
                      style: st.number(
                        fontSize: 44,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.5,
                        color: ObsidianColors.text,
                        shadows: const [Shadow(color: Color(0x738B5CF6), blurRadius: 22, offset: Offset(0, 6))],
                      ),
                    ),
                  ),
                ),
                if (usd != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '≈ $usd',
                      textAlign: TextAlign.center,
                      style: st.ui(fontSize: 13, color: ObsidianColors.textSec),
                    ),
                  ),
                const SizedBox(height: 14),
                ObsidianPanel(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  surface: const ObsidianSurface(
                    radius: 18,
                    color: Color(0x0AFFFFFF),
                    topHighlight: Color(0x14FFFFFF),
                  ),
                  child: Column(
                    children: [
                      // กระเป๋าต้นทาง — ผู้ใช้หลายกระเป๋าต้องเห็นว่าส่งจากใบไหน
                      row(
                        l.t('send.from'),
                        Text(
                          fromName != null && fromName.isNotEmpty
                              ? '$fromName · ${_obsShort(fromAddress)}'
                              : _obsShort(fromAddress),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: value,
                        ),
                      ),
                      row(
                        l.t('send.network'),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const TpixCoinLogo(size: 18),
                          const SizedBox(width: 6),
                          Text('TPIX Chain (4289)', style: value),
                        ]),
                      ),
                      row(
                        l.t('obs.send.gas'),
                        Text(
                          l.t('send.gasFreeVal'),
                          style: st.ui(fontSize: 13, fontWeight: FontWeight.w600, color: ObsidianColors.successSoft),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ObsidianButton.secondary(
                        label: l.t('send.cancel'),
                        height: 56,
                        onPressed: () => obsidianPopIfCurrent(sheetCtx, false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ObsidianButton(
                        label: symbol == 'TPIX'
                            ? l.t('send.confirmButton')
                            : l.t('send.confirmButtonToken').replaceAll('{symbol}', symbol),
                        height: 56,
                        onPressed: () => obsidianPopIfCurrent(sheetCtx, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════════
  //  ส่งสำเร็จ
  // ════════════════════════════════════════════════════════════

  Widget _buildObsidianSuccess(LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final to = _sentTo;
    final match = to == null ? null : _lookupFavorite(to);
    final who = match?.name ?? (to == null ? '' : _obsShort(to));
    final hash = _txHash;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const ObsidianScrim.pin(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                // จางเข้า (ตัวควบคุมเดิมของหน้าสำเร็จ — 35% แรกของ 1.5 วิ)
                child: AnimatedBuilder(
                  animation: _successController,
                  builder: (context, child) => Opacity(
                    opacity: (_successController.value / 0.35).clamp(0.0, 1.0),
                    child: child,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ObsidianCheckRing(),
                      const SizedBox(height: 14),
                      Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text(
                          l.t('send.success'),
                          style: st.ui(fontSize: 24, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                        ),
                      ),
                      if (_sentAmountText != null) ...[
                        const SizedBox(height: 14),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${groupDigits(_sentAmountText!)} ${_sentSymbol ?? ''}',
                            style: st.number(
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1,
                              color: ObsidianColors.text,
                            ),
                          ),
                        ),
                      ],
                      if (who.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          l.t('obs.send.sentTo').replaceAll('{name}', who),
                          textAlign: TextAlign.center,
                          style: st.ui(fontSize: 13.5, color: ObsidianColors.textSec),
                        ),
                      ],
                      if (hash != null && hash.length > 18) ...[
                        const SizedBox(height: 14),
                        Text(
                          'tx ${hash.substring(0, 6)}…${hash.substring(hash.length - 4)}',
                          style: st.mono(fontSize: 12, color: ObsidianColors.textMuted),
                        ),
                      ],
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: ObsidianButton.secondary(
                              label: l.t('obs.send.viewTx'),
                              height: 54,
                              onPressed: () {
                                // แตะซ้ำระหว่างเปลี่ยนหน้า → ไม่เปิดซ้อน
                                if (ModalRoute.of(context)?.isCurrent == false) return;
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (_) => const TxHistoryScreen()),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ObsidianButton(
                              label: l.t('send.goBack'),
                              height: 54,
                              onPressed: () => obsidianPopIfCurrent(context),
                            ),
                          ),
                        ],
                      ),
                      // เพิ่งส่งให้คนที่ยังไม่มีชื่อ → เสนอบันทึก (จังหวะที่ยังจำได้ว่าเป็นใคร)
                      if (to != null && match == null) ...[
                        const SizedBox(height: 16),
                        ObsidianPressable(
                          onTap: _saveSentRecipient,
                          semanticLabel: l.t('contacts.saveRecipient'),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_border_rounded, size: 18, color: ObsidianColors.warning),
                                const SizedBox(width: 6),
                                Text(
                                  l.t('contacts.saveRecipient'),
                                  style: st.ui(fontSize: 14, fontWeight: FontWeight.w600, color: ObsidianColors.warning),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

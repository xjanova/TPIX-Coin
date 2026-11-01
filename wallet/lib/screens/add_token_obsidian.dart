// TPIX Wallet — หน้าเพิ่มโทเค็นธีม Obsidian
//
// part ของ add_token_screen.dart โดยตั้งใจ: ค้นหา · อ่านสัญญา · จัดระดับความน่าเชื่อถือ · เพิ่มทีเดียว
// · กันกดซ้ำ · รายการจาก explorer ใช้ของเดิมทั้งหมด — ไฟล์นี้เปลี่ยนแค่หน้าตา
// (คำเตือนของปลอม/ไม่ยืนยัน/ยืนยันแค่ซอร์สโค้ดครบทุกข้อเหมือนธีมเดิม)
//
// Developed by Xman Studio

part of 'add_token_screen.dart';

extension _AddTokenObsidian on _AddTokenScreenState {
  Widget _obsBuild(LocaleProvider l, WalletProvider wallet) {
    final pad = MediaQuery.paddingOf(context);
    final idle = _foundToken == null && _prefill == null && _errorMsg == null && !_isLoading;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: ObsidianPageScrim()),
          Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(24, math.max(52.0, pad.top + 8), 24, 14),
                child: ObsidianPageHeader(
                  title: l.t('obs.token.title'),
                  subtitle: l.t('obs.token.subtitle'),
                  backLabel: l.t('obs.back'),
                  trailing: ObsidianHeaderTile(asset: ObsidianIcons.qr, label: l.t('obs.token.scan'), onTap: _scanQR),
                ),
              ),
              Expanded(
                child: ObsidianTopFade(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + pad.bottom),
                    children: [
                      _obsSearchCard(l),
                      if (_errorMsg != null) ...[
                        const SizedBox(height: 14),
                        ObsidianNotice(tone: ObsidianTone.danger, lines: [_errorMsg!]),
                      ],
                      // ข้อมูลจากรายการที่ยืนยันแล้ว ระหว่างรออ่านสัญญา
                      if (_foundToken == null && _prefill != null && _isLoading) ...[
                        const SizedBox(height: 14),
                        _obsPrefill(_prefill!, l),
                      ],
                      if (_foundToken != null) ...[const SizedBox(height: 14), _obsTokenPreview(l)],
                      if (idle) ...[
                        const SizedBox(height: 14),
                        _obsVerifiedList(wallet, l),
                        const SizedBox(height: 14),
                        _obsHowTo(l),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _obsSearchCard(LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    return ObsidianPanel(
      surface: ObsidianCards.form,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.t('token.contractAddress'), style: st.ui(fontSize: 12.5, color: ObsidianColors.textSec)),
          const SizedBox(height: 8),
          ObsidianTextField(
            controller: _controller,
            hint: l.t('token.inputHint'),
            mono: true,
            // ฟอนต์ mono บางเครื่องไม่มีอักษรไทย — hint/คำค้นภาษาไทยต้องไม่เป็นกล่อง
            fontFamilyFallback: _AddTokenScreenState.thaiFontFallback,
            onChanged: _onInputChanged,
            onSubmitted: (_) => _search(),
            suffix: IconButton(
              tooltip: l.t('obs.token.paste'),
              onPressed: _pasteFromClipboard,
              icon: const Icon(Icons.content_paste_rounded, size: 19, color: ObsidianColors.textMuted),
            ),
          ),
          const SizedBox(height: 12),
          ObsidianButton.secondary(
            label: l.t('token.search'),
            height: 48,
            loading: _isLoading,
            loadingLabel: l.t('token.searching'),
            onPressed: _isLoading ? null : _search,
          ),
        ],
      ),
    );
  }

  // ── การ์ดตัวอย่างโทเค็น ──

  /// ป้ายแคปซูลใต้ชื่อ — "ยืนยันแล้ว" (เขียว) / "ยืนยันซอร์สโค้ด" (ฟ้า คนละป้ายกัน)
  Widget _obsTrustPill({
    required IconData icon,
    required String label,
    required String hint,
    required Color color,
    required Color soft,
  }) {
    final st = ObsidianStyle.of(context);
    return Tooltip(
      message: hint,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: soft),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: st.ui(fontSize: 12, fontWeight: FontWeight.w600, color: soft),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _obsIdentity({
    required String name,
    required String symbol,
    required String? logoUrl,
    required TokenTrust? trust,
    required LocaleProvider l,
  }) {
    final st = ObsidianStyle.of(context);
    return Column(
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x668B5CF6), blurRadius: 24, spreadRadius: -4)],
          ),
          child: TokenAvatar(symbol: symbol, logoUrl: logoUrl, size: 56, color: ObsidianColors.violet),
        ),
        const SizedBox(height: 12),
        Text(
          name,
          textAlign: TextAlign.center,
          style: st.ui(fontSize: 18, fontWeight: FontWeight.w600, color: ObsidianColors.text, height: 1.35),
        ),
        Text(
          symbol,
          style: st.ui(fontSize: 14, fontWeight: FontWeight.w600, color: ObsidianColors.cyan),
        ),
        if (trust == TokenTrust.verified) ...[
          const SizedBox(height: 8),
          _obsTrustPill(
            icon: Icons.verified,
            label: l.t('token.verified'),
            hint: l.t('token.verifiedHint'),
            color: ObsidianColors.success,
            soft: ObsidianColors.successSoft,
          ),
        ],
        if (trust == TokenTrust.sourceVerified) ...[
          const SizedBox(height: 8),
          _obsTrustPill(
            icon: Icons.task_alt_rounded,
            label: l.t('token.sourceVerified'),
            hint: l.t('token.sourceVerifiedHint'),
            color: ObsidianColors.cyan,
            soft: ObsidianColors.cyan,
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _obsPrefill(TokenDef def, LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    return ObsidianPanel(
      surface: ObsidianCards.hero,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _obsIdentity(name: def.name, symbol: def.symbol, logoUrl: def.logoUrl, trust: TokenTrust.verified, l: l),
          ObsidianKv(l.t('token.contractAddress'), _AddTokenScreenState._short(def.address), mono: true),
          ObsidianKv(l.t('token.decimalsLabel'), '${def.decimals}'),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianColors.cyan),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(l.t('token.checkingContract'), style: st.ui(fontSize: 12.5, color: ObsidianColors.textSec)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _obsTokenPreview(LocaleProvider l) {
    final token = _foundToken!;
    final trust = _trust;
    return ObsidianPanel(
      surface: ObsidianCards.hero,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _obsIdentity(
            name: token.name,
            symbol: token.symbol,
            logoUrl: token.logoUrl,
            trust: trust?.trust,
            l: l,
          ),
          ObsidianKv(l.t('token.contractAddress'), token.shortAddress, mono: true),
          ObsidianKv(l.t('token.decimalsLabel'), '${token.decimals}'),
          if (_balance != null) ObsidianKv(l.t('home.balance'), '${_balance!.toStringAsFixed(4)} ${token.symbol}'),
          if (trust != null) ..._obsTrustNotices(trust, token, l),
          const SizedBox(height: 16),
          ObsidianButton(label: l.t('token.add'), loading: _isAdding, onPressed: _isAdding ? null : _addToken),
        ],
      ),
    );
  }

  /// คำเตือนตามผลตรวจ — ข้อความชุดเดียวกับหน้าเดิมทุกข้อ
  List<Widget> _obsTrustNotices(TokenTrustResult trust, TokenInfo token, LocaleProvider l) {
    final mismatch = trust.mismatches.isEmpty
        ? const <Widget>[]
        : [
            const SizedBox(height: 12),
            ObsidianNotice(
              tone: ObsidianTone.warning,
              title: l.t('token.mismatchTitle'),
              lines: [l.t('token.mismatchBody'), ..._mismatchRows(trust, token, l)],
            ),
          ];
    switch (trust.trust) {
      case TokenTrust.verified:
        return mismatch;
      case TokenTrust.sourceVerified:
        // ยืนยันซอร์สโค้ด ≠ TPIX ตรวจสอบ — ยังเตือนโทนเดียวกับ "ไม่ยืนยัน"
        return [
          const SizedBox(height: 12),
          ObsidianNotice(
            tone: ObsidianTone.warning,
            title: l.t('token.sourceVerifiedTitle'),
            lines: [l.t('token.sourceVerifiedBody')],
          ),
          ...mismatch,
        ];
      case TokenTrust.unverified:
        return [
          const SizedBox(height: 12),
          ObsidianNotice(
            tone: ObsidianTone.warning,
            title: l.t('token.unverifiedTitle'),
            lines: [l.t('token.unverifiedBody'), if (!trust.listAvailable) l.t('token.listUnavailable')],
          ),
        ];
      case TokenTrust.lookalike:
        return [
          const SizedBox(height: 12),
          ObsidianNotice(
            tone: ObsidianTone.danger,
            title: l.t('token.lookalikeTitle'),
            lines: _lookalikeLines(trust, l),
          ),
        ];
    }
  }

  // ── รายการโทเค็นที่ยืนยันแล้ว ──

  Widget _obsVerifiedList(WalletProvider wallet, LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final entries = _pickerEntries();
    final added = _AddTokenScreenState._addedKeys(wallet);
    final shown = entries.take(_AddTokenScreenState._pickerLimit).toList();
    return ObsidianPanel(
      surface: ObsidianCards.details,
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon3D(ObsidianIcons.coins, size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.t('token.listTitle'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: st.ui(fontSize: 14.5, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 34),
            child: Text(l.t('token.listSubtitle'), style: st.ui(fontSize: 12, color: ObsidianColors.textMuted)),
          ),
          const SizedBox(height: 6),
          // ไม่มีชุดที่ใช้ได้: กำลังโหลด (ครั้งแรก) หรือโหลดไม่ได้ → บอก + ลองใหม่ (ไม่ใช่รายการว่างเฉยๆ)
          if (!_AddTokenScreenState._pickerReady)
            _obsExplorerStatus(l, st)
          else ...[
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l.t(_query.isEmpty || _pickerEntries(all: true).isEmpty ? 'token.explorerEmpty' : 'token.listNoMatch'),
                  style: st.ui(fontSize: 12.5, color: ObsidianColors.textMuted),
                ),
              ),
            for (final t in shown) _obsPickerRow(t, added.contains(t.key), l, st),
            if (entries.length > shown.length)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  l.t('token.listMore').replaceAll('{n}', '${shown.length}').replaceAll('{total}', '${entries.length}'),
                  style: st.ui(fontSize: 11.5, color: ObsidianColors.textMuted),
                ),
              ),
            if (_AddTokenScreenState._listStale) _obsStaleNote(l, st),
          ],
        ],
      ),
    );
  }

  Widget _obsExplorerStatus(LocaleProvider l, ObsidianStyle st) {
    if (_explorerLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianColors.cyan),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l.t('token.explorerLoading'), style: st.ui(fontSize: 12.5, color: ObsidianColors.textSec)),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 6, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ObsidianNotice(tone: ObsidianTone.warning, lines: [l.t(_AddTokenScreenState._unavailableKey())]),
          const SizedBox(height: 10),
          ObsidianButton.secondary(
            key: const ValueKey('explorer-retry'),
            label: l.t('token.retry'),
            height: 44,
            onPressed: _retryExplorer,
          ),
        ],
      ),
    );
  }

  /// ชุดที่โชว์มาจากเครื่อง เพราะตรวจกับ explorer / รายการที่อนุมัติรอบล่าสุดไม่สำเร็จ
  Widget _obsStaleNote(LocaleProvider l, ObsidianStyle st) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            const Icon(Icons.schedule_rounded, size: 14, color: ObsidianColors.textMuted),
            const SizedBox(width: 5),
            Expanded(
              child: Text(l.t('token.explorerStale'), style: st.ui(fontSize: 11.5, color: ObsidianColors.textMuted)),
            ),
            SizedBox(
              height: 32,
              child: _explorerLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianColors.cyan),
                        ),
                      ),
                    )
                  : TextButton(
                      key: const ValueKey('explorer-retry'),
                      onPressed: _retryExplorer,
                      child: Text(l.t('token.retry'), style: st.ui(fontSize: 12, color: ObsidianColors.cyan)),
                    ),
            ),
          ],
        ),
      );

  Widget _obsPickerRow(_PickerItem t, bool isAdded, LocaleProvider l, ObsidianStyle st) {
    final busy = _quickAdding == t.key;
    return ObsidianPressable(
      // แตะที่แถว = ดูรายละเอียดก่อนเพิ่ม
      onTap: isAdded || busy
          ? null
          : () {
              _setInput(t.address);
              _search();
            },
      pressedScale: 0.985,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Color(0xCC000000), offset: Offset(0, 6), blurRadius: 11.3, spreadRadius: -4),
                ],
              ),
              child: TokenAvatar(symbol: t.symbol, logoUrl: t.logoUrl, size: 38, color: ObsidianColors.violet),
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
                          t.symbol,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: st.ui(fontSize: 14.5, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                        ),
                      ),
                      const SizedBox(width: 4),
                      TokenTrustIcon(trust: t.trust, size: 13),
                    ],
                  ),
                  // ที่อยู่สัญญาโชว์ทุกแถว — ชื่อซ้ำกันแยกได้ด้วยที่อยู่เท่านั้น
                  Text(
                    '${t.name} · ${_AddTokenScreenState._short(t.address)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: st.ui(fontSize: 11.5, color: ObsidianColors.textMuted),
                  ),
                ],
              ),
            ),
            // ขนาดคงที่ทุกสถานะ (เพิ่ม / กำลังเพิ่ม / เพิ่มแล้ว) — ไม่กระตุก
            SizedBox(
              width: 64,
              height: 36,
              child: Center(
                child: isAdded
                    ? Text(
                        l.t('token.addedShort'),
                        style: st.ui(fontSize: 11.5, fontWeight: FontWeight.w600, color: ObsidianColors.textMuted),
                      )
                    : busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianColors.cyan),
                      )
                    : Opacity(
                        opacity: _quickAdding == null ? 1 : 0.45,
                        child: ObsidianPressable(
                          key: ValueKey('obs-quick-add-${t.key}'),
                          onTap: _quickAdding == null ? () => _quickAdd(t) : null,
                          semanticLabel: '${l.t('token.add')} ${t.symbol}',
                          pressedScale: 0.9,
                          child: const CustomPaint(
                            painter: ObsidianSurfacePainter(
                              ObsidianSurface(
                                radius: 12,
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0xFF2A2E3B), Color(0xFF191C25)],
                                ),
                                topHighlight: Color(0x29FFFFFF),
                                ring: Color(0x5922D3EE),
                              ),
                            ),
                            child: SizedBox(
                              width: 40,
                              height: 32,
                              child: Icon(Icons.add_rounded, size: 20, color: ObsidianColors.cyan),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _obsHowTo(LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    return ObsidianPanel(
      surface: ObsidianCards.details,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon3D(ObsidianIcons.info, size: 22),
              const SizedBox(width: 8),
              Text(
                l.t('token.howTo'),
                style: st.ui(fontSize: 14, fontWeight: FontWeight.w600, color: ObsidianColors.text),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(l.t('token.howToDesc'), style: st.ui(fontSize: 12.5, color: ObsidianColors.textSec, height: 1.6)),
        ],
      ),
    );
  }
}

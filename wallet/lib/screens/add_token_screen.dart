import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../core/themes/tokens.dart';
import '../core/themes/widgets/screen_background.dart';
import '../models/chain_config.dart';
import '../models/token_info.dart';
import '../providers/wallet_provider.dart';
import '../services/db_service.dart';
import '../services/token_list_service.dart';
import '../services/token_service.dart';
import '../services/token_trust.dart';
import '../services/wallet_service.dart';
import '../widgets/qr_scanner_screen.dart';
import '../widgets/token_badges.dart';
import '../widgets/tpix_coin_logo.dart';

/// เพิ่มโทเค็นบน TPIX Chain
///
/// - ใส่ที่อยู่สัญญา → อ่านชื่อ/สัญลักษณ์/ทศนิยมจากสัญญาเสมอ (ข้อมูลบนเชนชนะ)
/// - อยู่ในรายการที่ยืนยันแล้ว → โชว์ข้อมูล/โลโก้จากรายการทันที + ป้าย "ยืนยันแล้ว"
///   ถ้าบนสัญญาไม่ตรงกับรายการ → ใช้ของสัญญา + เตือน
/// - ไม่อยู่ในรายการ → ยังเพิ่มได้ แต่เตือนชัดๆ · ชื่อซ้ำตัวที่ยืนยันแล้ว → เตือนของปลอม
///   และต้องกดยืนยันอีกชั้นก่อนเพิ่ม
/// - รายการ "โทเค็นบน TPIX Chain" ด้านล่าง: แตะ + เพิ่มได้ในทีเดียว
class AddTokenScreen extends StatefulWidget {
  const AddTokenScreen({super.key});

  @override
  State<AddTokenScreen> createState() => _AddTokenScreenState();
}

class _AddTokenScreenState extends State<AddTokenScreen> {
  /// แสดงในรายการได้ไม่เกินนี้ — ที่เหลือพิมพ์ค้นหาเอา
  static const _pickerLimit = 30;

  final _controller = TextEditingController();
  bool _isLoading = false;
  bool _isAdding = false;
  TokenInfo? _foundToken; // ข้อมูลจากสัญญา (+ โลโก้จากรายการเมื่อยืนยันแล้ว)
  TokenTrustResult? _trust;
  TokenDef? _prefill; // ข้อมูลจากรายการ — โชว์ระหว่างรออ่านสัญญา
  String? _errorMsg;
  double? _balance;
  String _query = '';
  String? _quickAdding; // ที่อยู่ที่กำลังเพิ่มจากรายการ (ตัวเล็ก)

  /// ทุกการค้นหาได้เลขใหม่ — ผลของการค้นหาเก่าที่กลับมาช้าถูกทิ้ง
  int _searchSeq = 0;
  String? _searchedInput;

  @override
  void initState() {
    super.initState();
    // โหลดรายการที่ยืนยันแล้วเบื้องหลัง (มีแคชในเครื่องก็ได้ทันที) — ไม่บล็อกหน้าจอ
    unawaited(context.read<WalletProvider>().refreshTokenList());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clearResult() {
    _foundToken = null;
    _trust = null;
    _prefill = null;
    _balance = null;
    _errorMsg = null;
  }

  void _onInputChanged(String value) {
    final q = value.trim();
    setState(() {
      _query = q;
      // แก้ข้อความหลังค้นหาแล้ว → ผลที่โชว์อยู่ไม่ใช่ของที่อยู่นี้แล้ว
      if (_searchedInput != null && q.toLowerCase() != _searchedInput) {
        _searchSeq++;
        _searchedInput = null;
        _isLoading = false;
        _clearResult();
      } else if (_errorMsg != null && _foundToken == null) {
        _errorMsg = null;
      }
    });
  }

  void _setInput(String text) {
    _controller.text = text;
    _query = text.trim();
  }

  void _scanQR() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QRScannerScreen(
          titleKey: 'import.scanQR',
          onScanned: (value) {
            // Parse address from QR (could be ethereum: URI)
            final addr = WalletService.parseAddressFromQR(value) ?? value.trim();
            _setInput(addr);
            Navigator.pop(context);
            _search();
          },
        ),
      ),
    );
  }

  Future<void> _search() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    final l = context.read<LocaleProvider>();
    final wallet = context.read<WalletProvider>();

    // Validate address format (+ checksum EIP-55 ถ้าเป็นตัวพิมพ์ผสม — กันพิมพ์ผิด)
    if (!WalletService.isValidAddress(input)) {
      // พิมพ์ชื่อ/สัญลักษณ์ → ใช้กรองรายการด้านล่าง (มีผล = ไม่ใช่ข้อผิดพลาด)
      if (!input.toLowerCase().startsWith('0x') && _pickerEntries(wallet).isNotEmpty) {
        FocusScope.of(context).unfocus();
        return;
      }
      setState(() {
        _clearResult();
        _errorMsg = l.t('token.invalidAddress');
      });
      return;
    }

    final seq = ++_searchSeq;
    final slot = wallet.activeSlot;
    _searchedInput = input.toLowerCase();
    setState(() {
      _isLoading = true;
      _clearResult();
      // อยู่ในรายการที่ยืนยันแล้ว → โชว์ข้อมูลจากรายการไปก่อนระหว่างอ่านสัญญา
      _prefill = TokenTrustService.verifiedFor(input, wallet.tokenList);
    });
    bool stale() => !mounted || seq != _searchSeq;

    void fail(String key) {
      if (stale()) return;
      setState(() {
        _isLoading = false;
        _prefill = null;
        _errorMsg = l.t(key);
      });
    }

    // Check if already added
    if (await DbService.tokenExists(input, slot)) return fail('token.alreadyAdded');

    // รายการที่ยืนยันแล้ว: ปกติมีในเครื่องอยู่แล้ว — ถ้าต้องรอเน็ต รอไม่เกิน 3 วิ
    final listFuture = TokenListService.load().timeout(
      const Duration(seconds: 3),
      onTimeout: () => TokenListService.current,
    );

    // อ่านจากสัญญาเสมอ — เน็ตล่ม ≠ "ไม่ใช่โทเค็น" (แยกข้อความ ไม่งั้นผู้ใช้คิดว่าที่อยู่ผิด)
    final TokenInfo? onChain;
    try {
      onChain = await TokenService.fetchTokenInfo(input, slot);
    } catch (_) {
      return fail('token.networkError');
    }
    final list = await listFuture;
    if (stale()) return;
    if (onChain == null) return fail('token.notFound');

    final trust = TokenTrustService.classify(
      address: onChain.contractAddress,
      name: onChain.name,
      symbol: onChain.symbol,
      decimals: onChain.decimals,
      list: list,
    );
    final token = _withVerifiedLogo(onChain, trust);

    // Fetch balance (ดึงไม่ได้ = ไม่โชว์ ไม่ใช่ 0)
    double? bal;
    final address = wallet.address;
    if (address != null) {
      bal = await TokenService.getFormattedBalance(token.contractAddress, address, token.decimals);
    }
    if (stale()) return;
    setState(() {
      _isLoading = false;
      _prefill = null;
      _foundToken = token;
      _trust = trust;
      _balance = bal;
    });
  }

  /// โลโก้ให้เฉพาะตัวที่ยืนยันแล้ว — ตัวไม่ยืนยันห้ามยืมโลโก้ของใคร (กันปลอมตัว)
  static TokenInfo _withVerifiedLogo(TokenInfo t, TokenTrustResult trust) {
    final logo = trust.isVerified ? trust.listed?.logoUrl : null;
    if (logo == null) return t;
    return TokenInfo(
      contractAddress: t.contractAddress,
      name: t.name,
      symbol: t.symbol,
      decimals: t.decimals,
      walletSlot: t.walletSlot,
      chainId: t.chainId,
      logoUrl: logo,
    );
  }

  Future<void> _addToken() async {
    final token = _foundToken;
    if (token == null || _isAdding) return; // double-tap guard
    if (_trust?.trust == TokenTrust.lookalike && !await _confirmLookalike(token)) return;
    if (!mounted) return;
    setState(() => _isAdding = true);

    final l = context.read<LocaleProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await DbService.addToken(token);
      if (!mounted) return;

      // Refresh token list in provider
      context.read<WalletProvider>().loadTokens();

      messenger.showSnackBar(
        SnackBar(
          content: Text('${l.t('token.added')} ${token.symbol}'),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.t('common.error'))));
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  /// ชื่อซ้ำตัวที่ยืนยันแล้ว → ต้องยืนยันอีกชั้น (ปุ่มยกเลิกเป็นทางหลัก)
  Future<bool> _confirmLookalike(TokenInfo token) async {
    final l = context.read<LocaleProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dc = AppColors.of(ctx);
        return AlertDialog(
          backgroundColor: dc.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.lg)),
          title: Text(l.t('token.lookalikeConfirmTitle'), style: const TextStyle(color: AppTheme.danger)),
          content: Text(
            '${token.name} (${token.symbol})\n${token.contractAddress}\n\n'
            '${l.t('token.lookalikeConfirmBody').replaceAll('{symbol}', token.symbol)}',
            style: TextStyle(color: dc.textSec),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.t('common.cancel'), style: TextStyle(color: dc.text, fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.t('token.addAnyway'), style: const TextStyle(color: AppTheme.danger)),
            ),
          ],
        );
      },
    );
    return ok == true;
  }

  /// แตะ + ในรายการที่ยืนยันแล้ว: อ่านสัญญา → ตรงกับรายการ = เพิ่มเลย
  /// ไม่ตรง = เปิดหน้าตรวจละเอียด (ผู้ใช้ต้องเห็นคำเตือนก่อน)
  Future<void> _quickAdd(TokenDef def) async {
    final key = def.address.toLowerCase();
    if (_quickAdding != null || _isAdding) return; // double-tap guard
    final l = context.read<LocaleProvider>();
    final wallet = context.read<WalletProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final slot = wallet.activeSlot;
    setState(() => _quickAdding = key);

    void toast(String text, {bool ok = false}) => messenger.showSnackBar(SnackBar(
          content: Text(text),
          backgroundColor: ok ? AppTheme.success : null,
          duration: const Duration(seconds: 2),
        ));

    try {
      if (await DbService.tokenExists(key, slot)) {
        unawaited(wallet.loadTokens());
        return;
      }
      final TokenInfo? onChain;
      try {
        onChain = await TokenService.fetchTokenInfo(key, slot);
      } catch (_) {
        if (mounted) toast(l.t('token.networkError'));
        return;
      }
      if (!mounted) return;
      if (onChain == null) {
        toast(l.t('token.notFound'));
        return;
      }
      final trust = TokenTrustService.classify(
        address: onChain.contractAddress,
        name: onChain.name,
        symbol: onChain.symbol,
        decimals: onChain.decimals,
        list: wallet.tokenList,
      );
      if (!trust.isVerified || trust.mismatches.isNotEmpty) {
        _setInput(def.address);
        unawaited(_search());
        return;
      }
      // สลับกระเป๋าระหว่างรอ → ไม่เพิ่มให้ผิดใบ
      if (wallet.activeSlot != slot) return;
      await DbService.addToken(_withVerifiedLogo(onChain, trust));
      if (!mounted) return;
      unawaited(wallet.loadTokens());
      toast('${l.t('token.added')} ${onChain.symbol}', ok: true);
    } catch (_) {
      if (mounted) toast(l.t('common.error'));
    } finally {
      if (mounted) setState(() => _quickAdding = null);
    }
  }

  /// โทเค็นที่ยืนยันแล้ว (รายการจากเซิร์ฟเวอร์ ∪ ค่าในตัวแอป) กรองตามคำค้น
  List<TokenDef> _pickerEntries(WalletProvider wallet) {
    final all = TokenTrustService.verifiedTokens(wallet.tokenList);
    final q = _query.toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((t) =>
            t.symbol.toLowerCase().contains(q) ||
            t.name.toLowerCase().contains(q) ||
            t.address.toLowerCase().startsWith(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final wallet = context.watch<WalletProvider>();
    final c = AppColors.of(context);
    final idle = _foundToken == null && _prefill == null && _errorMsg == null && !_isLoading;
    return Scaffold(
      body: TpixScreenBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_ios, color: c.text),
                    ),
                    const SizedBox(width: TpixGap.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.t('token.title'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
                        Text(l.t('token.subtitle'), style: TextStyle(fontSize: 12, color: c.textMuted)),
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: TpixGap.sm),

                      // Contract address input
                      Text(l.t('token.contractAddress'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSec)),
                      const SizedBox(height: TpixGap.sm),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              style: TextStyle(color: c.text, fontSize: 14, fontFamily: 'monospace'),
                              decoration: InputDecoration(
                                hintText: l.t('token.inputHint'),
                                hintStyle: TextStyle(color: c.textMuted),
                                filled: true,
                                fillColor: c.glassColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(TpixRadius.md),
                                  borderSide: BorderSide(color: c.glassBorder),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(TpixRadius.md),
                                  borderSide: BorderSide(color: c.glassBorder),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(TpixRadius.md),
                                  borderSide: const BorderSide(color: AppTheme.primary),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                suffixIcon: IconButton(
                                  onPressed: () async {
                                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                                    if (!mounted) return;
                                    if (data?.text != null) {
                                      _setInput(data!.text!.trim());
                                      _search();
                                    }
                                  },
                                  icon: Icon(Icons.paste, color: c.textMuted, size: 20),
                                ),
                              ),
                              onChanged: _onInputChanged,
                              onSubmitted: (_) => _search(),
                            ),
                          ),
                          const SizedBox(width: TpixGap.sm),
                          // Scan QR button
                          GestureDetector(
                            onTap: _scanQR,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(TpixRadius.md),
                                color: AppTheme.primary.withValues(alpha: 0.12),
                                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                              ),
                              child: const Icon(Icons.qr_code_scanner, color: AppTheme.primary, size: 24),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: TpixGap.md),

                      // Search button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _search,
                          icon: _isLoading
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2))
                              : const Icon(Icons.search, color: AppTheme.primary, size: 18),
                          label: Text(
                            _isLoading ? l.t('token.searching') : l.t('token.search'),
                            style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.md)),
                          ),
                        ),
                      ),

                      const SizedBox(height: TpixGap.xl),

                      // Error message
                      if (_errorMsg != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(TpixRadius.md),
                            color: AppTheme.danger.withValues(alpha: 0.08),
                            border: Border.all(color: AppTheme.danger.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: AppTheme.danger, size: 18),
                              const SizedBox(width: TpixGap.sm),
                              Expanded(child: Text(_errorMsg!, style: const TextStyle(color: AppTheme.danger, fontSize: 13))),
                            ],
                          ),
                        ),

                      // ข้อมูลจากรายการที่ยืนยันแล้ว ระหว่างรออ่านสัญญา
                      if (_foundToken == null && _prefill != null && _isLoading)
                        _buildPrefillPreview(_prefill!, l, c),

                      // Found token preview
                      if (_foundToken != null) _buildTokenPreview(l, c),

                      const SizedBox(height: TpixGap.xxl),

                      // โทเค็นที่ยืนยันแล้ว — แตะ + เพิ่มได้ทีเดียว
                      if (idle) ...[
                        _buildVerifiedList(wallet, l, c),
                        const SizedBox(height: TpixGap.lg),
                        _buildHintSection(l, c),
                        const SizedBox(height: TpixGap.xxl),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── การ์ดตัวอย่างโทเค็น ──

  Widget _previewCard({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TpixRadius.lg),
          gradient: LinearGradient(
            colors: [AppTheme.primary.withValues(alpha: 0.08), AppTheme.accent.withValues(alpha: 0.04)],
          ),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
        ),
        child: Column(children: children),
      );

  List<Widget> _identity({
    required String name,
    required String symbol,
    required String? logoUrl,
    required bool verified,
    required AppColors c,
  }) =>
      [
        TokenAvatar(symbol: symbol, logoUrl: logoUrl, size: 56, color: AppTheme.primary),
        const SizedBox(height: TpixGap.md),
        Text(name, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
        Text(symbol, style: const TextStyle(fontSize: 14, color: AppTheme.primary, fontWeight: FontWeight.w600)),
        if (verified) ...[
          const SizedBox(height: TpixGap.sm),
          const VerifiedTokenChip(),
        ],
        const SizedBox(height: TpixGap.md),
      ];

  Widget _buildPrefillPreview(TokenDef def, LocaleProvider l, AppColors c) {
    return _previewCard(children: [
      ..._identity(name: def.name, symbol: def.symbol, logoUrl: def.logoUrl, verified: true, c: c),
      _detailRow(l.t('token.contractAddress'), _short(def.address), c),
      _detailRow(l.t('token.decimalsLabel'), '${def.decimals}', c),
      const SizedBox(height: TpixGap.md),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)),
          const SizedBox(width: TpixGap.sm),
          Flexible(child: Text(l.t('token.checkingContract'), style: TextStyle(fontSize: 12, color: c.textSec))),
        ],
      ),
    ]);
  }

  Widget _buildTokenPreview(LocaleProvider l, AppColors c) {
    final token = _foundToken!;
    final trust = _trust;
    return _previewCard(children: [
      ..._identity(
        name: token.name,
        symbol: token.symbol,
        logoUrl: token.logoUrl,
        verified: trust?.isVerified ?? false,
        c: c,
      ),
      // Details
      _detailRow(l.t('token.contractAddress'), token.shortAddress, c),
      _detailRow(l.t('token.decimalsLabel'), '${token.decimals}', c),
      if (_balance != null)
        _detailRow(l.t('home.balance'), '${_balance!.toStringAsFixed(4)} ${token.symbol}', c),
      if (trust != null) ..._trustNotices(trust, token, l, c),
      const SizedBox(height: TpixGap.lg),
      // Add button
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isAdding ? null : _addToken,
          icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 20),
          label: Text(l.t('token.add'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.md)),
          ),
        ),
      ),
    ]);
  }

  /// คำเตือนตามผลตรวจ: ข้อมูลไม่ตรงรายการ / ไม่ยืนยัน / ชื่อเลียนแบบ
  List<Widget> _trustNotices(TokenTrustResult trust, TokenInfo token, LocaleProvider l, AppColors c) {
    switch (trust.trust) {
      case TokenTrust.verified:
        final listed = trust.listed;
        if (listed == null || trust.mismatches.isEmpty) return const [];
        String row(String label, String fromList, String fromChain) => l
            .t('token.mismatchRow')
            .replaceAll('{field}', label)
            .replaceAll('{listed}', fromList)
            .replaceAll('{chain}', fromChain);
        return [
          const SizedBox(height: TpixGap.md),
          _notice(
            icon: Icons.warning_amber_rounded,
            color: AppTheme.warm,
            title: l.t('token.mismatchTitle'),
            lines: [
              l.t('token.mismatchBody'),
              if (trust.mismatches.contains(TokenMetaField.name))
                row(l.t('token.fieldName'), listed.name, token.name),
              if (trust.mismatches.contains(TokenMetaField.symbol))
                row(l.t('token.fieldSymbol'), listed.symbol, token.symbol),
              if (trust.mismatches.contains(TokenMetaField.decimals))
                row(l.t('token.decimalsLabel'), '${listed.decimals}', '${token.decimals}'),
            ],
            c: c,
          ),
        ];
      case TokenTrust.unverified:
        return [
          const SizedBox(height: TpixGap.md),
          _notice(
            icon: Icons.info_outline,
            color: AppTheme.warm,
            title: l.t('token.unverifiedTitle'),
            lines: [
              l.t('token.unverifiedBody'),
              if (!trust.listAvailable) l.t('token.listUnavailable'),
            ],
            c: c,
          ),
        ];
      case TokenTrust.lookalike:
        return [
          const SizedBox(height: TpixGap.md),
          _notice(
            icon: Icons.gpp_maybe_rounded,
            color: AppTheme.danger,
            title: l.t('token.lookalikeTitle'),
            lines: [
              l.t('token.lookalikeBody'),
              for (final real in trust.lookalikes)
                real.isNative
                    ? l.t('token.lookalikeNative')
                    : l.t('token.lookalikeReal')
                        .replaceAll('{symbol}', real.symbol)
                        .replaceAll('{address}', real.address),
              if (!trust.listAvailable) l.t('token.listUnavailable'),
            ],
            c: c,
          ),
        ];
    }
  }

  Widget _notice({
    required IconData icon,
    required Color color,
    required String title,
    required List<String> lines,
    required AppColors c,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TpixRadius.sm),
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: TpixGap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                for (final line in lines) ...[
                  const SizedBox(height: TpixGap.xs),
                  Text(line, style: TextStyle(fontSize: 12, color: c.textSec, height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, AppColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: c.textMuted)),
          const SizedBox(width: TpixGap.md),
          // จอแคบ/ตัวอักษรใหญ่ → ตัดท้ายแทนล้นจอ
          Expanded(
            child: Text(value, textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.text, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  static String _short(String a) =>
      a.length > 12 ? '${a.substring(0, 6)}...${a.substring(a.length - 4)}' : a;

  // ── รายการโทเค็นที่ยืนยันแล้ว ──

  Widget _buildVerifiedList(WalletProvider wallet, LocaleProvider l, AppColors c) {
    final entries = _pickerEntries(wallet);
    final added = {
      for (final t in wallet.tokens)
        if (t.chainId == TokenListService.chainId) t.contractAddress.toLowerCase(),
    };
    final shown = entries.take(_pickerLimit).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: adaptiveGlassCard(context, borderRadius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified, color: AppTheme.primary, size: 18),
              const SizedBox(width: TpixGap.sm),
              Flexible(
                child: Text(l.t('token.listTitle'), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
              ),
            ],
          ),
          const SizedBox(height: TpixGap.hair),
          Text(l.t('token.listSubtitle'), style: TextStyle(fontSize: 11, color: c.textMuted)),
          const SizedBox(height: TpixGap.sm),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l.t('token.listNoMatch'), style: TextStyle(fontSize: 12, color: c.textMuted)),
            ),
          for (final t in shown) _pickerRow(t, added.contains(t.address.toLowerCase()), l, c),
          if (entries.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l.t('token.listMore')
                    .replaceAll('{n}', '${shown.length}')
                    .replaceAll('{total}', '${entries.length}'),
                style: TextStyle(fontSize: 11, color: c.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pickerRow(TokenDef t, bool isAdded, LocaleProvider l, AppColors c) {
    final busy = _quickAdding == t.address.toLowerCase();
    return InkWell(
      // แตะที่แถว = ดูรายละเอียดก่อนเพิ่ม
      onTap: isAdded || busy
          ? null
          : () {
              _setInput(t.address);
              _search();
            },
      borderRadius: BorderRadius.circular(TpixRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            TokenAvatar(symbol: t.symbol, logoUrl: t.logoUrl, size: 36, color: AppTheme.accent),
            const SizedBox(width: TpixGap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(t.symbol, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
                      ),
                      const SizedBox(width: TpixGap.xs),
                      const TokenTrustIcon(trust: TokenTrust.verified, size: 13),
                    ],
                  ),
                  Text('${t.name} · ${_short(t.address)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: c.textMuted)),
                ],
              ),
            ),
            // ขนาดคงที่ทุกสถานะ (เพิ่ม / กำลังเพิ่ม / เพิ่มแล้ว) — ไม่กระตุก
            SizedBox(
              width: 64,
              height: 36,
              child: Center(
                child: isAdded
                    ? Text(l.t('token.addedShort'), style: TextStyle(fontSize: 11, color: c.textMuted, fontWeight: FontWeight.w600))
                    : busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2))
                        : IconButton(
                            tooltip: l.t('token.add'),
                            onPressed: _quickAdding == null ? () => _quickAdd(t) : null,
                            icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary, size: 24),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHintSection(LocaleProvider l, AppColors c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: adaptiveGlassCard(context, borderRadius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: AppTheme.accent, size: 18),
              const SizedBox(width: TpixGap.sm),
              Text(l.t('token.howTo'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.accent)),
            ],
          ),
          const SizedBox(height: TpixGap.md),
          Text(l.t('token.howToDesc'), style: TextStyle(fontSize: 12, color: c.textSec, height: 1.5)),
        ],
      ),
    );
  }
}

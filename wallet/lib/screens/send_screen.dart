import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/themes/tokens.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../core/themes/widgets/screen_background.dart';
import '../models/contact.dart';
import '../models/token_info.dart';
import '../providers/wallet_provider.dart';
import '../widgets/tx_auth.dart';
import '../services/masternode_service.dart';
import '../services/rpc_client.dart';
import '../services/synth_service.dart';
import '../services/db_service.dart';
import '../services/wallet_service.dart';
import '../utils/units.dart';
import '../widgets/contact_picker.dart';
import '../widgets/qr_scanner_screen.dart';
import '../widgets/tpix_coin_logo.dart';

class SendScreen extends StatefulWidget {
  /// ที่อยู่ปลายทางที่เติมมาให้ล่วงหน้า (เช่น มาจากการสแกน QR ที่หน้าหลัก)
  final String? initialAddress;

  /// โทเค็นที่เลือกไว้ล่วงหน้า (ที่อยู่สัญญา) — null = TPIX
  final String? initialTokenAddress;

  const SendScreen({super.key, this.initialAddress, this.initialTokenAddress});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> with SingleTickerProviderStateMixin {
  final _addressController = TextEditingController();
  final _amountController = TextEditingController();
  bool _isSending = false;
  bool _isSent = false;
  String? _txHash;

  /// กันกดส่งซ้อน "ตั้งแต่แตะปุ่ม" จนจบ — รวมช่วงสแกนนิ้ว/ใส่ PIN/กล่องยืนยัน
  /// (_isSending ตั้งหลังยืนยันแล้วเท่านั้น แตะสองทีระหว่างสแกนนิ้วเคยเปิดสองรอบได้)
  bool _busy = false;

  /// เหรียญที่เลือกส่ง: null = TPIX (native), ไม่ null = ที่อยู่สัญญาโทเค็น (ตัวเล็ก)
  String? _selectedToken;

  /// รายการโปรดไว้ทำทางลัด (โหลดครั้งเดียวตอนเปิดหน้า แล้วรีเฟรชเมื่อมีการบันทึก)
  List<Contact> _favorites = const [];

  /// รายการโปรดที่ตรงกับที่อยู่ที่พิมพ์อยู่ตอนนี้ — ไว้โชว์ชื่อแทนเลข 0x…
  Contact? _matched;

  /// ที่อยู่ผู้รับของธุรกรรมที่ส่งสำเร็จ (ไว้เสนอให้บันทึกชื่อในหน้าสำเร็จ)
  String? _sentTo;

  late AnimationController _successController;

  @override
  void initState() {
    super.initState();
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    // เติมที่อยู่จาก QR ที่สแกนมาจากหน้าหลัก (ถ้ามี)
    final preset = widget.initialAddress;
    if (preset != null && preset.isNotEmpty) {
      _addressController.text = preset;
    }
    _selectedToken = widget.initialTokenAddress?.toLowerCase();

    _addressController.addListener(_onAddressChanged);
    _loadFavorites();
  }

  /// โหลดรายการโปรดขึ้นมาแสดงเป็นทางลัด
  Future<void> _loadFavorites() async {
    final list = await DbService.getContacts(limit: 12);
    if (!mounted) return;
    setState(() {
      _favorites = list;
      _matched = null; // คำนวณใหม่จากลิสต์ชุดใหม่ด้านล่าง
    });
    _onAddressChanged();
  }

  /// ที่อยู่ในช่องเปลี่ยน → หาว่าตรงกับรายการโปรดไหน
  /// ค้นจากลิสต์ในหน่วยความจำ ไม่ยิง DB ทุกตัวอักษรที่พิมพ์
  void _onAddressChanged() {
    final found = _lookupFavorite(_addressController.text);
    if (found?.id == _matched?.id) return;
    if (!mounted) return;
    setState(() => _matched = found);
  }

  Contact? _lookupFavorite(String address) {
    final typed = address.trim().toLowerCase();
    if (typed.isEmpty) return null;
    for (final c in _favorites) {
      if (c.address == typed) return c;
    }
    return null;
  }

  /// เลือกจากรายการโปรด
  Future<void> _pickFavorite() async {
    final picked = await showContactPicker(context);
    if (picked == null || !mounted) return;
    _addressController.text = picked.address;
    SynthService.playTap();
  }

  /// บันทึก/แก้ชื่อของที่อยู่ที่อยู่ในช่องตอนนี้
  Future<void> _saveCurrentAddress() async {
    final address = _addressController.text.trim();
    final l = context.read<LocaleProvider>();
    if (!WalletService.isValidAddress(address)) {
      _showError(l.t('send.invalidAddress'));
      return;
    }
    final saved = await showSaveContactDialog(
      context,
      address: address,
      existing: _matched,
    );
    if (saved == null || !mounted) return;
    await _loadFavorites();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.t('contacts.saved').replaceAll('{name}', saved.name)),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _addressController.removeListener(_onAddressChanged);
    _addressController.dispose();
    _amountController.dispose();
    _successController.dispose();
    super.dispose();
  }

  void _scanQR() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QRScannerScreen(
          titleKey: 'send.scanQR',
          onScanned: (value) {
            final parsed = WalletService.parseAddressFromQR(value);
            if (parsed != null) {
              _addressController.text = parsed;
            } else {
              _showError(context.read<LocaleProvider>().t('send.invalidAddress'));
            }
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  // ================================================================
  // เหรียญที่เลือก
  // ================================================================

  /// โทเค็นบน TPIX Chain ที่ส่งได้ (สัญญายังอยู่) — ตัวที่สัญญาหายไปแล้วไม่ให้เลือก
  List<TokenInfo> _sendableTokens(WalletProvider wallet) =>
      wallet.activeTokens.where((t) => t.chainId == 4289).toList();

  /// โทเค็นที่เลือกอยู่ (null = TPIX หรือโทเค็นที่เลือกไว้หายไปแล้ว)
  TokenInfo? _selectedTokenInfo(WalletProvider wallet) {
    final sel = _selectedToken;
    if (sel == null) return null;
    for (final t in _sendableTokens(wallet)) {
      if (t.contractAddress.toLowerCase() == sel) return t;
    }
    return null;
  }

  String _symbolOf(TokenInfo? token) => token?.symbol ?? 'TPIX';
  int _decimalsOf(TokenInfo? token) => token?.decimals ?? 18;

  /// ยอดหน่วยย่อยของเหรียญที่เลือก — null = ยังไม่รู้ยอด
  BigInt? _rawBalanceOf(WalletProvider wallet, TokenInfo? token) => token == null
      ? wallet.balanceWei
      : wallet.getTokenBalanceRaw(token.contractAddress);

  void _selectAsset(String? tokenAddress) {
    if (_selectedToken == tokenAddress) return;
    setState(() {
      _selectedToken = tokenAddress;
      // ทศนิยมคนละแบบ — จำนวนเดิมอาจผิดความหมาย ล้างทิ้งให้ใส่ใหม่
      _amountController.clear();
    });
    SynthService.playTap();
  }

  /// แปลง error เป็นข้อความที่ผู้ใช้อ่านเข้าใจ — ห้ามโชว์ "Exception: ..." ดิบ
  String _friendlyError(Object e, LocaleProvider l) {
    if (e is RpcUnavailableException) return l.t('send.errNetwork');
    if (e is WalletChangedException) return l.t('send.errWalletChanged');
    if (e is InsufficientGasException) return l.t('send.errGas');
    if (e is RpcException) {
      final m = e.message.toLowerCase();
      if (m.contains('insufficient funds') || m.contains('exceeds balance')) {
        return l.t('send.insufficientBalance');
      }
      // ข้อความจากโหนด (เช่น execution reverted) — ไม่มี URL/ข้อมูลลับ แสดงต่อท้ายได้
      final short = e.message.length > 120 ? '${e.message.substring(0, 120)}…' : e.message;
      return '${l.t('send.errFailed')}: $short';
    }
    return l.t('send.errFailed');
  }

  Future<void> _send() async {
    if (_busy || _isSending) return; // double-tap guard (ตั้งแต่แตะครั้งแรก)
    _busy = true;
    try {
      await _sendFlow();
    } finally {
      _busy = false;
    }
  }

  Future<void> _sendFlow() async {
    final address = _addressController.text.trim();
    final l = context.read<LocaleProvider>();
    final wallet = context.read<WalletProvider>();

    if (!WalletService.isValidAddress(address)) {
      _showError(l.t('send.invalidAddress'));
      return;
    }

    // ปลายทางเป็นสัญญาสเตคมาสเตอร์โหนด = โอนเข้าตรงๆ ไม่ใช่การสเตค
    // TPIX จะถูก receive() นับเป็นเงินบริจาคเข้ากองรางวัล ขอคืนไม่ได้ (โทเค็นก็ติดถาวร)
    // → หยุดตั้งแต่ก่อนถาม PIN แล้วชี้ไปหน้ามาสเตอร์โหนด
    if (await MasterNodeService.isRegistryRecipient(address)) {
      if (mounted) _showError(l.t('send.errRegistry'));
      return;
    }
    if (!mounted) return;

    // เหรียญที่เลือกต้องยังอยู่ (เช่นสลับกระเป๋าแล้วกระเป๋าใหม่ไม่มีโทเค็นนี้)
    final token = _selectedTokenInfo(wallet);
    // → กลับไปเลือก TPIX และล้างจำนวน ให้ผู้ใช้ตรวจแล้วกดใหม่เอง (ไม่ส่งเหรียญที่ไม่ได้ตั้งใจ)
    if (_selectedToken != null && token == null) {
      setState(() {
        _selectedToken = null;
        _amountController.clear();
      });
      return;
    }
    final symbol = _symbolOf(token);
    final decimals = _decimalsOf(token);

    final parsed = Units.parse(_amountController.text, decimals);
    if (!parsed.isOk) {
      _showError(parsed.error == AmountError.tooManyDecimals
          ? l.t('send.tooManyDecimals')
              .replaceAll('{symbol}', symbol)
              .replaceAll('{n}', '$decimals')
          : l.t('send.invalidAmount'));
      return;
    }
    final amount = parsed.value!;

    // เทียบยอดแบบ BigInt — ยังไม่รู้ยอดก็ไม่เดา
    final available = _rawBalanceOf(wallet, token);
    if (available == null) {
      _showError(l.t('send.balanceUnknown'));
      return;
    }
    if (amount > available) {
      _showError(l.t('send.insufficientBalance'));
      return;
    }

    // จำกระเป๋าที่ผู้ใช้เห็นตอนนี้ — ถ้าถูกสลับระหว่างยืนยัน ต้องไม่ส่งจากใบอื่น
    final fromAddress = wallet.address;
    final fromName = wallet.activeWallet?.name;
    if (fromAddress == null) return;

    // Authentication required before send — สแกนนิ้วไม่ผ่าน/ไม่ได้เปิดไว้ → ใส่ PIN
    final authenticated = await authorizeTransaction(
      context,
      reason: token == null
          ? l.t('send.authRequired')
          : l.t('send.authRequiredToken').replaceAll('{symbol}', symbol),
    );
    if (!authenticated || !mounted) return;

    // Show confirmation dialog
    final confirmed = await _showConfirmation(
      address: address,
      amountText: Units.format(amount, decimals),
      symbol: symbol,
      fromAddress: fromAddress,
      fromName: fromName,
      l: l,
    );
    if (confirmed != true || !mounted) return;

    if (wallet.address?.toLowerCase() != fromAddress.toLowerCase()) {
      _showError(l.t('send.errWalletChanged'));
      return;
    }

    setState(() => _isSending = true);
    SynthService.playSend();

    try {
      final txHash = token == null
          ? await wallet.sendTPIX(address, amount, expectedFrom: fromAddress)
          : await wallet.sendToken(token, address, amount, expectedFrom: fromAddress);
      // นับว่ารายการโปรดนี้ถูกใช้ (ไม่สร้างแถวใหม่ถ้ายังไม่เคยบันทึกชื่อ)
      // ล้มก็ไม่เป็นไร ห้ามให้สถิติมาทำให้การส่งที่สำเร็จแล้วดูเหมือนพัง
      unawaited(DbService.markContactUsed(address).catchError((_) {}));
      if (!mounted) return;
      _sentTo = address;
      setState(() {
        _isSent = true;
        _txHash = txHash;
        _isSending = false;
      });
      _successController.forward();
      SynthService.playSendSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      SynthService.playError();
      _showError(_friendlyError(e, l));
    }
  }

  Future<bool?> _showConfirmation({
    required String address,
    required String amountText,
    required String symbol,
    required String fromAddress,
    required String? fromName,
    required LocaleProvider l,
  }) {
    final c = AppColors.of(context);
    String short(String a) => '${a.substring(0, 8)}...${a.substring(a.length - 6)}';
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(TpixRadius.lg)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: c.textMuted.withValues(alpha: 0.3),
                  ),
                ),
              ),
              const SizedBox(height: TpixGap.xl),
              Text(l.t('send.confirmTitle'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
              const SizedBox(height: TpixGap.xl),
              // กระเป๋าต้นทาง — ผู้ใช้ที่มีหลายกระเป๋าต้องเห็นว่ากำลังส่งจากใบไหน
              _confirmRow(
                l.t('send.from'),
                fromName != null && fromName.isNotEmpty
                    ? '$fromName · ${short(fromAddress)}'
                    : short(fromAddress),
              ),
              // ผู้รับ — ถ้าเคยบันทึกชื่อไว้ให้โชว์ชื่อด้วย
              // คนตรวจ "ส่งให้น้องเอ" ได้แม่นกว่าตรวจเลขย่อ 0x1234…abcdef
              if (_lookupFavorite(address) case final match?) ...[
                _confirmRow(l.t('send.confirmTo'), match.name,
                    valueColor: AppTheme.success),
                _confirmRow(l.t('send.confirmAddress'), short(address)),
              ] else
                _confirmRow(l.t('send.confirmTo'), short(address)),
              // Amount — ตัวเลขเต็มที่จะส่งจริง (ไม่ปัด)
              _confirmRow(l.t('send.confirmAmount'), '$amountText $symbol'),
              _confirmRow(l.t('send.network'), 'TPIX Chain (4289)'),
              // Gas
              _confirmRow(l.t('send.gasFee').replaceAll(': ', ''), l.t('send.gasFreeVal'), valueColor: AppTheme.success),
              const SizedBox(height: TpixGap.xxl),
              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetCtx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: c.glassBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.sm)),
                      ),
                      child: Text(l.t('send.cancel'), style: TextStyle(color: c.textSec)),
                    ),
                  ),
                  const SizedBox(width: TpixGap.md),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(sheetCtx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.sm)),
                      ),
                      child: Text(
                        symbol == 'TPIX'
                            ? l.t('send.confirmButton')
                            : l.t('send.confirmButtonToken').replaceAll('{symbol}', symbol),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TpixGap.sm),
            ],
          ),
        ),
      ),
    );
  }

  /// บันทึกชื่อให้ผู้รับของธุรกรรมที่เพิ่งส่งสำเร็จ
  Future<void> _saveSentRecipient() async {
    final address = _sentTo;
    if (address == null) return;
    final saved = await showSaveContactDialog(context, address: address);
    if (saved == null || !mounted) return;
    await DbService.markContactUsed(address);
    await _loadFavorites();
  }

  /// ชิปทางลัดหนึ่งอัน — กดแล้วเติมที่อยู่ลงช่องทันที
  Widget _buildFavoriteChip(Contact contact, AppColors c) {
    final selected = _matched?.id == contact.id;
    return SizedBox(
      width: 62,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(TpixRadius.md),
          onTap: () {
            _addressController.text = contact.address;
            SynthService.playTap();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppTheme.success : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ContactAvatar(contact: contact, size: 42),
              ),
              const SizedBox(height: TpixGap.xs),
              Text(
                contact.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? AppTheme.success : c.textSec,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _confirmRow(String label, String value, {Color? valueColor}) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: c.textMuted)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 14, color: valueColor ?? c.text, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TpixScreenBackground(
        child: SafeArea(
          child: Builder(
            builder: (context) {
              final l = context.watch<LocaleProvider>();
              return _isSent ? _buildSuccess(l) : _buildForm(l);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildForm(LocaleProvider l) {
    final c = AppColors.of(context);
    final wallet = context.watch<WalletProvider>();
    final tokens = _sendableTokens(wallet);
    final token = _selectedTokenInfo(wallet);
    final symbol = _symbolOf(token);
    // เลื่อนได้เสมอ แต่ถ้าที่ว่างพอ Spacer ยังดันปุ่มส่งไปติดขอบล่างเหมือนเดิม
    return LayoutBuilder(
      builder: (_, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
          child: IntrinsicHeight(
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
              // Expanded — หัวข้อ+คำอธิบายยาวหรือเครื่องตั้งตัวอักษรใหญ่
              // ต้องตัดเป็น … ไม่ใช่ดันแถวจนล้นขอบขวา
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        token == null
                            ? l.t('send.title')
                            : l.t('send.titleToken').replaceAll('{symbol}', symbol),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
                    Text(l.t('send.subtitle'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textMuted)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: TpixGap.xxxl),

          // ── ผู้รับ + ทางลัดรายการโปรด ──
          Row(
            children: [
              // Expanded/Flexible แทน Spacer — Spacer ยอมหดเหลือ 0 ก็จริง
              // แต่ตัวหนังสือสองข้างยังกางเต็มที่จนล้นขอบขวาได้
              Expanded(
                child: Text(l.t('send.toAddress'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: c.textSec)),
              ),
              Flexible(
                child: TextButton.icon(
                  onPressed: _pickFavorite,
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(Icons.star_rounded, size: 18, color: c.brandWarm),
                  label: Text(
                    l.t('contacts.title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        color: c.brandWarm,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: TpixGap.xs),
          TextField(
            controller: _addressController,
            style: TextStyle(color: c.text, fontSize: 14, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: '0x...',
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
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ดาว = บันทึกที่อยู่นี้ไว้ในรายการโปรด (ทึบ = บันทึกแล้ว กดเพื่อแก้ชื่อ)
                  IconButton(
                    tooltip: l.t(_matched == null
                        ? 'contacts.saveTitle'
                        : 'contacts.editTitle'),
                    icon: Icon(
                      _matched == null
                          ? Icons.star_border_rounded
                          : Icons.star_rounded,
                      color: _matched == null ? c.textMuted : c.brandWarm,
                    ),
                    onPressed: _saveCurrentAddress,
                  ),
                  IconButton(
                    tooltip: l.t('send.scanQR'),
                    icon: const Icon(Icons.qr_code_scanner,
                        color: AppTheme.primary),
                    onPressed: _scanQR,
                  ),
                  const SizedBox(width: TpixGap.xs),
                ],
              ),
            ),
          ),

          // ชื่อของที่อยู่นี้ — ให้ผู้ใช้มั่นใจว่ากำลังส่งให้ใคร ไม่ใช่แค่เลข 0x…
          if (_matched != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Row(
                children: [
                  ContactAvatar(contact: _matched!, size: 22),
                  const SizedBox(width: TpixGap.sm),
                  Flexible(
                    child: Text(
                      _matched!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.success),
                    ),
                  ),
                ],
              ),
            ),

          // ── แถวชิปรายการโปรด (ทางลัดกดทีเดียวติด) ──
          if (_favorites.isNotEmpty) ...[
            const SizedBox(height: TpixGap.lg),
            SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                itemCount: _favorites.length,
                separatorBuilder: (_, __) => const SizedBox(width: TpixGap.md),
                itemBuilder: (_, i) => _buildFavoriteChip(_favorites[i], c),
              ),
            ),
          ],

          const SizedBox(height: TpixGap.xxl),

          // ── เลือกเหรียญ (มีให้เลือกเมื่อกระเป๋ามีโทเค็นบน TPIX Chain เช่น USDT) ──
          // ใช้ Wrap ไม่ใช่ ListView — จำนวนเหรียญน้อย และไม่ไปปนกับแถวชิปรายการโปรด
          if (tokens.isNotEmpty) ...[
            Text(l.t('send.asset'), style: TextStyle(fontSize: 14, color: c.textSec)),
            const SizedBox(height: TpixGap.sm),
            Wrap(
              spacing: TpixGap.sm,
              runSpacing: TpixGap.sm,
              children: [
                _assetChip(
                  label: 'TPIX',
                  logo: const TpixCoinLogo(size: 20),
                  selected: token == null,
                  onTap: () => _selectAsset(null),
                  c: c,
                ),
                for (final t in tokens)
                  _assetChip(
                    label: t.symbol,
                    logo: TokenAvatar(
                      symbol: t.symbol,
                      logoUrl: wallet.tokenLogo(t),
                      size: 20,
                      color: AppTheme.accent,
                    ),
                    selected: token?.contractAddress.toLowerCase() ==
                        t.contractAddress.toLowerCase(),
                    onTap: () => _selectAsset(t.contractAddress.toLowerCase()),
                    c: c,
                  ),
              ],
            ),
            const SizedBox(height: TpixGap.xl),
          ],

          // Amount
          Text(l.t('send.amount'), style: TextStyle(fontSize: 14, color: c.textSec)),
          const SizedBox(height: TpixGap.sm),
          TextField(
            controller: _amountController,
            // ทศนิยมต้องพิมพ์ได้ทุกเครื่อง (TextInputType.number บาง keyboard ไม่มีจุด)
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: TextStyle(color: c.text, fontSize: 24, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: TextStyle(color: c.textMuted.withValues(alpha: 0.5)),
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
              suffixText: symbol,
              suffixStyle: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600),
            ),
          ),

          const SizedBox(height: TpixGap.md),

          // Balance hint — MAX ใส่ยอดเต็มจริงทุกหลัก (ของเดิมปัด 4 ตำแหน่ง ซึ่งปัดขึ้นจนเกินยอดได้)
          Builder(builder: (_) {
            final raw = _rawBalanceOf(wallet, token);
            final decimals = _decimalsOf(token);
            final shown = raw == null
                ? '—'
                : token == null
                    ? wallet.formattedBalance
                    : Units.toDouble(raw, decimals).toStringAsFixed(4);
            return GestureDetector(
              onTap: raw == null || raw == BigInt.zero
                  ? null
                  : () => _amountController.text = Units.format(raw, decimals),
              child: Row(
                children: [
                  // Flexible + ellipsis — ยอดเงินยาวๆ หรือเครื่องที่ตั้งตัวอักษรใหญ่
                  // ต้องไม่ดันแถวจนล้นขอบขวา (เห็นเป็นแถบเหลืองดำ)
                  Flexible(
                    child: Text(l.t('send.balance'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textMuted)),
                  ),
                  Flexible(
                    child: Text('$shown $symbol',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: TpixGap.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: AppTheme.primary.withValues(alpha: 0.1),
                    ),
                    child: const Text('MAX', style: TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: TpixGap.lg),

          // Fee info
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TpixRadius.sm),
              color: AppTheme.success.withValues(alpha: 0.06),
              border: Border.all(color: AppTheme.success.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_gas_station, color: AppTheme.success, size: 18),
                const SizedBox(width: TpixGap.sm),
                Flexible(
                  child: Text(l.t('send.gasFee'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.textSec)),
                ),
                Flexible(
                  child: Text(l.t('send.gasFreeVal'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppTheme.success, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Send button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSending ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.md)),
              ),
              child: _isSending
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        const SizedBox(width: TpixGap.md),
                        Text(l.t('send.sending'), style: const TextStyle(fontSize: 16, color: Colors.white)),
                      ],
                    )
                  : Text(
                      token == null
                          ? l.t('send.button')
                          : l.t('send.buttonToken').replaceAll('{symbol}', symbol),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ชิปเลือกเหรียญหนึ่งอัน
  Widget _assetChip({
    required String label,
    required Widget logo,
    required bool selected,
    required VoidCallback onTap,
    required AppColors c,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(TpixRadius.md),
        onTap: _isSending ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TpixRadius.md),
            color: selected ? AppTheme.primary.withValues(alpha: 0.15) : c.glassColor,
            border: Border.all(
              color: selected ? AppTheme.primary : c.glassBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              logo,
              const SizedBox(width: TpixGap.sm),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppTheme.primary : c.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(LocaleProvider l) {
    final c = AppColors.of(context);
    return Center(
      child: AnimatedBuilder(
        animation: _successController,
        builder: (_, __) {
          final scale = 0.5 + (_successController.value * 0.5);
          final opacity = _successController.value.clamp(0.0, 1.0);
          return Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Success circle with checkmark
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AppTheme.success, Color(0xFF00E676)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.success.withValues(alpha: 0.4),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 60),
                  ),

                  const SizedBox(height: TpixGap.xxxl),

                  Text(l.t('send.success'), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: c.text)),
                  const SizedBox(height: TpixGap.sm),
                  Text(l.t('send.confirmed'), style: const TextStyle(fontSize: 16, color: AppTheme.success)),

                  const SizedBox(height: TpixGap.xxl),

                  if (_txHash != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: adaptiveGlassCard(context, borderRadius: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tag, size: 14, color: c.textMuted),
                          const SizedBox(width: TpixGap.sm),
                          Text(
                            '${_txHash!.substring(0, 10)}...${_txHash!.substring(_txHash!.length - 8)}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),

                  // เพิ่งส่งให้คนที่ยังไม่มีชื่อ → เสนอบันทึกทันที
                  // จังหวะนี้คือตอนที่ผู้ใช้ยังจำได้ว่าที่อยู่นี้คือใคร
                  if (_sentTo != null && _lookupFavorite(_sentTo!) == null) ...[
                    const SizedBox(height: TpixGap.xxl),
                    OutlinedButton.icon(
                      onPressed: _saveSentRecipient,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        side: BorderSide(color: c.brandWarm.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(TpixRadius.md)),
                      ),
                      icon: Icon(Icons.star_border_rounded,
                          size: 20, color: c.brandWarm),
                      label: Text(
                        l.t('contacts.saveRecipient'),
                        style: TextStyle(
                            fontSize: 14,
                            color: c.brandWarm,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],

                  const SizedBox(height: TpixGap.huge),

                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.md)),
                    ),
                    child: Text(l.t('send.goBack'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

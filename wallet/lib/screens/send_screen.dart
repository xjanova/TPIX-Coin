import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show NumberFormat;
import '../core/themes/tokens.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../core/themes/theme_bundle.dart';
import '../core/themes/widgets/screen_background.dart';
import '../models/chain_config.dart';
import '../models/contact.dart';
import '../models/token_info.dart';
import '../providers/wallet_provider.dart';
import '../widgets/tx_auth.dart';
import '../services/masternode_service.dart';
import '../services/rpc_client.dart';
import '../services/synth_service.dart';
import '../services/db_service.dart';
import '../services/wallet_service.dart';
import '../utils/balance_watch.dart';
import '../utils/eip681.dart';
import '../utils/units.dart';
import '../widgets/contact_picker.dart';
import '../widgets/obsidian/obsidian.dart';
import '../widgets/obsidian/obsidian_glyph.dart';
import '../widgets/obsidian/obsidian_scrim.dart';
import '../widgets/obsidian/obsidian_top_bar.dart';
import '../widgets/obsidian/pin_pad.dart';
import '../widgets/qr_scanner_screen.dart';
import '../widgets/tpix_coin_logo.dart';
import 'tx_history_screen.dart';

// หน้าส่งธีม Obsidian (ใช้ตรรกะการส่งเดิมของหน้านี้ร่วมกัน)
part 'send_obsidian.dart';

class SendScreen extends StatefulWidget {
  /// ที่อยู่ปลายทางที่เติมมาให้ล่วงหน้า (เช่น มาจากการสแกน QR ที่หน้าหลัก)
  final String? initialAddress;

  /// โทเค็นที่เลือกไว้ล่วงหน้า (ที่อยู่สัญญา) — null = TPIX
  final String? initialTokenAddress;

  /// คำขอชำระเงิน EIP-681 (QR ร้าน / ลิงก์ ethereum: จากแอปอื่น) — เติมผู้รับ + ยอดเป๊ะให้
  /// แล้วล็อกช่องยอดไว้ ผู้ใช้ยังต้องยืนยันตัวตน + กดยืนยันตามปกติทุกครั้ง (ไม่ส่งเอง)
  final PaymentRequest? initialRequest;

  const SendScreen({super.key, this.initialAddress, this.initialTokenAddress, this.initialRequest});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

/// เครือข่ายของคำขอชำระเงินใช้กับหน้าส่งนี้ได้ไหม — หน้าส่งโอนได้เฉพาะบน TPIX Chain (4289)
/// null = ใช้ได้ (ระบุ 4289 หรือไม่ระบุ chain) · ไม่ null = ข้อความเตือนพร้อมแสดง (ห้ามเติมอะไรลงฟอร์ม)
String? paymentRequestChainError(PaymentRequest r, LocaleProvider l) {
  final id = r.chainId;
  if (id == null || id == ChainConfig.tpix.chainId) return null;
  for (final c in ChainConfig.all) {
    if (c.chainId == id) return l.t('pay.wrongChain').replaceAll('{chain}', '${c.name} ($id)');
  }
  return l.t('pay.unsupportedChain').replaceAll('{id}', '$id');
}

/// ข้อความเมื่ออ่านคำขอชำระเงินไม่ผ่าน (ไม่โชว์ชื่อ enum ดิบให้ผู้ใช้เห็น)
String paymentRequestParseError(Eip681Error e, LocaleProvider l) => switch (e) {
      Eip681Error.badAmount || Eip681Error.conflictingAmount => l.t('pay.badAmount'),
      Eip681Error.badChainId => l.t('pay.badChain'),
      _ => l.t('pay.invalidRequest'),
    };

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

  /// จำนวน + สัญลักษณ์ของธุรกรรมที่ส่งสำเร็จ (หน้าสำเร็จธีม Obsidian โชว์ตัวเลขจริงที่ส่ง)
  String? _sentAmountText;
  String? _sentSymbol;

  bool get _isObsidian => TpixThemeExtension.of(context).themeId == ThemeId.obsidian;

  // ── คำขอชำระเงินจากร้าน (EIP-681) ──
  // ร้านจับคู่การชำระด้วยยอดเป๊ะทุก wei → ช่องยอดล็อกไว้ ผู้ใช้กด "แก้ยอดเอง" ได้ถ้าตั้งใจจริง
  /// ผู้รับตามคำขอ — ที่อยู่ในช่องเปลี่ยนไปจากนี้ = เลิกใช้คำขอนี้ (ล้างแถบ/ปลดล็อกเอง)
  String? _reqRecipient;

  /// ยอดหน่วยย่อยตามคำขอ (> 0)
  BigInt? _reqAmount;

  /// เหรียญตามคำขอ: null = TPIX, ไม่ null = สัญญาโทเค็น (ตัวเล็ก)
  String? _reqToken;

  /// ล็อกช่องยอดอยู่ไหม (false หลังผู้ใช้กด "แก้ยอดเอง")
  bool _reqLocked = false;

  bool get _hasRequest => _reqAmount != null;

  /// ยอดของร้านล็อกอยู่ตอนนี้ (ช่องยอด/ปุ่ม % /MAX/เปลี่ยนเหรียญ ใช้ไม่ได้)
  bool get _amountLocked => _hasRequest && _reqLocked;

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

    // คำขอชำระเงินจากหน้าหลัก/ลิงก์ — รอเฟรมแรกเพื่อให้อ่านรายการโทเค็นและโชว์คำเตือนได้
    final request = widget.initialRequest;
    if (request != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyPaymentRequest(request);
      });
    }
  }

  /// เติมฟอร์มจากคำขอชำระเงิน — ไม่ผ่านด่านใดด่านหนึ่ง = เตือนแล้ว "ไม่เติมอะไรเลย"
  /// (เติมครึ่ง ๆ เช่นได้ผู้รับแต่ยอดผิดเหรียญ อันตรายกว่าฟอร์มว่าง)
  void _applyPaymentRequest(PaymentRequest r) {
    if (_isSending) return;
    final l = context.read<LocaleProvider>();
    final wallet = context.read<WalletProvider>();

    final chainError = paymentRequestChainError(r, l);
    if (chainError != null) {
      _showError(chainError);
      return;
    }

    // โทเค็น: ต้องเป็นโทเค็นบน TPIX Chain ที่กระเป๋ารู้จักอยู่แล้ว (รู้ทศนิยมแน่นอน)
    TokenInfo? token;
    final tokenAddress = r.tokenAddress?.toLowerCase();
    if (tokenAddress != null) {
      for (final t in _sendableTokens(wallet)) {
        if (t.contractAddress.toLowerCase() == tokenAddress) token = t;
      }
      if (token == null) {
        _showError(l.t('pay.unknownToken'));
        return;
      }
    }
    final decimals = _decimalsOf(token);
    final amount = r.amountIn(decimals);
    if (r.hasAmount && amount == null) {
      _showError(l.t('pay.badAmount'));
      return;
    }

    // URI บอก 4289 แต่กระเป๋ากำลังดูเชนอื่น → สลับให้ตรงกับที่ร้านขอ (หน้าส่งโอนบน 4289 อยู่แล้ว)
    if (r.chainId == ChainConfig.tpix.chainId && wallet.activeChainId != ChainConfig.tpix.chainId) {
      unawaited(wallet.switchChain(ChainConfig.tpix.chainId).catchError((_) {}));
    }

    final hasAmount = amount != null && amount > BigInt.zero;
    // ตั้งค่าคำขอก่อนเปลี่ยนช่องผู้รับ — ตัวฟังช่องผู้รับจะได้ไม่ล้างคำขอที่เพิ่งตั้ง
    _reqRecipient = hasAmount ? r.recipient : null;
    _reqAmount = hasAmount ? amount : null;
    _reqToken = hasAmount ? tokenAddress : null;
    _reqLocked = hasAmount;
    _selectedToken = tokenAddress;
    _addressController.text = r.recipient;
    // ยอดเต็มทุกหลัก (สูงสุด 18 ตำแหน่ง) — ห้ามปัด ร้านจับคู่ด้วยยอดเป๊ะ
    if (hasAmount) {
      _amountController.text = Units.format(amount, decimals);
    } else {
      _amountController.clear();
    }
    setState(() {});
    SynthService.playTap();
  }

  /// ล้างคำขอชำระเงิน (ผู้ใช้เปลี่ยนผู้รับไปจากที่ร้านขอ)
  void _clearPaymentRequest() {
    _reqRecipient = null;
    _reqAmount = null;
    _reqToken = null;
    _reqLocked = false;
  }

  /// "แก้ยอดเอง" ↔ "ใช้ยอดของร้าน"
  void _toggleRequestLock() {
    final amount = _reqAmount;
    if (amount == null || _isSending) return;
    if (_reqLocked) {
      _reqLocked = false;
    } else {
      // คืนยอดและเหรียญตามคำขอ แล้วล็อกกลับ
      _selectedToken = _reqToken;
      final token = _selectedTokenInfo(context.read<WalletProvider>());
      _amountController.text = Units.format(amount, _decimalsOf(token));
      _reqLocked = true;
    }
    setState(() {});
    SynthService.playTap();
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
    // ผู้รับไม่ใช่คนเดียวกับในคำขอชำระเงินแล้ว → คำขอนั้นไม่เกี่ยวแล้ว ปลดล็อก/ซ่อนแถบ
    final req = _reqRecipient;
    if (req != null && _addressController.text.trim().toLowerCase() != req.toLowerCase()) {
      if (mounted) setState(_clearPaymentRequest);
    }
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
            Navigator.pop(context);
            _handleScanned(value);
          },
        ),
      ),
    );
  }

  /// QR ที่สแกน/วางได้ — คำขอชำระเงิน (ethereum:…?value=) เติมผู้รับ+ยอด, ที่อยู่ล้วนเติมผู้รับอย่างเดียว
  void _handleScanned(String value) {
    if (!mounted) return;
    final l = context.read<LocaleProvider>();
    final res = Eip681.parse(value);
    if (res.request case final r?) {
      _applyPaymentRequest(r);
      return;
    }
    if (res.error != Eip681Error.notEip681) {
      _showError(paymentRequestParseError(res.error!, l));
      return;
    }
    final parsed = WalletService.parseAddressFromQR(value);
    if (parsed != null) {
      _addressController.text = parsed;
    } else {
      _showError(l.t('send.invalidAddress'));
    }
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
    if (_amountLocked) return; // ยอดของร้านล็อกอยู่ — เปลี่ยนเหรียญไม่ได้จนกว่าจะกด "แก้ยอดเอง"
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

    // ยอดของร้านล็อกอยู่ → ต้องตรงคำขอทุกหลัก ทั้งผู้รับ เหรียญ และยอด (กันหลุดจากทางอื่นที่แก้ช่องได้)
    if (_amountLocked &&
        (address.toLowerCase() != _reqRecipient?.toLowerCase() ||
            _selectedToken != _reqToken ||
            amount != _reqAmount)) {
      _showError(l.t('pay.mismatch'));
      return;
    }

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
    final amountText = Units.format(amount, decimals);
    final authenticated = await authorizeTransaction(
      context,
      reason: token == null
          ? l.t('send.authRequired')
          : l.t('send.authRequiredToken').replaceAll('{symbol}', symbol),
      // ป้ายสรุปบนหน้า PIN ธีม Obsidian (ธีมอื่นไม่ใช้)
      summary: _authSummary(address, amountText, symbol, token, l),
    );
    if (!authenticated || !mounted) return;

    // Show confirmation dialog
    final confirmed = await _showConfirmation(
      address: address,
      amountText: amountText,
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
      _sentAmountText = amountText;
      _sentSymbol = symbol;
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
    if (_isObsidian) {
      return _obsConfirm(
        address: address,
        amountText: amountText,
        symbol: symbol,
        fromAddress: fromAddress,
        fromName: fromName,
        l: l,
      );
    }
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

  /// แถบบอกว่ายอดมาจากคำขอชำระเงินของร้าน — โชว์ยอดเต็มทุกหลัก + ปุ่ม "แก้ยอดเอง"/"ใช้ยอดของร้าน"
  /// [obsidian] เลือกชุดสีตามธีม (ตรรกะเดียวกันทั้งสองธีม)
  Widget _buildRequestNote(LocaleProvider l, WalletProvider wallet, {required bool obsidian}) {
    final amount = _reqAmount;
    if (amount == null) return const SizedBox.shrink();
    TokenInfo? token;
    for (final t in _sendableTokens(wallet)) {
      if (t.contractAddress.toLowerCase() == _reqToken) token = t;
    }
    final locked = _reqLocked;
    final c = obsidian ? null : AppColors.of(context);
    final accent = locked
        ? (obsidian ? ObsidianColors.cyan : AppTheme.primary)
        : (obsidian ? ObsidianColors.warning : AppTheme.warm);
    final textColor = obsidian ? ObsidianColors.text : c!.text;
    final secColor = obsidian ? ObsidianColors.textSec : c!.textSec;
    final amountText = '${groupDigits(Units.format(amount, _decimalsOf(token)))} ${_symbolOf(token)}';

    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(TpixRadius.md),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded, size: 16, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l.t('pay.requestTitle'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: accent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // ยอดเต็มทุกหลัก ตัดบรรทัดได้ (ไม่ย่อด้วย … — ผู้ใช้ต้องเทียบกับหน้าร้านได้ครบ)
            SelectableText(
              amountText,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 6),
            Text(
              l.t(locked ? 'pay.requestLocked' : 'pay.requestUnlocked'),
              style: TextStyle(fontSize: 12, height: 1.4, color: secColor),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _isSending ? null : _toggleRequestLock,
                icon: Icon(locked ? Icons.edit_rounded : Icons.undo_rounded, size: 16, color: accent),
                label: Text(
                  l.t(locked ? 'pay.unlock' : 'pay.restore'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accent),
                ),
              ),
            ),
          ],
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
    // ธีม Obsidian มีเลย์เอาต์ของตัวเอง (send_obsidian.dart) — ธีมอื่นใช้ของเดิมด้านล่าง
    if (_isObsidian) {
      final l = context.watch<LocaleProvider>();
      return _isSent ? _buildObsidianSuccess(l) : _buildObsidianForm(l);
    }
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
            // ยอดจากคำขอชำระเงินของร้าน — ล็อกไว้จนกว่าผู้ใช้กด "แก้ยอดเอง"
            readOnly: _amountLocked,
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
              onTap: raw == null || raw == BigInt.zero || _amountLocked
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

          if (_hasRequest) ...[
            const SizedBox(height: TpixGap.md),
            _buildRequestNote(l, wallet, obsidian: false),
          ],

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

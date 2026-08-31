import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../core/themes/widgets/screen_background.dart';
import '../models/contact.dart';
import '../providers/wallet_provider.dart';
import '../services/biometric_service.dart';
import '../services/synth_service.dart';
import '../services/db_service.dart';
import '../services/wallet_service.dart';
import '../widgets/contact_picker.dart';
import '../widgets/qr_scanner_screen.dart';

class SendScreen extends StatefulWidget {
  /// ที่อยู่ปลายทางที่เติมมาให้ล่วงหน้า (เช่น มาจากการสแกน QR ที่หน้าหลัก)
  final String? initialAddress;

  const SendScreen({super.key, this.initialAddress});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> with SingleTickerProviderStateMixin {
  final _addressController = TextEditingController();
  final _amountController = TextEditingController();
  bool _isSending = false;
  bool _isSent = false;
  String? _txHash;

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

  void _send() async {
    if (_isSending) return; // double-tap guard
    final address = _addressController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());

    final l = context.read<LocaleProvider>();
    if (!WalletService.isValidAddress(address)) {
      _showError(l.t('send.invalidAddress'));
      return;
    }
    if (amount == null || amount <= 0) {
      _showError(l.t('send.invalidAmount'));
      return;
    }

    // Balance check
    final wallet = context.read<WalletProvider>();
    if (amount > wallet.balance) {
      _showError(l.t('send.insufficientBalance'));
      return;
    }

    // Authentication required before send
    final bioService = BiometricService();
    bool authenticated = false;
    if (await bioService.isEnabled() && await bioService.isDeviceSupported()) {
      authenticated = await bioService.authenticate(l.t('send.authRequired'));
    }

    // Fallback: require PIN re-entry if biometric failed or unavailable
    if (!authenticated) {
      if (!mounted) return;
      final pinOk = await _showPinVerification(l);
      if (pinOk != true) return;
    }

    if (!mounted) return;

    // Show confirmation dialog
    final confirmed = await _showConfirmation(address, amount, l);
    if (confirmed != true || !mounted) return;

    setState(() => _isSending = true);
    SynthService.playSend();

    try {
      final txHash = await wallet.sendTPIX(address, amount);
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
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<bool?> _showConfirmation(String address, double amount, LocaleProvider l) {
    final c = AppColors.of(context);
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
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
            const SizedBox(height: 20),
            Text(l.t('send.confirmTitle'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
            const SizedBox(height: 20),
            // ผู้รับ — ถ้าเคยบันทึกชื่อไว้ให้โชว์ชื่อด้วย
            // คนตรวจ "ส่งให้น้องเอ" ได้แม่นกว่าตรวจเลขย่อ 0x1234…abcdef
            if (_lookupFavorite(address) case final match?) ...[
              _confirmRow(l.t('send.confirmTo'), match.name,
                  valueColor: AppTheme.success),
              _confirmRow(
                l.t('send.confirmAddress'),
                '${address.substring(0, 8)}...${address.substring(address.length - 6)}',
              ),
            ] else
              _confirmRow(
                l.t('send.confirmTo'),
                '${address.substring(0, 8)}...${address.substring(address.length - 6)}',
              ),
            // Amount
            _confirmRow(l.t('send.confirmAmount'), '${amount.toStringAsFixed(4)} TPIX'),
            // Gas
            _confirmRow(l.t('send.gasFee').replaceAll(': ', ''), l.t('send.gasFreeVal'), valueColor: AppTheme.success),
            const SizedBox(height: 24),
            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: c.glassBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(l.t('send.cancel'), style: TextStyle(color: c.textSec)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(l.t('send.confirmButton'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showPinVerification(LocaleProvider l) {
    final c = AppColors.of(context);
    final pinController = TextEditingController();
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l.t('pin.unlock'), style: TextStyle(color: c.text, fontSize: 16)),
        content: TextField(
          controller: pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
          style: TextStyle(color: c.text, fontSize: 24, letterSpacing: 8),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••••',
            hintStyle: TextStyle(color: c.textMuted.withValues(alpha: 0.3)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3))),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary)),
          ),
          onChanged: (val) async {
            if (val.length == 6) {
              final wallet = context.read<WalletProvider>();
              // Verify PIN by trying unlock (already unlocked, so just check hash)
              final service = WalletService();
              final isLocked = await service.isPinLocked();
              if (isLocked) {
                if (ctx.mounted) Navigator.pop(ctx, false);
                return;
              }
              // Use the provider's existing unlock check
              final success = await wallet.unlock(val);
              if (ctx.mounted) Navigator.pop(ctx, success);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              pinController.dispose();
              Navigator.pop(ctx, false);
            },
            child: Text(l.t('send.cancel'), style: const TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    ).then((result) {
      pinController.dispose();
      return result;
    });
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
          borderRadius: BorderRadius.circular(14),
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
              const SizedBox(height: 5),
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
              const SizedBox(width: 8),
              // Expanded — หัวข้อ+คำอธิบายยาวหรือเครื่องตั้งตัวอักษรใหญ่
              // ต้องตัดเป็น … ไม่ใช่ดันแถวจนล้นขอบขวา
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.t('send.title'),
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

          const SizedBox(height: 32),

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
          const SizedBox(height: 4),
          TextField(
            controller: _addressController,
            style: TextStyle(color: c.text, fontSize: 14, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: '0x...',
              hintStyle: TextStyle(color: c.textMuted),
              filled: true,
              fillColor: c.glassColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: c.glassBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: c.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
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
                  const SizedBox(width: 4),
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
                  const SizedBox(width: 8),
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
            const SizedBox(height: 14),
            SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                itemCount: _favorites.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _buildFavoriteChip(_favorites[i], c),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Amount
          Text(l.t('send.amount'), style: TextStyle(fontSize: 14, color: c.textSec)),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: c.text, fontSize: 24, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: TextStyle(color: c.textMuted.withValues(alpha: 0.5)),
              filled: true,
              fillColor: c.glassColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: c.glassBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: c.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppTheme.primary),
              ),
              suffixText: 'TPIX',
              suffixStyle: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600),
            ),
          ),

          const SizedBox(height: 12),

          // Balance hint
          Consumer<WalletProvider>(
            builder: (_, wallet, __) => GestureDetector(
              onTap: () => _amountController.text = wallet.balance.toStringAsFixed(4),
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
                    child: Text('${wallet.formattedBalance} TPIX',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 4),
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
            ),
          ),

          const SizedBox(height: 16),

          // Fee info
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppTheme.success.withValues(alpha: 0.06),
              border: Border.all(color: AppTheme.success.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_gas_station, color: AppTheme.success, size: 18),
                const SizedBox(width: 8),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _isSending
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Text(l.t('send.sending'), style: const TextStyle(fontSize: 16, color: Colors.white)),
                      ],
                    )
                  : Text(l.t('send.button'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ],
            ),
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

                  const SizedBox(height: 32),

                  Text(l.t('send.success'), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: c.text)),
                  const SizedBox(height: 8),
                  Text(l.t('send.confirmed'), style: const TextStyle(fontSize: 16, color: AppTheme.success)),

                  const SizedBox(height: 24),

                  if (_txHash != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: adaptiveGlassCard(context, borderRadius: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tag, size: 14, color: c.textMuted),
                          const SizedBox(width: 6),
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
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _saveSentRecipient,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        side: BorderSide(color: c.brandWarm.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
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

                  const SizedBox(height: 40),

                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
